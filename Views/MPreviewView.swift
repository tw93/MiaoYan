import Carbon.HIToolbox
import PDFKit
import WebKit

#if os(iOS)
    import NightNight
#endif
public typealias MPreviewViewClosure = () -> Void
class MPreviewView: WKWebView, WKUIDelegate, WKNavigationDelegate {
    private weak var note: Note?
    private var closure: MPreviewViewClosure?
    public static var template: String?
    private var backgroundMask: NSView?
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
        configuration.suppressesIncrementalRendering = false
        // Basic WebKit configuration for quieter operation
        configuration.preferences.setValue(false, forKey: "developerExtrasEnabled")
        configuration.preferences.setValue(false, forKey: "javaScriptCanOpenWindowsAutomatically")
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        super.init(frame: frame, configuration: configuration)
        navigationDelegate = self
        #if os(OSX)
            setValue(false, forKey: "drawsBackground")
        #else
            isOpaque = false
            backgroundColor = UIColor.clear
            scrollView.backgroundColor = UIColor.clear
        #endif
        Self.ensureBundlePreinitialized()
        load(note: note)
        // Add background mask immediately when view hierarchy is ready
        DispatchQueue.main.async {
            self.addBackgroundMaskWhenNeeded()
        }
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    private func addBackgroundMaskWhenNeeded() {
        // Remove existing mask if any
        backgroundMask?.removeFromSuperview()
        backgroundMask = nil
        guard let container = self.superview else { return }
        // Create a large mask that covers the entire container
        // This will be behind the WebView and show when elastic scrolling reveals areas
        let maskView = NSView()
        maskView.wantsLayer = true
        maskView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        // Make the mask much larger than the container to cover all elastic scroll areas
        let containerBounds = container.bounds
        let expandedFrame = CGRect(
            x: containerBounds.minX - 500,
            y: containerBounds.minY - 500,
            width: containerBounds.width + 1000,
            height: containerBounds.height + 1000
        )
        maskView.frame = expandedFrame
        maskView.autoresizingMask = [.width, .height]
        // Add the mask behind the WebView - this is key!
        container.addSubview(maskView, positioned: .below, relativeTo: self)
        // Store reference for cleanup
        self.backgroundMask = maskView
    }
    override var isHidden: Bool {
        didSet {
            // Remove mask when preview is hidden (switching to edit mode)
            // Add mask when preview is shown (switching to preview mode)
            if isHidden {
                backgroundMask?.removeFromSuperview()
                backgroundMask = nil
            } else {
                // Re-add mask immediately when preview becomes visible
                DispatchQueue.main.async {
                    self.addBackgroundMaskWhenNeeded()
                }
            }
        }
    }
    override func removeFromSuperview() {
        // Clean up the background mask when preview view is removed
        backgroundMask?.removeFromSuperview()
        backgroundMask = nil
        super.removeFromSuperview()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == kVK_ANSI_C, event.modifierFlags.contains(.command) {
            DispatchQueue.main.async {
                self.evaluateJavaScript("document.execCommand('copy', false, null)", completionHandler: nil)
            }
            return false
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
    public func exportPdf() {
        guard let vc = ViewController.shared() else { return }
        guard #available(macOS 11.0, *) else {
            vc.toastExport(status: false)
            return
        }
        waitForImagesLoaded { [weak self] in
            guard let self else { return }
            getContentHeight { contentHeight in
                guard let height = contentHeight else {
                    vc.toastExport(status: false)
                    return
                }
                let pdfConfiguration = WKPDFConfiguration()
                pdfConfiguration.rect = CGRect(x: 0, y: 0, width: self.bounds.width, height: height)
                self.createPDF(configuration: pdfConfiguration) { result in
                    self.handlePDFExportResult(result, viewController: vc)
                }
            }
        }
    }
    private func waitForImagesLoaded(completion: @escaping () -> Void) {
        // Simplified: only wait for first 3 images, max 1 second
        var retryCount = 0
        func checkImages() {
            evaluateJavaScript("document.querySelectorAll('img[loading=\"eager\"]').length === 0 || Array.from(document.querySelectorAll('img[loading=\"eager\"]')).every(img => img.complete)") { result, _ in
                if let loaded = result as? Bool, loaded || retryCount > 10 {
                    completion()
                } else {
                    retryCount += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        checkImages()
                    }
                }
            }
        }
        checkImages()
    }
    // MARK: - Helper Methods
    private func getContentHeight(completion: @escaping (CGFloat?) -> Void) {
        evaluateJavaScript("document.body.scrollHeight") { height, error in
            guard let contentHeight = height as? CGFloat, error == nil else {
                completion(nil)
                return
            }
            completion(contentHeight)
        }
    }
    private func getContentDimensions(completion: @escaping (CGFloat, CGFloat) -> Void) {
        evaluateJavaScript("document.body.scrollHeight") { height, _ in
            guard let contentHeight = height as? CGFloat else { return }
            self.evaluateJavaScript("document.body.scrollWidth") { width, _ in
                guard let contentWidth = width as? CGFloat else { return }
                completion(contentHeight, contentWidth)
            }
        }
    }
    private func executeJavaScriptWhenReady(_ script: String, completion: (() -> Void)? = nil) {
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
    private func handlePDFExportResult(_ result: Result<Data, Error>, viewController: Any) {
        guard let vc = viewController as? ViewController else { return }
        switch result {
        case .success(let pdfData):
            saveToDownloads(data: pdfData, extension: "pdf", viewController: vc)
        case .failure:
            vc.toastExport(status: false)
        }
    }
    private func handleImageExportResult(image: NSImage?, error: Error?, viewController: Any) {
        guard let vc = viewController as? ViewController else { return }
        if let image {
            guard let desktopURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                vc.toastExport(status: false)
                return
            }
            let currentName = note?.getExportTitle() ?? "MiaoYan"
            let destinationURL = desktopURL.appendingPathComponent(currentName + ".png")
            do {
                try image.savePNGRepresentationToURL(url: destinationURL)
                vc.toastExport(status: true)
            } catch {
                vc.toastExport(status: false)
            }
        } else {
            vc.toastExport(status: false)
        }
    }
    private func saveToDownloads(content: String, extension: String, viewController: Any) {
        saveToDownloads(data: content.data(using: .utf8) ?? Data(), extension: `extension`, viewController: viewController)
    }
    private func saveToDownloads(data: Data, extension: String, viewController: Any) {
        guard let vc = viewController as? ViewController else { return }
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            vc.toastExport(status: false)
            return
        }
        let currentName = note?.getExportTitle() ?? "MiaoYan"
        let fileURL = downloadsURL.appendingPathComponent(currentName + "." + `extension`)
        do {
            try data.write(to: fileURL, options: .atomic)
            vc.toastExport(status: true)
        } catch {
            vc.toastExport(status: false)
        }
    }
    @available(macOS 11.0, *)
    private func combinePDFs(pdfDatas: [Data]) -> Data? {
        let pdfDocument = PDFDocument()
        for pdfData in pdfDatas {
            if let dataDocument = PDFDocument(data: pdfData) {
                for pageIndex in 0..<dataDocument.pageCount {
                    if let page = dataDocument.page(at: pageIndex) {
                        pdfDocument.insert(page, at: pdfDocument.pageCount)
                    }
                }
            }
        }
        return pdfDocument.dataRepresentation()
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
                    self.getContentDimensions { contentHeight, windowHeight in
                        let offset = contentHeight - windowHeight
                        if offset > 0 {
                            let scrollerTop = offset * pre
                            self.evaluateJavaScript("window.scrollTo({ top: \(scrollerTop), behavior: 'instant' })", completionHandler: nil)
                        }
                    }
                })
        }
    }
    public func exportHtml() {
        guard let vc = ViewController.shared() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.executeJavaScriptWhenReady(
                "",
                completion: {
                    self.evaluateJavaScript("document.documentElement.outerHTML.toString()") { html, error in
                        guard let contentHtml = html as? String, error == nil else {
                            vc.toastExport(status: false)
                            return
                        }
                        self.saveToDownloads(content: contentHtml, extension: "html", viewController: vc)
                    }
                })
        }
    }
    public func exportImage() {
        guard let vc = ViewController.shared() else { return }
        waitForImagesLoaded { [weak self] in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.executeJavaScriptWhenReady(
                    "",
                    completion: {
                        self.getContentDimensions { contentHeight, contentWidth in
                            let config = WKSnapshotConfiguration()
                            config.rect = CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
                            config.afterScreenUpdates = true
                            config.snapshotWidth = NSNumber(value: Double(contentWidth) * 2.0)
                            self.frame.size.height = contentHeight
                            self.takeSnapshot(with: config) { image, error in
                                self.handleImageExportResult(image: image, error: error, viewController: vc)
                            }
                        }
                    })
            }
        }
    }
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            return
        }
        switch navigationAction.navigationType {
        case .linkActivated:
            decisionHandler(.cancel)
            if isFootNotes(url: url) {
                return
            }
            #if os(iOS)
                UIApplication.shared.openURL(url)
            #elseif os(OSX)
                NSWorkspace.shared.open(url)
            #endif
        default:
            decisionHandler(.allow)
        }
    }
    public func load(note: Note, force: Bool = false) {
        let isFirstLoad = self.note == nil
        let shouldHideForTransition = isFirstLoad || force
        if shouldHideForTransition {
            self.alphaValue = 0.0
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let markdownString = note.getPrettifiedContent()
            let imagesStorage = note.project.url
            let css = HtmlManager.previewStyle()
            DispatchQueue.main.async {
                try? self.loadHTMLView(markdownString, css: css, imagesStorage: imagesStorage)
                self.note = note
                if shouldHideForTransition {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSAnimationContext.runAnimationGroup({ context in
                            context.duration = 0.2
                            self.animator().alphaValue = 1.0
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
        #if os(iOS)
            if NightNight.theme == .night {
                template = template.replacingOccurrences(of: "CUSTOM_CSS", with: "darkmode")
            }
        #else
            if UserDataService.instance.isDark {
                template = template.replacingOccurrences(of: "CUSTOM_CSS", with: "darkmode")
            }
        #endif
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
    func loadHTMLView(_ markdownString: String, css: String, imagesStorage: URL? = nil) throws {
        var htmlString = renderMarkdownHTML(markdown: markdownString)!
        if let imagesStorage {
            htmlString = loadImages(imagesStorage: imagesStorage, html: htmlString)
        }
        guard let vc = ViewController.shared() else { return }
        var pageHTMLString = try HtmlManager.htmlFromTemplate(htmlString, css: css, currentName: vc.titleLabel.stringValue)
        if UserDefaultsManagement.magicPPT {
            pageHTMLString = try HtmlManager.htmlFromTemplate(markdownString, css: css, currentName: vc.titleLabel.stringValue)
        }
        let indexURL = HtmlManager.createTemporaryBundle(pageHTMLString: pageHTMLString)
        if let i = indexURL {
            let accessURL = i.deletingLastPathComponent()
            loadFileURL(i, allowingReadAccessTo: accessURL)
        }
    }
    private static func ensureBundlePreinitialized() {
        guard !bundleInitialized else { return }
        initQueue.async {
            guard !Self.bundleInitialized else { return }
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
                    print("Bundle initialization error: \(error.localizedDescription)")
                }
            }
            Self.bundleInitialized = true
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
            i = i + 1
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
            vc.setDividerColor(for: vc.splitView, hidden: true)
            vc.setDividerColor(for: vc.sidebarSplitView, hidden: true)
            vc.titleLabel.backgroundColor = NSColor(named: "mainBackground")
        } else {
            vc.sidebarSplitView.setValue(NSColor(css: message), forKey: "dividerColor")
            vc.splitView.setValue(NSColor(css: message), forKey: "dividerColor")
        }
    }
}
