import Foundation

class ImageLinkParser {

    static let markdownImageRegex = try! NSRegularExpression(
        pattern: "!\\[([^\\]]*)\\]\\(([^\\)]+)\\)",
        options: []
    )

    static let htmlImageRegex = try! NSRegularExpression(
        pattern: "<img[^>]*src\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>",
        options: [.caseInsensitive]
    )

    static func detectImageLink(in text: String, at location: Int) -> ImageLinkInfo? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        if let markdownInfo = detectMarkdownImage(in: nsText, at: location, fullRange: fullRange) {
            return markdownInfo
        }

        if let htmlInfo = detectHtmlImage(in: nsText, at: location, fullRange: fullRange) {
            return htmlInfo
        }

        return nil
    }

    private static func detectMarkdownImage(in text: NSString, at location: Int, fullRange: NSRange) -> ImageLinkInfo? {
        var result: ImageLinkInfo?

        markdownImageRegex.enumerateMatches(in: text as String, options: [], range: fullRange) { match, _, stop in
            guard let match = match else { return }

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

            if NSLocationInRange(location, match.range) {
                let srcRange = match.range(at: 1)

                if srcRange.location != NSNotFound {
                    let src = text.substring(with: srcRange)
                    let fullMatch = text.substring(with: match.range)

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

    static func getAllImageLinks(in text: String) -> [ImageLinkInfo] {
        var links: [ImageLinkInfo] = []
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

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

enum ImageLinkType {
    case markdown
    case html
}

struct ImageLinkInfo {
    let type: ImageLinkType
    let src: String
    let alt: String
    let range: NSRange
    let srcRange: NSRange
}
