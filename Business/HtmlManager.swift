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

    static func lightModeExportCSS() -> String {
        return """
            @media print, screen {
               :root {
                   --bg-color: #FFFFFF !important;
                   --text-color: #262626 !important;
                   --code-bg: #f7f7f7 !important;
                   --side-bar-bg-color: #fafafa !important;
                   --control-text-color: #777 !important;
                   --primary-color: #fd8258 !important;
               }
               html, body {
                   background-color: #FFFFFF !important;
                   color: #262626 !important;
               }
            }
            """
    }

    static func darkModeExportCSS() -> String {
        return """
            @media print, screen {
               :root {
                   --bg-color: #23282D !important;
                   --text-color: #E7E9EA !important;
                   --code-bg: #282e33 !important;
                   --side-bar-bg-color: #23282D !important;
                   --control-text-color: #999 !important;
                   --primary-color: #fd8258 !important;
               }
               html, body {
                   background-color: #23282D !important;
                   color: #E7E9EA !important;
               }
            }
            """
    }

    @MainActor
    static func exportCSS() -> String {
        // Follow user's theme setting for export
        return UserDataService.instance.isDark ? darkModeExportCSS() : lightModeExportCSS()
    }

    // Print-only pagination rules injected into the offscreen WKWebView that hosts PDF export.
    // Paper size and page margins come from NSPrintInfo; macOS WebKit below 15.2 ignores
    // `@page { size; margin }`, so this stylesheet sticks to properties that work on 11.5+.
    //
    // The compact spacing overrides fight `.heti` typography defaults, which are tuned for
    // on-screen reading (1.74 line-height, 1.6em paragraph gutters). Print rendering gets
    // tighter metrics closer to a typeset article.
    static func paginatedPrintCSS() -> String {
        return """
            @media print {
                html, body {
                    margin: 0 !important;
                    padding: 0 !important;
                    background: #FFFFFF !important;
                    color: #262626 !important;
                    -webkit-print-color-adjust: exact;
                    print-color-adjust: exact;
                }
                #write {
                    max-width: none !important;
                    width: auto !important;
                    margin: 0 !important;
                    padding: 0 !important;
                }

                /* Pull the first element on page 1 flush with the top margin. */
                .heti > *:first-child,
                #write > *:first-child,
                #export-generated-title {
                    margin-top: 0 !important;
                    margin-block-start: 0 !important;
                    padding-top: 0 !important;
                }

                /* Page-break rules. Let content flow naturally: no forced h1 page break
                   (that strategy left huge bottom gaps on short sections). Keep break-inside:
                   avoid only on small, coherent blocks — not on img, since tall images forced
                   to the next page created worse gaps than the occasional split. */
                h1, h2, h3, h4, h5, h6 { page-break-after: avoid; }
                pre, table, figure, blockquote,
                .miaoyan-mermaid, .md-diagram-panel {
                    page-break-inside: avoid;
                }
                img {
                    max-width: 100% !important;
                    display: block;
                    margin-left: auto;
                    margin-right: auto;
                }

                /* Compact vertical rhythm: .heti defaults are 1.6em/0.8em, too airy for print. */
                .heti, body { line-height: 1.55 !important; }
                .heti p,
                .heti ul, .heti ol,
                .heti blockquote,
                .heti table,
                .heti pre,
                .heti hr,
                .heti figure {
                    margin-block-start: 0.6em !important;
                    margin-block-end: 0.6em !important;
                }
                .heti h1 {
                    margin-block-start: 0.9em !important;
                    margin-block-end: 0.4em !important;
                }
                .heti h2, .heti h3, .heti h4, .heti h5, .heti h6 {
                    margin-block-start: 0.7em !important;
                    margin-block-end: 0.3em !important;
                }
                .heti li > p,
                .heti li > ul,
                .heti li > ol {
                    margin-block-start: 0.2em !important;
                    margin-block-end: 0.2em !important;
                }

                .toc-nav, .toc-hover-trigger, .toc-pin-btn {
                    display: none !important;
                }
                a { color: inherit !important; text-decoration: none !important; }
            }
            """
    }

    // Cached regex patterns
    private static let imageRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "<img[^>]*?src=\"([^\"]*)\"[^>]*?/?>")
    }()

    private static let videoSrcRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "<(?:video|source)\\b[^>]*?\\bsrc=\"([^\"]*)\"[^>]*?/?>", options: [.caseInsensitive])
    }()

    private static let htmlTagPatterns: [NSRegularExpression] = {
        let patterns = [
            try? NSRegularExpression(pattern: "<(?:img|br|hr|input|meta|link|area|base|col|embed|source|track|wbr)\\s*[^>]*/?\\s*>", options: [.caseInsensitive]),
            try? NSRegularExpression(pattern: "<(\\w+)[^>]*>[^<]*</\\1>", options: [.caseInsensitive]),
        ]
        return patterns.compactMap { $0 }
    }()

    // Paths
    private static let webkitPreviewURL: URL = {
        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseURL
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "MiaoYan", isDirectory: true)
            .appendingPathComponent("wkPreview", isDirectory: true)
    }()
    private static let previewHealthCheckPaths = [
        "index.html",
        "ppt.html",
        "css/base.css",
        "css/typography.css",
        "js/app.js",
        "js/common.js",
    ]

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
        let codeFontName = UserDefaultsManagement.codeFontName
        let fontConfig = ":root { --text-font: \"\(UserDefaultsManagement.previewFontName)\", \(fontStack); --code-text-font: \"\(codeFontName)\", \(codeFontStack); }"

        if UserDefaultsManagement.magicPPT {
            return "\(fontConfig) :root { --r-main-font: \"\(UserDefaultsManagement.previewFontName)\", sans-serif;}"
        }

        if UserDefaultsManagement.presentation {
            return "html {font-size: \(UserDefaultsManagement.presentationFontSize)px} \(fontConfig) #write { max-width: 100%;}"
        } else {
            let paddingStyle = UserDefaultsManagement.isOnExportHtml ? " padding-top: 24px" : ""

            var maxWidth = UserDefaultsManagement.previewWidth == UserDefaultsManagement.FullWidthValue ? "100%" : UserDefaultsManagement.previewWidth
            var writeCSS = "max-width: \(maxWidth); margin: 0"

            if UserDefaultsManagement.isOnExportHtml {
                maxWidth = "760px"
                writeCSS = "max-width: \(maxWidth); margin: 0 auto;"

                return "\(HtmlManager.exportCSS()) html {font-size: \(UserDefaultsManagement.previewFontSize)px; \(paddingStyle)} \(fontConfig) #write { \(writeCSS) }"
            }

            return "html {font-size: \(UserDefaultsManagement.previewFontSize)px; \(paddingStyle)} \(fontConfig) #write { \(writeCSS) }"
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

    private static func optimizeCDNImageURL(_ url: String) -> String {
        // Apply OSS compression for alipay CDN images (skip GIF/SVG)
        let lowerURL = url.lowercased()
        guard lowerURL.contains("alipayobjects.com") || lowerURL.contains("alicdn.com") || lowerURL.contains("fliggy.com") else {
            return url
        }
        // Skip GIF/SVG including URLs with query strings like image.gif?token=abc
        guard lowerURL.range(of: #"\.(gif|svg)(\?|#|$)"#, options: .regularExpression) == nil else {
            return url
        }
        let separator = url.contains("?") ? "&" : "?"
        return "\(url)\(separator)x-oss-process=image/auto-orient,1/resize,w_1600/format,webp"
    }

    // Transparent 1x1 GIF placeholder — used by Swift-side lazy image injection
    // Matches the placeholder in common.js so JS can pick up data-src and load the real image
    static let lazyPlaceholder = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"

    static func processImages(in html: String, imagesStorage: URL) -> String {
        guard let regex = imageRegex else {
            Task { @MainActor in
                AppDelegate.trackError(
                    NSError(
                        domain: "HtmlManager", code: 1,
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

        // Batch file existence checks to reduce I/O overhead
        let fileManager = FileManager.default
        var pathCache: [String: Bool] = [:]

        for (index, imageInfo) in images.enumerated() {
            let isFirstImage = index == 0

            // CDN images (http/https): rewrite to lazy-load format in Swift so browser never
            // starts downloading them before JS runs.
            // First image loads eagerly (hero/cover); rest use data-src + placeholder.
            if imageInfo.srcPath.starts(with: "http://") || imageInfo.srcPath.starts(with: "https://") {
                if isFirstImage {
                    // Hero image: keep eager, but compress if it's an alipay OSS image
                    let optimized = optimizeCDNImageURL(imageInfo.srcPath)
                    if optimized != imageInfo.srcPath {
                        htmlString = updateImageSrc(in: htmlString, fullMatch: imageInfo.fullMatch, oldSrc: imageInfo.srcPath, newSrc: optimized)
                    }
                } else {
                    // Non-hero CDN images: rewrite src → placeholder, add data-src + lazy-image class
                    let optimized = optimizeCDNImageURL(imageInfo.srcPath)
                    let lazyTag = imageInfo.fullMatch
                        .replacingOccurrences(of: "src=\"\(imageInfo.srcPath)\"", with: "src=\"\(lazyPlaceholder)\" data-src=\"\(optimized)\"")
                        .replacingOccurrences(of: "class=\"", with: "class=\"lazy-image ")
                    let finalTag = lazyTag.contains("class=") ? lazyTag : lazyTag.replacingOccurrences(of: "<img ", with: "<img class=\"lazy-image\" ")
                    htmlString = htmlString.replacingOccurrences(of: imageInfo.fullMatch, with: finalTag)
                }
                continue
            }

            let cleanPath = cleanImagePath(imageInfo.srcPath)

            // Local images: apply lazy loading (except first image)
            if isAbsolutePath(cleanPath) {
                let exists = pathCache[cleanPath] ?? fileManager.fileExists(atPath: cleanPath)
                pathCache[cleanPath] = exists

                if exists {
                    if isFirstImage {
                        // First image: eager load
                        htmlString = updateImageSrc(in: htmlString, fullMatch: imageInfo.fullMatch, oldSrc: imageInfo.srcPath, newSrc: "file://\(cleanPath)")
                    } else {
                        // Rest: lazy load
                        let lazyTag = imageInfo.fullMatch
                            .replacingOccurrences(of: "src=\"\(imageInfo.srcPath)\"", with: "src=\"\(lazyPlaceholder)\" data-src=\"file://\(cleanPath)\"")
                            .replacingOccurrences(of: "class=\"", with: "class=\"lazy-image ")
                        let finalTag = lazyTag.contains("class=") ? lazyTag : lazyTag.replacingOccurrences(of: "<img ", with: "<img class=\"lazy-image\" ")
                        htmlString = htmlString.replacingOccurrences(of: imageInfo.fullMatch, with: finalTag)
                    }
                } else {
                    htmlString = htmlString.replacingOccurrences(of: imageInfo.fullMatch, with: imageNotFoundPlaceholder)
                }
                continue
            }

            // Process relative paths - convert to absolute file:// URLs with lazy loading
            let absolutePath = imagesStorage.appendingPathComponent(cleanPath).path
            let exists = pathCache[absolutePath] ?? fileManager.fileExists(atPath: absolutePath)
            pathCache[absolutePath] = exists

            if exists {
                if isFirstImage {
                    htmlString = updateImageSrc(in: htmlString, fullMatch: imageInfo.fullMatch, oldSrc: imageInfo.srcPath, newSrc: "file://\(absolutePath)")
                } else {
                    let lazyTag = imageInfo.fullMatch
                        .replacingOccurrences(of: "src=\"\(imageInfo.srcPath)\"", with: "src=\"\(lazyPlaceholder)\" data-src=\"file://\(absolutePath)\"")
                        .replacingOccurrences(of: "class=\"", with: "class=\"lazy-image ")
                    let finalTag = lazyTag.contains("class=") ? lazyTag : lazyTag.replacingOccurrences(of: "<img ", with: "<img class=\"lazy-image\" ")
                    htmlString = htmlString.replacingOccurrences(of: imageInfo.fullMatch, with: finalTag)
                }
            } else {
                htmlString = htmlString.replacingOccurrences(of: imageInfo.fullMatch, with: imageNotFoundPlaceholder)
            }
        }

        // Process <video src> and <source src> — rewrite local paths to file://
        // CDN (http/https) video src: force preload="none" to prevent WebKit from
        // blocking preview while downloading a remote video
        if let videoRegex = videoSrcRegex {
            let videoResults = videoRegex.matches(in: htmlString, range: NSRange(htmlString.startIndex..., in: htmlString))
            let videoMatches = videoResults.compactMap { match -> (fullMatch: String, srcPath: String)? in
                guard let fullRange = Range(match.range, in: htmlString),
                    let srcRange = Range(match.range(at: 1), in: htmlString)
                else { return nil }
                return (String(htmlString[fullRange]), String(htmlString[srcRange]))
            }

            for videoInfo in videoMatches {
                if videoInfo.srcPath.starts(with: "http://") || videoInfo.srcPath.starts(with: "https://") {
                    // Remote video: disable eager preload so CDN latency/failure doesn't block preview
                    let noPreload = videoInfo.fullMatch
                        .replacingOccurrences(of: #"\bpreload="[^"]*""#, with: "preload=\"none\"", options: .regularExpression)
                        .replacingOccurrences(of: #"(?<=[^-\w])preload(?=[^=]|$)"#, with: "preload=\"none\"", options: .regularExpression)
                    if noPreload != videoInfo.fullMatch {
                        htmlString = htmlString.replacingOccurrences(of: videoInfo.fullMatch, with: noPreload)
                    }
                    continue
                }

                let cleanPath = cleanImagePath(videoInfo.srcPath)
                if isAbsolutePath(cleanPath) {
                    let exists = pathCache[cleanPath] ?? fileManager.fileExists(atPath: cleanPath)
                    pathCache[cleanPath] = exists

                    if exists {
                        var updatedTag = videoInfo.fullMatch
                            .replacingOccurrences(of: "src=\"\(videoInfo.srcPath)\"", with: "src=\"file://\(cleanPath)\"")
                        if !updatedTag.contains("preload=") {
                            updatedTag = updatedTag.replacingOccurrences(of: "<video ", with: "<video preload=\"none\" ")
                        }
                        htmlString = htmlString.replacingOccurrences(of: videoInfo.fullMatch, with: updatedTag)
                    }
                } else {
                    let absolutePath = imagesStorage.appendingPathComponent(cleanPath).path
                    let exists = pathCache[absolutePath] ?? fileManager.fileExists(atPath: absolutePath)
                    pathCache[absolutePath] = exists

                    if exists {
                        var updatedTag = videoInfo.fullMatch
                            .replacingOccurrences(of: "src=\"\(videoInfo.srcPath)\"", with: "src=\"file://\(absolutePath)\"")
                        if !updatedTag.contains("preload=") {
                            updatedTag = updatedTag.replacingOccurrences(of: "<video ", with: "<video preload=\"none\" ")
                        }
                        htmlString = htmlString.replacingOccurrences(of: videoInfo.fullMatch, with: updatedTag)
                    }
                }
            }
        }

        return htmlString
    }

    private static let fencedCodeBlockRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "(?m)^(`{3,}|~{3,}).*\\n[\\s\\S]*?^\\1\\s*$", options: [])
    }()

    private static let inlineCodeRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "(`+)(?!`).+?(?<!`)\\1(?!`)", options: [])
    }()

    private static func matchRanges(using regex: NSRegularExpression?, in text: String) -> [NSRange] {
        guard let regex = regex else { return [] }
        let fullRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: fullRange).map { $0.range }
    }

    private static func codeBlockRanges(in text: String) -> [NSRange] {
        var ranges = matchRanges(using: fencedCodeBlockRegex, in: text)

        let inlineRanges = matchRanges(using: inlineCodeRegex, in: text)
        ranges.append(
            contentsOf: inlineRanges.filter { inlineRange in
                !ranges.contains { $0.intersection(inlineRange) != nil }
            })

        return ranges
    }

    private static func isInsideCodeBlock(_ range: NSRange, codeRanges: [NSRange]) -> Bool {
        for codeRange in codeRanges where codeRange.intersection(range) != nil {
            return true
        }
        return false
    }

    static func processImagesInMarkdown(_ markdown: String, imagesStorage: URL) -> String {
        let pattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return markdown
        }

        let codeRanges = codeBlockRanges(in: markdown)
        let nsMarkdown = markdown as NSString
        let results = regex.matches(in: markdown, range: NSRange(location: 0, length: nsMarkdown.length))

        // Collect replacements with their ranges (only non-code-block matches)
        var replacements: [(range: NSRange, replacement: String)] = []

        for match in results {
            if isInsideCodeBlock(match.range, codeRanges: codeRanges) {
                continue
            }
            guard match.numberOfRanges >= 3 else { continue }

            let alt = nsMarkdown.substring(with: match.range(at: 1))
            let srcPath = nsMarkdown.substring(with: match.range(at: 2))

            guard !srcPath.starts(with: "http://"),
                !srcPath.starts(with: "https://"),
                !srcPath.starts(with: "file://")
            else {
                continue
            }

            let cleanPath = cleanImagePath(srcPath)

            if isAbsolutePath(cleanPath) {
                if FileManager.default.fileExists(atPath: cleanPath) {
                    replacements.append((match.range, "![\(alt)](file://\(cleanPath))"))
                }
                continue
            }

            let absolutePath = imagesStorage.appendingPathComponent(cleanPath).path
            if FileManager.default.fileExists(atPath: absolutePath) {
                replacements.append((match.range, "![\(alt)](file://\(absolutePath))"))
            }
        }

        // Apply replacements in reverse order to preserve earlier ranges
        let mutable = NSMutableString(string: markdown)
        for item in replacements.reversed() {
            mutable.replaceCharacters(in: item.range, with: item.replacement)
        }

        return mutable as String
    }

    // MARK: - Bundle and Resource Management

    static func getDownViewBundle() -> Bundle? {
        return downViewBundle
    }

    static func previewBundleURL() -> URL {
        return webkitPreviewURL
    }

    private static func areRequiredPreviewResourcesMissing() -> Bool {
        let fileManager = FileManager.default
        return previewHealthCheckPaths.contains { relativePath in
            !fileManager.fileExists(atPath: webkitPreviewURL.appendingPathComponent(relativePath).path)
        }
    }

    private static func syncBundleContents(from sourceDirectory: URL, to destinationDirectory: URL) throws -> Bool {
        let fileManager = FileManager.default
        var repairedAnyFile = false

        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true, attributes: nil)

        let sourceItems = try fileManager.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        for sourceItem in sourceItems {
            let resourceValues = try sourceItem.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            let destinationItem = destinationDirectory.appendingPathComponent(
                sourceItem.lastPathComponent,
                isDirectory: resourceValues.isDirectory == true
            )

            if resourceValues.isDirectory == true {
                repairedAnyFile = (try syncBundleContents(from: sourceItem, to: destinationItem)) || repairedAnyFile
                continue
            }

            // Check if file needs update: missing or source is newer
            var needsUpdate = !fileManager.fileExists(atPath: destinationItem.path)
            if !needsUpdate, let sourceModDate = resourceValues.contentModificationDate {
                let destResourceValues = try? destinationItem.resourceValues(forKeys: [.contentModificationDateKey])
                if let destModDate = destResourceValues?.contentModificationDate {
                    needsUpdate = sourceModDate > destModDate
                } else {
                    needsUpdate = true
                }
            }

            guard needsUpdate else {
                continue
            }

            try fileManager.createDirectory(
                at: destinationItem.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )

            if fileManager.fileExists(atPath: destinationItem.path) {
                try fileManager.removeItem(at: destinationItem)
            }

            try fileManager.copyItem(at: sourceItem, to: destinationItem)
            repairedAnyFile = true
        }

        return repairedAnyFile
    }

    @MainActor
    @discardableResult
    static func ensurePreviewResourcesAvailable() -> Bool {
        guard let bundle = getDownViewBundle(),
            let bundleResourceURL = bundle.resourceURL
        else {
            return false
        }

        let fileManager = FileManager.default
        var repairedResources = areRequiredPreviewResourcesMissing()

        do {
            repairedResources = (try syncBundleContents(from: bundleResourceURL, to: webkitPreviewURL)) || repairedResources
        } catch {
            AppDelegate.trackError(error, context: "HtmlManager.ensurePreviewResourcesAvailable.copyBundleResource")
        }

        if let customCSS = UserDefaultsManagement.markdownPreviewCSS {
            let cssDst = webkitPreviewURL.appendingPathComponent("css", isDirectory: true)
            let styleDst = cssDst.appendingPathComponent("markdown-preview.css", isDirectory: false)
            do {
                try fileManager.createDirectory(at: cssDst, withIntermediateDirectories: true, attributes: nil)
                let needsRefresh = !fileManager.fileExists(atPath: styleDst.path)
                    || !fileManager.contentsEqual(atPath: customCSS.path, andPath: styleDst.path)
                if needsRefresh {
                    if fileManager.fileExists(atPath: styleDst.path) {
                        try fileManager.removeItem(at: styleDst)
                    }
                    try fileManager.copyItem(at: customCSS, to: styleDst)
                    repairedResources = true
                }
            } catch {
                AppDelegate.trackError(error, context: "HtmlManager.ensurePreviewResourcesAvailable.copyCustomCSS")
            }
        }

        return repairedResources
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
        if UserDefaultsManagement.isOnExportHtml, !htmlString.hasPrefix("<h1>") {
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

        if UserDefaultsManagement.isOnExportPPT {
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
        guard getDownViewBundle() != nil else {
            return nil
        }
        _ = ensurePreviewResourcesAvailable()

        let indexName = "index-\(UUID().uuidString).html"
        let indexURL = webkitPreviewURL.appendingPathComponent(indexName)

        try? pageHTMLString.write(to: indexURL, atomically: true, encoding: .utf8)

        // Clean up old index files asynchronously to prevent storage growth
        Task.detached {
            let fileManager = FileManager.default
            guard let contents = try? fileManager.contentsOfDirectory(at: webkitPreviewURL, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else { return }

            let now = Date()
            for fileURL in contents {
                if fileURL.lastPathComponent.hasPrefix("index-") && fileURL.pathExtension == "html" && fileURL.lastPathComponent != indexName {
                    if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                        let creationDate = attrs[.creationDate] as? Date
                    {
                        // Remove files older than 5 minutes to ensure parallel loading finishes
                        if now.timeIntervalSince(creationDate) > 300 {
                            try? fileManager.removeItem(at: fileURL)
                        }
                    }
                }
            }
        }

        return indexURL
    }

    // MARK: - JavaScript Utilities
    static let checkImagesScript = """
        (function() {
            // Force-load any lazy images so they are included in the export
            document.querySelectorAll('img[data-src]').forEach(function(img) {
                img.src = img.dataset.src;
                img.classList.remove('lazy-image');
                img.removeAttribute('data-src');
            });

            var images = document.getElementsByTagName('img');
            if (images.length === 0) return true;

            for (var i = 0; i < images.length; i++) {
                if (!images[i].complete) return false;
            }
            return true;
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
