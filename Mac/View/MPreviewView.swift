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

    init(frame: CGRect, note: Note, closure: MPreviewViewClosure?) {
        self.closure = closure
        let userContentController = WKUserContentController()
        userContentController.add(HandlerCheckbox(), name: "checkbox")
        userContentController.add(HandlerSelection(), name: "newSelectionDetected")
        userContentController.add(HandlerCodeCopy(), name: "notification")
        userContentController.add(HandlerRevealBackgroundColor(), name: "revealBackgroundColor")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController

        super.init(frame: frame, configuration: configuration)

        navigationDelegate = self

        #if os(OSX)
            setValue(false, forKey: "drawsBackground")
        #else
            isOpaque = false
            backgroundColor = UIColor.clear
            scrollView.backgroundColor = UIColor.clear
        #endif

        load(note: note)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == kVK_ANSI_C, event.modifierFlags.contains(.command) {
            DispatchQueue.main.async {
                self.evaluateJavaScript("document.execCommand('copy', false, null)", completionHandler: nil)
            }
            return false
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
            if menuItem.identifier?.rawValue == "WKMenuItemIdentifierSpeechMenu" ||
                menuItem.identifier?.rawValue == "WKMenuItemIdentifierTranslate" ||
                menuItem.identifier?.rawValue == "WKMenuItemIdentifierSearchWeb" ||
                menuItem.identifier?.rawValue == "WKMenuItemIdentifierShareMenu" ||
                menuItem.identifier?.rawValue == "WKMenuItemIdentifierLookUp"
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
        let checkImagesScript = """
        (function() {
            var images = document.getElementsByTagName('img');
            var loadedCount = 0;
            var totalImages = images.length;

            if (totalImages === 0) {
                return true; // No images to load
            }

            for (var i = 0; i < totalImages; i++) {
                if (images[i].complete && images[i].naturalWidth > 0) {
                    loadedCount++;
                }
            }

            return loadedCount === totalImages;
        })();
        """

        let maxRetries = 100 // Maximum wait time: 10 seconds (100 * 0.1s)
        var retryCount = 0

        func checkImages() {
            evaluateJavaScript(checkImagesScript) { result, _ in
                if let allLoaded = result as? Bool, allLoaded {
                    completion()
                } else if retryCount < maxRetries {
                    retryCount += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        checkImages()
                    }
                } else {
                    // Timeout - proceed anyway to avoid infinite waiting
                    completion()
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
        evaluateJavaScript("document.readyState") { complete, _ in
            guard complete != nil else { return }

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
        guard let vc = viewController as? ViewController else { return }

        guard let path = NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first else {
            vc.toastExport(status: false)
            return
        }

        let currentName = note?.getExportTitle() ?? "MiaoYan"
        let filePath = path + "/" + currentName + "." + `extension`

        do {
            try content.write(to: URL(fileURLWithPath: filePath), atomically: true, encoding: .utf8)
            vc.toastExport(status: true)
        } catch {
            vc.toastExport(status: false)
        }
    }

    private func saveToDownloads(data: Data, extension: String, viewController: Any) {
        guard let vc = viewController as? ViewController else { return }

        guard let path = NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first else {
            vc.toastExport(status: false)
            return
        }

        let currentName = note?.getExportTitle() ?? "MiaoYan"
        let filePath = path + "/" + currentName + "." + `extension`
        let fileURL = URL(fileURLWithPath: filePath)

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
                for pageIndex in 0 ..< dataDocument.pageCount {
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
            self.executeJavaScriptWhenReady("", completion: {
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
            self.executeJavaScriptWhenReady("", completion: {
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
                self.executeJavaScriptWhenReady("", completion: {
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
        /// Do not re-load already loaded view
        guard self.note != note || force else {
            return
        }

        let markdownString = note.getPrettifiedContent()

        let imagesStorage = note.project.url
        let css = MarkdownView.getPreviewStyle()

        try? loadHTMLView(markdownString, css: css, imagesStorage: imagesStorage)

        self.note = note
    }

    private func getTemplate(css: String) -> String? {
        guard let bundle = getDownViewBundle(),
              let baseURL = getBaseURL(bundle: bundle)
        else {
            return nil
        }

        guard var template = try? String(contentsOf: baseURL, encoding: .utf8) else {
            return nil
        }

        if UserDefaultsManagement.magicPPT {
            return template
        }

        template = template.replacingOccurrences(of: "DOWN_CSS", with: css)

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

        var pageHTMLString = try htmlFromTemplate(htmlString, css: css)

        if UserDefaultsManagement.magicPPT {
            pageHTMLString = try htmlFromTemplate(markdownString, css: css)
        }

        print(">>>>>>")
        print(pageHTMLString)

        let indexURL = createTemporaryBundle(pageHTMLString: pageHTMLString)

        if let i = indexURL {
            let accessURL = i.deletingLastPathComponent()
            loadFileURL(i, allowingReadAccessTo: accessURL)
        }
    }

    func createTemporaryBundle(pageHTMLString: String) -> URL? {
        guard let bundle = getDownViewBundle(),
              let bundleResourceURL = bundle.resourceURL
        else {
            return nil
        }

        let customCSS = UserDefaultsManagement.markdownPreviewCSS

        let webkitPreview = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wkPreview")

        try? FileManager.default.createDirectory(at: webkitPreview, withIntermediateDirectories: true, attributes: nil)

        let indexURL = webkitPreview.appendingPathComponent("index.html")

        // If updating markdown contents, no need to re-copy bundle.
        if !FileManager.default.fileExists(atPath: indexURL.path) {
            // Copy bundle resources to temporary location.
            do {
                let fileList = try FileManager.default.contentsOfDirectory(atPath: bundleResourceURL.path)

                for file in fileList {
                    if customCSS != nil, file == "css" {
                        continue
                    }

                    let tmpURL = webkitPreview.appendingPathComponent(file)

                    try FileManager.default.copyItem(atPath: bundleResourceURL.appendingPathComponent(file).path, toPath: tmpURL.path)
                }
            } catch {
                print(error)
            }
        }

        if let customCSS {
            let cssDst = webkitPreview.appendingPathComponent("css")
            let styleDst = cssDst.appendingPathComponent("markdown-preview.css", isDirectory: false)

            do {
                try FileManager.default.createDirectory(at: cssDst, withIntermediateDirectories: false, attributes: nil)
                _ = try FileManager.default.copyItem(at: customCSS, to: styleDst)
            } catch {
                print(error)
            }
        }

        // Write generated index.html to temporary location.
        try? pageHTMLString.write(to: indexURL, atomically: true, encoding: .utf8)

        return indexURL
    }

    private func loadImages(imagesStorage: URL, html: String) -> String {
        return html.processLocalImages(with: imagesStorage)
    }

    func htmlFromTemplate(_ htmlString: String, css: String) throws -> String {
        guard let vc = ViewController.shared(),
              let bundle = getDownViewBundle(),
              let baseURL = getBaseURL(bundle: bundle)
        else {
            return ""
        }

        var template = try String(contentsOf: baseURL, encoding: .utf8)

        template = template.replacingOccurrences(of: "DOWN_CSS", with: css)

        let (fontPath, downMeta) = getFontPathAndMeta()
        template = template.replacingOccurrences(of: "DOWN_FONT_PATH", with: fontPath)
        template = template.replacingOccurrences(of: "DOWN_META", with: downMeta)

        if UserDefaultsManagement.isOnExport {
            template = template.replacingOccurrences(of: "DOWN_EXPORT_TYPE", with: "ppt")
        }

        if UserDefaultsManagement.magicPPT {
            let downTheme = getPPTTheme()
            template = template.replacingOccurrences(of: "DOWN_THEME", with: downTheme)

            let newHtmlString = htmlString.replacingOccurrences(of: "](/i/", with: "](./i/")
            return template.replacingOccurrences(of: "DOWN_RAW", with: newHtmlString)
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

        let htmlContent = getHtmlContent(htmlString, currentName: vc.titleLabel.stringValue)
        return template.replacingOccurrences(of: "DOWN_HTML", with: htmlContent)
    }
}

class HandlerCheckbox: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage)
    {
        guard let position = message.body as? String else { return }
        guard let note = EditTextView.note else { return }

        let content = note.content.unLoadCheckboxes().unLoadImages()
        let string = content.string
        let range = NSRange(0 ..< string.count)

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

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage)
    {
        let message = (message.body as! String).trimmingCharacters(in: .whitespacesAndNewlines)

        HandlerCodeCopy.selectionString = message
    }
}

class HandlerSelection: NSObject, WKScriptMessageHandler {
    public static var selectionString: String?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage)
    {
        let message = (message.body as! String).trimmingCharacters(in: .whitespacesAndNewlines)

        HandlerSelection.selectionString = message
    }
}

// Used to solve the adaptation of the left border/title color change with background color in PPT mode.
class HandlerRevealBackgroundColor: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage)
    {
        guard let vc = ViewController.shared() else { return }
        let message = (message.body as! String).trimmingCharacters(in: .whitespacesAndNewlines)
        if message == "" {
            vc.setDividerHidden(hidden: true)
            vc.setSideDividerHidden(hidden: true)
            vc.titleLabel.backgroundColor = NSColor(named: "mainBackground")
        } else {
            vc.sidebarSplitView.setValue(NSColor(css: message), forKey: "dividerColor")
            vc.splitView.setValue(NSColor(css: message), forKey: "dividerColor")
            vc.titleLabel.backgroundColor = NSColor(css: message)
        }
    }
}

// MARK: - Bundle and Resource Management Extensions

extension MPreviewView {
    private func getDownViewBundle() -> Bundle? {
        guard let path = Bundle.main.path(forResource: "DownView", ofType: ".bundle") else { return nil }
        return Bundle(url: URL(fileURLWithPath: path))
    }

    private func getBaseURL(bundle: Bundle) -> URL? {
        let resourceName = UserDefaultsManagement.magicPPT ? "ppt" : "index"
        return bundle.url(forResource: resourceName, withExtension: "html")
    }

    private func getFontPathAndMeta() -> (String, String) {
        if UserDefaultsManagement.isOnExportHtml {
            ("https://gw.alipayobjects.com/os/k/html2/Fonts",
             "<base href=\"https://gw.alipayobjects.com/os/k/html2/\">")
        } else {
            (Bundle.main.resourceURL?.path ?? "", "")
        }
    }

    private func getPPTTheme() -> String {
        let themeFile = UserDataService.instance.isDark ? "night.css" : "white.css"
        return "<link rel=\"stylesheet\" href=\"ppt/dist/theme/\(themeFile)\" id=\"theme\" />"
    }

    private func getHtmlContent(_ htmlString: String, currentName: String) -> String {
        if UserDefaultsManagement.isOnExport, !htmlString.hasPrefix("<h1>") {
            return "<h1>\(currentName)</h1>" + htmlString
        }
        return htmlString
    }
}
