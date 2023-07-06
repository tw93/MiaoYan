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
                menuItem.identifier?.rawValue == "WKMenuItemIdentifierLookUp" {
                menuItem.isHidden = true
            }
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        closure?()
    }

    public func exportPdf() {
        guard let vc = ViewController.shared() else { return }
        // 获取 WKWebView 的内容大小
        var a4Size = CGSize(width: 800, height: 1120)
        if UserDefaultsManagement.isOnExportPPT {
            a4Size = CGSize(width: 1536, height: 957)
        }

        let pageWidth = a4Size.width
        let maxHeight: CGFloat = 14355.0

        super.frame.size.width = pageWidth

        super.evaluateJavaScript("document.body.scrollHeight", completionHandler: { height, error in
            guard let height = height as? CGFloat, error == nil else {
                vc.toastExport(status: false)
                return
            }
            if #available(macOS 11.0, *) {
                let numberOfParts = Int(ceil(height / maxHeight))
                let newDocument = PDFDocument()

                // 设置 PDF 分页
                func processPart(_ partIndex: Int) {
                    let partY = CGFloat(partIndex) * maxHeight
                    let partHeight = min(maxHeight, height - partY)

                    let pdfConfiguration = WKPDFConfiguration()
                    pdfConfiguration.rect = CGRect(x: 0, y: partY, width: super.bounds.width, height: partHeight)

                    super.createPDF(configuration: pdfConfiguration) { result in
                        switch result {
                        case .success(let pdfData):
                            // 使用 PDFKit 进行分页

                            let pdfDocument = PDFDocument(data: pdfData)

                            for i in 0 ..< (pdfDocument?.pageCount ?? 0) {
                                guard let page = pdfDocument?.page(at: i) else {
                                    return
                                }

                                let pageBounds = page.bounds(for: .cropBox)
                                let subPageCount = Int(ceil(pageBounds.height / a4Size.height))

                                for j in 0 ..< subPageCount {
                                    let subPageRect = CGRect(x: 0, y: CGFloat(subPageCount - j - 1) * a4Size.height, width: pageWidth, height: a4Size.height)

                                    guard let subPage = page.copy() as? PDFPage else {
                                        return
                                    }

                                    subPage.setBounds(subPageRect, for: .cropBox)
                                    newDocument.insert(subPage, at: newDocument.pageCount)
                                }
                            }

                            if partIndex < numberOfParts - 1 {
                                processPart(partIndex + 1)
                            } else {
                                if let newPDFData = newDocument.dataRepresentation() {
                                    if let path = NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first {
                                        vc.toastExport(status: true)
                                        let currentName = self.note?.getExportTitle()
                                        let filePath: String = path + "/" + (currentName ?? "MiaoYan") + ".pdf"
                                        try! newPDFData.write(to: URL(fileURLWithPath: filePath))
                                    }

                                } else {}
                            }

                        case .failure:
                            vc.toastExport(status: false)
                            return
                        }
                    }
                }

                processPart(0)

            } else {
                // Fallback on earlier versions
                vc.toastExport(status: false)
            }
        })
    }

    public func slideTo(index: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            super.evaluateJavaScript("document.readyState", completionHandler: { complete, _ in
                if complete != nil {
                    let javascript = "Reveal.slide(\(index));"
                    self.evaluateJavaScript(javascript, completionHandler: nil)
                }
            })
        }
    }

    public func scrollToPosition(pre: CGFloat) {
        if pre == 0.0 { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            super.evaluateJavaScript("document.readyState", completionHandler: { complete, _ in
                if complete != nil {
                    super.evaluateJavaScript("document.body.offsetHeight", completionHandler: { height, _ in
                        guard let contentHeight = height as? CGFloat else {
                            print("Content height could not be obtained"); return
                        }
                        super.evaluateJavaScript("document.documentElement.clientHeight", completionHandler: { [weak self] wHeight, _ in
                            let windowHeight = wHeight as! CGFloat
                            let offset = contentHeight - windowHeight
                            if offset > 0 {
                                let scrollerTop = offset * pre
                                self?.evaluateJavaScript("window.scrollTo({ top: \(scrollerTop), behavior: 'instant' })", completionHandler: nil)
                            }
                        })
                    })
                }
            })
        }
    }

    public func exportHtml() {
        guard let vc = ViewController.shared() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            super.evaluateJavaScript("document.readyState", completionHandler: { complete, _ in
                if complete != nil {
                    super.evaluateJavaScript("document.documentElement.outerHTML.toString()", completionHandler: { html, _ in
                        guard let contentHtml = html as? String else {
                            print("Content html could not be obtained"); return
                        }
                        if let path = NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first {
                            let currentName = self.note?.getExportTitle()
                            let filePath: String = path + "/" + (currentName ?? "MiaoYan") + ".html"
                            try! contentHtml.write(to: URL(fileURLWithPath: filePath), atomically: false, encoding: .utf8)
                            vc.toastExport(status: true)
                        }
                    })
                }
            })
        }
    }

    public func exportImage() {
        guard let vc = ViewController.shared() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            super.evaluateJavaScript("document.readyState", completionHandler: { complete, _ in
                if complete != nil {
                    super.evaluateJavaScript("document.body.offsetHeight", completionHandler: { height, _ in
                        guard let contentHeight = height as? CGFloat else {
                            print("Content height could not be obtained"); return
                        }
                        super.evaluateJavaScript("document.body.offsetWidth", completionHandler: { [weak self] width, _ in
                            if let contentWidth = width as? CGFloat {
                                let config = WKSnapshotConfiguration()
                                config.rect = CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
                                config.afterScreenUpdates = false
                                self?.frame.size.height = contentHeight
                                self?.takeSnapshot(with: config, completionHandler: { image, error in
                                    if let image = image {
                                        if let desktopURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                                            let currentName = self?.note?.getExportTitle()
                                            let destinationURL = desktopURL.appendingPathComponent(currentName! + ".jpeg")
                                            try! image.saveJPEGRepresentationToURL(url: destinationURL)
                                        }
                                        vc.toastExport(status: true)
                                        print("Got snapshot")
                                    } else {
                                        print("Failed taking snapshot: \(error?.localizedDescription ?? "--")")
                                        vc.toastExport(status: false)
                                    }
                                })
                            }
                        })
                    })
                }
            })
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

        cleanCache()
        try? loadHTMLView(markdownString, css: css, imagesStorage: imagesStorage)

        self.note = note
    }

    public func cleanCache() {
        URLCache.shared.removeAllCachedResponses()

        HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)

        WKWebsiteDataStore.default().fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            records.forEach { record in
                WKWebsiteDataStore.default().removeData(ofTypes: record.dataTypes, for: [record], completionHandler: {})
            }
        }
    }

    private func getTemplate(css: String) -> String? {
        let path = Bundle.main.path(forResource: "DownView", ofType: ".bundle")
        let url = NSURL.fileURL(withPath: path!)
        let bundle = Bundle(url: url)
        var baseURL = bundle!.url(forResource: "index", withExtension: "html")!

        if UserDefaultsManagement.magicPPT {
            baseURL = bundle!.url(forResource: "ppt", withExtension: "html")!
        }

        guard var template = try? NSString(contentsOf: baseURL, encoding: String.Encoding.utf8.rawValue) else {
            return nil
        }

        if UserDefaultsManagement.magicPPT {
            return template as String
        }

        template = template.replacingOccurrences(of: "DOWN_CSS", with: css) as NSString

        #if os(iOS)
            if NightNight.theme == .night {
                template = template.replacingOccurrences(of: "CUSTOM_CSS", with: "darkmode") as NSString
            }
        #else
            if UserDataService.instance.isDark {
                template = template.replacingOccurrences(of: "CUSTOM_CSS", with: "darkmode") as NSString
            }
        #endif

        return template as String
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

        if let imagesStorage = imagesStorage {
            htmlString = loadImages(imagesStorage: imagesStorage, html: htmlString)
        }

        var pageHTMLString = try htmlFromTemplate(htmlString, css: css)

        if UserDefaultsManagement.magicPPT {
            pageHTMLString = try htmlFromTemplate(markdownString, css: css)
        }

//        print(">>>>>>")
//        print(pageHTMLString)
        let indexURL = createTemporaryBundle(pageHTMLString: pageHTMLString)

        if let i = indexURL {
            let accessURL = i.deletingLastPathComponent()
            loadFileURL(i, allowingReadAccessTo: accessURL)
        }
    }

    func createTemporaryBundle(pageHTMLString: String) -> URL? {
        let path = Bundle.main.path(forResource: "DownView", ofType: ".bundle")
        let url = NSURL.fileURL(withPath: path!)
        let bundle = Bundle(url: url)

        guard let bundleResourceURL = bundle?.resourceURL else { return nil }

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

        if let customCSS = customCSS {
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
        var htmlString = html

        do {
            let regex = try NSRegularExpression(pattern: "<img.*?src=\"([^\"]*)\"")
            let results = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

            let images = results.map {
                String(html[Range($0.range, in: html)!])
            }

            for image in images {
                var localPath = image.replacingOccurrences(of: "<img src=\"", with: "").dropLast()

                let localPathClean = localPath.removingPercentEncoding ?? String(localPath)

                let fullImageURL = imagesStorage
                let imageURL = fullImageURL.appendingPathComponent(localPathClean)

                let webkitPreview = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wkPreview")

                let create = webkitPreview
                    .appendingPathComponent(localPathClean)
                    .deletingLastPathComponent()
                let destination = webkitPreview.appendingPathComponent(localPathClean)

                try? FileManager.default.createDirectory(atPath: create.path, withIntermediateDirectories: true, attributes: nil)
                try? FileManager.default.removeItem(at: destination)
                try? FileManager.default.copyItem(at: imageURL, to: destination)

                if localPath.first == "/" {
                    localPath.remove(at: localPath.startIndex)
                }

                let imPath = "<img src=\"" + localPath + "\""

                htmlString = htmlString.replacingOccurrences(of: image, with: imPath)
            }
        } catch {
            print("Images regex: \(error.localizedDescription)")
        }

        return htmlString
    }

    func htmlFromTemplate(_ htmlString: String, css: String) throws -> String {
        guard let vc = ViewController.shared() else {
            return ""
        }
        let path = Bundle.main.path(forResource: "DownView", ofType: ".bundle")
        let url = NSURL.fileURL(withPath: path!)
        let bundle = Bundle(url: url)

        var baseURL = bundle!.url(forResource: "index", withExtension: "html")!

        if UserDefaultsManagement.magicPPT {
            baseURL = bundle!.url(forResource: "ppt", withExtension: "html")!
        }

        var template = try NSString(contentsOf: baseURL, encoding: String.Encoding.utf8.rawValue)

        template = template.replacingOccurrences(of: "DOWN_CSS", with: css) as NSString

        var fontPath = Bundle.main.resourceURL!.path
        var downMeta = ""

        // 兼容一下 Html 的场景
        if UserDefaultsManagement.isOnExportHtml {
            fontPath = "https://gw.alipayobjects.com/os/k/html2/Fonts"
            downMeta = "<base href=\"https://gw.alipayobjects.com/os/k/html2/\">"
        }

        template = template.replacingOccurrences(of: "DOWN_FONT_PATH", with: fontPath) as NSString
        template = template.replacingOccurrences(of: "DOWN_META", with: downMeta) as NSString

        if UserDefaultsManagement.isOnExport {
            template = template.replacingOccurrences(of: "DOWN_EXPORT_TYPE", with: "ppt") as NSString
        }

        if UserDefaultsManagement.magicPPT {
            var downTheme = "<link rel=\"stylesheet\" href=\"ppt/dist/theme/white.css\" id=\"theme\" />"
            if UserDataService.instance.isDark {
                downTheme = "<link rel=\"stylesheet\" href=\"ppt/dist/theme/night.css\" id=\"theme\" />"
            }
            template = template.replacingOccurrences(of: "DOWN_THEME", with: downTheme) as NSString

            // 兼容一些ppt下面图片拖动进去，相对位置的问题
            let newHtmlString = htmlString.replacingOccurrences(of: "](/i/", with: "](./i/")
            return template.replacingOccurrences(of: "DOWN_RAW", with: newHtmlString)
        }

        #if os(iOS)
            if NightNight.theme == .night {
                template = template.replacingOccurrences(of: "CUSTOM_CSS", with: "darkmode") as NSString
            }
        #else
            if UserDataService.instance.isDark {
                template = template.replacingOccurrences(of: "CUSTOM_CSS", with: "darkmode") as NSString
            }
        #endif
        var htmlContent = htmlString
        let currentName = vc.titleLabel.stringValue
        if UserDefaultsManagement.isOnExport, !htmlString.hasPrefix("<h1>") {
            htmlContent = "<h1>\(String(describing: currentName))</h1>" + htmlString
        }
        return template.replacingOccurrences(of: "DOWN_HTML", with: htmlContent)
    }
}

class HandlerCheckbox: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
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
                               didReceive message: WKScriptMessage) {
        let message = (message.body as! String).trimmingCharacters(in: .whitespacesAndNewlines)

        HandlerCodeCopy.selectionString = message
    }
}

class HandlerSelection: NSObject, WKScriptMessageHandler {
    public static var selectionString: String?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        let message = (message.body as! String).trimmingCharacters(in: .whitespacesAndNewlines)

        HandlerSelection.selectionString = message
    }
}

// 用于解决ppt模式下背景颜色变化左侧边框颜色的适配
class HandlerRevealBackgroundColor: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let vc = ViewController.shared() else { return }
        let message = (message.body as! String).trimmingCharacters(in: .whitespacesAndNewlines)
        if message == "" {
            vc.setDividerHidden(hidden: true)
            vc.setSideDividerHidden(hidden: true)
        } else {
            vc.sidebarSplitView.setValue(NSColor(css: message), forKey: "dividerColor")
            vc.splitView.setValue(NSColor(css: message), forKey: "dividerColor")
        }
    }
}
