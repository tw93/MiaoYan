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

    /// The range, without its line ending, of the line holding `offset`,
    /// read from that line alone. Return and paste ask this of the caret, and
    /// counting lines from the top made Return cost 16 ms in a note of 34,000
    /// lines.
    public static func range(around offset: Int, in text: NSString) -> NSRange {
        var start = min(max(offset, 0), text.length)
        // Between the two units of `\r\n` is the end of the line before.
        if start > 0, start < text.length, text.character(at: start) == 0x0A, text.character(at: start - 1) == 0x0D {
            start -= 1
        }
        while start > 0 {
            let unit = text.character(at: start - 1)
            if unit == 0x0A || unit == 0x0D { break }
            start -= 1
        }
        return NSRange(location: start, length: end(from: start, in: text).end - start)
    }

    /// Calls `body` with each line's index and range, without its line
    /// ending, until it returns false; one pass over the text.
    static func forEach(in text: NSString, _ body: (Int, NSRange) -> Bool) {
        var start = 0
        var index = 0
        while true {
            let (end, next) = end(from: start, in: text)
            guard body(index, NSRange(location: start, length: end - start)), next < text.length else { return }
            start = next
            index += 1
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

/// What Return does at the end of a list or quote line: the next item's
/// marker, or the quote's `>`, is written for the writer, and Return on an
/// item or quote line left empty ends the list or quote. The Mac editor and
/// the iPhone and iPad editor both take their Return from here.
public enum ListContinuation {
    public struct Edit: Equatable {
        /// The range of the old text to replace.
        public let range: NSRange
        public let replacement: String
        /// Where the caret goes afterwards, in the new text.
        public let caret: Int
    }

    /// The edit for Return with the caret at `caret`, or nil when a plain
    /// newline is right: the caret is not at the end of a list or quote
    /// line, the line is neither, or it sits inside a fenced code block,
    /// where `- name:` is code.
    public static func edit(in text: NSString, caret: Int) -> Edit? {
        guard caret >= 0, caret <= text.length else { return nil }
        let line = SourceLines.range(around: caret, in: text)
        guard caret == NSMaxRange(line), let edit = lineEdit(in: text, line: line, caret: caret),
            // Last, since it reads the note from the top: most lines are
            // neither items nor quotes.
            !isInFencedCode(lineStart: line.location, in: text)
        else { return nil }
        return edit
    }

    /// The rule on `line` alone, the caret at its end; internal for the test
    /// that holds it to the line counting it replaced.
    static func lineEdit(in text: NSString, line: NSRange, caret: Int) -> Edit? {
        let prefix: String
        if ruleRegex.firstMatch(in: text as String, range: line) == nil,  // `* * *` and `- - -` are rules, not items.
            let match = itemRegex.firstMatch(in: text as String, range: line)
        {
            let indent = text.substring(with: match.range(at: 1))
            let bullet = text.substring(with: match.range(at: 2))
            let isTask = match.range(at: 3).location != NSNotFound
            guard !text.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces).isEmpty else {
                // An item with nothing in it: Return hands the line back.
                return Edit(range: line, replacement: "", caret: line.location)
            }
            prefix = indent + next(bullet) + " " + (isTask ? "[ ] " : "")
        } else if let match = quoteRegex.firstMatch(in: text as String, range: line) {
            guard !text.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces).isEmpty else {
                // An empty quote line ends the quote, however deep it was.
                return Edit(range: line, replacement: "", caret: line.location)
            }
            // `> > ` keeps its depth.
            prefix = text.substring(with: match.range(at: 1))
        } else {
            return nil
        }
        let insertion = lineBreak(in: text) + prefix
        return Edit(
            range: NSRange(location: caret, length: 0), replacement: insertion,
            caret: caret + (insertion as NSString).length)
    }

    /// The line ending Return writes: a note written with CRLF keeps one
    /// kind of line ending.
    public static func lineBreak(in text: NSString) -> String {
        text.range(of: "\r\n").location == NSNotFound ? "\n" : "\r\n"
    }

    /// Whether `offset` lies on a line inside a fenced code block. A block
    /// opens at a line starting with three backticks and closes at the next
    /// line of three backticks and nothing else but spaces; a fence never
    /// closed is no block, as the editors' highlighting draws it.
    public static func isInFencedCode(at offset: Int, in text: NSString) -> Bool {
        guard offset >= 0, offset <= text.length else { return false }
        return isInFencedCode(lineStart: SourceLines.range(around: offset, in: text).location, in: text)
    }

    /// Lines are told apart by where they start, so finding the caret's line
    /// costs no count from the top, and fences are read unit by unit rather
    /// than through a substring of every line.
    private static func isInFencedCode(lineStart target: Int, in text: NSString) -> Bool {
        // A quick out for the common note with no fence at all.
        guard text.range(of: "```").location != NSNotFound else { return false }
        var openedAt: Int?
        var inside = false
        SourceLines.forEach(in: text) { _, range in
            let start = range.location
            if let opened = openedAt {
                if isClosingFence(range, in: text) {
                    inside = opened < target && target <= start
                    openedAt = nil
                    return !inside && start < target
                }
                return true
            }
            if opensFence(range, in: text) { openedAt = start }
            return start < target
        }
        return inside
    }

    private static func opensFence(_ line: NSRange, in text: NSString) -> Bool {
        line.length >= 3 && (0..<3).allSatisfy { text.character(at: line.location + $0) == 0x60 }
    }

    /// Three backticks and nothing else but spaces and tabs.
    private static func isClosingFence(_ line: NSRange, in text: NSString) -> Bool {
        opensFence(line, in: text)
            && (line.location + 3..<NSMaxRange(line)).allSatisfy {
                let unit = text.character(at: $0)
                return unit == 0x20 || unit == 0x09
            }
    }

    /// The end, without its line ending, of the closing fence of the fenced
    /// code block holding the line that starts at `lineStart`, its opening
    /// and closing fences included; nil outside one. A fence never closed is
    /// no block, as everywhere else here.
    static func fencedBlockEnd(lineStart: Int, in text: NSString) -> Int? {
        guard text.range(of: "```").location != NSNotFound else { return nil }
        let line = SourceLines.range(around: lineStart, in: text)
        let inside = isInFencedCode(lineStart: line.location, in: text)
        guard inside || opensFence(line, in: text) else { return nil }
        if inside, isClosingFence(line, in: text) { return NSMaxRange(line) }
        var end: Int?
        SourceLines.forEach(in: text) { _, range in
            guard range.location > line.location else { return true }
            if isClosingFence(range, in: text) {
                end = NSMaxRange(range)
                return false
            }
            return true
        }
        return end
    }

    /// `3.` becomes `4.`; a bullet stays as it is.
    private static func next(_ bullet: String) -> String {
        guard let closer = bullet.last, closer == "." || closer == ")", let number = Int(bullet.dropLast()) else {
            return bullet
        }
        return "\(number + 1)\(closer)"
    }

    // These run on one cmark line only, so `^` and `$` are its ends: with
    // `.anchorsMatchLines` they also matched at U+2028 and U+2029 inside it,
    // and `text<U+2028>- ` read as an empty item whose Return deleted the
    // whole line. `.` crosses those separators for the same reason.
    private static let itemRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*(?:>[ \t]*)*)([-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\][ \t]+|\[[ xX]\]$)?(.*)$"#,
        options: [.dotMatchesLineSeparators])
    /// A quote line: one or more `>`, the last followed by a space or tab.
    private static let quoteRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*(?:>[ \t]*)*>[ \t]+)(.*)$"#, options: [.dotMatchesLineSeparators])
    private static let ruleRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
}

/// Where a file or picture dropped on the editor goes, the same on the Mac
/// and the iPhone and iPad (maintainer 2026-11-26): after the line it was
/// let go on, never splitting it, and after the whole table or fenced code
/// block when it was let go inside one, where a link would have become a
/// row of the table or a line of the code.
public enum DropPlacement {
    /// The offset the dropped link's line goes after: the end, without its
    /// line ending, of the line holding `offset`, or of the table or fenced
    /// code block holding that line.
    public static func lineEnd(around offset: Int, in text: NSString) -> Int {
        let line = SourceLines.range(around: min(max(offset, 0), text.length), in: text)
        if let fence = ListContinuation.fencedBlockEnd(lineStart: line.location, in: text) { return fence }
        if let table = TableEditing.locate(in: text, selection: NSRange(location: line.location, length: 0)) {
            return NSMaxRange(table.range)
        }
        return NSMaxRange(line)
    }
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

    /// The todo button of the iPhone and iPad insert bar, which does what the
    /// Mac's Format > Todo does on the same line: when the first line with
    /// words is already a task, the boxes are ticked or cleared; otherwise the
    /// lines become tasks, as `toggle(.task)` makes them.
    public static func todo(in text: NSString, selection: NSRange) -> Edit? {
        guard selection.location >= 0, NSMaxRange(selection) <= text.length else { return nil }
        var start = 0
        var end = 0
        var contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: selection)
        let first = text.substring(with: NSRange(location: start, length: contentsEnd - start))
            .components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
            .first { !Line($0).words.trimmingCharacters(in: .whitespaces).isEmpty }
        if let first, Line(first).is(.task) { return toggleTask(in: text, selection: selection) }
        return toggle(.task, in: text, selection: selection)
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

    // MARK: Line kinds

    /// What the iPhone and iPad insert panel turns lines into.
    public enum LineKind: Equatable, Sendable {
        case heading(Int), bullet, numbered, task, quote
    }

    /// Turns the lines the selection touches into `kind`, or back into plain
    /// text when the first one with words already is that kind, as Joplin's
    /// toolbar does: a heading of another level, or another kind of list
    /// item, keeps its words and takes the new marker. Lines without words
    /// are left alone unless no line has any, so an empty line takes the
    /// marker with the caret after it. `>` quote markers stay in front and do
    /// not count as the line's kind, except for `quote` itself.
    public static func toggle(_ kind: LineKind, in text: NSString, selection: NSRange) -> Edit? {
        guard selection.location >= 0, NSMaxRange(selection) <= text.length else { return nil }
        var start = 0
        var end = 0
        var contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: selection)
        let lines = text.substring(with: NSRange(location: start, length: contentsEnd - start))
            .components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        let worded = lines.filter { !Line($0).words.trimmingCharacters(in: .whitespaces).isEmpty }
        let removing = worded.first.map { Line($0).is(kind) } ?? false
        let touchesEmpty = worded.isEmpty
        var number = 0
        return rewrite(in: text, selection: selection) { raw in
            let line = Line(raw)
            if !touchesEmpty, line.words.trimmingCharacters(in: .whitespaces).isEmpty { return raw }
            if removing { return line.indent + (kind == .quote ? line.dequoted : line.quote + line.words) }
            switch kind {
            case .quote:
                return line.indent + "> " + line.quote + line.marker + line.words
            case .heading(let level):
                return line.quote + String(repeating: "#", count: min(max(level, 1), 6)) + " " + line.words
            case .bullet:
                return line.indent + line.quote + "- " + line.words
            case .task:
                return line.indent + line.quote + "- [ ] " + line.words
            case .numbered:
                number += 1
                return line.indent + line.quote + "\(number). " + line.words
            }
        }
    }

    /// One line cut into its indent, `>` markers, block marker and words.
    private struct Line {
        var indent = ""
        var quote = ""
        var marker = ""
        var words = ""
        var heading = 0
        var item: LineKind?

        init(_ line: String) {
            let ns = line as NSString
            guard let match = Self.shape.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
                words = line
                return
            }
            func part(_ index: Int) -> String {
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
            indent = part(1)
            quote = part(2)
            marker = part(3)
            words = part(4)
            let trimmed = marker.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                heading = trimmed.count
            } else if trimmed.hasSuffix("]") {
                item = .task
            } else if let first = trimmed.first, first.isNumber {
                item = .numbered
            } else if !trimmed.isEmpty {
                item = .bullet
            }
        }

        /// The line without its first `>` marker.
        var dequoted: String {
            let ns = quote as NSString
            guard let match = Self.oneQuote.firstMatch(in: quote, range: NSRange(location: 0, length: ns.length)) else {
                return quote + marker + words
            }
            return ns.replacingCharacters(in: match.range, with: "") + marker + words
        }

        func `is`(_ kind: LineKind) -> Bool {
            switch kind {
            case .heading(let level): return heading == level
            case .quote: return !quote.isEmpty
            default: return item == kind
            }
        }

        private static let shape = try! NSRegularExpression(
            pattern: #"^([ \t]*)((?:>[ \t]?)*)(#{1,6}[ \t]+|(?:[-*+]|\d{1,9}[.)])[ \t]+\[[ xX]\][ \t]+|(?:[-*+]|\d{1,9}[.)])[ \t]+)?(.*)$"#,
            options: [.dotMatchesLineSeparators])
        private static let oneQuote = try! NSRegularExpression(pattern: #"^>[ \t]?"#)
    }

    private static let taskRegex = try! NSRegularExpression(pattern: #"^[ \t>]*(?:[-*+]|\d+[.)])[ \t]+\[([ xX])\]"#)
    private static let itemRegex = try! NSRegularExpression(pattern: #"^[ \t>]*(?:[-*+]|\d+[.)])[ \t]+"#)
    private static let orderedRegex = try! NSRegularExpression(pattern: #"^([ \t]*)(\d{1,9}[.)])([ \t]+|$)(.?)"#)
}

/// Blocks the iPhone and iPad insert panel puts on lines of their own: a code
/// block, a divider and a table. A block never joins the paragraph around it:
/// `---` right under a line of text makes that line a heading, and a line
/// right under a table becomes one of its rows, so a blank line goes between
/// the block and any words above or below it.
public enum BlockInsert {
    public typealias Edit = LineEdits.Edit

    /// A fenced code block with the caret on its empty middle line, or
    /// around the selected lines.
    public static func codeBlock(in text: NSString, selection: NSRange) -> Edit? {
        let lineBreak = ListContinuation.lineBreak(in: text)
        if selection.length > 0 {
            var start = 0
            var end = 0
            var contentsEnd = 0
            text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: selection)
            let body = text.substring(with: NSRange(location: start, length: contentsEnd - start))
            let block = "```" + lineBreak + body + lineBreak + "```"
            return place(block, caret: NSRange(location: 3, length: 0), in: text, selection: selection, replacingLines: true)
        }
        let block = "```" + lineBreak + lineBreak + "```"
        return place(block, caret: NSRange(location: 3 + (lineBreak as NSString).length, length: 0), in: text, selection: selection)
    }

    /// `---` with the caret on the line after it.
    public static func divider(in text: NSString, selection: NSRange) -> Edit? {
        let lineBreak = ListContinuation.lineBreak(in: text)
        let block = "---" + lineBreak
        return place(block, caret: NSRange(location: (block as NSString).length, length: 0), in: text, selection: selection, endsWithLine: true)
    }

    /// `TableEditing.template(headers:)` with its first header selected.
    public static func table(headers: [String], in text: NSString, selection: NSRange) -> Edit? {
        let lineBreak = ListContinuation.lineBreak(in: text)
        let template = TableEditing.template(headers: headers)
        let block = template.text.replacingOccurrences(of: "\n", with: lineBreak)
        return place(block, caret: template.selection, in: text, selection: selection)
    }

    /// Puts `block` on the caret's line when that line is empty (or in place
    /// of the selected lines), otherwise on new lines after it, with a blank
    /// line between it and words above or below. `caret` is relative to the
    /// block. A block that `endsWithLine` already brings the line after it.
    private static func place(
        _ block: String, caret: NSRange, in text: NSString, selection: NSRange,
        replacingLines: Bool = false, endsWithLine: Bool = false
    ) -> Edit? {
        guard selection.location >= 0, NSMaxRange(selection) <= text.length else { return nil }
        let lineBreak = ListContinuation.lineBreak(in: text)
        var start = 0
        var end = 0
        var contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: selection)
        let range: NSRange
        let before: String
        if replacingLines || !hasWords(text, from: start, to: contentsEnd) {
            range = NSRange(location: start, length: contentsEnd - start)
            before = start > 0 && hasWords(lineBefore: start, in: text) ? lineBreak : ""
        } else {
            range = NSRange(location: contentsEnd, length: 0)
            before = lineBreak + lineBreak
        }
        var after = ""
        if !endsWithLine, end < text.length {
            var nextStart = 0
            var nextEnd = 0
            var nextContentsEnd = 0
            text.getLineStart(&nextStart, end: &nextEnd, contentsEnd: &nextContentsEnd, for: NSRange(location: end, length: 0))
            if hasWords(text, from: nextStart, to: nextContentsEnd) { after = lineBreak }
        }
        let offset = range.location + (before as NSString).length
        return Edit(
            range: range, replacement: before + block + after,
            selection: NSRange(location: offset + caret.location, length: caret.length))
    }

    private static func hasWords(_ text: NSString, from start: Int, to end: Int) -> Bool {
        !text.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func hasWords(lineBefore start: Int, in text: NSString) -> Bool {
        var aboveStart = 0
        var aboveEnd = 0
        var aboveContentsEnd = 0
        text.getLineStart(&aboveStart, end: &aboveEnd, contentsEnd: &aboveContentsEnd, for: NSRange(location: start - 1, length: 0))
        return hasWords(text, from: aboveStart, to: aboveContentsEnd)
    }
}
