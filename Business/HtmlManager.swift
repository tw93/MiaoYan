import Foundation
import WebKit

private struct ImageLocation {
    let source: URL
    let dest: URL
    let displayPath: String
}

class HtmlManager {
    private static let fontStack = "-apple-system, BlinkMacSystemFont, \"Helvetica Neue\", Helvetica, Arial, \"PingFang SC\", \"Hiragino Sans GB\", \"Microsoft YaHei\", sans-serif"
    private static let codeFontStack = "SFMono-Regular, Menlo, Consolas, \"Liberation Mono\", \"Courier New\", monospace"

    // Cached regex patterns
    private static let imageRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "<img[^>]*?src=\"([^\"]*)\"[^>]*?/?>")
    }()

    private static let htmlTagPatterns: [NSRegularExpression] = {
        let patterns = [
            try? NSRegularExpression(pattern: "<(?:img|br|hr|input|meta|link|area|base|col|embed|source|track|wbr)\\s*[^>]*/?\\s*>", options: [.caseInsensitive]),
            try? NSRegularExpression(pattern: "<(\\w+)[^>]*>[^<]*</\\1>", options: [.caseInsensitive]),
        ]
        return patterns.compactMap { $0 }
    }()

    // Paths
    private static let webkitPreviewURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wkPreview")

    // Constants
    private static let cdnBaseURL = "https://cdn.miaoyan.app/Resources"
    private static let imgTagMinLength = 26
    private static let imageNotFoundPlaceholder =
        "<img src=\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='120' height='80'%3E%3Crect width='120' height='80' fill='%23f5f5f5' stroke='%23ddd' stroke-width='1'/%3E%3Ctext x='50%25' y='50%25' text-anchor='middle' dy='.3em' fill='%23999' font-size='12' font-family='sans-serif'%3EImage Not Found%3C/text%3E%3C/svg%3E\" alt=\"Image not found\" style=\"max-width: 120px; opacity: 0.6;\" />"

    // Cached instances
    private static let downViewBundle: Bundle? = {
        guard let path = Bundle.main.path(forResource: "DownView", ofType: "bundle") else { return nil }
        return Bundle(path: path)
    }()

    @MainActor
    static func previewStyle() -> String {
        // Add font configuration
        var codeFontName = UserDefaultsManagement.previewFontName
        if UserDefaultsManagement.codeFontName != UserDefaultsManagement.previewFontName {
            codeFontName = UserDefaultsManagement.codeFontName
        }

        let fontConfig = ":root { --text-font: \(UserDefaultsManagement.previewFontName), \(fontStack); --code-text-font: \(codeFontName), \(codeFontStack); }"

        if UserDefaultsManagement.magicPPT {
            return "\(fontConfig) :root { --r-main-font: \(UserDefaultsManagement.previewFontName), sans-serif;}"
        }

        if UserDefaultsManagement.presentation {
            return "html {font-size: \(UserDefaultsManagement.presentationFontSize)px} \(fontConfig) #write { max-width: 100%;}"
        } else {
            let paddingStyle = UserDefaultsManagement.isOnExport ? " padding-top: 24px" : ""
            let maxWidth = UserDefaultsManagement.previewWidth == UserDefaultsManagement.FullWidthValue ? "100%" : UserDefaultsManagement.previewWidth
            let writeCSS = "max-width: \(maxWidth); margin: 0"

            return "html {font-size: \(UserDefaultsManagement.previewFontSize)px; \(paddingStyle)} \(fontConfig) #write { \(writeCSS)}"
        }
    }

    // Theme CSS handling moved to HTML templates

    private static func cleanImagePath(_ path: String) -> String {
        var cleaned = path.removingPercentEncoding ?? path
        if cleaned.starts(with: "file://") {
            cleaned = String(cleaned.dropFirst(7))
        }
        return cleaned
    }

    private static func isAbsolutePath(_ path: String) -> Bool {
        return path.starts(with: "/") && !path.starts(with: "/i/")
    }

    private static func resolveImageLocation(_ cleanPath: String, imagesStorage: URL) -> ImageLocation {
        // Absolute system path (not relative to project)
        if isAbsolutePath(cleanPath) {
            let imageURL = URL(fileURLWithPath: cleanPath)
            let filename = imageURL.lastPathComponent
            return ImageLocation(
                source: imageURL,
                dest: webkitPreviewURL.appendingPathComponent(filename),
                displayPath: filename
            )
        }

        // Relative path: maintain directory structure
        return ImageLocation(
            source: imagesStorage.appendingPathComponent(cleanPath),
            dest: webkitPreviewURL.appendingPathComponent(cleanPath),
            displayPath: cleanPath
        )
    }

    private static func copyImageIfNeeded(from source: URL, to destination: URL) {
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }

        let directory = destination.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(atPath: directory.path, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            Task { @MainActor in
                AppDelegate.trackError(error, context: "HtmlManager.copyImageIfNeeded")
            }
        }
    }

    private static func updateImageSrc(in html: String, fullMatch: String, oldSrc: String, newSrc: String) -> String {
        let updatedTag = fullMatch.replacingOccurrences(of: "src=\"\(oldSrc)\"", with: "src=\"\(newSrc)\"")
        return html.replacingOccurrences(of: fullMatch, with: updatedTag)
    }

    static func processImages(in html: String, imagesStorage: URL) -> String {
        guard let regex = imageRegex else {
            Task { @MainActor in
                AppDelegate.trackError(
                    NSError(domain: "HtmlManager", code: 1,
                           userInfo: [NSLocalizedDescriptionKey: "Invalid image regex pattern"]),
                    context: "HtmlManager.processImages.regex"
                )
            }
            return html
        }

        var htmlString = html

        let results = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        let images = results.compactMap { match -> (fullMatch: String, srcPath: String)? in
            guard let fullRange = Range(match.range, in: html),
                let srcRange = Range(match.range(at: 1), in: html)
            else { return nil }
            return (String(html[fullRange]), String(html[srcRange]))
        }

        for imageInfo in images {
            guard !imageInfo.srcPath.starts(with: "http://"),
                !imageInfo.srcPath.starts(with: "https://")
            else {
                continue
            }

            let cleanPath = cleanImagePath(imageInfo.srcPath)

            // Check if it's an absolute system path
            if isAbsolutePath(cleanPath) {
                if FileManager.default.fileExists(atPath: cleanPath) {
                    htmlString = updateImageSrc(in: htmlString, fullMatch: imageInfo.fullMatch, oldSrc: imageInfo.srcPath, newSrc: "file://\(cleanPath)")
                } else {
                    htmlString = htmlString.replacingOccurrences(of: imageInfo.fullMatch, with: imageNotFoundPlaceholder)
                }
                continue
            }

            // Process relative paths
            let imageLocation = resolveImageLocation(cleanPath, imagesStorage: imagesStorage)
            copyImageIfNeeded(from: imageLocation.source, to: imageLocation.dest)

            var finalPath = imageLocation.displayPath
            if finalPath.first == "/" {
                finalPath.remove(at: finalPath.startIndex)
            }

            htmlString = updateImageSrc(in: htmlString, fullMatch: imageInfo.fullMatch, oldSrc: imageInfo.srcPath, newSrc: finalPath)
        }

        return htmlString
    }

    // MARK: - Bundle and Resource Management

    static func getDownViewBundle() -> Bundle? {
        return downViewBundle
    }

    private static func escapeForPPT(_ content: String) -> String {
        // Don't escape backticks as they're needed for code blocks in Markdown
        // Reveal.js markdown plugin handles them correctly
        return
            content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "](/i/", with: "](./i/")
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
                "\(cdnBaseURL)/Fonts",
                "<base href=\"\(cdnBaseURL)/DownView.bundle/\">"
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
            return "<h1>\(currentName)</h1>\(htmlString)"
        }
        return htmlString
    }

    // MARK: - Template Processing

    private static func applyTemplateReplacements(_ template: String, replacements: [String: String]) -> String {
        var result = template
        for (placeholder, value) in replacements {
            result = result.replacingOccurrences(of: placeholder, with: value)
        }
        return result
    }

    @MainActor
    static func htmlFromTemplate(_ htmlString: String, css: String, currentName: String) throws -> String {
        guard let bundle = getDownViewBundle(),
            let baseURL = getBaseURL(bundle: bundle)
        else {
            return ""
        }

        let template = try String(contentsOf: baseURL, encoding: .utf8)

        let (fontPath, downMeta) = getFontPathAndMeta()
        let customCSS = UserDataService.instance.isDark ? "darkmode" : "lightmode"

        var replacements: [String: String] = [
            "DOWN_CSS": css,
            "DOWN_FONT_PATH": fontPath,
            "DOWN_META": downMeta,
            "CUSTOM_CSS": customCSS,
        ]

        if UserDefaultsManagement.isOnExport {
            replacements["DOWN_EXPORT_TYPE"] = "ppt"
        }

        if UserDefaultsManagement.magicPPT {
            replacements["DOWN_THEME"] = getPPTTheme()
            replacements["DOWN_RAW"] = escapeForPPT(htmlString)
            return applyTemplateReplacements(template, replacements: replacements)
        }

        replacements["DOWN_HTML"] = getHtmlContent(htmlString, currentName: currentName)
        return applyTemplateReplacements(template, replacements: replacements)
    }

    @MainActor
    static func createTemporaryBundle(pageHTMLString: String) -> URL? {
        guard let bundle = getDownViewBundle(),
            let bundleResourceURL = bundle.resourceURL
        else {
            return nil
        }

        let customCSS = UserDefaultsManagement.markdownPreviewCSS

        try? FileManager.default.createDirectory(at: webkitPreviewURL, withIntermediateDirectories: true, attributes: nil)

        let indexURL = webkitPreviewURL.appendingPathComponent("index.html")

        if !FileManager.default.fileExists(atPath: indexURL.path) {
            do {
                let fileList = try FileManager.default.contentsOfDirectory(atPath: bundleResourceURL.path)
                for file in fileList {
                    if customCSS != nil, file == "css" { continue }
                    let tmpURL = webkitPreviewURL.appendingPathComponent(file)
                    try FileManager.default.copyItem(atPath: bundleResourceURL.appendingPathComponent(file).path, toPath: tmpURL.path)
                }
            } catch {
                Task { @MainActor in
                    AppDelegate.trackError(error, context: "HtmlManager.createTemporaryBundle.copyBundleResource")
                }
            }
        }

        if let customCSS {
            let cssDst = webkitPreviewURL.appendingPathComponent("css")
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

        for regex in htmlTagPatterns {
            let matches = regex.matches(in: content, range: fullRange)
            matchRanges.append(contentsOf: matches.map { $0.range })
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

        if adjustedOffset <= imgTagMinLength && restored.hasPrefix("<img") {
            if let endIndex = restored.firstIndex(of: ">") {
                let tagEndPosition = restored.distance(from: restored.startIndex, to: endIndex) + 1
                adjustedOffset = max(adjustedOffset, tagEndPosition)
            }
        }

        return adjustedOffset
    }
}
