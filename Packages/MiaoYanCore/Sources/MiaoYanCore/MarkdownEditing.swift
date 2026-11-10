import Foundation

/// Source lines as cmark counts them: a line ends only at `\n`, `\r\n` or
/// `\r`. `NSString.lineRange` also breaks at U+2028, U+2029 and U+0085,
/// which text pasted from the web carries, so a line number the preview
/// reports (`data-sourcepos`) would land on the wrong line.
public enum SourceLines {
    /// The UTF-16 range of line `index` (0-based) without its line ending,
    /// or nil when the text has fewer lines.
    public static func range(ofLine index: Int, in text: NSString) -> NSRange? {
        var start = 0
        for _ in 0..<max(index, 0) {
            let next = end(from: start, in: text).next
            guard next < text.length else { return nil }
            start = next
        }
        return NSRange(location: start, length: end(from: start, in: text).end - start)
    }

    /// The 0-based line holding UTF-16 `offset`.
    public static func line(atOffset offset: Int, in text: NSString) -> Int {
        let limit = min(max(offset, 0), text.length)
        var line = 0
        var start = 0
        while true {
            let next = end(from: start, in: text).next
            if next > limit || next >= text.length { return line }
            start = next
            line += 1
        }
    }

    private static func end(from start: Int, in text: NSString) -> (end: Int, next: Int) {
        var index = start
        while index < text.length {
            let unit = text.character(at: index)
            if unit == 0x0A { return (index, index + 1) }
            if unit == 0x0D {
                let crlf = index + 1 < text.length && text.character(at: index + 1) == 0x0A
                return (index, index + (crlf ? 2 : 1))
            }
            index += 1
        }
        return (text.length, text.length)
    }
}

/// The `[ ]` of a task item, found by the line the preview reports.
public enum TaskMarker {
    /// The range of the space or x inside `[ ]` on the task item at
    /// `bodyLine` (1-based, counted after the frontmatter the preview drops).
    public static func range(in text: String, bodyLine: Int) -> NSRange? {
        let target = Frontmatter.lineCount(of: text) + bodyLine - 1
        guard target >= 0, let line = SourceLines.range(ofLine: target, in: text as NSString),
            let match = itemRegex.firstMatch(in: text, range: line),
            match.range(at: 1).location != NSNotFound
        else { return nil }
        return match.range(at: 1)
    }

    /// `text` with that task item ticked or cleared, or nil when the line
    /// holds no task item.
    public static func toggled(_ text: String, bodyLine: Int) -> String? {
        guard let range = range(in: text, bodyLine: bodyLine) else { return nil }
        let marker = (text as NSString).substring(with: range)
        return (text as NSString).replacingCharacters(in: range, with: marker == " " ? "x" : " ")
    }

    private static let itemRegex = try! NSRegularExpression(
        pattern: #"^[ \t>]*(?:[-*+]|\d+[.)])[ \t]+\[([ xX])\]"#, options: [.anchorsMatchLines])
}

/// What Return does at the end of a list line: the next item's marker is
/// written for the writer, and Return on an item left empty ends the list.
public enum ListContinuation {
    public struct Edit: Equatable {
        /// The range of the old text to replace.
        public let range: NSRange
        public let replacement: String
        /// Where the caret goes afterwards, in the new text.
        public let caret: Int
    }

    /// The edit for Return with the caret at `caret`, or nil when a plain
    /// newline is right: the caret is not at the end of a list line, or the
    /// line is no list item.
    public static func edit(in text: NSString, caret: Int) -> Edit? {
        guard caret >= 0, caret <= text.length else { return nil }
        let lineIndex = SourceLines.line(atOffset: caret, in: text)
        guard let line = SourceLines.range(ofLine: lineIndex, in: text), caret == NSMaxRange(line),
            let match = itemRegex.firstMatch(in: text as String, range: line)
        else { return nil }
        let indent = text.substring(with: match.range(at: 1))
        let bullet = text.substring(with: match.range(at: 2))
        let isTask = match.range(at: 3).location != NSNotFound
        let content = text.substring(with: match.range(at: 4))

        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            // An item with nothing in it: Return hands the line back.
            return Edit(range: line, replacement: "", caret: line.location)
        }
        let insertion = "\n" + indent + next(bullet) + " " + (isTask ? "[ ] " : "")
        return Edit(
            range: NSRange(location: caret, length: 0), replacement: insertion,
            caret: caret + (insertion as NSString).length)
    }

    /// `3.` becomes `4.`; a bullet stays as it is.
    private static func next(_ bullet: String) -> String {
        guard let closer = bullet.last, closer == "." || closer == ")", let number = Int(bullet.dropLast()) else {
            return bullet
        }
        return "\(number + 1)\(closer)"
    }

    private static let itemRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*(?:>[ \t]*)*)([-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\][ \t]+|\[[ xX]\]$)?(.*)$"#,
        options: [.anchorsMatchLines])
}
