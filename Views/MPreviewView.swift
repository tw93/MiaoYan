// swiftlint:disable file_length
import Carbon.HIToolbox
import QuartzCore
import WebKit

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var handler: WKScriptMessageHandler?

    init(_ handler: WKScriptMessageHandler) {
        self.handler = handler
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        handler?.userContentController(userContentController, didReceive: message)
    }
}

public typealias MPreviewViewClosure = () -> Void

// MARK: - Protocol Definition
@MainActor
protocol MPreviewScrollDelegate: AnyObject {
    func previewDidScroll(ratio: CGFloat)
}

@MainActor
class MPreviewView: WKWebView, WKUIDelegate {
    private var scrollObserverInjected = false
    internal var isUpdatingContent = false
    nonisolated(unsafe) private var contentUpdateWorkItem: DispatchWorkItem?
    private var originalRedrawPolicy: NSView.LayerContentsRedrawPolicy?
    private var contentUpdateVersion: UInt = 0
    private(set) var hasLoadedTemplate = false
    static var hasCompletedInitialLoad = false
    private var loadCompletion: (() -> Void)?

    // MARK: - JavaScript Timing Constants

    private enum JavaScriptTiming {
        static let diagramInitDelay = 100  // milliseconds
        static let imageLoadTimeout: TimeInterval = 0.8  // WebView image load timeout (increased for diagram rendering)
    }

    @objcMembers
    private final class NavigationDelegateProxy: NSObject, WKNavigationDelegate {
        weak var owner: MPreviewView?

        init(owner: MPreviewView) {
            self.owner = owner
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let owner else {
                return .allow
            }
            return await owner.handleNavigationAction(navigationAction)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            owner?.webView(webView, didFinish: navigation)
        }
    }

    private lazy var navigationProxy = NavigationDelegateProxy(owner: self)
    private weak var note: Note?
    private var closure: MPreviewViewClosure?
    public static var template: String?
    private static var bundleInitialized = false
    private static let initQueue = DispatchQueue(label: "preview.init", qos: .userInitiated)
    weak var scrollDelegate: MPreviewScrollDelegate?
    init(frame: CGRect, note: Note, closure: MPreviewViewClosure?) {
        self.closure = closure
        let userContentController = WKUserContentController()
        userContentController.add(HandlerCheckbox(), name: "checkbox")
        userContentController.add(HandlerSelection(), name: "newSelectionDetected")
        userContentController.add(HandlerCodeCopy(), name: "notification")
        userContentController.add(HandlerRevealBackgroundColor(), name: "revealBackgroundColor")
        userContentController.add(HandlerPreviewScroll(), name: "previewScroll")
        userContentController.add(HandlerTOCTip(), name: "tocTipClicked")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        // macOS Sequoia beta: Simplified configuration to avoid sandbox conflicts
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        // Allow incremental rendering to avoid feeling "stuck" before load finishes
        configuration.suppressesIncrementalRendering = false
        // Basic WebKit configuration for quieter operation
        #if DEBUG
            configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif
        configuration.preferences.setValue(false, forKey: "javaScriptCanOpenWindowsAutomatically")
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        super.init(frame: frame, configuration: configuration)
        navigationDelegate = navigationProxy

        // Note: Frame is manually managed by EditTextView to avoid resize flicker
        // autoresizingMask is intentionally not set

        // Keep the same background color between native and web layers
        setValue(false, forKey: "drawsBackground")
        wantsLayer = true
        let bgNSColor = determineBackgroundColor()
        layer?.backgroundColor = bgNSColor.cgColor
        layer?.isOpaque = false
        // Use sRGB color space to avoid HDR tone mapping
        if #available(macOS 10.12, *) {
            layer?.contentsFormat = .RGBA8Uint
        }
        // Optimize layer rendering during resize
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.drawsAsynchronously = false
        // Fill under-page area with the same color to cover rubber-banding gaps (macOS 12+)
        if #available(macOS 12.0, *) {
            setValue(bgNSColor, forKey: "underPageBackgroundColor")
        }
        if let hostingScrollView = subviews.compactMap({ $0 as? NSScrollView }).first {
            hostingScrollView.drawsBackground = false
            hostingScrollView.backgroundColor = bgNSColor
            // 禁用弹性滚动
            hostingScrollView.hasVerticalScroller = false
            hostingScrollView.hasHorizontalScroller = false
            hostingScrollView.verticalScroller = nil
            hostingScrollView.horizontalScroller = nil
            hostingScrollView.hasVerticalRuler = false
            hostingScrollView.hasHorizontalRuler = false
            hostingScrollView.rulersVisible = false
            hostingScrollView.scrollerStyle = .overlay
            hostingScrollView.horizontalScrollElasticity = .none
            hostingScrollView.verticalScrollElasticity = .none
            let clipView = hostingScrollView.contentView
            clipView.drawsBackground = false
            clipView.backgroundColor = bgNSColor
        } else if let clipView = subviews.compactMap({ $0 as? NSClipView }).first {
            clipView.drawsBackground = false
            clipView.backgroundColor = bgNSColor
        }
        // Set webview appearance to match current theme
        self.appearance = UserDataService.instance.isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)

        Self.ensureBundlePreinitialized()
        load(note: note)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        AppDelegate.trackError(NSError(domain: "InitError", code: 1, userInfo: [NSLocalizedDescriptionKey: "MPreviewView does not support NSCoder initialization"]), context: "MPreviewView.init")
        return nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            configuration.userContentController.removeScriptMessageHandler(forName: "logging")
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        // Cancel pending content update work items to prevent crashes
        contentUpdateWorkItem?.cancel()
    }

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        if originalRedrawPolicy == nil {
            originalRedrawPolicy = layerContentsRedrawPolicy
        }
        layerContentsRedrawPolicy = .duringViewResize
        needsDisplay = true
        layer?.setNeedsDisplay()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        if let originalRedrawPolicy {
            layerContentsRedrawPolicy = originalRedrawPolicy
            self.originalRedrawPolicy = nil
        } else {
            layerContentsRedrawPolicy = .onSetNeedsDisplay
        }
        needsDisplay = true
        layer?.setNeedsDisplay()
    }

    private func setupScrollObserver() {
        guard !scrollObserverInjected else { return }
        // Use JavaScript with requestAnimationFrame for smoother scroll sync
        let script = """
                (function() {
                    let rafId = null;
                    let lastReportedRatio = -1;

                    function reportScroll() {
                        const doc = document.scrollingElement || document.documentElement || document.body;
                        const currentScroll = window.pageYOffset || doc.scrollTop || 0;
                        const maxScroll = Math.max(0, (doc.scrollHeight || document.body.scrollHeight) - window.innerHeight);

                        const ratio = maxScroll === 0 ? 0 : currentScroll / maxScroll;

                        // Only report if ratio changed significantly (> 0.1% difference)
                        if (Math.abs(ratio - lastReportedRatio) > 0.001) {
                            window.webkit.messageHandlers.previewScroll.postMessage(ratio);
                            lastReportedRatio = ratio;
                        }
                    }

                    window.addEventListener('scroll', function() {
                        // Cancel previous animation frame to avoid duplicate work
                        if (rafId !== null) {
                            cancelAnimationFrame(rafId);
                        }

                        // Use requestAnimationFrame for 60fps smooth sync
                        rafId = requestAnimationFrame(function() {
                            reportScroll();
                            rafId = null;
                        });
                    }, { passive: true });
                })();
            """

        evaluateJavaScript(script, completionHandler: nil)
        scrollObserverInjected = true
    }

    // MARK: - Appearance Helpers

    private func determineDarkTheme() -> Bool {
        switch UserDefaultsManagement.appearanceType {
        case .Light: return false
        case .Dark: return true
        case .System, .Custom: return UserDataService.instance.isDark
        }
    }

    private func determineBackgroundColor() -> NSColor {
        if UserDefaultsManagement.appearanceType == .Custom {
            return UserDefaultsManagement.bgColor
        }

        return determineDarkTheme() ? Theme.previewDarkBackgroundColor : Theme.backgroundColor
    }

    public func updateAppearance() {
    }

    // MARK: - Standard Find Actions

    @objc func performFindPanelAction(_ sender: Any?) {
        var resolvedAction: NSFindPanelAction?
        if let menuItem = sender as? NSMenuItem {
            resolvedAction = NSFindPanelAction(rawValue: UInt(menuItem.tag))
        } else if let number = sender as? NSNumber {
            resolvedAction = NSFindPanelAction(rawValue: number.uintValue)
        }

        guard let action = resolvedAction else {
            showSearchBar()
            return
        }

        switch action {
        case .showFindPanel:
            showSearchBar()
        case .next:
            findNext()
        case .previous:
            findPrevious()
        default:
            showSearchBar()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == kVK_ANSI_F,
            event.modifierFlags.contains(.command),
            !event.modifierFlags.contains(.option),
            !event.modifierFlags.contains(.control)
        {
            showSearchBar()
            return true
        }

        if event.keyCode == kVK_ANSI_G,
            event.modifierFlags.contains(.command),
            !event.modifierFlags.contains(.option),
            !event.modifierFlags.contains(.control)
        {
            if event.modifierFlags.contains(.shift) {
                findPrevious()
            } else {
                findNext()
            }
            return true
        }

        if event.keyCode == kVK_ANSI_C, event.modifierFlags.contains(.command) {
            DispatchQueue.main.async {
                self.copySelectionToPasteboard()
            }
            return false
        }

        if event.keyCode == kVK_Escape, UserDefaultsManagement.presentation, !UserDefaultsManagement.magicPPT {
            DispatchQueue.main.async {
                if let vc = ViewController.shared() {
                    vc.disablePresentation()
                }
            }
            return true
        }

        if event.keyCode == kVK_Escape, UserDefaultsManagement.magicPPT {
            DispatchQueue.main.async {
                if let vc = ViewController.shared() {
                    vc.disableMiaoYanPPT()
                }
            }
            return true
        }
        if event.keyCode == kVK_Space, UserDefaultsManagement.magicPPT {
            DispatchQueue.main.async {
                self.evaluateJavaScript("Reveal.next();", completionHandler: nil)
            }
            return false
        }
        if UserDefaultsManagement.magicPPT {
            return false
        }

        return false
    }

    func copySelectionToPasteboard() {
        let script = """
                (function() {
                    const selection = window.getSelection();
                    if (!selection || selection.rangeCount === 0) {
                        return { text: "", html: "" };
                    }
                    const text = selection.toString() || "";
                    const range = selection.getRangeAt(0).cloneContents();
                    const container = document.createElement('div');
                    container.appendChild(range);
                    return {
                        text: text,
                        html: container.innerHTML || ""
                    };
                })();
            """

        evaluateJavaScript(script) { result, _ in
            guard let payload = result as? [String: Any] else { return }
            let text = payload["text"] as? String ?? ""
            let html = payload["html"] as? String ?? ""
            guard !text.isEmpty else { return }

            let pasteboard = NSPasteboard.general
            var types: [NSPasteboard.PasteboardType] = [.string]
            if !html.isEmpty {
                types.append(.html)
            }
            pasteboard.declareTypes(types, owner: nil)
            pasteboard.setString(text, forType: .string)
            if !html.isEmpty {
                pasteboard.setString(html, forType: .html)
            }
        }
    }
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        for menuItem in menu.items {
            if menuItem.identifier?.rawValue == "WKMenuItemIdentifierSpeechMenu" || menuItem.identifier?.rawValue == "WKMenuItemIdentifierTranslate" || menuItem.identifier?.rawValue == "WKMenuItemIdentifierSearchWeb"
                || menuItem.identifier?.rawValue == "WKMenuItemIdentifierShareMenu" || menuItem.identifier?.rawValue == "WKMenuItemIdentifierLookUp"
            {
                menuItem.isHidden = true
            }
        }
    }
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        scrollObserverInjected = false
        Self.hasCompletedInitialLoad = true
        closure?()
        loadCompletion?()
        loadCompletion = nil

        // Set up scroll observation after WebView is fully loaded
        setupScrollObserver()
        showTOCTipIfNeeded()
    }

    // MARK: - Helper Methods
    func resetTemplateState() {
        hasLoadedTemplate = false
    }

    private func buildUpdateScript(html: String, initializeMath: Bool, initializeDiagrams: Bool, preserveScroll: Bool) -> String {
        var initScripts: [String] = []

        if initializeMath {
            initScripts.append(
                """
                    if (typeof renderMathInElement === 'function') {
                        renderMathInElement(document.body, {
                            delimiters: [
                                {left: "$$", right: "$$", display: true},
                                {left: "$", right: "$", display: false},
                                {left: "\\\\(", right: "\\\\)", display: false},
                                {left: "\\\\[", right: "\\\\]", display: true}
                            ],
                            processEscapes: true,
                            ignoredClasses: ['katex-display', 'katex', 'skip-math-dollar']
                        });
                    }
                """)
        }

        if initializeDiagrams {
            initScripts.append(
                """
                    if (window.DiagramHandler && typeof window.DiagramHandler.initializeAll === 'function') {
                        setTimeout(() => window.DiagramHandler.initializeAll(), \(JavaScriptTiming.diagramInitDelay));
                    }
                """)
        }

        let initialization = initScripts.joined(separator: "\n")

        return """
                (function() {
                    const container = document.querySelector('.markdown-body') || document.body;
                    if (!container) return;

                    const preserveScroll = \(preserveScroll ? "true" : "false");
                    let savedRatio = 0;
                    let isNearBottom = false;

                    if (preserveScroll) {
                        // Save scroll ratio (not absolute position) for better stability
                        const doc = document.scrollingElement || document.documentElement || document.body;
                        const maxScroll = Math.max(0, (doc.scrollHeight || document.body.scrollHeight) - window.innerHeight);
                        savedRatio = maxScroll > 0 ? (window.pageYOffset || doc.scrollTop || 0) / maxScroll : 0;

                        // Check if we're near the bottom (within 10 pixels)
                        isNearBottom = maxScroll > 0 && (maxScroll - (window.pageYOffset || doc.scrollTop || 0)) < 10;
                    }

                    container.innerHTML = `\(html)`;
                    \(initialization)

                    if (preserveScroll) {
                        // Wait for images to load before restoring scroll to prevent jitter
                        const images = container.querySelectorAll('img');
                        if (images.length > 0) {
                            let loadedCount = 0;
                            const totalImages = images.length;
                            const imageLoadTimeout = setTimeout(() => {
                                restoreScroll();
                            }, 300); // Reduced timeout for faster response

                            function restoreScroll() {
                                clearTimeout(imageLoadTimeout);
                                requestAnimationFrame(() => {
                                    const newDoc = document.scrollingElement || document.documentElement || document.body;
                                    const newMaxScroll = Math.max(0, (newDoc.scrollHeight || document.body.scrollHeight) - window.innerHeight);

                                    // If was at bottom, stay at bottom; otherwise restore ratio
                                    const targetScroll = isNearBottom ? newMaxScroll : newMaxScroll * savedRatio;
                                    window.scrollTo(0, targetScroll);
                                });
                            }

                            images.forEach(img => {
                                if (img.complete) {
                                    loadedCount++;
                                    if (loadedCount === totalImages) {
                                        restoreScroll();
                                    }
                                } else {
                                    img.addEventListener('load', () => {
                                        loadedCount++;
                                        if (loadedCount === totalImages) {
                                            restoreScroll();
                                        }
                                    }, { once: true });
                                    img.addEventListener('error', () => {
                                        loadedCount++;
                                        if (loadedCount === totalImages) {
                                            restoreScroll();
                                        }
                                    }, { once: true });
                                }
                            });
                        } else {
                            // No images, restore scroll immediately
                            requestAnimationFrame(() => {
                                const newDoc = document.scrollingElement || document.documentElement || document.body;
                                const newMaxScroll = Math.max(0, (newDoc.scrollHeight || document.body.scrollHeight) - window.innerHeight);

                                // If was at bottom, stay at bottom; otherwise restore ratio
                                const targetScroll = isNearBottom ? newMaxScroll : newMaxScroll * savedRatio;
                                window.scrollTo(0, targetScroll);
                            });
                        }
                    } else {
                        // No scroll preservation: reset to top
                        requestAnimationFrame(() => {
                            window.scrollTo(0, 0);
                        });
                    }
                })();
            """
    }

    // Internal so it can be used by extensions in other files
    func executeJavaScriptWhenReady(_ script: String, completion: (() -> Void)? = nil) {
        guard !script.isEmpty || completion != nil else { return }
        evaluateJavaScript("document.readyState") { [weak self] complete, _ in
            guard let self = self, complete != nil else { return }
            if let completion {
                completion()
            } else {
                self.evaluateJavaScript(script, completionHandler: nil)
            }
        }
    }
    public func slideTo(index: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.executeJavaScriptWhenReady("Reveal.slide(\(index));")
        }
    }
    public func scrollToPosition(pre: CGFloat) {
        let clamped = Double(max(min(pre, 1), 0))
        let script = """
                (function() {
                    const doc = document.scrollingElement || document.documentElement || document.body;
                    const maxScroll = Math.max(0, (doc.scrollHeight || document.body.scrollHeight) - window.innerHeight);
                    const target = maxScroll * \(clamped);
                    window.scrollTo(0, target);
                })();
            """
        // Direct execution without async wrapper for smoother scrolling
        // Note: Errors are silently ignored here for performance (called frequently during scroll sync)
        self.evaluateJavaScript(script) { _, error in
            if let error = error {
                // Only log errors in debug builds to avoid log spam
                #if DEBUG
                    print("[ScrollSync] JavaScript execution error: \(error.localizedDescription)")
                #endif
            }
        }
    }
    private func handleNavigationAction(_ navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else {
            return .allow
        }

        switch navigationAction.navigationType {
        case .linkActivated:
            if isFootNotes(url: url) {
                return .cancel
            }
            NSWorkspace.shared.open(url)
            return .cancel
        default:
            return .allow
        }
    }
    public func load(note: Note, force: Bool = false, completion: (() -> Void)? = nil) {
        self.loadCompletion = completion
        // No alpha animation here - parent view controller handles transitions
        // This avoids double-animation when toggling preview mode
        Task { @MainActor [weak self, note] in
            guard let self else { return }
            let markdownString = note.getPrettifiedContent()
            let imagesStorage = note.project.url
            let css = HtmlManager.previewStyle()
            do {
                try self.loadHTMLView(markdownString, css: css, imagesStorage: imagesStorage)
                self.hasLoadedTemplate = true
                self.note = note
            } catch {
                self.hasLoadedTemplate = false
                AppDelegate.trackError(error, context: "MPreviewView.load")
                // Fallback: try to load minimal content
                let basicHTML = "<html><body><p>Failed to load preview</p></body></html>"
                self.loadHTMLString(basicHTML, baseURL: nil)
            }
        }
    }

    // Lightweight content update for split view (preserves scroll position)
    public func updateContent(note: Note, preserveScroll: Bool = true) {
        Task { @MainActor [weak self, note] in
            guard let self else { return }
            self.contentUpdateVersion &+= 1
            let updateVersion = self.contentUpdateVersion

            // Cancel previous content update reset task to avoid premature re-enable
            self.contentUpdateWorkItem?.cancel()

            // Disable scroll sync during content update
            self.isUpdatingContent = true

            let markdownString = note.getPrettifiedContent()
            let imagesStorage = note.project.url

            // Performance: render Markdown on background thread to avoid blocking UI
            let useGithubLineBreak = UserDefaultsManagement.editorLineBreak == "Github"
            let htmlString = await Task.detached {
                return renderMarkdownHTML(markdown: markdownString, useGithubLineBreak: useGithubLineBreak)
            }.value

            guard let htmlString = htmlString else {
                await MainActor.run {
                    AppDelegate.trackError(
                        NSError(
                            domain: "MarkdownRenderError", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to render markdown in updateContent"]),
                        context: "MPreviewView.updateContent"
                    )
                    // Fallback: reload the full view instead of silent failure
                    self.isUpdatingContent = false
                    self.contentUpdateWorkItem = nil
                    self.load(note: note, force: true)
                }
                return
            }
            guard updateVersion == self.contentUpdateVersion else { return }
            guard self.note == nil || self.note === note else { return }

            let processedHtmlString = self.loadImages(imagesStorage: imagesStorage, html: htmlString)

            // Escape HTML for JavaScript injection
            let escapedHTML =
                processedHtmlString
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")

            // Detect special content requiring renderer initialization
            let needsMath = escapedHTML.contains("$$") || escapedHTML.contains("$")
            let needsDiagrams =
                escapedHTML.contains("language-mermaid")
                || escapedHTML.contains("language-plantuml")
                || escapedHTML.contains("language-markmap")

            let script = self.buildUpdateScript(
                html: escapedHTML,
                initializeMath: needsMath,
                initializeDiagrams: needsDiagrams,
                preserveScroll: preserveScroll
            )

            Task { @MainActor [weak self] in
                guard let self else { return }
                guard updateVersion == self.contentUpdateVersion else { return }
                guard self.note == nil || self.note === note else { return }

                // Execute JavaScript with proper error handling
                do {
                    _ = try await self.evaluateJavaScript(script)
                } catch {
                    AppDelegate.trackError(error, context: "MPreviewView.updateContent.jsExec")
                    // Fallback: reload the full view on JavaScript failure
                    self.isUpdatingContent = false
                    self.contentUpdateWorkItem = nil
                    self.load(note: note, force: true)
                    return
                }

                // Re-setup scroll observer after content update
                self.setupScrollObserver()

                // Re-enable scroll sync after images have loaded
                // Use DispatchWorkItem to ensure proper cancellation on rapid updates
                let resetWorkItem = DispatchWorkItem { [weak self] in
                    self?.isUpdatingContent = false
                    self?.contentUpdateWorkItem = nil
                }
                self.contentUpdateWorkItem = resetWorkItem
                DispatchQueue.main.asyncAfter(deadline: .now() + JavaScriptTiming.imageLoadTimeout, execute: resetWorkItem)
            }
            self.note = note
        }
    }

    private func getTemplate(css: String) -> String? {
        guard let bundle = HtmlManager.getDownViewBundle(),
            let baseURL = HtmlManager.getBaseURL(bundle: bundle)
        else {
            return nil
        }
        guard var template = try? String(contentsOf: baseURL, encoding: .utf8) else {
            return nil
        }
        template = template.replacingOccurrences(of: "DOWN_CSS", with: css)
        if UserDefaultsManagement.magicPPT {
            // For PPT mode, also replace the theme placeholder
            let pptTheme = HtmlManager.getPPTTheme()
            template = template.replacingOccurrences(of: "DOWN_THEME", with: pptTheme)
        }

        // Theme handling is now done via CSS imports in HtmlManager.previewStyle()
        return template
    }

    private func isFootNotes(url: URL) -> Bool {
        let webkitPreview = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wkPreview")
            .appendingPathComponent("index.html")
            .absoluteString
        let link = url.absoluteString.replacingOccurrences(of: webkitPreview, with: "")
        if link.starts(with: "#") {
            let anchor = link.dropFirst()
            let javascript = "document.getElementById('\(anchor)').offsetTop"
            evaluateJavaScript(javascript) { [weak self] result, _ in
                if let offset = result as? CGFloat {
                    self?.evaluateJavaScript("window.scrollTo(0,\(offset))", completionHandler: nil)
                }
            }
            return true
        }
        return false
    }
    enum PreviewError: Error {
        case markdownRenderFailed
        case viewControllerUnavailable
        case htmlTemplateError
        case temporaryBundleCreationFailed

        var localizedDescription: String {
            switch self {
            case .markdownRenderFailed:
                return "Failed to render markdown content"
            case .viewControllerUnavailable:
                return "View controller not available"
            case .htmlTemplateError:
                return "Failed to create HTML template"
            case .temporaryBundleCreationFailed:
                return "Failed to create temporary bundle"
            }
        }
    }

    func loadHTMLView(_ markdownString: String, css: String, imagesStorage: URL? = nil) throws {
        let useGithubLineBreak = UserDefaultsManagement.editorLineBreak == "Github"
        guard let htmlString = renderMarkdownHTML(markdown: markdownString, useGithubLineBreak: useGithubLineBreak) else {
            throw PreviewError.markdownRenderFailed
        }

        let processedHtmlString: String
        if let imagesStorage {
            processedHtmlString = loadImages(imagesStorage: imagesStorage, html: htmlString)
        } else {
            processedHtmlString = htmlString
        }

        guard let vc = ViewController.shared() else {
            throw PreviewError.viewControllerUnavailable
        }

        let pageHTMLString: String
        if UserDefaultsManagement.magicPPT {
            // Process images in markdown for PPT mode
            let processedMarkdown = imagesStorage.map { HtmlManager.processImagesInMarkdown(markdownString, imagesStorage: $0) } ?? markdownString
            pageHTMLString = try HtmlManager.htmlFromTemplate(processedMarkdown, css: css, currentName: vc.titleLabel.stringValue)
        } else {
            pageHTMLString = try HtmlManager.htmlFromTemplate(processedHtmlString, css: css, currentName: vc.titleLabel.stringValue)
        }

        guard let indexURL = HtmlManager.createTemporaryBundle(pageHTMLString: pageHTMLString) else {
            throw PreviewError.temporaryBundleCreationFailed
        }

        // Allow access to root directory to support absolute path images
        let accessURL = URL(fileURLWithPath: "/")
        loadFileURL(indexURL, allowingReadAccessTo: accessURL)
    }
    private static func ensureBundlePreinitialized() {
        Task { @MainActor in
            guard !bundleInitialized else { return }
            Task.detached {
                await MainActor.run {
                    guard !Self.bundleInitialized else { return }
                }
                let webkitPreview = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wkPreview")
                if !FileManager.default.fileExists(atPath: webkitPreview.path),
                    let bundle = HtmlManager.getDownViewBundle(),
                    let bundleResourceURL = bundle.resourceURL
                {
                    try? FileManager.default.createDirectory(at: webkitPreview, withIntermediateDirectories: true, attributes: nil)
                    do {
                        let fileList = try FileManager.default.contentsOfDirectory(atPath: bundleResourceURL.path)
                        for file in fileList {
                            let tmpURL = webkitPreview.appendingPathComponent(file)
                            try? FileManager.default.copyItem(atPath: bundleResourceURL.appendingPathComponent(file).path, toPath: tmpURL.path)
                        }
                    } catch {
                        await AppDelegate.trackError(error, context: "MPreviewView.bundleInit")
                    }
                }
                await MainActor.run {
                    Self.bundleInitialized = true
                }
            }
        }
    }

    private func loadImages(imagesStorage: URL, html: String) -> String {
        return HtmlManager.processImages(in: html, imagesStorage: imagesStorage)
    }

    // MARK: - TOC Hint
    func showTOCTipIfNeeded() {
        guard !UserDefaultsManagement.hasShownTOCTip else { return }
        UserDefaultsManagement.hasShownTOCTip = true

        // Inject Red Dot script
        let script = """
                (function() {
                    var trigger = document.querySelector('.toc-hover-trigger');
                    if (!trigger) return;

                    // Avoid duplicate dots
                    if (document.getElementById('toc-red-dot-hint')) return;

                    var dot = document.createElement('div');
                    dot.id = 'toc-red-dot-hint';
                    dot.innerText = 'TOC';
                    dot.style.position = 'absolute';
                    dot.style.backgroundColor = '#FF3B30'; // System Red
                    dot.style.color = 'white';
                    dot.style.fontSize = '8px';
                    dot.style.fontWeight = 'bold';
                    dot.style.padding = '2px 5px';
                    dot.style.borderRadius = '8px';
                    dot.style.top = '12px'; // Adjust based on visual testing
                    dot.style.right = '12px';
                    dot.style.zIndex = '9999';
                    dot.style.boxShadow = '0 1px 3px rgba(0,0,0,0.2)';
                    dot.style.cursor = 'pointer';
                    dot.style.pointerEvents = 'auto'; // Make badge clickable directly

                    trigger.appendChild(dot);

                    // Function to dismiss
                    function dismiss() {
                        if (dot) dot.remove();
                        window.webkit.messageHandlers.tocTipClicked.postMessage("clicked");
                    }

                    // Click on badge: dismiss AND click trigger (to open TOC)
                    dot.addEventListener('click', function(e) {
                        e.stopPropagation(); // Stop bubbling to avoid double triggering if logic is complex
                        dismiss();
                        trigger.click(); // Manually trigger the TOC opening
                    }, { once: true });

                    // Click on trigger (e.g. user missed the badge but hit the area): dismiss
                    trigger.addEventListener('click', function() {
                        dismiss();
                    }, { once: true });
                })();
            """
        executeJavaScriptWhenReady(script)
    }
}
class HandlerTOCTip: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        UserDefaultsManagement.hasShownTOCTip = true
    }
}
class HandlerCheckbox: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let position = message.body as? String else { return }
        guard let note = EditTextView.note else { return }
        let content = note.content.unLoadCheckboxes().unLoadImages()
        let string = content.string
        let range = NSRange(0..<string.count)
        var i = 0
        NotesTextProcessor.allTodoInlineRegex.matches(string, range: range) { result in
            guard let range = result?.range else { return }
            if i == Int(position) {
                let substring = content.mutableString.substring(with: range)
                if substring.contains("- [x] ") {
                    content.replaceCharacters(in: range, with: "- [ ] ")
                } else {
                    content.replaceCharacters(in: range, with: "- [x] ")
                }
                note.save(content: content)
            }
            i += 1
        }
    }
}

class HandlerCodeCopy: NSObject, WKScriptMessageHandler {
    public static var selectionString: String? {
        didSet {
            guard let copyBlock = selectionString else {
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyBlock, forType: .string)
        }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let message = (message.body as! String).trimmingCharacters(in: .whitespacesAndNewlines)
        HandlerCodeCopy.selectionString = message
    }
}

class HandlerSelection: NSObject, WKScriptMessageHandler {
    public static var selectionString: String?
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let message = (message.body as! String).trimmingCharacters(in: .whitespacesAndNewlines)
        HandlerSelection.selectionString = message
    }
}
// Used to solve the adaptation of the left border/title color change with background color in PPT mode.

class HandlerRevealBackgroundColor: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let vc = ViewController.shared() else { return }
        let message = (message.body as! String).trimmingCharacters(in: .whitespacesAndNewlines)
        if message == "" {
            vc.titleLabel.backgroundColor = Theme.backgroundColor
        } else {
            vc.sidebarSplitView.setValue(NSColor(css: message), forKey: "dividerColor")
            vc.splitView.setValue(NSColor(css: message), forKey: "dividerColor")
        }
    }
}

class HandlerPreviewScroll: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let previewView = message.webView as? MPreviewView else {
            return
        }

        if let ratio = message.body as? Double {
            Task { @MainActor in
                previewView.scrollDelegate?.previewDidScroll(ratio: CGFloat(ratio))
            }
        } else if let ratio = message.body as? CGFloat {
            Task { @MainActor in
                previewView.scrollDelegate?.previewDidScroll(ratio: ratio)
            }
        } else if let ratio = message.body as? Int {
            Task { @MainActor in
                previewView.scrollDelegate?.previewDidScroll(ratio: CGFloat(ratio))
            }
        }
    }
}

// MARK: - Preview Search Bar
@MainActor
class PreviewSearchBar: NSView {
    private final class SearchField: NSSearchField {
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if handlePreviewShortcuts(event) {
                return true
            }
            return false
        }

        override func keyDown(with event: NSEvent) {
            if handlePreviewShortcuts(event) {
                return
            }
            super.keyDown(with: event)
        }

        private func handlePreviewShortcuts(_ event: NSEvent) -> Bool {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control) else {
                return false
            }

            switch Int(event.keyCode) {
            case Int(kVK_ANSI_3):
                if NSApp.sendAction(#selector(ViewController.togglePreview(_:)), to: nil, from: self) {
                    return true
                }
                ViewController.shared()?.togglePreview()
                return true
            case Int(kVK_ANSI_4):
                if NSApp.sendAction(#selector(ViewController.togglePresentation(_:)), to: nil, from: self) {
                    return true
                }
                ViewController.shared()?.togglePresentation()
                return true
            default:
                return false
            }
        }
    }

    enum Mode {
        case find
        case replace
    }

    private let searchField = SearchField()
    private let replaceField = NSSearchField()
    private let matchLabel = NSTextField()
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let replaceButton = NSButton()
    private let replaceAllButton = NSButton()
    private let doneButton = NSButton()
    private var panelBaseColor: NSColor = Theme.backgroundColor

    private var currentMatchIndex: Int = 0
    private var totalMatches: Int = 0
    private var mode: Mode = .find

    var onSearch: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onReplace: ((String) -> Void)?
    var onReplaceAll: ((String) -> Void)?
    var onClose: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        autoresizingMask = []
        wantsLayer = true
        applyCornerMask()
        layer?.borderWidth = 0
        layer?.borderColor = nil
        updatePanelBackground()

        searchField.placeholderString = I18n.str("Search")
        searchField.font = NSFont.systemFont(ofSize: 13)
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.sendsSearchStringImmediately = true
        searchField.focusRingType = .none
        searchField.delegate = self
        if let cell = searchField.cell as? NSSearchFieldCell {
            cell.focusRingType = .none
            cell.searchButtonCell = nil
            cell.cancelButtonCell = nil
        }
        addSubview(searchField)

        replaceField.placeholderString = I18n.str("Replace")
        replaceField.font = NSFont.systemFont(ofSize: 13)
        replaceField.translatesAutoresizingMaskIntoConstraints = false
        replaceField.focusRingType = .none
        if let cell = replaceField.cell as? NSSearchFieldCell {
            cell.focusRingType = .none
            cell.searchButtonCell = nil
            cell.cancelButtonCell = nil
        }
        addSubview(replaceField)

        matchLabel.isEditable = false
        matchLabel.isBordered = false
        matchLabel.drawsBackground = false
        matchLabel.font = NSFont.systemFont(ofSize: 11)
        matchLabel.textColor = .secondaryLabelColor
        matchLabel.alignment = .center
        matchLabel.stringValue = ""
        matchLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(matchLabel)

        previousButton.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: I18n.str("Previous"))
        previousButton.bezelStyle = .shadowlessSquare
        previousButton.isBordered = false
        previousButton.target = self
        previousButton.action = #selector(previousClicked)
        previousButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previousButton)

        nextButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: I18n.str("Next"))
        nextButton.bezelStyle = .shadowlessSquare
        nextButton.isBordered = false
        nextButton.target = self
        nextButton.action = #selector(nextClicked)
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nextButton)

        replaceButton.image = createReplaceIcon()
        replaceButton.bezelStyle = .shadowlessSquare
        replaceButton.isBordered = false
        replaceButton.target = self
        replaceButton.action = #selector(replaceClicked)
        replaceButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(replaceButton)

        replaceAllButton.image = createReplaceAllIcon()
        replaceAllButton.bezelStyle = .shadowlessSquare
        replaceAllButton.isBordered = false
        replaceAllButton.target = self
        replaceAllButton.action = #selector(replaceAllClicked)
        replaceAllButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(replaceAllButton)

        doneButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: I18n.str("Done"))
        doneButton.bezelStyle = .shadowlessSquare
        doneButton.isBordered = false
        doneButton.target = self
        doneButton.action = #selector(doneClicked)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(doneButton)

        replaceField.isHidden = true
        replaceButton.isHidden = true
        replaceAllButton.isHidden = true

        setupConstraints()
    }

    private var searchFieldTopConstraint: NSLayoutConstraint!
    private var buttonGroupLeading: CGFloat = 250

    private func setupConstraints() {
        searchFieldTopConstraint = searchField.topAnchor.constraint(equalTo: topAnchor, constant: 8)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchFieldTopConstraint,
            searchField.widthAnchor.constraint(equalToConstant: 180),

            matchLabel.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 6),
            matchLabel.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            matchLabel.widthAnchor.constraint(equalToConstant: 50),

            previousButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonGroupLeading),
            previousButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 28),
            previousButton.heightAnchor.constraint(equalToConstant: 22),

            nextButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 2),
            nextButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 28),
            nextButton.heightAnchor.constraint(equalToConstant: 22),

            doneButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            doneButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            doneButton.widthAnchor.constraint(equalToConstant: 28),
            doneButton.heightAnchor.constraint(equalToConstant: 22),

            replaceField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            replaceField.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            replaceField.widthAnchor.constraint(equalToConstant: 180),

            replaceButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonGroupLeading),
            replaceButton.centerYAnchor.constraint(equalTo: replaceField.centerYAnchor),
            replaceButton.widthAnchor.constraint(equalToConstant: 28),
            replaceButton.heightAnchor.constraint(equalToConstant: 22),

            replaceAllButton.leadingAnchor.constraint(equalTo: replaceButton.trailingAnchor, constant: 2),
            replaceAllButton.centerYAnchor.constraint(equalTo: replaceField.centerYAnchor),
            replaceAllButton.widthAnchor.constraint(equalToConstant: 28),
            replaceAllButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @objc private func searchFieldChanged() {
        let searchText = searchField.stringValue
        onSearch?(searchText)
    }

    @objc private func previousClicked() {
        onPrevious?()
    }

    @objc private func nextClicked() {
        onNext?()
    }

    @objc private func replaceClicked() {
        let replaceText = replaceField.stringValue
        onReplace?(replaceText)
    }

    @objc private func replaceAllClicked() {
        let replaceText = replaceField.stringValue
        onReplaceAll?(replaceText)
    }

    @objc private func doneClicked() {
        onClose?()
    }

    func updateMatchInfo(current: Int, total: Int) {
        currentMatchIndex = current
        totalMatches = total

        if total > 0 {
            matchLabel.stringValue = "\(current)/\(total)"
            matchLabel.textColor = .labelColor
        } else if !searchField.stringValue.isEmpty {
            matchLabel.stringValue = "0/0"
            matchLabel.textColor = Theme.linkColor
        } else {
            matchLabel.stringValue = ""
        }

        previousButton.isEnabled = total > 0
        nextButton.isEnabled = total > 0
        replaceButton.isEnabled = total > 0
        replaceAllButton.isEnabled = total > 0
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
        let isReplaceMode = (mode == .replace)
        replaceField.isHidden = !isReplaceMode
        replaceButton.isHidden = !isReplaceMode
        replaceAllButton.isHidden = !isReplaceMode

        if isReplaceMode {
            searchFieldTopConstraint.constant = 11
        } else {
            searchFieldTopConstraint.constant = 8
        }
    }

    private func clearSearchField() {
        if let editor = searchField.currentEditor() {
            editor.selectAll(nil)
            editor.delete(nil)
        }
        searchField.stringValue = ""
        onSearch?("")
    }

    func focusSearchField(selectAll: Bool = false) {
        window?.makeFirstResponder(searchField)
        if selectAll, let editor = searchField.currentEditor() {
            DispatchQueue.main.async {
                editor.selectAll(nil)
            }
        }
    }

    func setSearchText(_ text: String, selectAll: Bool = true) {
        searchField.stringValue = text
        if selectAll {
            window?.makeFirstResponder(searchField)
            if let editor = searchField.currentEditor() {
                editor.selectAll(nil)
            }
        }
    }

    func configureAppearance(baseColor: NSColor) {
        panelBaseColor = baseColor
        updatePanelBackground()
    }

    var searchText: String {
        searchField.stringValue
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == kVK_Delete,
            flags.contains(.command),
            !flags.contains(.option),
            !flags.contains(.control)
        {
            clearSearchField()
            return true
        }
        return false
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onClose?()
        } else if event.keyCode == 36 {
            if event.modifierFlags.contains(.shift) {
                onPrevious?()
            } else {
                onNext?()
            }
        } else {
            super.keyDown(with: event)
        }
    }
}

extension PreviewSearchBar: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        let searchText = searchField.stringValue
        onSearch?(searchText)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        case #selector(NSText.deleteToBeginningOfLine(_:)),
            #selector(NSText.deleteToBeginningOfParagraph(_:)):
            clearSearchField()
            return true
        case #selector(NSResponder.insertNewline(_:)),
            #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                onPrevious?()
            } else {
                onNext?()
            }
            return true
        default:
            return false
        }
    }
}

extension PreviewSearchBar {
    fileprivate static func panelBackgroundColor(base: NSColor) -> NSColor {
        guard let rgb = base.usingColorSpace(.sRGB) else {
            return base
        }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        if luminance < 0.5 {
            // Dark mode: deepen the tone slightly for clearer separation
            return (rgb.shadow(withLevel: 0.18) ?? rgb)
        } else {
            // Light mode: add subtle depth so the bar stays visible
            return (rgb.shadow(withLevel: 0.08) ?? rgb)
        }
    }

    fileprivate func updatePanelBackground() {
        guard wantsLayer else { return }
        let panelColor = PreviewSearchBar.panelBackgroundColor(base: panelBaseColor)
        layer?.backgroundColor = panelColor.cgColor

        updateShadowAppearance(for: panelColor)
        applyCornerMask()
    }

    fileprivate func updateShadowAppearance(for color: NSColor) {
        guard wantsLayer, let rgb = color.usingColorSpace(.sRGB) else { return }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        if luminance < 0.5 {
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = 0.45
            layer?.shadowRadius = 12
            layer?.shadowOffset = NSSize(width: 0, height: -4)
        } else {
            layer?.shadowColor = NSColor.black.withAlphaComponent(0.35).cgColor
            layer?.shadowOpacity = 0.35
            layer?.shadowRadius = 9
            layer?.shadowOffset = NSSize(width: 0, height: -2.5)
        }
    }

    fileprivate func applyCornerMask() {
        guard wantsLayer else { return }
        if #available(macOS 10.13, *) {
            layer?.cornerRadius = 8
            layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            layer?.masksToBounds = true
            layer?.mask = nil
        } else {
            let maskLayer = CAShapeLayer()
            maskLayer.frame = bounds
            maskLayer.path = leftRoundedCornerPath(radius: 8).cgPath
            layer?.mask = maskLayer
        }
    }

    fileprivate func leftRoundedCornerPath(radius: CGFloat) -> NSBezierPath {
        let rect = bounds
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        let path = NSBezierPath()
        path.move(to: NSPoint(x: maxX, y: maxY))
        path.line(to: NSPoint(x: minX + radius, y: maxY))
        path.appendArc(withCenter: NSPoint(x: minX + radius, y: maxY - radius), radius: radius, startAngle: 90, endAngle: 180, clockwise: true)
        path.line(to: NSPoint(x: minX, y: minY + radius))
        path.appendArc(withCenter: NSPoint(x: minX + radius, y: minY + radius), radius: radius, startAngle: 180, endAngle: 270, clockwise: true)
        path.line(to: NSPoint(x: maxX, y: minY))
        path.close()
        return path
    }

    private func createReplaceIcon() -> NSImage? {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.isTemplate = true

        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let path = NSBezierPath()
        let scale: CGFloat = 16.0 / 24.0

        path.move(to: NSPoint(x: 14 * scale, y: (24 - 4) * scale))
        path.curve(
            to: NSPoint(x: 15 * scale, y: (24 - 3) * scale),
            controlPoint1: NSPoint(x: 14.552 * scale, y: (24 - 4) * scale),
            controlPoint2: NSPoint(x: 15 * scale, y: (24 - 3.552) * scale))

        path.move(to: NSPoint(x: 15 * scale, y: (24 - 10) * scale))
        path.curve(
            to: NSPoint(x: 14 * scale, y: (24 - 9) * scale),
            controlPoint1: NSPoint(x: 15 * scale, y: (24 - 9.448) * scale),
            controlPoint2: NSPoint(x: 14.552 * scale, y: (24 - 9) * scale))

        path.move(to: NSPoint(x: 21 * scale, y: (24 - 4) * scale))
        path.curve(
            to: NSPoint(x: 20 * scale, y: (24 - 3) * scale),
            controlPoint1: NSPoint(x: 21 * scale, y: (24 - 3.448) * scale),
            controlPoint2: NSPoint(x: 20.552 * scale, y: (24 - 3) * scale))

        path.move(to: NSPoint(x: 21 * scale, y: (24 - 9) * scale))
        path.curve(
            to: NSPoint(x: 20 * scale, y: (24 - 10) * scale),
            controlPoint1: NSPoint(x: 21 * scale, y: (24 - 9.552) * scale),
            controlPoint2: NSPoint(x: 20.552 * scale, y: (24 - 10) * scale))

        path.move(to: NSPoint(x: 3 * scale, y: (24 - 7) * scale))
        path.line(to: NSPoint(x: 6 * scale, y: (24 - 10) * scale))
        path.line(to: NSPoint(x: 9 * scale, y: (24 - 7) * scale))

        path.move(to: NSPoint(x: 6 * scale, y: (24 - 10) * scale))
        path.line(to: NSPoint(x: 6 * scale, y: (24 - 5) * scale))
        path.curve(
            to: NSPoint(x: 8 * scale, y: (24 - 3) * scale),
            controlPoint1: NSPoint(x: 6 * scale, y: (24 - 3.895) * scale),
            controlPoint2: NSPoint(x: 6.895 * scale, y: (24 - 3) * scale))
        path.line(to: NSPoint(x: 10 * scale, y: (24 - 3) * scale))

        path.appendRoundedRect(
            NSRect(x: 3 * scale, y: (24 - 21) * scale, width: 7 * scale, height: 7 * scale),
            xRadius: 1 * scale, yRadius: 1 * scale)

        NSColor.black.setStroke()
        path.lineWidth = 1.0
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()

        image.unlockFocus()
        return image
    }

    private func createReplaceAllIcon() -> NSImage? {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.isTemplate = true

        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let path = NSBezierPath()
        let scale: CGFloat = 16.0 / 24.0

        path.move(to: NSPoint(x: 14 * scale, y: (24 - 14) * scale))
        path.curve(
            to: NSPoint(x: 15 * scale, y: (24 - 15) * scale),
            controlPoint1: NSPoint(x: 14.552 * scale, y: (24 - 14) * scale),
            controlPoint2: NSPoint(x: 15 * scale, y: (24 - 14.448) * scale))
        path.line(to: NSPoint(x: 15 * scale, y: (24 - 20) * scale))
        path.curve(
            to: NSPoint(x: 14 * scale, y: (24 - 21) * scale),
            controlPoint1: NSPoint(x: 15 * scale, y: (24 - 20.552) * scale),
            controlPoint2: NSPoint(x: 14.552 * scale, y: (24 - 21) * scale))

        path.move(to: NSPoint(x: 14 * scale, y: (24 - 4) * scale))
        path.curve(
            to: NSPoint(x: 15 * scale, y: (24 - 3) * scale),
            controlPoint1: NSPoint(x: 14.552 * scale, y: (24 - 4) * scale),
            controlPoint2: NSPoint(x: 15 * scale, y: (24 - 3.552) * scale))

        path.move(to: NSPoint(x: 15 * scale, y: (24 - 10) * scale))
        path.curve(
            to: NSPoint(x: 14 * scale, y: (24 - 9) * scale),
            controlPoint1: NSPoint(x: 15 * scale, y: (24 - 9.448) * scale),
            controlPoint2: NSPoint(x: 14.552 * scale, y: (24 - 9) * scale))

        path.move(to: NSPoint(x: 19 * scale, y: (24 - 14) * scale))
        path.curve(
            to: NSPoint(x: 20 * scale, y: (24 - 15) * scale),
            controlPoint1: NSPoint(x: 19.552 * scale, y: (24 - 14) * scale),
            controlPoint2: NSPoint(x: 20 * scale, y: (24 - 14.448) * scale))
        path.line(to: NSPoint(x: 20 * scale, y: (24 - 20) * scale))
        path.curve(
            to: NSPoint(x: 19 * scale, y: (24 - 21) * scale),
            controlPoint1: NSPoint(x: 20 * scale, y: (24 - 20.552) * scale),
            controlPoint2: NSPoint(x: 19.552 * scale, y: (24 - 21) * scale))

        path.move(to: NSPoint(x: 21 * scale, y: (24 - 4) * scale))
        path.curve(
            to: NSPoint(x: 20 * scale, y: (24 - 3) * scale),
            controlPoint1: NSPoint(x: 21 * scale, y: (24 - 3.448) * scale),
            controlPoint2: NSPoint(x: 20.552 * scale, y: (24 - 3) * scale))

        path.move(to: NSPoint(x: 21 * scale, y: (24 - 9) * scale))
        path.curve(
            to: NSPoint(x: 20 * scale, y: (24 - 10) * scale),
            controlPoint1: NSPoint(x: 21 * scale, y: (24 - 9.552) * scale),
            controlPoint2: NSPoint(x: 20.552 * scale, y: (24 - 10) * scale))

        path.move(to: NSPoint(x: 3 * scale, y: (24 - 7) * scale))
        path.line(to: NSPoint(x: 6 * scale, y: (24 - 10) * scale))
        path.line(to: NSPoint(x: 9 * scale, y: (24 - 7) * scale))

        path.move(to: NSPoint(x: 6 * scale, y: (24 - 10) * scale))
        path.line(to: NSPoint(x: 6 * scale, y: (24 - 5) * scale))
        path.curve(
            to: NSPoint(x: 8 * scale, y: (24 - 3) * scale),
            controlPoint1: NSPoint(x: 6 * scale, y: (24 - 3.895) * scale),
            controlPoint2: NSPoint(x: 6.895 * scale, y: (24 - 3) * scale))
        path.line(to: NSPoint(x: 10 * scale, y: (24 - 3) * scale))

        path.appendRoundedRect(
            NSRect(x: 3 * scale, y: (24 - 21) * scale, width: 7 * scale, height: 7 * scale),
            xRadius: 1 * scale, yRadius: 1 * scale)

        NSColor.black.setStroke()
        path.lineWidth = 1.0
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()

        image.unlockFocus()
        return image
    }
}

extension NSBezierPath {
    fileprivate var cgPath: CGPath {
        let path = CGMutablePath()
        let points = UnsafeMutablePointer<NSPoint>.allocate(capacity: 3)
        defer { points.deallocate() }
        for index in 0..<elementCount {
            let type = element(at: index, associatedPoints: points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            default:
                break
            }
        }
        return path
    }
}

extension PreviewSearchBar {
    override func layout() {
        super.layout()
        applyCornerMask()
    }
}

// MARK: - MPreviewView Search Extension
extension MPreviewView {
    private static var searchBarKey: UInt8 = 0
    private static var lastSearchTextKey: UInt8 = 0
    private static var searchMatchCountKey: UInt8 = 0
    private static var searchCurrentIndexKey: UInt8 = 0
    private static var searchTimerKey: UInt8 = 0
    private static var searchSequenceKey: UInt8 = 0
    private static var searchBarHeightConstraintKey: UInt8 = 0

    private var searchBar: PreviewSearchBar? {
        get {
            objc_getAssociatedObject(self, &MPreviewView.searchBarKey) as? PreviewSearchBar
        }
        set {
            objc_setAssociatedObject(self, &MPreviewView.searchBarKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private var lastSearchText: String {
        get {
            objc_getAssociatedObject(self, &MPreviewView.lastSearchTextKey) as? String ?? ""
        }
        set {
            objc_setAssociatedObject(self, &MPreviewView.lastSearchTextKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private var searchMatchCount: Int {
        get {
            objc_getAssociatedObject(self, &MPreviewView.searchMatchCountKey) as? Int ?? 0
        }
        set {
            objc_setAssociatedObject(self, &MPreviewView.searchMatchCountKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private var searchCurrentMatchIndex: Int {
        get {
            objc_getAssociatedObject(self, &MPreviewView.searchCurrentIndexKey) as? Int ?? 0
        }
        set {
            objc_setAssociatedObject(self, &MPreviewView.searchCurrentIndexKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private var searchTimer: Timer? {
        get {
            objc_getAssociatedObject(self, &MPreviewView.searchTimerKey) as? Timer
        }
        set {
            objc_setAssociatedObject(self, &MPreviewView.searchTimerKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private var searchSequence: Int {
        get {
            objc_getAssociatedObject(self, &MPreviewView.searchSequenceKey) as? Int ?? 0
        }
        set {
            objc_setAssociatedObject(self, &MPreviewView.searchSequenceKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private var searchBarHeightConstraint: NSLayoutConstraint? {
        get {
            objc_getAssociatedObject(self, &MPreviewView.searchBarHeightConstraintKey) as? NSLayoutConstraint
        }
        set {
            objc_setAssociatedObject(self, &MPreviewView.searchBarHeightConstraintKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    var isSearchBarVisible: Bool {
        searchBar != nil
    }

    private func getViewController() -> ViewController? {
        return self.window?.contentViewController as? ViewController
    }

    func showSearchBar(mode: PreviewSearchBar.Mode = .find) {
        if let existingBar = searchBar {
            existingBar.setMode(mode)

            let newHeight: CGFloat = (mode == .replace) ? 76 : 40
            searchBarHeightConstraint?.constant = newHeight

            existingBar.focusSearchField(selectAll: true)
            if !lastSearchText.isEmpty {
                performSearch(lastSearchText)
            }

            if let vc = getViewController(), existingBar.superview !== vc.view {
                existingBar.removeFromSuperview()
            } else if existingBar.superview != nil {
                return
            }
        }

        let bar = searchBar ?? PreviewSearchBar(frame: .zero)
        if searchBar == nil {
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.configureAppearance(baseColor: determineBackgroundColor())

            bar.onSearch = { [weak self] text in
                self?.scheduleSearch(text)
            }

            bar.onNext = { [weak self] in
                self?.findNext()
            }

            bar.onPrevious = { [weak self] in
                self?.findPrevious()
            }

            bar.onReplace = { [weak self] replaceText in
                self?.replaceNext(with: replaceText)
            }

            bar.onReplaceAll = { [weak self] replaceText in
                self?.replaceAll(with: replaceText)
            }

            bar.onClose = { [weak self] in
                self?.hideSearchBar()
            }
            searchBar = bar
        }

        bar.setMode(mode)

        var targetContainer: NSView?
        var layoutGuideView: NSView?

        if let vc = getViewController() {
            targetContainer = vc.view
            layoutGuideView = self.enclosingScrollView ?? self
        } else if let scrollView = self.enclosingScrollView, let parent = scrollView.superview {
            targetContainer = parent
            layoutGuideView = scrollView
        } else {
            targetContainer = self
            layoutGuideView = self
        }

        if let container = targetContainer, let guide = layoutGuideView {
            if bar.superview !== container {
                container.addSubview(bar)
                activateSearchBarConstraints(bar: bar, container: container, guide: guide, mode: mode)
            }
        }

        DispatchQueue.main.async {
            bar.focusSearchField(selectAll: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if !self.lastSearchText.isEmpty {
                    self.performSearch(self.lastSearchText)
                }
            }
        }
    }

    private func activateSearchBarConstraints(bar: NSView, container: NSView, guide: NSView, mode: PreviewSearchBar.Mode = .find) {
        let barHeight: CGFloat = (mode == .replace) ? 76 : 40
        let barWidth: CGFloat = 360
        let marginRight: CGFloat = 26
        let marginTop: CGFloat = 0

        let heightConstraint = bar.heightAnchor.constraint(equalToConstant: barHeight)
        searchBarHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: guide.topAnchor, constant: marginTop),
            bar.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -marginRight),
            bar.widthAnchor.constraint(equalToConstant: barWidth),
            heightConstraint,
        ])
    }

    func hideSearchBar() {
        searchTimer?.invalidate()
        searchTimer = nil
        clearSearchHighlights()
        searchBar?.removeFromSuperview()
        searchBar = nil
        lastSearchText = ""
        searchMatchCount = 0
        searchCurrentMatchIndex = 0
    }

    private func scheduleSearch(_ text: String) {
        // Cancel previous timer
        searchTimer?.invalidate()

        // If text is empty, clear immediately
        guard !text.isEmpty else {
            performSearch(text)
            return
        }

        // Schedule search with delay (0.15s for quick response)
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performSearch(text)
            }
        }
    }

    private func performSearch(_ text: String) {
        searchSequence += 1
        let currentSequence = searchSequence
        let shouldResetSelection = text != lastSearchText

        guard !text.isEmpty else {
            clearSearchHighlights()
            searchBar?.updateMatchInfo(current: 0, total: 0)
            lastSearchText = ""
            searchMatchCount = 0
            searchCurrentMatchIndex = 0
            return
        }

        let executeSearch: () -> Void = { [weak self] in
            guard
                let self,
                self.searchSequence == currentSequence
            else { return }

            self.lastSearchText = text
            if shouldResetSelection {
                self.searchCurrentMatchIndex = 0
            } else {
                self.searchCurrentMatchIndex = min(self.searchCurrentMatchIndex, max(self.searchMatchCount - 1, 0))
            }
            if #available(macOS 13.0, *) {
                self.performModernSearch(text, sequence: currentSequence, resetIndex: shouldResetSelection)
            } else {
                self.performJavaScriptSearch(text, sequence: currentSequence, resetIndex: shouldResetSelection)
            }
        }

        if shouldResetSelection {
            resetSearchSelection { [weak self] in
                guard
                    let self,
                    self.searchSequence == currentSequence
                else { return }
                executeSearch()
            }
        } else {
            executeSearch()
        }
    }

    @available(macOS 13.0, *)
    private func performModernSearch(_ text: String, sequence: Int, resetIndex: Bool) {
        let config = WKFindConfiguration()
        config.caseSensitive = false
        config.backwards = false
        config.wraps = true

        find(text, configuration: config) { [weak self] result in
            guard let self = self, self.searchSequence == sequence else { return }
            DispatchQueue.main.async {
                if result.matchFound {
                    self.countMatches(text, sequence: sequence, resetIndex: resetIndex)
                } else {
                    self.searchBar?.updateMatchInfo(current: 0, total: 0)
                }
            }
        }
    }

    private func performJavaScriptSearch(_ text: String, sequence: Int, resetIndex: Bool) {
        let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let script = """
            window.find('\(escapedText)', false, false, true, false, false, false);
            """

        evaluateJavaScript(script) { [weak self] _, _ in
            guard let self = self, self.searchSequence == sequence else { return }
            self.countMatches(text, sequence: sequence, resetIndex: resetIndex)
        }
    }

    private func countMatches(_ text: String, sequence: Int, resetIndex: Bool) {
        let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let script = """
            (function() {
                const text = '\(escapedText)';
                const regex = new RegExp(text, 'gi');
                const bodyText = document.body.innerText || document.body.textContent;
                const matches = bodyText.match(regex);
                return matches ? matches.length : 0;
            })();
            """

        evaluateJavaScript(script) { [weak self] result, _ in
            guard let self = self, self.searchSequence == sequence else { return }
            DispatchQueue.main.async {
                if let count = result as? Int {
                    self.searchMatchCount = count
                    if count == 0 {
                        self.searchCurrentMatchIndex = 0
                        self.searchBar?.updateMatchInfo(current: 0, total: 0)
                        return
                    }

                    if resetIndex {
                        self.searchCurrentMatchIndex = 0
                        self.focusFirstPreviewMatch(with: text)
                    } else if self.searchCurrentMatchIndex >= count {
                        self.searchCurrentMatchIndex = max(count - 1, 0)
                    }

                    self.searchBar?.updateMatchInfo(current: self.searchCurrentMatchIndex + 1, total: count)
                }
            }
        }
    }

    func findNext() {
        guard !lastSearchText.isEmpty, searchMatchCount > 0 else { return }

        searchCurrentMatchIndex = (searchCurrentMatchIndex + 1) % searchMatchCount
        searchBar?.updateMatchInfo(current: searchCurrentMatchIndex + 1, total: searchMatchCount)

        performWebFind(backwards: false)
    }

    func findPrevious() {
        guard !lastSearchText.isEmpty, searchMatchCount > 0 else { return }

        searchCurrentMatchIndex = (searchCurrentMatchIndex - 1 + searchMatchCount) % searchMatchCount
        searchBar?.updateMatchInfo(current: searchCurrentMatchIndex + 1, total: searchMatchCount)

        performWebFind(backwards: true)
    }

    func replaceNext(with replaceText: String) {
        guard let editArea = getViewController()?.editArea else { return }
        editArea.replaceNext(with: replaceText)
    }

    func replaceAll(with replaceText: String) {
        guard let editArea = getViewController()?.editArea else { return }
        editArea.replaceAll(with: replaceText)
    }

    private func performWebFind(backwards: Bool) {
        guard !lastSearchText.isEmpty else { return }

        if #available(macOS 13.0, *) {
            let config = WKFindConfiguration()
            config.caseSensitive = false
            config.backwards = backwards
            config.wraps = true

            find(lastSearchText, configuration: config) { _ in }
        } else {
            let escapedText = lastSearchText.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let script = "window.find('\(escapedText)', false, \(backwards ? "true" : "false"), true, false, false, false);"
            evaluateJavaScript(script, completionHandler: nil)
        }
    }

    private func focusFirstPreviewMatch(with text: String) {
        guard !text.isEmpty else { return }

        let escapedText =
            text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")

        let script = """
            (function() {
                const query = '\(escapedText)';
                if (!query) { return false; }
                const lowerQuery = query.toLowerCase();
                const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT, null);
                if (!walker) { return false; }
                const selection = window.getSelection();
                if (!selection) { return false; }
                while (walker.nextNode()) {
                    const node = walker.currentNode;
                    if (!node || !node.textContent) { continue; }
                    const textContent = node.textContent;
                    const index = textContent.toLowerCase().indexOf(lowerQuery);
                    if (index !== -1) {
                        const range = document.createRange();
                        range.setStart(node, index);
                        range.setEnd(node, index + query.length);
                        selection.removeAllRanges();
                        selection.addRange(range);
                        const element = node.parentElement || node.parentNode;
                        if (element && element.scrollIntoView) {
                            element.scrollIntoView({ block: 'center', behavior: 'auto' });
                        }
                        return true;
                    }
                }
                return false;
            })();
            """

        evaluateJavaScript(script, completionHandler: nil)
    }

    private func clearSearchHighlights() {
        let script = "window.getSelection().removeAllRanges();"
        evaluateJavaScript(script, completionHandler: nil)
    }

    private func resetSearchSelection(completion: @escaping () -> Void) {
        let script = """
            (function() {
                const selection = window.getSelection();
                if (!selection) { return false; }
                const root = document.body || document.documentElement;
                if (!root) { return false; }
                const range = document.createRange();
                range.selectNodeContents(root);
                range.collapse(true);
                selection.removeAllRanges();
                selection.addRange(range);
                return true;
            })();
            """
        evaluateJavaScript(script) { _, _ in
            completion()
        }
    }
}
