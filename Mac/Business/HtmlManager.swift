import Foundation
import WebKit

/// 管理HTML预览和处理的工具类
class HtmlManager {

    /// 获取Markdown预览的CSS样式
    static func previewStyle() -> String {
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
            let writeCSS = UserDefaultsManagement.isOnExportHtml ? " max-width: 800px; margin: 0 auto" : "max-width: \(UserDefaultsManagement.previewWidth);"

            return
                "html {font-size: \(UserDefaultsManagement.previewFontSize)px; \(paddingStyle)} :root { --text-font: \(UserDefaultsManagement.previewFontName), sans-serif; --code-text-font: \(codeFontName),sans-serif; } #write { \(writeCSS)}"
        }
    }

    static func processImages(in html: String, imagesStorage: URL) -> String {
        var htmlString = html

        do {
            let regex = try NSRegularExpression(pattern: "<img[^>]*?src=\"([^\"]*)\"[^>]*?>")
            let results = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

            let images = results.compactMap { match -> (fullMatch: String, srcPath: String)? in
                guard let fullRange = Range(match.range, in: html),
                    let srcRange = Range(match.range(at: 1), in: html)
                else { return nil }
                return (String(html[fullRange]), String(html[srcRange]))
            }

            let webkitPreview = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wkPreview")

            for imageInfo in images {
                var localPath = imageInfo.srcPath

                guard !localPath.starts(with: "http://"), !localPath.starts(with: "https://") else {
                    continue
                }

                let localPathClean = localPath.removingPercentEncoding ?? String(localPath)
                let imageURL = imagesStorage.appendingPathComponent(localPathClean)
                let destination = webkitPreview.appendingPathComponent(localPathClean)

                if !FileManager.default.fileExists(atPath: destination.path) {
                    let create = destination.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(atPath: create.path, withIntermediateDirectories: true, attributes: nil)
                    try? FileManager.default.copyItem(at: imageURL, to: destination)
                }

                if localPath.first == "/" {
                    localPath.remove(at: localPath.startIndex)
                }

                let imPath = "<img src=\"" + localPath + "\""
                htmlString = htmlString.replacingOccurrences(of: imageInfo.fullMatch, with: imPath)
            }
        } catch {
            print("Image processing regex error: \(error.localizedDescription)")
        }

        return htmlString
    }

    // MARK: - Bundle and Resource Management

    /// 获取DownView Bundle
    static func getDownViewBundle() -> Bundle? {
        guard let path = Bundle.main.path(forResource: "DownView", ofType: ".bundle") else { return nil }
        return Bundle(url: URL(fileURLWithPath: path))
    }

    /// 获取基础URL
    static func getBaseURL(bundle: Bundle) -> URL? {
        let resourceName = UserDefaultsManagement.magicPPT ? "ppt" : "index"
        return bundle.url(forResource: resourceName, withExtension: "html")
    }

    /// 获取字体路径和Meta信息
    static func getFontPathAndMeta() -> (String, String) {
        if UserDefaultsManagement.isOnExportHtml {
            return (
                "https://gw.alipayobjects.com/os/k/html2/Fonts",
                "<base href=\"https://gw.alipayobjects.com/os/k/html2/\">"
            )
        } else {
            return (Bundle.main.resourceURL?.path ?? "", "")
        }
    }

    /// 获取PPT主题
    static func getPPTTheme() -> String {
        let themeFile = UserDataService.instance.isDark ? "night.css" : "white.css"
        return "<link rel=\"stylesheet\" href=\"ppt/dist/theme/\(themeFile)\" id=\"theme\" />"
    }

    /// 处理HTML内容，添加标题
    static func getHtmlContent(_ htmlString: String, currentName: String) -> String {
        if UserDefaultsManagement.isOnExport, !htmlString.hasPrefix("<h1>") {
            return "<h1>\(currentName)</h1>" + htmlString
        }
        return htmlString
    }

    // MARK: - Template Processing

    /// 从模板生成HTML
    static func htmlFromTemplate(_ htmlString: String, css: String, currentName: String) throws -> String {
        guard let bundle = getDownViewBundle(),
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

            // Escape the markdown content for JavaScript template literal
            var escapedContent = htmlString.replacingOccurrences(of: "\\", with: "\\\\")
            escapedContent = escapedContent.replacingOccurrences(of: "`", with: "\\`")
            escapedContent = escapedContent.replacingOccurrences(of: "$", with: "\\$")
            escapedContent = escapedContent.replacingOccurrences(of: "](/i/", with: "](./i/")

            return template.replacingOccurrences(of: "DOWN_RAW", with: escapedContent)
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

        let htmlContent = getHtmlContent(htmlString, currentName: currentName)
        return template.replacingOccurrences(of: "DOWN_HTML", with: htmlContent)
    }

    /// 创建临时Bundle
    static func createTemporaryBundle(pageHTMLString: String) -> URL? {
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
                print("Bundle resource copy error: \(error.localizedDescription)")
            }
        }

        if let customCSS {
            let cssDst = webkitPreview.appendingPathComponent("css")
            let styleDst = cssDst.appendingPathComponent("markdown-preview.css", isDirectory: false)

            do {
                try FileManager.default.createDirectory(at: cssDst, withIntermediateDirectories: false, attributes: nil)
                _ = try FileManager.default.copyItem(at: customCSS, to: styleDst)
            } catch {
                print("Custom CSS copy error: \(error.localizedDescription)")
            }
        }

        // Write generated index.html to temporary location.
        try? pageHTMLString.write(to: indexURL, atomically: true, encoding: .utf8)

        return indexURL
    }

    // MARK: - JavaScript Utilities

    /// 等待图片加载完成的JavaScript检查脚本
    static let checkImagesScript = """
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
}
