import Foundation

/// Emphasis on Chinese, Japanese or Korean stays upright. Their faces have no
/// italic, so WebKit slants the ideographs synthetically, and disabling style
/// synthesis instead (`font-synthesis: weight`) also dropped the synthetic
/// bold of single-weight faces such as TsangerJinKai when italic was asked.
/// An `<em>` whose text uses one of those scripts takes a `lang` for it, and
/// the stylesheets slant only an `em` without one. Decided per element, since
/// the Mac preview has no document language and the iPhone's dominant one
/// says nothing about a single phrase.
public enum Emphasis {
    private static let emRegex = try? NSRegularExpression(
        pattern: #"<em>(.*?)</em>"#, options: [.dotMatchesLineSeparators])
    private static let tagRegex = try? NSRegularExpression(pattern: #"<[^>]*>"#)

    /// The rendered HTML with every CJK `<em>` given its `lang`; other markup,
    /// including tags inside the emphasis, is left as it was.
    public static func markCJK(in html: String) -> String {
        guard html.contains("<em>"), let emRegex else { return html }
        let ns = html as NSString
        var result = ""
        var last = 0
        for match in emRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let inner = ns.substring(with: match.range(at: 1))
            if let lang = language(of: plainText(inner)) {
                result += "<em lang=\"\(lang)\">\(inner)</em>"
            } else {
                result += ns.substring(with: match.range)
            }
            last = NSMaxRange(match.range)
        }
        result += ns.substring(from: last)
        return result
    }

    /// `ja` for kana, `ko` for Hangul, `zh` for Han alone, nil otherwise.
    static func language(of text: String) -> String? {
        var han = false
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF: return "ja"
            case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF: return "ko"
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FFFF: han = true
            default: continue
            }
        }
        return han ? "zh" : nil
    }

    private static func plainText(_ html: String) -> String {
        guard html.contains("<"), let tagRegex else { return html }
        return tagRegex.stringByReplacingMatches(
            in: html, range: NSRange(location: 0, length: (html as NSString).length), withTemplate: "")
    }
}
