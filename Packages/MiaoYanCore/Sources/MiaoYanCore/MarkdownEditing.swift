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
            // `* * *` and `- - -` are rules, not items.
            ruleRegex.firstMatch(in: text as String, range: line) == nil,
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
        // A note written with CRLF keeps one kind of line ending.
        let lineBreak = text.range(of: "\r\n").location == NSNotFound ? "\n" : "\r\n"
        let insertion = lineBreak + indent + next(bullet) + " " + (isTask ? "[ ] " : "")
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

    // Both run on one cmark line only, so `^` and `$` are its ends: with
    // `.anchorsMatchLines` they also matched at U+2028 and U+2029 inside it,
    // and `text<U+2028>- ` read as an empty item whose Return deleted the
    // whole line. `.` crosses those separators for the same reason.
    private static let itemRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*(?:>[ \t]*)*)([-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\][ \t]+|\[[ xX]\]$)?(.*)$"#,
        options: [.dotMatchesLineSeparators])
    private static let ruleRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
}

/// Line commands the iPhone and iPad editor runs from a hardware keyboard,
/// the Mac Format menu's Shift Right, Shift Left and Todo: each returns the
/// one replacement to make and the selection to leave.
public enum LineEdits {
    public struct Edit: Equatable {
        public let range: NSRange
        public let replacement: String
        public let selection: NSRange
    }

    /// Two more spaces before every line the selection touches; an empty
    /// line stays empty. Under an ordered item CommonMark nests only at the
    /// item's content column (three spaces for `1. `, four for `10. `), so
    /// when the line above the selection is one, the lines move that far.
    public static func indent(in text: NSString, selection: NSRange) -> Edit? {
        var padding = 2
        if let parent = orderedParent(in: text, selection: selection), parent.firstIndent < parent.contentColumn {
            padding = parent.contentColumn - parent.firstIndent
        }
        let spaces = String(repeating: " ", count: padding)
        return rewrite(in: text, selection: selection) { $0.isEmpty ? $0 : spaces + $0 }
    }

    /// A leading tab, or up to two leading spaces, off every line the
    /// selection touches; lines that `indent` nested under an ordered item
    /// go back to that item's own indent.
    public static func outdent(in text: NSString, selection: NSRange) -> Edit? {
        var width = 2
        if let parent = orderedParent(in: text, selection: selection),
            parent.firstIndent > parent.indent, parent.firstIndent <= parent.contentColumn
        {
            width = parent.firstIndent - parent.indent
        }
        return rewrite(in: text, selection: selection) { line in
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            return String(line.dropFirst(line.prefix(width).prefix(while: { $0 == " " }).count))
        }
    }

    /// An ordered item's indent and content column, and the indent of the
    /// selection's first line below it, in columns with tabs every four.
    private struct OrderedParent {
        let indent: Int
        let contentColumn: Int
        let firstIndent: Int
    }

    /// The ordered item on the line just above the selection's first line.
    private static func orderedParent(in text: NSString, selection: NSRange) -> OrderedParent? {
        guard selection.location >= 0, NSMaxRange(selection) <= text.length else { return nil }
        var start = 0
        var end = 0
        var contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: selection.location, length: 0))
        guard start > 0 else { return nil }
        let first = text.substring(with: NSRange(location: start, length: contentsEnd - start))
        var aboveStart = 0
        var aboveContentsEnd = 0
        text.getLineStart(&aboveStart, end: &end, contentsEnd: &aboveContentsEnd, for: NSRange(location: start - 1, length: 0))
        let above = text.substring(with: NSRange(location: aboveStart, length: aboveContentsEnd - aboveStart))
        guard let match = orderedRegex.firstMatch(in: above, range: NSRange(location: 0, length: (above as NSString).length))
        else { return nil }
        let ns = above as NSString
        let indent = columns(of: ns.substring(with: match.range(at: 1)))
        let afterMarker = indent + match.range(at: 2).length
        // One to four spaces after the marker set the content column; more
        // than four, or none before the line ends, count as one.
        let gap = columns(of: ns.substring(with: match.range(at: 3)), from: afterMarker) - afterMarker
        let contentColumn = afterMarker + (gap >= 1 && gap <= 4 && match.range(at: 4).length > 0 ? gap : 1)
        let leading = String(first.prefix(while: { $0 == " " || $0 == "\t" }))
        return OrderedParent(indent: indent, contentColumn: contentColumn, firstIndent: columns(of: leading))
    }

    /// The column after `whitespace` written from column `from`.
    private static func columns(of whitespace: String, from: Int = 0) -> Int {
        whitespace.reduce(from) { column, character in character == "\t" ? column + 4 - column % 4 : column + 1 }
    }

    /// Ticks or clears the task on each line the selection touches; a list
    /// item without a box gains an empty one, and plain text becomes a task.
    public static func toggleTask(in text: NSString, selection: NSRange) -> Edit? {
        rewrite(in: text, selection: selection) { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            let ns = line as NSString
            let whole = NSRange(location: 0, length: ns.length)
            if let match = taskRegex.firstMatch(in: line, range: whole) {
                let mark = match.range(at: 1)
                return ns.replacingCharacters(in: mark, with: ns.substring(with: mark) == " " ? "x" : " ")
            }
            if let match = itemRegex.firstMatch(in: line, range: whole) {
                return ns.replacingCharacters(in: NSRange(location: NSMaxRange(match.range), length: 0), with: "[ ] ")
            }
            // The indent and any `>` quote markers stay in front of the box.
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" || $0 == ">" })
            return indent + "- [ ] " + line.dropFirst(indent.count)
        }
    }

    /// Applies `change` to each line of the selection's lines. A caret keeps
    /// its distance from the end of its line; a selection becomes the lines.
    private static func rewrite(in text: NSString, selection: NSRange, _ change: (String) -> String) -> Edit? {
        guard selection.location >= 0, NSMaxRange(selection) <= text.length else { return nil }
        var start = 0
        var contentsEnd = 0
        var end = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: selection)
        // The lines without the last one's ending, so that ending stays put.
        let block = NSRange(location: start, length: contentsEnd - start)
        let old = text.substring(with: block)
        let new = old.components(separatedBy: "\n").map { line -> String in
            line.hasSuffix("\r") ? change(String(line.dropLast())) + "\r" : change(line)
        }.joined(separator: "\n")
        guard new != old else { return nil }
        let newLength = (new as NSString).length
        if selection.length == 0 {
            let fromEnd = NSMaxRange(block) - selection.location
            let caret = block.location + max(0, newLength - fromEnd)
            return Edit(range: block, replacement: new, selection: NSRange(location: caret, length: 0))
        }
        return Edit(range: block, replacement: new, selection: NSRange(location: block.location, length: newLength))
    }

    private static let taskRegex = try! NSRegularExpression(pattern: #"^[ \t>]*(?:[-*+]|\d+[.)])[ \t]+\[([ xX])\]"#)
    private static let itemRegex = try! NSRegularExpression(pattern: #"^[ \t>]*(?:[-*+]|\d+[.)])[ \t]+"#)
    private static let orderedRegex = try! NSRegularExpression(pattern: #"^([ \t]*)(\d{1,9}[.)])([ \t]+|$)(.?)"#)
}
