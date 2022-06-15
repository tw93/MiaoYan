import Carbon.HIToolbox
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
        userContentController.add(HandlerSelection(), name: "newSelectionDetected")
        userContentController.add(HandlerCodeCopy(), name: "notification")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController

        super.init(frame: frame, configuration: configuration)

        navigationDelegate = self

#if os(OSX)
        if #available(macOS 10.13, *) {
            setValue(false, forKey: "drawsBackground")
        }
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
                guard let string = HandlerSelection.selectionString else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
                pasteboard.setString(string, forType: NSPasteboard.PasteboardType.string)
            }

            return false
        }

        return super.performKeyEquivalent(with: event)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        closure?()
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return }

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
        guard self.note != note || force else { return }

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
        let baseURL = bundle!.url(forResource: "index", withExtension: "html")!

        guard var template = try? NSString(contentsOf: baseURL, encoding: String.Encoding.utf8.rawValue) else { return nil }
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

        let pageHTMLString = try htmlFromTemplate(htmlString, css: css)

        print(pageHTMLString)

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

        guard let bundleResourceURL = bundle?.resourceURL
        else { return nil }

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
        let path = Bundle.main.path(forResource: "DownView", ofType: ".bundle")
        let url = NSURL.fileURL(withPath: path!)
        let bundle = Bundle(url: url)
        let baseURL = bundle!.url(forResource: "index", withExtension: "html")!

        var template = try NSString(contentsOf: baseURL, encoding: String.Encoding.utf8.rawValue)

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
        return template.replacingOccurrences(of: "DOWN_HTML", with: htmlString)
    }
}

class HandlerCodeCopy: NSObject, WKScriptMessageHandler {
    public static var selectionString: String? {
        didSet {
            guard let copyBlock = selectionString else { return }
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
