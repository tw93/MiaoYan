import Foundation

/// Leading YAML frontmatter, the one rule every surface that shows a note's
/// body follows: the Mac preview and export, the iPhone reader, card
/// previews and search snippets.
public enum Frontmatter {
    /// The note body after a leading `---` block, or the whole text when it
    /// does not open with one or the block is never closed on its own line.
    public static func body(of markdown: String) -> Substring {
        guard markdown.hasPrefix("---\n") || markdown.hasPrefix("---\r\n") else {
            return Substring(markdown)
        }
        // "---\n" and "---\r\n" are both 4 Characters: \r\n is a single grapheme.
        let afterOpening = markdown.index(markdown.startIndex, offsetBy: 4)
        // Grapheme-aware search never matches the "\n" inside a "\r\n" cluster,
        // so CRLF documents need their own needle.
        guard
            let closingRange = markdown.range(of: "\n---", range: afterOpening..<markdown.endIndex)
                ?? markdown.range(of: "\r\n---", range: afterOpening..<markdown.endIndex)
        else {
            return Substring(markdown)
        }
        // Closing fence must be its own line: end-of-string or followed by a newline
        // (which is the "\r\n" grapheme in CRLF documents).
        let afterClose = closingRange.upperBound
        if afterClose == markdown.endIndex {
            return Substring("")
        }
        let nextChar = markdown[afterClose]
        guard nextChar == "\n" || nextChar == "\r" || nextChar == "\r\n" else {
            return Substring(markdown)
        }
        let bodyStart = markdown.index(after: afterClose)
        return markdown[bodyStart..<markdown.endIndex]
    }
}
