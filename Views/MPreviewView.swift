import Carbon.HIToolbox
import WebKit

public typealias MPreviewViewClosure = () -> Void
@MainActor
class MPreviewView: WKWebView, WKUIDelegate {
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
    }

    private lazy var navigationProxy = NavigationDelegateProxy(owner: self)
    private weak var note: Note?
    private var closure: MPreviewViewClosure?
    public static var template: String?
    private static var bundleInitialized = false
    private static let initQueue = DispatchQueue(label: "preview.init", qos: .userInitiated)
    init(frame: CGRect, note: Note, closure: MPreviewViewClosure?) {
        self.closure = closure
        let userContentController = WKUserContentController()
        userContentController.add(HandlerCheckbox(), name: "checkbox")
        userContentController.add(HandlerSelection(), name: "newSelectionDetected")
        userContentController.add(HandlerCodeCopy(), name: "notification")
        userContentController.add(HandlerRevealBackgroundColor(), name: "revealBackgroundColor")
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

        // Auto-resize with parent view
        autoresizingMask = [.width, .height]

        // Keep the same background color between native and web layers
        setValue(false, forKey: "drawsBackground")
        wantsLayer = true
        let bgNSColor = determineBackgroundColor()
        layer?.backgroundColor = bgNSColor.cgColor
        layer?.isOpaque = false
        // Fill under-page area with the same color to cover rubber-banding gaps
        setValue(bgNSColor, forKey: "underPageBackgroundColor")
        if let hostingScrollView = subviews.compactMap({ $0 as? NSScrollView }).first {
            hostingScrollView.drawsBackground = false
            hostingScrollView.backgroundColor = bgNSColor
            // 禁用弹性滚动
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
        // No additional background mask needed
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        AppDelegate.trackError(NSError(domain: "InitError", code: 1, userInfo: [NSLocalizedDescriptionKey: "MPreviewView does not support NSCoder initialization"]), context: "MPreviewView.init")
        return nil
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

    // MARK: - Appearance Update
    // Appearance Update (kept for backward compatibility but not used)
    public func updateAppearance() {
        // This method is kept for compatibility but the new approach is to recreate the WebView
        // instead of trying to update its appearance, which is more reliable
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == kVK_ANSI_C, event.modifierFlags.contains(.command) {
            DispatchQueue.main.async {
                self.evaluateJavaScript("document.execCommand('copy', false, null)", completionHandler: nil)
            }
            return false
        }
        // Handle ESC in presentation modes
        // - PPT mode: exit PPT completely
        // - Presentation (preview fullscreen) mode: exit presentation and restore layout
        if event.keyCode == kVK_Escape, UserDefaultsManagement.presentation, !UserDefaultsManagement.magicPPT {
            DispatchQueue.main.async {
                if let vc = ViewController.shared() {
                    vc.disablePresentation()
                }
            }
            return true  // Consume the event to avoid only exiting fullscreen
        }
        // Handle ESC in PPT mode - exit PPT mode
        if event.keyCode == kVK_Escape, UserDefaultsManagement.magicPPT {
            DispatchQueue.main.async {
                if let vc = ViewController.shared() {
                    vc.disableMiaoYanPPT()
                }
            }
            return true  // Consume the event
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
        return super.performKeyEquivalent(with: event)
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
        closure?()

    }

    // MARK: - Helper Methods
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
        guard pre != 0.0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.executeJavaScriptWhenReady(
                "",
                completion: {
                    self.evaluateJavaScript("document.body.scrollHeight") { height, _ in
                        guard let contentHeight = height as? CGFloat else { return }
                        self.evaluateJavaScript("window.innerHeight") { windowHeight, _ in
                            guard let windowHeight = windowHeight as? CGFloat else { return }
                            let offset = contentHeight - windowHeight
                            if offset > 0 {
                                let scrollerTop = offset * pre
                                self.evaluateJavaScript("window.scrollTo({ top: \(scrollerTop), behavior: 'instant' })", completionHandler: nil)
                            }
                        }
                    }
                })
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
    public func load(note: Note, force: Bool = false) {
        let isFirstLoad = self.note == nil
        let shouldHideForTransition = isFirstLoad || force

        // For dark mode, maintain the dark background color during transition
        if shouldHideForTransition && UserDataService.instance.isDark {
            // Keep the background visible but hide content smoothly
            self.alphaValue = 0.9
        } else if shouldHideForTransition {
            self.alphaValue = 0.0
        }

        Task.detached { [weak self, note] in
            let markdownString = await note.getPrettifiedContent()
            let imagesStorage = await note.project.url
            let css = await HtmlManager.previewStyle()
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                do {
                    try self.loadHTMLView(markdownString, css: css, imagesStorage: imagesStorage)
                    self.note = note
                } catch {
                    AppDelegate.trackError(error, context: "MPreviewView.load")
                    // Fallback: try to load minimal content
                    let basicHTML = "<html><body><p>Failed to load preview</p></body></html>"
                    self.loadHTMLString(basicHTML, baseURL: nil)
                }

                if shouldHideForTransition {
                    // Reduced delay for smoother transition
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 50_000_000)  // 0.05 seconds
                        await NSAnimationContext.runAnimationGroup({ context in
                            context.duration = 0.15
                            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                            self?.animator().alphaValue = 1.0
                        })
                    }
                }
            }
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
        guard let htmlString = renderMarkdownHTML(markdown: markdownString) else {
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
            pageHTMLString = try HtmlManager.htmlFromTemplate(markdownString, css: css, currentName: vc.titleLabel.stringValue)
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
