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
    func previewDidScroll(line: CGFloat)
}

@MainActor
class MPreviewView: WKWebView, WKUIDelegate {
    private var scrollObserverInjected = false
    internal var isUpdatingContent = false
    nonisolated(unsafe) private var contentUpdateWorkItem: DispatchWorkItem?
    private var originalRedrawPolicy: NSView.LayerContentsRedrawPolicy?
    private var contentUpdateVersion: UInt = 0
    private(set) var hasLoadedTemplate = false
    /// True between `load()` calling `loadFileURL` and `webView(_:didFinish:)`
    /// firing. While true, the WKWebView is in the middle of swapping its DOM
    /// for the bundled template, so any incremental DOM mutation we run will
    /// be wiped when the navigation lands. Used by `updateContent` to defer
    /// split-view paste/typing updates until the template is actually live.
    private var isLoadingTemplate = false
    /// Set by `updateContent` when it is invoked while `isLoadingTemplate`
    /// is true. The didFinish handler consumes it to re-run the update once
    /// the template DOM is ready, otherwise rapid paste after entering
    /// split mode leaves the right pane stuck on the pre-paste content.
    private var pendingPostLoadUpdateNote: Note?
    /// Closures queued by callers (e.g. enablePreview's makeFirstResponder
    /// and scrollToPosition) that need the preview DOM to be ready first.
    /// Drained in webView(_:didFinish:). Replaces fixed asyncAfter timers
    /// that would either fire too early on slow loads or waste time on fast
    /// ones.
    private var postReadyCallbacks: [() -> Void] = []
    /// Whether this preview is currently rendered as the right pane of
    /// MiaoYan's split editor. Tracked locally so we can re-apply the
    /// `body.miaoyan-split-mode` class on every webView(_:didFinish:),
    /// because each `load(note:)` rebuilds the bundled HTML and the body
    /// element starts out without our class. Driven by setSplitChrome.
    private var splitChromeEnabled = false
    private var lastRendererInitializationTime: TimeInterval = 0
    static var hasCompletedInitialLoad = false
    private var loadCompletion: (() -> Void)?
    private var appDidBecomeActiveObserver: NSObjectProtocol?

    // MARK: - JavaScript Timing Constants

    private enum JavaScriptTiming {
        static let diagramInitDelay = 100  // milliseconds
        static let imageLoadTimeout: TimeInterval = 0.4  // WebView image load timeout
        static let diagramLoadTimeout: TimeInterval = 0.8  // Extended timeout for diagram rendering
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

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            owner?.webViewWebContentProcessDidTerminate(webView)
        }
    }

    private lazy var navigationProxy = NavigationDelegateProxy(owner: self)
    private weak var note: Note?
    private var closure: MPreviewViewClosure?
    public static var template: String?
    private static var bundleInitialized = false
    private static let initQueue = DispatchQueue(label: "preview.init", qos: .userInitiated)
    weak var scrollDelegate: MPreviewScrollDelegate?
    var displayedNote: Note? {
        note
    }

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
        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleApplicationDidBecomeActive()
            }
        }

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
            removeAppDidBecomeActiveObserver()
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
        // Source-line anchor sync: queries data-sourcepos attributes emitted by cmark-gfm
        // and builds a {line, top} index for binary-search interpolation (VS Code algorithm).
        let script = """
                (function() {
                    if (window.__miaoyanSync) { return; }
                    var anchors = [];
                    var rebuildTimer = null;
                    var rafId = null;
                    var lastReportedLine = -1;

                    function rebuildAnchors() {
                        var els = document.querySelectorAll('[data-sourcepos]');
                        var result = [];
                        for (var i = 0; i < els.length; i++) {
                            var el = els[i];
                            if (el.offsetHeight === 0) { continue; }
                            if (el.offsetParent === null && el !== document.body) { continue; }
                            var attr = el.getAttribute('data-sourcepos');
                            if (!attr) { continue; }
                            var line = parseInt(attr, 10);
                            if (isNaN(line) || line < 1) { continue; }
                            var top = el.getBoundingClientRect().top + window.scrollY;
                            result.push({ line: line, top: top });
                        }
                        result.sort(function(a, b) { return a.line - b.line; });
                        anchors = result;
                    }

                    function lineForScroll(scrollY) {
                        if (anchors.length === 0) { return 0; }
                        if (scrollY <= anchors[0].top) { return anchors[0].line; }
                        var last = anchors[anchors.length - 1];
                        if (scrollY >= last.top) { return last.line; }
                        var lo = 0, hi = anchors.length - 1;
                        while (lo + 1 < hi) {
                            var mid = (lo + hi) >> 1;
                            if (anchors[mid].top <= scrollY) { lo = mid; } else { hi = mid; }
                        }
                        var a = anchors[lo], b = anchors[hi];
                        if (b.top === a.top) { return a.line; }
                        return a.line + (b.line - a.line) * (scrollY - a.top) / (b.top - a.top);
                    }

                    function scrollToLine(line) {
                        if (anchors.length === 0) { return false; }
                        var first = anchors[0], last = anchors[anchors.length - 1];
                        if (line <= first.line) { window.scrollTo(0, first.top); return true; }
                        if (line >= last.line) { window.scrollTo(0, last.top); return true; }
                        var lo = 0, hi = anchors.length - 1;
                        while (lo + 1 < hi) {
                            var mid = (lo + hi) >> 1;
                            if (anchors[mid].line <= line) { lo = mid; } else { hi = mid; }
                        }
                        var a = anchors[lo], b = anchors[hi];
                        var frac = (b.line === a.line) ? 0 : (line - a.line) / (b.line - a.line);
                        window.scrollTo(0, a.top + (b.top - a.top) * frac);
                        return true;
                    }

                    function scheduleRebuild() {
                        if (rebuildTimer !== null) { clearTimeout(rebuildTimer); }
                        rebuildTimer = setTimeout(function() {
                            rebuildTimer = null;
                            rebuildAnchors();
                        }, 100);
                    }

                    window.__miaoyanSync = {
                        rebuild: function() { rebuildAnchors(); },
                        lineForScroll: lineForScroll,
                        scrollToLine: scrollToLine
                    };

                    if (document.readyState === 'loading') {
                        document.addEventListener('DOMContentLoaded', rebuildAnchors);
                    } else {
                        rebuildAnchors();
                    }
                    window.addEventListener('load', rebuildAnchors);
                    if (typeof ResizeObserver !== 'undefined') {
                        new ResizeObserver(scheduleRebuild).observe(document.body);
                    }

                    window.addEventListener('scroll', function() {
                        if (rafId !== null) { cancelAnimationFrame(rafId); }
                        rafId = requestAnimationFrame(function() {
                            rafId = null;
                            var scrollY = window.pageYOffset || 0;
                            var line = lineForScroll(scrollY);
                            if (Math.abs(line - lastReportedLine) > 0.1) {
                                window.webkit.messageHandlers.previewScroll.postMessage({ line: line });
                                lastReportedLine = line;
                            }
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

    func determineBackgroundColor() -> NSColor {
        if UserDefaultsManagement.appearanceType == .Custom {
            return UserDefaultsManagement.bgColor
        }

        return determineDarkTheme() ? Theme.previewDarkBackgroundColor : Theme.backgroundColor
    }

    public func updateAppearance() {
        let isDark = determineDarkTheme()
        self.appearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        let js = """
                (function() {
                    var body = document.body;
                    if (!body) return;
                    body.classList.remove('darkmode', 'lightmode');
                    body.classList.add('\(isDark ? "darkmode" : "lightmode")');
                })();
            """
        evaluateJavaScript(js, completionHandler: nil)
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

        if event.keyCode == kVK_Escape {
            if let vc = AppContext.shared.viewController {
                if vc.sessionMagicPPTMode {
                    DispatchQueue.main.async {
                        vc.disableMiaoYanPPT()
                    }
                    return true
                } else if vc.sessionPresentationMode {
                    DispatchQueue.main.async {
                        vc.disablePresentation()
                    }
                    return true
                }
            }
        }

        if event.keyCode == kVK_Space,
            let vc = AppContext.shared.viewController,
            vc.sessionMagicPPTMode
        {
            DispatchQueue.main.async {
                self.evaluateJavaScript("Reveal.next();", completionHandler: nil)
            }
            return false
        }

        if let vc = AppContext.shared.viewController, vc.sessionMagicPPTMode {
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
        isLoadingTemplate = false
        closure?()
        loadCompletion?()
        loadCompletion = nil

        // Re-apply split-mode chrome on every fresh template. load(note:)
        // rebuilds the page from index.html so the body class set by an
        // earlier setSplitChrome call gets reset. Inject again here while
        // the cached state says we're still in split mode.
        if splitChromeEnabled {
            evaluateJavaScript(
                "document.body.classList.add('miaoyan-split-mode');",
                completionHandler: nil)
        }

        // Set up scroll observation after WebView is fully loaded
        setupScrollObserver()
        showTOCTipIfNeeded()

        // Drain any updateContent calls that arrived while the template was
        // still loading (typical: user pastes immediately after entering
        // split mode or after switching notes). Without this, the split
        // pane stays stuck on whatever the bundled template rendered with
        // the pre-paste note.content snapshot.
        if let pending = pendingPostLoadUpdateNote {
            pendingPostLoadUpdateNote = nil
            updateContent(note: pending, preserveScroll: false)
        }

        // Drain any post-ready callbacks queued by enablePreview etc.
        let callbacks = postReadyCallbacks
        postReadyCallbacks.removeAll()
        for cb in callbacks {
            cb()
        }
    }

    /// Runs the closure once the preview DOM is ready. If we are already
    /// past `webView(_:didFinish:)` for the current template, the closure
    /// fires immediately on the main actor; otherwise it is queued and
    /// drained when didFinish lands. Replaces fixed asyncAfter delays
    /// scattered across mode-transition code.
    public func runWhenPreviewReady(_ block: @escaping () -> Void) {
        if hasLoadedTemplate && !isLoadingTemplate {
            block()
        } else {
            postReadyCallbacks.append(block)
        }
    }

    /// Toggle the `body.miaoyan-split-mode` class so base.css can hide the
    /// WebKit-rendered scrollbar while the preview is the right pane of the
    /// split editor. The state is also persisted on `splitChromeEnabled` so
    /// `webView(_:didFinish:)` can re-apply it after every full template
    /// reload (note switch in split mode triggers a fresh load).
    public func setSplitChrome(_ enabled: Bool) {
        splitChromeEnabled = enabled
        let script =
            enabled
            ? "document.body.classList.add('miaoyan-split-mode');"
            : "document.body.classList.remove('miaoyan-split-mode');"
        runWhenPreviewReady { [weak self] in
            self?.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    /// Toggle the in-preview table-of-contents panel. The TOC itself lives in
    /// the preview's JavaScript (`window.MiaoYanTOC`, see common.js); this
    /// just drives it from the menu / keyboard. No-op in PPT mode where the
    /// reveal.js template has no TOC.
    public func toggleTOC() {
        runWhenPreviewReady { [weak self] in
            self?.evaluateJavaScript(
                "window.MiaoYanTOC && window.MiaoYanTOC.toggle();", completionHandler: nil)
        }
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        AppDelegate.trackError(NSError(domain: "WKWebViewError", code: 1, userInfo: [NSLocalizedDescriptionKey: "WebContent process terminated"]), context: "MPreviewView.WebContentTerminated")

        if let note = self.note {
            // Reload the view explicitly
            self.load(note: note, force: true)
        }
    }

    // MARK: - Helper Methods
    func resetTemplateState() {
        hasLoadedTemplate = false
    }

    func resetPreviewStateForReuse() {
        contentUpdateVersion &+= 1
        contentUpdateWorkItem?.cancel()
        contentUpdateWorkItem = nil
        loadCompletion = nil
        isUpdatingContent = false
        scrollObserverInjected = false
        hasLoadedTemplate = false
        isLoadingTemplate = false
        pendingPostLoadUpdateNote = nil
        postReadyCallbacks.removeAll()
        splitChromeEnabled = false
        note = nil
        stopLoading()
    }

    private func buildUpdateScript(html: String, initializeMath: Bool, initializeDiagrams: Bool, preserveScroll: Bool) -> String {
        var initScripts: [String] = []

        if initializeMath {
            initScripts.append(
                """
                    if (typeof renderMathInElement === 'function') {
                        const renderMath = () => {
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
                        };

                        if ('requestIdleCallback' in window) {
                            requestIdleCallback(renderMath, { timeout: 100 });
                        } else {
                            setTimeout(renderMath, 0);
                        }
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

        // Always re-initialize lazy loading after content update
        initScripts.append(
            """
                if (window.MiaoYanCommon && typeof window.MiaoYanCommon.optimizeImages === 'function') {
                    window.MiaoYanCommon.optimizeImages();
                }
            """)

        let initialization = initScripts.joined(separator: "\n")

        return """
                (function() {
                    const container = document.querySelector('.markdown-body') || document.body;
                    if (!container) return;

                    const preserveScroll = \(preserveScroll ? "true" : "false");
                    let savedLine = 0;
                    let usedAnchorScroll = false;

                    if (preserveScroll && window.__miaoyanSync) {
                        savedLine = window.__miaoyanSync.lineForScroll(window.pageYOffset || 0);
                        usedAnchorScroll = true;
                    } else if (preserveScroll) {
                        // Fallback: ratio-based save when anchor index not yet built
                        const doc = document.scrollingElement || document.documentElement || document.body;
                        const maxScroll = Math.max(0, (doc.scrollHeight || document.body.scrollHeight) - window.innerHeight);
                        savedLine = maxScroll > 0 ? (window.pageYOffset || doc.scrollTop || 0) / maxScroll : 0;
                    }

                    container.innerHTML = `\(html)`;
                    \(initialization)

                    if (preserveScroll) {
                        requestAnimationFrame(() => {
                            if (usedAnchorScroll && window.__miaoyanSync) {
                                window.__miaoyanSync.rebuild();
                                window.__miaoyanSync.scrollToLine(savedLine);
                            } else if (!usedAnchorScroll) {
                                // Ratio fallback
                                const newDoc = document.scrollingElement || document.documentElement || document.body;
                                const newMaxScroll = Math.max(0, (newDoc.scrollHeight || document.body.scrollHeight) - window.innerHeight);
                                window.scrollTo(0, newMaxScroll * savedLine);
                            }
                        });
                    } else {
                        requestAnimationFrame(() => { window.scrollTo(0, 0); });
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
        // Wait for the preview's WKNavigation to actually finish rather than
        // hard-coding 1.0s. Reveal.js is reachable as soon as the bundle
        // navigation lands; the previous fixed timer either fired before
        // Reveal was defined (silently failed) or wasted ~700ms after it.
        runWhenPreviewReady { [weak self] in
            self?.evaluateJavaScript("Reveal.slide(\(index));", completionHandler: nil)
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
        self.evaluateJavaScript(script) { _, error in
            #if DEBUG
                if let error = error { print("[ScrollSync] scrollToPosition error: \(error.localizedDescription)") }
            #endif
        }
    }

    public func scrollToLine(_ line: CGFloat, fallbackRatio: CGFloat? = nil) {
        let clampedFallback = fallbackRatio.map { Double(max(min($0, 1), 0)) }
        let fallback = clampedFallback.map { String($0) } ?? "null"
        let script = """
                (function() {
                    const fallbackRatio = \(fallback);
                    const canUseLineSync = window.__miaoyanSync && typeof window.__miaoyanSync.scrollToLine === 'function';
                    const didScroll = canUseLineSync ? window.__miaoyanSync.scrollToLine(\(line)) : false;
                    if (!didScroll && fallbackRatio !== null) {
                        const doc = document.scrollingElement || document.documentElement || document.body;
                        const maxScroll = Math.max(0, (doc.scrollHeight || document.body.scrollHeight) - window.innerHeight);
                        window.scrollTo(0, maxScroll * fallbackRatio);
                    }
                })();
            """
        evaluateJavaScript(script) { _, error in
            #if DEBUG
                if let error = error { print("[ScrollSync] scrollToLine error: \(error.localizedDescription)") }
            #endif
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
        // Mark the template-load window. updateContent will defer until this
        // clears in webView(_:didFinish:) so split-view edits made during the
        // load don't get wiped by the bundle's DOM replacement.
        isLoadingTemplate = true
        // Drop any deferred update that was queued for a different note;
        // we're about to load a new template that supersedes it.
        if let pending = pendingPostLoadUpdateNote, pending !== note {
            pendingPostLoadUpdateNote = nil
        }
        Task { @MainActor [weak self, note] in
            guard let self else { return }
            let markdownString = note.getPrettifiedContent()
            let imagesStorage = note.project.url
            let css = HtmlManager.previewStyle()
            let useGithubLineBreak = UserDefaultsManagement.editorLineBreak == "Github"
            let isMagicPPT = UserDefaultsManagement.magicPPT

            // Move markdown rendering and image processing to background thread
            let rendered: (processedHtml: String, processedMarkdown: String?)? = await Task.detached {
                if isMagicPPT {
                    let processedMarkdown = HtmlManager.processImagesInMarkdown(markdownString, imagesStorage: imagesStorage)
                    return (processedMarkdown, processedMarkdown)
                }
                guard let html = renderMarkdownHTML(markdown: markdownString, useGithubLineBreak: useGithubLineBreak) else {
                    return nil
                }
                let processed = HtmlManager.processImages(in: html, imagesStorage: imagesStorage)
                return (processed, nil)
            }.value

            guard let rendered else {
                self.hasLoadedTemplate = false
                self.isLoadingTemplate = false
                // Drop queued post-ready callbacks so they don't fire against
                // the next, unrelated template (slideTo with a stale index,
                // makeFirstResponder on a webview that displays a different
                // note).
                self.postReadyCallbacks.removeAll()
                self.pendingPostLoadUpdateNote = nil
                AppDelegate.trackError(
                    NSError(
                        domain: "MarkdownRenderError", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to render markdown in load"]),
                    context: "MPreviewView.load")
                self.loadHTMLString("<html><body><p>Failed to load preview</p></body></html>", baseURL: nil)
                return
            }

            do {
                guard let vc = AppContext.shared.viewController else { return }
                let pageHTMLString = try HtmlManager.htmlFromTemplate(
                    rendered.processedHtml, css: css, currentName: vc.titleLabel.stringValue)
                guard let indexURL = HtmlManager.createTemporaryBundle(pageHTMLString: pageHTMLString) else {
                    throw PreviewError.temporaryBundleCreationFailed
                }
                self.loadFileURL(indexURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
                self.hasLoadedTemplate = true
                self.note = note
            } catch {
                self.hasLoadedTemplate = false
                self.isLoadingTemplate = false
                self.postReadyCallbacks.removeAll()
                self.pendingPostLoadUpdateNote = nil
                AppDelegate.trackError(error, context: "MPreviewView.load")
                self.loadHTMLString("<html><body><p>Failed to load preview</p></body></html>", baseURL: nil)
            }
        }
    }

    // Lightweight content update for split view (preserves scroll position)
    public func updateContent(note: Note, preserveScroll: Bool = true) {
        Task { @MainActor [weak self, note] in
            guard let self else { return }
            self.contentUpdateVersion &+= 1
            let updateVersion = self.contentUpdateVersion

            self.contentUpdateWorkItem?.cancel()
            self.contentUpdateWorkItem = nil

            if let currentNote = self.note, currentNote !== note {
                self.isUpdatingContent = false
                self.load(note: note, force: true)
                return
            }

            // Defer if the template is still loading. Running the incremental
            // DOM mutation now would either no-op (no .markdown-body yet) or
            // be overwritten when the bundle's index.html navigation lands.
            // didFinish picks up pendingPostLoadUpdateNote and re-runs us
            // against the freshly-rendered DOM with the latest note.content
            // (which by then includes whatever the user just pasted/typed).
            if self.isLoadingTemplate || !self.hasLoadedTemplate {
                self.pendingPostLoadUpdateNote = note
                self.isUpdatingContent = false
                return
            }

            self.isUpdatingContent = true

            let markdownString = note.getPrettifiedContent()
            let imagesStorage = note.project.url
            let useGithubLineBreak = UserDefaultsManagement.editorLineBreak == "Github"

            // Phase 1: Render Markdown only (fast, ~20ms) — inject immediately so text is visible
            let htmlString = await Task.detached {
                renderMarkdownHTML(markdown: markdownString, useGithubLineBreak: useGithubLineBreak)
            }.value

            guard let htmlString else {
                AppDelegate.trackError(
                    NSError(
                        domain: "MarkdownRenderError", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to render markdown in updateContent"]),
                    context: "MPreviewView.updateContent"
                )
                self.isUpdatingContent = false
                self.contentUpdateWorkItem = nil
                self.load(note: note, force: true)
                return
            }
            guard updateVersion == self.contentUpdateVersion else {
                self.isUpdatingContent = false
                return
            }

            // Detect special content on unescaped HTML to avoid false positives
            let needsMath = htmlString.contains("$$") || htmlString.contains("$")
            let needsDiagrams =
                htmlString.contains("language-mermaid")
                || htmlString.contains("language-plantuml")
                || htmlString.contains("language-markmap")

            let rawEscaped =
                htmlString
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            let now = Date().timeIntervalSince1970
            let shouldInitializeSpecialRenderers =
                (needsMath || needsDiagrams)
                && (!preserveScroll || now - self.lastRendererInitializationTime > 0.8)
            if shouldInitializeSpecialRenderers {
                self.lastRendererInitializationTime = now
            }

            let phase1Script = self.buildUpdateScript(
                html: rawEscaped,
                initializeMath: shouldInitializeSpecialRenderers && needsMath,
                initializeDiagrams: shouldInitializeSpecialRenderers && needsDiagrams,
                preserveScroll: preserveScroll
            )

            do {
                _ = try await self.evaluateJavaScript(phase1Script)
            } catch {
                AppDelegate.trackError(error, context: "MPreviewView.updateContent.phase1")
                self.isUpdatingContent = false
                self.contentUpdateWorkItem = nil
                self.load(note: note, force: true)
                return
            }

            self.setupScrollObserver()

            // Phase 2: Process image paths in background (~50-200ms) — patch srcs without DOM rebuild
            guard updateVersion == self.contentUpdateVersion else {
                self.isUpdatingContent = false
                return
            }
            self.note = note

            let processedHtml = await Task.detached {
                HtmlManager.processImages(in: htmlString, imagesStorage: imagesStorage)
            }.value

            guard updateVersion == self.contentUpdateVersion else {
                self.isUpdatingContent = false
                return
            }

            if processedHtml != htmlString {
                let patchScript = MPreviewView.buildImagePatchScript(processedHtml: processedHtml)
                do {
                    _ = try await self.evaluateJavaScript(patchScript)
                } catch {
                    AppDelegate.trackError(error, context: "MPreviewView.updateContent.phase2")
                }
            }

            self.isUpdatingContent = false
            self.contentUpdateWorkItem = nil
        }
    }

    // Patch image src attributes in place without rebuilding the DOM.
    // processedHtml contains the final img src / data-src values in document order.
    private static func buildImagePatchScript(processedHtml: String) -> String {
        struct ImgUpdate {
            let src: String
            let isLazy: Bool
        }

        var updates: [ImgUpdate] = []
        let pattern = #"<img\s[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return ""
        }
        let ns = processedHtml as NSString
        let matches = regex.matches(in: processedHtml, range: NSRange(location: 0, length: ns.length))

        let srcRegex = try? NSRegularExpression(pattern: #"\bsrc="([^"]*)""#)
        let dataSrcRegex = try? NSRegularExpression(pattern: #"\bdata-src="([^"]*)""#)
        let lazyRegex = try? NSRegularExpression(pattern: #"\blazy-image\b"#)

        for match in matches {
            let tag = ns.substring(with: match.range)
            let tagNS = tag as NSString
            let tagRange = NSRange(location: 0, length: tagNS.length)

            let isLazy = lazyRegex?.firstMatch(in: tag, range: tagRange) != nil

            if isLazy,
                let m = dataSrcRegex?.firstMatch(in: tag, range: tagRange),
                let r = Range(m.range(at: 1), in: tag)
            {
                updates.append(ImgUpdate(src: String(tag[r]), isLazy: true))
            } else if let m = srcRegex?.firstMatch(in: tag, range: tagRange),
                let r = Range(m.range(at: 1), in: tag)
            {
                updates.append(ImgUpdate(src: String(tag[r]), isLazy: false))
            }
        }

        guard !updates.isEmpty else { return "" }

        let lazyPlaceholder = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
        var jsonParts: [String] = []
        for u in updates {
            let escapedSrc = u.src
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            jsonParts.append("{\"src\":\"\(escapedSrc)\",\"lazy\":\(u.isLazy ? "true" : "false")}")
        }
        let jsonArray = "[" + jsonParts.joined(separator: ",") + "]"

        return """
            (function() {
                const container = document.querySelector('.markdown-body') || document.body;
                const imgs = container.querySelectorAll('img');
                const updates = \(jsonArray);
                const placeholder = '\(lazyPlaceholder)';
                updates.forEach(function(u, i) {
                    if (i >= imgs.length) return;
                    const img = imgs[i];
                    if (u.lazy) {
                        img.setAttribute('data-src', u.src);
                        img.src = placeholder;
                        img.classList.add('lazy-image');
                    } else {
                        img.src = u.src;
                        img.classList.remove('lazy-image');
                        img.removeAttribute('data-src');
                    }
                });
                if (window.MiaoYanCommon) window.MiaoYanCommon.optimizeImages();
            })();
            """
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
        let webkitPreviewDir = HtmlManager.previewBundleURL().absoluteString

        let urlString = url.absoluteString
        if urlString.starts(with: webkitPreviewDir) && urlString.contains("#") {
            if let hashRange = urlString.range(of: "#") {
                let anchor = String(urlString[hashRange.upperBound...])
                if !anchor.isEmpty {
                    let javascript = "document.getElementById('\(anchor)').offsetTop"
                    evaluateJavaScript(javascript) { [weak self] result, _ in
                        if let offset = result as? CGFloat {
                            self?.evaluateJavaScript("window.scrollTo(0,\(offset))", completionHandler: nil)
                        }
                    }
                    return true
                }
            }
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

        guard let vc = AppContext.shared.viewController else {
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
            _ = HtmlManager.ensurePreviewResourcesAvailable()
            Self.bundleInitialized = true
        }
    }

    @MainActor
    private func handleApplicationDidBecomeActive() {
        guard hasLoadedTemplate else { return }
        guard HtmlManager.ensurePreviewResourcesAvailable() else { return }
        guard let note else { return }
        load(note: note, force: true)
    }

    @MainActor
    private func removeAppDidBecomeActiveObserver() {
        guard let appDidBecomeActiveObserver else { return }
        NotificationCenter.default.removeObserver(appDidBecomeActiveObserver)
        self.appDidBecomeActiveObserver = nil
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
