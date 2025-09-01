import Foundation

class ImageLinkParser {

    // Markdown 图片链接正则: ![alt](src)
    static let markdownImageRegex = try! NSRegularExpression(
        pattern: "!\\[([^\\]]*)\\]\\(([^\\)]+)\\)",
        options: []
    )

    // HTML img 标签正则: <img src="...">
    static let htmlImageRegex = try! NSRegularExpression(
        pattern: "<img[^>]*src\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>",
        options: [.caseInsensitive]
    )

    // 检测指定位置是否为图片链接
    static func detectImageLink(in text: String, at location: Int) -> ImageLinkInfo? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // 检查 Markdown 格式
        if let markdownInfo = detectMarkdownImage(in: nsText, at: location, fullRange: fullRange) {
            return markdownInfo
        }

        // 检查 HTML 格式
        if let htmlInfo = detectHtmlImage(in: nsText, at: location, fullRange: fullRange) {
            return htmlInfo
        }

        return nil
    }

    private static func detectMarkdownImage(in text: NSString, at location: Int, fullRange: NSRange) -> ImageLinkInfo? {
        var result: ImageLinkInfo?

        markdownImageRegex.enumerateMatches(in: text as String, options: [], range: fullRange) { match, _, stop in
            guard let match = match else { return }

            // 检查光标是否在匹配范围内
            if NSLocationInRange(location, match.range) {
                let srcRange = match.range(at: 2)
                let altRange = match.range(at: 1)

                if srcRange.location != NSNotFound {
                    let src = text.substring(with: srcRange)
                    let alt = altRange.location != NSNotFound ? text.substring(with: altRange) : ""

                    result = ImageLinkInfo(
                        type: .markdown,
                        src: src,
                        alt: alt,
                        range: match.range,
                        srcRange: srcRange
                    )
                    stop.pointee = true
                }
            }
        }

        return result
    }

    private static func detectHtmlImage(in text: NSString, at location: Int, fullRange: NSRange) -> ImageLinkInfo? {
        var result: ImageLinkInfo?

        htmlImageRegex.enumerateMatches(in: text as String, options: [], range: fullRange) { match, _, stop in
            guard let match = match else { return }

            // 检查光标是否在匹配范围内
            if NSLocationInRange(location, match.range) {
                let srcRange = match.range(at: 1)

                if srcRange.location != NSNotFound {
                    let src = text.substring(with: srcRange)
                    let fullMatch = text.substring(with: match.range)

                    // 尝试提取 alt 属性
                    let alt = extractAltFromHtmlImg(fullMatch)

                    result = ImageLinkInfo(
                        type: .html,
                        src: src,
                        alt: alt,
                        range: match.range,
                        srcRange: srcRange
                    )
                    stop.pointee = true
                }
            }
        }

        return result
    }

    private static func extractAltFromHtmlImg(_ htmlImg: String) -> String {
        let altRegex = try! NSRegularExpression(
            pattern: "alt\\s*=\\s*[\"']([^\"']+)[\"']",
            options: [.caseInsensitive]
        )

        let range = NSRange(location: 0, length: htmlImg.count)
        if let match = altRegex.firstMatch(in: htmlImg, options: [], range: range) {
            let altRange = match.range(at: 1)
            if altRange.location != NSNotFound {
                return (htmlImg as NSString).substring(with: altRange)
            }
        }

        return ""
    }

    // 获取所有图片链接
    static func getAllImageLinks(in text: String) -> [ImageLinkInfo] {
        var links: [ImageLinkInfo] = []
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // 获取 Markdown 图片
        markdownImageRegex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }

            let srcRange = match.range(at: 2)
            let altRange = match.range(at: 1)

            if srcRange.location != NSNotFound {
                let src = nsText.substring(with: srcRange)
                let alt = altRange.location != NSNotFound ? nsText.substring(with: altRange) : ""

                let info = ImageLinkInfo(
                    type: .markdown,
                    src: src,
                    alt: alt,
                    range: match.range,
                    srcRange: srcRange
                )
                links.append(info)
            }
        }

        // 获取 HTML 图片
        htmlImageRegex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }

            let srcRange = match.range(at: 1)

            if srcRange.location != NSNotFound {
                let src = nsText.substring(with: srcRange)
                let fullMatch = nsText.substring(with: match.range)
                let alt = extractAltFromHtmlImg(fullMatch)

                let info = ImageLinkInfo(
                    type: .html,
                    src: src,
                    alt: alt,
                    range: match.range,
                    srcRange: srcRange
                )
                links.append(info)
            }
        }

        return links
    }
}

// 图片链接类型
enum ImageLinkType {
    case markdown
    case html
}

// 图片链接信息
struct ImageLinkInfo {
    let type: ImageLinkType
    let src: String
    let alt: String
    let range: NSRange  // 整个匹配的范围
    let srcRange: NSRange  // src 的范围
}
