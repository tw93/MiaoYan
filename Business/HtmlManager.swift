import Foundation
import WebKit

class HtmlManager {

    @MainActor
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
            Task { @MainActor in
                AppDelegate.trackError(error, context: "HtmlManager.processImages.regex")
            }
        }

        return htmlString
    }

    // MARK: - Bundle and Resource Management

    static func getDownViewBundle() -> Bundle? {
        guard let path = Bundle.main.path(forResource: "DownView", ofType: "bundle") else { return nil }
        return Bundle(path: path)
    }

    @MainActor
    static func getBaseURL(bundle: Bundle) -> URL? {
        let resourceName = UserDefaultsManagement.magicPPT ? "ppt" : "index"
        return bundle.url(forResource: resourceName, withExtension: "html")
    }

    @MainActor
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

    @MainActor
    static func getPPTTheme() -> String {
        let themeFile = UserDataService.instance.isDark ? "night.css" : "white.css"
        return "<link rel=\"stylesheet\" href=\"ppt/dist/theme/\(themeFile)\" id=\"theme\" />"
    }

    @MainActor
    static func getHtmlContent(_ htmlString: String, currentName: String) -> String {
        if UserDefaultsManagement.isOnExport, !htmlString.hasPrefix("<h1>") {
            return "<h1>\(currentName)</h1>" + htmlString
        }
        return htmlString
    }

    // MARK: - Template Processing

    @MainActor
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

            var escapedContent = htmlString.replacingOccurrences(of: "\\", with: "\\\\")
            escapedContent = escapedContent.replacingOccurrences(of: "`", with: "\\`")
            escapedContent = escapedContent.replacingOccurrences(of: "$", with: "\\$")
            escapedContent = escapedContent.replacingOccurrences(of: "](/i/", with: "](./i/")

            return template.replacingOccurrences(of: "DOWN_RAW", with: escapedContent)
        }

        if UserDataService.instance.isDark {
            template = template.replacingOccurrences(of: "CUSTOM_CSS", with: "darkmode")
        }

        let htmlContent = getHtmlContent(htmlString, currentName: currentName)
        return template.replacingOccurrences(of: "DOWN_HTML", with: htmlContent)
    }

    @MainActor
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

        if !FileManager.default.fileExists(atPath: indexURL.path) {
            do {
                let fileList = try FileManager.default.contentsOfDirectory(atPath: bundleResourceURL.path)
                for file in fileList {
                    if customCSS != nil, file == "css" { continue }
                    let tmpURL = webkitPreview.appendingPathComponent(file)
                    try FileManager.default.copyItem(atPath: bundleResourceURL.appendingPathComponent(file).path, toPath: tmpURL.path)
                }
            } catch {
                Task { @MainActor in
                    AppDelegate.trackError(error, context: "HtmlManager.createTemporaryBundle.copyBundleResource")
                }
            }
        }

        if let customCSS {
            let cssDst = webkitPreview.appendingPathComponent("css")
            let styleDst = cssDst.appendingPathComponent("markdown-preview.css", isDirectory: false)
            do {
                try FileManager.default.createDirectory(at: cssDst, withIntermediateDirectories: false, attributes: nil)
                _ = try FileManager.default.copyItem(at: customCSS, to: styleDst)
            } catch {
                Task { @MainActor in
                    AppDelegate.trackError(error, context: "HtmlManager.createTemporaryBundle.copyCustomCSS")
                }
            }
        }

        try? pageHTMLString.write(to: indexURL, atomically: true, encoding: .utf8)
        return indexURL
    }

    // MARK: - JavaScript Utilities
    static let checkImagesScript = """
        (function() {
            var images = document.getElementsByTagName('img');
            var loadedCount = 0;
            var totalImages = images.length;

            if (totalImages === 0) {
                return true;
            }

            for (var i = 0; i < totalImages; i++) {
                if (images[i].complete && images[i].naturalWidth > 0) {
                    loadedCount++;
                }
            }

            return loadedCount === totalImages;
        })();
        """

    // MARK: - HTML Tag Protection
    static func protectHTMLTags(in content: String) -> (protectedContent: String, placeholders: [String: String]) {
        var protectedContent = content
        var placeholders: [String: String] = [:]
        let fullRange = NSRange(content.startIndex..., in: content)
        var matchRanges: [NSRange] = []

        do {
            let htmlPatterns = [
                "<(?:img|br|hr|input|meta|link|area|base|col|embed|source|track|wbr)\\s*[^>]*/?\\s*>",
                "<(\\w+)[^>]*>[^<]*</\\1>",
            ]

            for pattern in htmlPatterns {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let matches = regex.matches(in: content, range: fullRange)
                matchRanges.append(contentsOf: matches.map { $0.range })
            }

        } catch {
            Task { @MainActor in
                AppDelegate.trackError(error, context: "HtmlManager.protectHTMLTags.regex")
            }
        }

        matchRanges.sort { $0.location > $1.location }

        for range in matchRanges {
            guard range.location + range.length <= content.utf16.count,
                let swiftRange = Range(range, in: content)
            else { continue }

            let htmlTag = String(content[swiftRange])
            let placeholder = "HTML_PLACEHOLDER_\(UUID().uuidString.prefix(8))"
            placeholders[placeholder] = htmlTag

            protectedContent = (protectedContent as NSString).replacingCharacters(in: range, with: placeholder)
        }

        return (protectedContent, placeholders)
    }

    static func restoreHTMLTags(in content: String, with placeholders: [String: String]) -> String {
        var restoredContent = content

        let sortedPlaceholders = placeholders.sorted { (first, second) -> Bool in
            guard let firstRange = restoredContent.range(of: first.key),
                let secondRange = restoredContent.range(of: second.key)
            else {
                return false
            }
            return firstRange.lowerBound < secondRange.lowerBound
        }

        for (placeholder, htmlTag) in sortedPlaceholders {
            if let range = restoredContent.range(of: placeholder) {
                restoredContent.replaceSubrange(range, with: htmlTag)
            }
        }

        return restoredContent
    }

    static func adjustCursorForProtectedContent(cursor: Int, original: String, protected: String) -> Int {
        let lengthDiff = protected.count - original.count
        return max(0, min(cursor + lengthDiff, protected.count))
    }

    static func adjustCursorAfterRestore(originalOffset: Int, protected: String, restored: String) -> Int {
        let lengthDiff = restored.count - protected.count
        var adjustedOffset = originalOffset + lengthDiff

        adjustedOffset = max(0, min(adjustedOffset, restored.count))

        if adjustedOffset <= 26 && restored.hasPrefix("<img") {
            if let endIndex = restored.firstIndex(of: ">") {
                let tagEndPosition = restored.distance(from: restored.startIndex, to: endIndex) + 1
                adjustedOffset = max(adjustedOffset, tagEndPosition)
            }
        }

        return adjustedOffset
    }
}
