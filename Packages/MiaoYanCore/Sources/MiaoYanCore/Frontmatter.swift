import Foundation

/// Leading YAML frontmatter, the one rule every surface that shows a note's
/// body follows: the Mac preview and export, the iPhone reader, card
/// previews and search snippets.
public enum Frontmatter {
    /// The note body after a leading `---` block, or the whole text when it
    /// does not open with one, the block is never closed on its own line, or
    /// the block is not YAML. A slide deck opens with `---` too, and stripping
    /// its first slide as frontmatter lost that slide in PPT and the preview.
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
        if afterClose != markdown.endIndex {
            let nextChar = markdown[afterClose]
            guard nextChar == "\n" || nextChar == "\r" || nextChar == "\r\n" else {
                return Substring(markdown)
            }
        }
        guard looksLikeYAML(markdown[afterOpening..<closingRange.lowerBound]) else {
            return Substring(markdown)
        }
        if afterClose == markdown.endIndex {
            return Substring("")
        }
        let bodyStart = markdown.index(after: afterClose)
        return markdown[bodyStart..<markdown.endIndex]
    }

    /// True when the text opens with `---` and no later line closes it, as
    /// happens when a card reads only the first bytes of a long note.
    public static func opensUnclosedBlock(_ markdown: String) -> Bool {
        guard markdown.hasPrefix("---\n") || markdown.hasPrefix("---\r\n") else { return false }
        let afterOpening = markdown.index(markdown.startIndex, offsetBy: 4)
        var searchStart = afterOpening
        while let range = markdown.range(of: "\n---", range: searchStart..<markdown.endIndex)
            ?? markdown.range(of: "\r\n---", range: searchStart..<markdown.endIndex)
        {
            if range.upperBound == markdown.endIndex { return false }
            let next = markdown[range.upperBound]
            if next == "\n" || next == "\r" || next == "\r\n" { return false }
            searchStart = range.upperBound
        }
        return true
    }

    /// At least one `key: value` line, and every other non-blank line a
    /// continuation (indented or a `- ` list item) or a `#` comment. A
    /// Markdown heading alone never qualifies.
    static func looksLikeYAML(_ block: Substring) -> Bool {
        var keys = 0
        for line in block.split(whereSeparator: \.isNewline) {
            guard let first = line.first, !line.allSatisfy(\.isWhitespace) else { continue }
            if first == " " || first == "\t" || line == "-" || line.hasPrefix("- ") { continue }
            if first == "#" { continue }
            guard let colon = line.firstIndex(of: ":") else { return false }
            let after = line.index(after: colon)
            guard after == line.endIndex || line[after] == " " || line[after] == "\t" else { return false }
            keys += 1
        }
        return keys > 0
    }
}
