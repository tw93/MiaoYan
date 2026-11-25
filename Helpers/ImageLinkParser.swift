import Foundation
import MiaoYanCore

class ImageLinkParser {

    // Patterns are compile-time literals; compilation cannot fail at runtime.
    // If a future edit breaks the pattern, the precondition fires at first use
    // instead of crashing inside `enumerateMatches` with a less actionable trace.
    static let markdownImageRegex: NSRegularExpression = {
        let pattern = "!\\[([^\\]]*)\\]\\(([^\\)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            preconditionFailure("ImageLinkParser.markdownImageRegex literal is invalid: \(pattern)")
        }
        return regex
    }()

    static let htmlImageRegex: NSRegularExpression = {
        let pattern = "<img[^>]*src\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            preconditionFailure("ImageLinkParser.htmlImageRegex literal is invalid: \(pattern)")
        }
        return regex
    }()

    private static let htmlAltRegex: NSRegularExpression = {
        let pattern = "alt\\s*=\\s*[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            preconditionFailure("ImageLinkParser.htmlAltRegex literal is invalid: \(pattern)")
        }
        return regex
    }()

    static func detectImageLink(in text: String, at location: Int) -> ImageLinkInfo? {
        detectImageLink(in: text as NSString, at: location)
    }

    /// Runs on every mouse move over the editor, so it reads only the block
    /// around `location`, never the whole note. Both patterns can cross a
    /// line break (an `<img>` with its attributes on lines of their own, alt
    /// text wrapped onto a second line), but neither Markdown nor HTML lets
    /// an image run past a blank line, so the window is the lines up to the
    /// nearest blank line on each side, at most `hoverLineReach` lines each
    /// way. An image spread over more lines than that is not found. A video
    /// or a file written as an image is not one (`isPreviewableImage`).
    static func detectImageLink(in text: NSString, at location: Int) -> ImageLinkInfo? {
        let window = hoverWindow(around: location, in: text)
        let local = text.substring(with: window) as NSString
        let localRange = NSRange(location: 0, length: local.length)
        let localLocation = location - window.location

        let found =
            detectMarkdownImage(in: local, at: localLocation, fullRange: localRange)
            ?? detectHtmlImage(in: local, at: localLocation, fullRange: localRange)
        guard let found, isPreviewableImage(src: found.src) else { return nil }
        func shifted(_ range: NSRange) -> NSRange { NSRange(location: range.location + window.location, length: range.length) }
        return ImageLinkInfo(type: found.type, src: found.src, alt: found.alt, range: shifted(found.range), srcRange: shifted(found.srcRange))
    }

    /// Whether the hover preview should load `src` as an image. A video
    /// written as one, `![](/files/clip.mov)`, was read with NSImage on the
    /// main thread after every 0.3s hover and, never drawing, read again on
    /// the next; the same for any other file. The kind comes from the shared
    /// `AttachmentFile` rule. A name with no extension and a `data:` URI still
    /// go, and so does a remote address that is not a video, since an image
    /// endpoint can end in anything (`avatar.php?u=1`).
    static func isPreviewableImage(src: String) -> Bool {
        var path = src.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("<"), let end = path.firstIndex(of: ">") {
            path = String(path[path.index(after: path.startIndex)..<end])
        } else {
            path = String(path.prefix { !$0.isWhitespace })
        }
        let lower = path.lowercased()
        if lower.hasPrefix("data:") { return true }
        let bare = path.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? path
        let ext = (bare as NSString).pathExtension
        guard !ext.isEmpty else { return true }
        switch AttachmentFile.kind(ofExtension: ext) {
        case .image: return true
        case .video: return false
        case .file: return lower.hasPrefix("http://") || lower.hasPrefix("https://")
        }
    }

    static let hoverLineReach = 32
    private static let visible = CharacterSet.whitespacesAndNewlines.inverted

    static func hoverWindow(around location: Int, in text: NSString) -> NSRange {
        let length = text.length
        let at = min(max(location, 0), length)
        func isBlank(_ line: NSRange) -> Bool {
            text.rangeOfCharacter(from: visible, options: [], range: line).location == NSNotFound
        }
        var window = text.paragraphRange(for: NSRange(location: at, length: 0))
        var steps = 0
        while window.location > 0, steps < hoverLineReach {
            let above = text.paragraphRange(for: NSRange(location: window.location - 1, length: 0))
            if isBlank(above) { break }
            window = NSUnionRange(above, window)
            steps += 1
        }
        steps = 0
        while NSMaxRange(window) < length, steps < hoverLineReach {
            let below = text.paragraphRange(for: NSRange(location: NSMaxRange(window), length: 0))
            if isBlank(below) { break }
            window = NSUnionRange(window, below)
            steps += 1
        }
        return window
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
        let range = NSRange(location: 0, length: htmlImg.count)
        if let match = htmlAltRegex.firstMatch(in: htmlImg, options: [], range: range) {
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
