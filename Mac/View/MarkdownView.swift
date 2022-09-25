import Highlightr
import WebKit

#if os(iOS)
import NightNight
#endif

public typealias DownViewClosure = () -> Void

open class MarkdownView: WKWebView {
    public init(imagesStorage: URL? = nil, frame: CGRect, markdownString: String, openLinksInBrowser: Bool = true, css: String, templateBundle: Bundle? = nil, didLoadSuccessfully: DownViewClosure? = nil) throws {
        self.didLoadSuccessfully = didLoadSuccessfully

        if let templateBundle = templateBundle {
            bundle = templateBundle
        } else {
            let classBundle = Bundle(for: MarkdownView.self)
            let url = classBundle.url(forResource: "DownView", withExtension: "bundle")!
            bundle = Bundle(url: url)!
        }

        let userContentController = WKUserContentController()
        userContentController.add(HandlerCopyCode(), name: "notification")

        #if os(OSX)
        userContentController.add(HandlerMouseOver(), name: "mouseover")
        userContentController.add(HandlerMouseOut(), name: "mouseout")
        #endif

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController

        super.init(frame: frame, configuration: configuration)

        #if os(OSX)
        setValue(false, forKey: "drawsBackground")
        #else
        isOpaque = false
        backgroundColor = UIColor.clear
        scrollView.backgroundColor = UIColor.clear
        #endif

        if openLinksInBrowser || didLoadSuccessfully != nil { navigationDelegate = self }
        try loadHTMLView(markdownString, imagesStorage: imagesStorage)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(markdownString: String, didLoadSuccessfully: DownViewClosure? = nil) throws {
        if let didLoadSuccessfully = didLoadSuccessfully {
            self.didLoadSuccessfully = didLoadSuccessfully
        }

        try loadHTMLView(markdownString)
    }

    public static func getPreviewStyle() -> String {
        if UserDefaultsManagement.magicPPT {
            return ":root { --r-main-font: \(UserDefaultsManagement.previewFontName), sans-serif;}"
        }

        var codeFontName = UserDefaultsManagement.previewFontName
        if UserDefaultsManagement.codeFontName != UserDefaultsManagement.previewFontName {
            codeFontName = UserDefaultsManagement.codeFontName
        }
        if UserDefaultsManagement.presentation {
            return "html {font-size: \(UserDefaultsManagement.presentationFontSize)px} :root { --text-font: \(UserDefaultsManagement.previewFontName), sans-serif; --code-text-font: \(codeFontName),sans-serif; } #write { max-width: 100%;}"
        } else {
            let paddingStyle = UserDefaultsManagement.isOnExport ? " padding-top: 24px" : ""
            return "html {font-size: \(UserDefaultsManagement.previewFontSize)px; \(paddingStyle)} :root { --text-font: \(UserDefaultsManagement.previewFontName), sans-serif; --code-text-font: \(codeFontName),sans-serif; } #write { max-width: \(UserDefaultsManagement.previewWidth);}"
        }
    }

    let bundle: Bundle

    fileprivate lazy var baseURL: URL = bundle.url(forResource: "index", withExtension: "html")!

    fileprivate lazy var pptURL: URL = bundle.url(forResource: "ppt", withExtension: "html")!

    fileprivate var didLoadSuccessfully: DownViewClosure?

    func createTemporaryBundle(pageHTMLString: String) -> URL? {
        guard let bundleResourceURL = bundle.resourceURL
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
}

// MARK: - Private API

private extension MarkdownView {
    func loadHTMLView(_ markdownString: String, imagesStorage: URL? = nil) throws {
        var htmlString = renderMarkdownHTML(markdown: markdownString)!

        if let imagesStorage = imagesStorage {
            htmlString = loadImages(imagesStorage: imagesStorage, html: htmlString)
        }

        let pageHTMLString = try htmlFromTemplate(htmlString)

        let indexURL = createTemporaryBundle(pageHTMLString: pageHTMLString)

        if let i = indexURL {
            let accessURL = i.deletingLastPathComponent()
            loadFileURL(i, allowingReadAccessTo: accessURL)
        }
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

                guard !localPath.starts(with: "http://"), !localPath.starts(with: "https://") else {
                    continue
                }

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

                var orientation = 0
                let url = NSURL(fileURLWithPath: imageURL.path)
                if let imageSource = CGImageSourceCreateWithURL(url, nil) {
                    let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as Dictionary?
                    if let orientationProp = imageProperties?[kCGImagePropertyOrientation] as? Int {
                        orientation = orientationProp
                    }
                }

                if localPath.first == "/" {
                    localPath.remove(at: localPath.startIndex)
                }

                let imPath = "<img data-orientation=\"\(orientation)\" class=\"miaoyan-preview\" src=\"" + localPath + "\""

                htmlString = htmlString.replacingOccurrences(of: image, with: imPath)
            }
        } catch {
            print("Images regex: \(error.localizedDescription)")
        }

        return htmlString
    }

    func htmlFromTemplate(_ htmlString: String) throws -> String {
        let template = try NSString(contentsOf: baseURL, encoding: String.Encoding.utf8.rawValue)
        return template.replacingOccurrences(of: "DOWN_HTML", with: htmlString)
    }
}

// MARK: - WKNavigationDelegate

extension MarkdownView: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return }

        switch navigationAction.navigationType {
        case .linkActivated:
            decisionHandler(.cancel)
            NSWorkspace.shared.open(url)
        default:
            decisionHandler(.allow)
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didLoadSuccessfully?()
    }
}

class HandlerCopyCode: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        let message = (message.body as! String).trimmingCharacters(in: .whitespacesAndNewlines)
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
        pasteboard.setString(message, forType: NSPasteboard.PasteboardType.string)
    }
}

class HandlerMouseOver: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        NSCursor.pointingHand.set()
    }
}

class HandlerMouseOut: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        NSCursor.arrow.set()
    }
}
