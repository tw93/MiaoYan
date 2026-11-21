import Foundation

/// Keys and commands for a Markdown table edited as text: Tab and Shift-Tab
/// move between cells, Return goes to the next row and adds one after the
/// last, and rows and columns can be added, removed and aligned. Every
/// command also tidies the table, with the padding Format writes (Prettier's:
/// columns as wide as their widest cell, a wide character counting two).
///
/// The table was typed pipe by pipe before, Tab indented the row and Return
/// broke it (reader feedback, 2026-11-20). The keys follow the table editor
/// behind Obsidian's Advanced Tables, except that Tab in a row's last cell
/// goes on to the next row, as in Bear and a word processor, where theirs
/// starts a new column. The Mac editor and the iPhone and iPad editor both
/// take their table edits from here.
public enum TableEditing {
    public enum Alignment: Equatable, Sendable {
        case none, left, center, right
    }

    public enum Command: Equatable, Sendable {
        case nextCell, previousCell, nextRow
        case insertRowAbove, insertRowBelow, deleteRow
        case insertColumnLeft, insertColumnRight, deleteColumn
        case align(Alignment)
    }

    public struct Edit: Equatable {
        /// The range of the old text to replace; empty when only the
        /// selection moves.
        public let range: NSRange
        public let replacement: String
        /// The selection afterwards, in the new text: the cell's words, or
        /// a caret in an empty cell.
        public let selection: NSRange
    }

    /// Whether the selection sits in a table these commands can edit.
    public static func isInTable(in text: NSString, selection: NSRange) -> Bool {
        locate(in: text, selection: selection) != nil
    }

    /// The edit for `command`, or nil when the selection is not in a table
    /// (it spans lines, the line is prose or fenced code) or the command has
    /// nothing to act on there, like deleting the header row or a table's
    /// only column.
    public static func edit(_ command: Command, in text: NSString, selection: NSRange) -> Edit? {
        guard let located = locate(in: text, selection: selection) else { return nil }
        // Return before a row's first pipe pushes the row down, as anywhere else.
        if command == .nextRow, selection.length == 0, located.atRowStart { return nil }
        var table = located.table
        var focus = located.focus
        var leavesTable = false
        guard apply(command, to: &table, focus: &focus, leavesTable: &leavesTable) else { return nil }

        let lineBreak = located.lineBreak
        let rendered = render(table, lineBreak: lineBreak, focus: leavesTable ? nil : focus)
        var replacement = rendered.text
        var selection = rendered.selection
        if leavesTable {
            // The removed row's line stays, empty, and takes the caret.
            replacement += lineBreak
            selection = NSRange(location: (replacement as NSString).length, length: 0)
        }
        return minimal(old: located.range, in: text, new: replacement, selection: selection)
    }

    /// Changes `table` and moves `focus` as `command` asks; false when the
    /// command has nothing to act on.
    private static func apply(_ command: Command, to table: inout Table, focus: inout Focus, leavesTable: inout Bool) -> Bool {
        // Row 0 is the header and row 1 the line of dashes, as in the file.
        let bodyIndex = focus.row - 2
        let lastColumn = table.width - 1

        switch command {
        case .nextCell:
            if focus.row == 1 {
                focus = Focus(row: 2, column: 0)
            } else if focus.column < lastColumn {
                focus.column += 1
            } else {
                focus = Focus(row: focus.row == 0 ? 2 : focus.row + 1, column: 0)
            }
        case .previousCell:
            if focus.row == 1 {
                focus = Focus(row: 0, column: lastColumn)
            } else if focus.column > 0 {
                focus.column -= 1
            } else if focus.row >= 2 {
                focus = Focus(row: focus.row == 2 ? 0 : focus.row - 1, column: lastColumn)
            }
        case .nextRow:
            if bodyIndex >= 0, bodyIndex == table.body.count - 1, table.body[bodyIndex].allSatisfy(\.isEmpty) {
                // Return on a last row left empty hands the line back, as it
                // does for an empty list item.
                table.body.removeLast()
                leavesTable = true
            } else {
                focus = Focus(row: focus.row < 2 ? 2 : focus.row + 1, column: 0)
            }
        case .insertRowAbove, .insertRowBelow:
            let at = bodyIndex < 0 ? 0 : (command == .insertRowAbove ? bodyIndex : bodyIndex + 1)
            table.body.insert(Array(repeating: "", count: table.width), at: at)
            focus.row = at + 2
        case .deleteRow:
            guard bodyIndex >= 0 else { return false }
            table.body.remove(at: bodyIndex)
            focus.row = table.body.isEmpty ? 0 : min(bodyIndex, table.body.count - 1) + 2
        case .insertColumnLeft, .insertColumnRight:
            let at = command == .insertColumnLeft ? focus.column : focus.column + 1
            table.header.insert("", at: at)
            table.alignments.insert(.none, at: at)
            for index in table.body.indices { table.body[index].insert("", at: at) }
            focus.column = at
            if focus.row == 1 { focus.row = 0 }
        case .deleteColumn:
            guard table.width > 1 else { return false }
            table.header.remove(at: focus.column)
            table.alignments.remove(at: focus.column)
            for index in table.body.indices { table.body[index].remove(at: focus.column) }
            focus.column = min(focus.column, table.width - 1)
        case .align(let alignment):
            table.alignments[focus.column] = alignment
        }
        if !leavesTable, focus.row >= 2, focus.row - 2 >= table.body.count {
            // Past the last row: a new one.
            table.body.append(Array(repeating: "", count: table.width))
            focus.row = table.body.count + 1
        }
        if focus.row == 1 { focus.row = 0 }
        return true
    }

    // MARK: - The table in the text

    struct Table: Equatable {
        /// What stands before the first pipe of every row: the indentation.
        var indent: String
        var header: [String]
        var alignments: [Alignment]
        var body: [[String]]

        var width: Int { header.count }
    }

    struct Focus: Equatable {
        var row: Int
        var column: Int
    }

    /// One line of a table as it stands in the text.
    struct Row {
        let range: NSRange
        /// Without the spaces around them and the empty pieces outside the
        /// first and last pipe.
        let cells: [String]
        /// What stands before the first pipe, or before the first cell.
        let indent: String
        /// Whether the line starts with a pipe, and whether it ends with one.
        let leads: Bool
        let trails: Bool
        let hasPipe: Bool
    }

    struct Located {
        let table: Table
        /// The table's lines, without the last one's line break.
        let range: NSRange
        let focus: Focus
        /// The caret stands before the row's first pipe or first word.
        let atRowStart: Bool
        /// The line break the table's own lines end with.
        let lineBreak: String
        /// False for a row still being typed, with no line of dashes yet.
        let hasDelimiter: Bool
    }

    static func locate(in text: NSString, selection: NSRange) -> Located? {
        guard selection.location >= 0, NSMaxRange(selection) <= text.length else { return nil }
        let caretSpan = line(at: selection.location, in: text)
        guard NSMaxRange(selection) <= NSMaxRange(caretSpan.contents) else { return nil }
        let caretRow = row(of: text.substring(with: caretSpan.contents), at: caretSpan.contents)
        guard caretRow.hasPipe else { return nil }

        // The run of lines with a pipe around the caret, read outward from
        // it: a table deep in a long note costs its own lines, not the note's.
        var lines = [caretRow]
        var caret = 0
        var top = caretSpan.contents.location
        while top > 0 {
            var end = top - 1
            if text.character(at: end) == 0x0A, end > 0, text.character(at: end - 1) == 0x0D { end -= 1 }
            let span = line(at: end, in: text)
            let above = row(of: text.substring(with: span.contents), at: span.contents)
            guard above.hasPipe else { break }
            lines.insert(above, at: 0)
            caret += 1
            top = span.contents.location
        }
        var next = caretSpan.next
        var last = caretSpan.contents
        while next < text.length, next > NSMaxRange(last) {
            let span = line(at: next, in: text)
            let below = row(of: text.substring(with: span.contents), at: span.contents)
            guard below.hasPipe else { break }
            lines.append(below)
            last = span.contents
            next = span.next
        }

        // A table starts at the line above its first line of dashes; lines
        // above that are a paragraph the table interrupts.
        var start: Int
        var hasDelimiter = true
        if let delimiter = lines.indices.dropFirst().first(where: { isDelimiter(lines[$0].cells) }) {
            start = delimiter - 1
            guard caret >= start else { return nil }
        } else {
            // No dashes yet: a row being typed. Only a line closed by pipes
            // at both ends with two cells or more is taken for one, or `|x|`
            // and `|a| + |b|` in a sentence would be made into tables; the
            // dashes are then written for the writer.
            func typed(_ row: Row) -> Bool { row.leads && row.trails && row.cells.count >= 2 && !isDelimiter(row.cells) }
            guard typed(lines[caret]) else { return nil }
            hasDelimiter = false
            start = caret
            while start > 0, typed(lines[start - 1]) { start -= 1 }
            if let stop = lines[caret...].firstIndex(where: { !typed($0) }) { lines.removeSubrange(stop...) }
        }
        let rows = Array(lines[start...])
        guard let headerLine = rows.first, let lastLine = rows.last, !isCode(headerLine, in: text) else { return nil }
        let bodyLines = rows.dropFirst(hasDelimiter ? 2 : 1)
        let width = max(rows.enumerated().filter { !(hasDelimiter && $0.offset == 1) }.map(\.element.cells.count).max() ?? 1, 1)
        func padded(_ cells: [String]) -> [String] { cells + Array(repeating: "", count: width - cells.count) }
        var alignments = hasDelimiter ? rows[1].cells.map(alignment) : []
        alignments = Array(alignments.prefix(width)) + Array(repeating: Alignment.none, count: max(width - alignments.count, 0))
        let table = Table(indent: headerLine.indent, header: padded(headerLine.cells), alignments: alignments, body: bodyLines.map { padded($0.cells) })

        let row = caret - start
        let focusRow = hasDelimiter ? row : (row == 0 ? 0 : row + 1)
        let inRow = selection.location - rows[row].range.location
        let column = min(self.column(at: inRow, in: text.substring(with: rows[row].range)), width - 1)
        let range = NSRange(location: headerLine.range.location, length: NSMaxRange(lastLine.range) - headerLine.range.location)
        // The break after the header is the table's own; a table of one
        // line takes the note's.
        let headerEnd = NSMaxRange(headerLine.range)
        let afterHeader = line(at: headerLine.range.location, in: text).next
        let lineBreak = afterHeader > headerEnd ? text.substring(with: NSRange(location: headerEnd, length: afterHeader - headerEnd)) : ListContinuation.lineBreak(in: text)
        return Located(
            table: table, range: range, focus: Focus(row: focusRow, column: column),
            atRowStart: inRow <= (rows[row].indent as NSString).length, lineBreak: lineBreak, hasDelimiter: hasDelimiter)
    }

    /// The line of the file holding `offset`, without its line ending, and
    /// where the next line starts. A line ends at `\n`, `\r\n` or `\r`
    /// only, as in `SourceLines`.
    private static func line(at offset: Int, in text: NSString) -> (contents: NSRange, next: Int) {
        func isBreak(_ unit: unichar) -> Bool { unit == 0x0A || unit == 0x0D }
        var start = min(max(offset, 0), text.length)
        while start > 0, !isBreak(text.character(at: start - 1)) { start -= 1 }
        var end = min(max(offset, 0), text.length)
        while end < text.length, !isBreak(text.character(at: end)) { end += 1 }
        var next = end
        if next < text.length {
            next += text.character(at: next) == 0x0D && next + 1 < text.length && text.character(at: next + 1) == 0x0A ? 2 : 1
        }
        return (NSRange(location: start, length: end - start), next)
    }

    /// Whether the table whose first line is `header` is code or a formula
    /// and not a table at all: indented four columns or more, inside a
    /// fence of backticks or tildes (one never closed runs to the end, as
    /// the preview draws it), or between two `$$` lines.
    private static func isCode(_ header: Row, in text: NSString) -> Bool {
        let columns = header.indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        if columns >= 4 { return true }
        let limit = header.range.location
        let above = NSRange(location: 0, length: limit)
        func appears(_ mark: String) -> Bool { text.range(of: mark, options: .literal, range: above).location != NSNotFound }
        // The common note has none of these and is not read any further.
        guard appears("```") || appears("~~~") || appears("$$") else { return false }
        var state = CodeState()
        SourceLines.forEach(in: text) { _, range in
            guard range.location < limit else { return false }
            state.take(text.substring(with: range))
            return true
        }
        return state.isCode
    }

    /// Whether the lines read so far leave a fence or a `$$` formula open.
    private struct CodeState {
        private var fence: (mark: Character, count: Int)?
        private var inMath = false

        var isCode: Bool { fence != nil || inMath }

        mutating func take(_ raw: String) {
            let line = raw.drop { $0 == " " || $0 == "\t" }
            if let open = fence {
                let run = line.prefix { $0 == open.mark }.count
                if run >= open.count, line.dropFirst(run).allSatisfy({ $0 == " " || $0 == "\t" }) { fence = nil }
            } else if let mark = line.first, mark == "`" || mark == "~", line.prefix(while: { $0 == mark }).count >= 3 {
                fence = (mark, line.prefix { $0 == mark }.count)
            } else if line.hasPrefix("$$") || line.hasSuffix("$$"), line.components(separatedBy: "$$").count % 2 == 0 {
                // A line that starts or ends a formula carries one `$$`;
                // `$$ x $$` on one line carries two and opens nothing.
                inMath.toggle()
            }
        }
    }

    // MARK: - Where the pipes stand

    /// A table as it stands in the text, for an editor that lines its
    /// columns up on screen without changing a character.
    public struct Layout: Equatable, Sendable {
        /// The table's lines, without the last one's line break.
        public let range: NSRange
        /// One for each column.
        public let alignments: [Alignment]
        /// For each line from the header down (the second is the line of
        /// dashes), the UTF-16 offsets in the text where its cells start:
        /// at the cell's pipe, or at the first word of a row written without
        /// a leading pipe. The last offset is the pipe that closes the last
        /// cell, so a row holds one cell fewer than offsets.
        public let rows: [[Int]]
    }

    /// The tables of `text`, or only those on the whole lines `lines`
    /// covers. They are the tables the commands above edit: a run of lines
    /// with a pipe, from the line above its first line of dashes down. A
    /// row still being typed, with no dashes under it, is not one yet.
    ///
    /// Read from the top, the fences and formulas are followed on the way;
    /// read for a few lines, each header is checked against the lines above
    /// it, as the commands check it, so both name the same tables.
    public static func layouts(in text: NSString, lines: NSRange? = nil) -> [Layout] {
        var found: [Layout] = []
        var run: [(row: Row, inCode: Bool)] = []
        var state = CodeState()
        let follows = lines == nil && ["```", "~~~", "$$"].contains { text.range(of: $0, options: .literal).location != NSNotFound }

        func close() {
            defer { run.removeAll(keepingCapacity: true) }
            guard let delimiter = run.indices.dropFirst().first(where: { isDelimiter(run[$0].row.cells) }) else { return }
            let rows = run[(delimiter - 1)...].map(\.row)
            guard let header = rows.first, let last = rows.last else { return }
            guard header.indent.reduce(0, { $0 + ($1 == "\t" ? 4 : 1) }) < 4 else { return }
            guard !(lines == nil ? run[delimiter - 1].inCode : isCode(header, in: text)) else { return }
            let starts = rows.map { row -> [Int] in
                let cuts = separators(in: text.substring(with: row.range)).map { row.range.location + $0 }
                return row.leads ? cuts : [row.range.location + (row.indent as NSString).length] + cuts
            }
            let width = max((starts.map(\.count).max() ?? 1) - 1, 0)
            let marked = rows[1].cells.map(alignment).prefix(width)
            found.append(
                Layout(
                    range: NSRange(location: header.range.location, length: NSMaxRange(last.range) - header.range.location),
                    alignments: marked + Array(repeating: Alignment.none, count: width - marked.count), rows: starts))
        }

        var offset = min(max(lines?.location ?? 0, 0), text.length)
        let end = min(lines.map(NSMaxRange) ?? text.length, text.length)
        while offset < end {
            let span = line(at: offset, in: text)
            let inCode = state.isCode
            if follows { state.take(text.substring(with: span.contents)) }
            if text.range(of: "|", options: .literal, range: span.contents).location != NSNotFound {
                let row = row(of: text.substring(with: span.contents), at: span.contents)
                if row.hasPipe { run.append((row, inCode)) } else { close() }
            } else {
                close()
            }
            guard span.next > offset else { break }
            offset = span.next
        }
        close()
        return found
    }

    /// The separators of a row: every pipe not escaped by a backslash, as
    /// cmark-gfm splits a row (a pipe inside a code span splits too). The
    /// pipe of a `[[note|label]]` link is left alone: the preview splits
    /// there as well, but padding it would break the link for good.
    private static func separators(in line: String) -> [Int] {
        let units = Array(line.utf16)
        var offsets: [Int] = []
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit == 0x5C {
                index += 2
                continue
            }
            if unit == 0x5B, index + 3 < units.count, units[index + 1] == 0x5B,
                let close = (index + 2...units.count - 2).first(where: { units[$0] == 0x5D && units[$0 + 1] == 0x5D })
            {
                index = close + 2
                continue
            }
            if unit == 0x7C { offsets.append(index) }
            index += 1
        }
        return offsets
    }

    /// A line read as a table row. Only spaces and tabs are trimmed from a
    /// cell, as cmark-gfm and Prettier trim it: a no-break or an ideographic
    /// space at a cell's edge is the writer's text.
    private static func row(of line: String, at range: NSRange = NSRange(location: 0, length: 0)) -> Row {
        func isBlank(_ text: String) -> Bool { text.allSatisfy { $0 == " " || $0 == "\t" } }
        let source = line as NSString
        let cuts = separators(in: line)
        var pieces: [String] = []
        var from = 0
        for offset in cuts {
            pieces.append(source.substring(with: NSRange(location: from, length: offset - from)))
            from = offset + 1
        }
        pieces.append(source.substring(from: from))
        var indent = ""
        var leads = false
        var trails = false
        if let head = pieces.first, isBlank(head), !cuts.isEmpty {
            indent = head
            leads = true
            pieces.removeFirst()
        } else if let head = pieces.first {
            indent = String(head.prefix { $0 == " " || $0 == "\t" })
        }
        if pieces.count > 1, let tail = pieces.last, isBlank(tail) {
            trails = true
            pieces.removeLast()
        }
        let cells = pieces.map { piece -> String in
            let inner = piece.drop { $0 == " " || $0 == "\t" }
            return String(inner.dropLast(inner.reversed().prefix { $0 == " " || $0 == "\t" }.count))
        }
        return Row(range: range, cells: cells, indent: indent, leads: leads, trails: trails, hasPipe: !cuts.isEmpty && !isBlank(line))
    }

    /// The cell holding the UTF-16 offset `offset` of `line`.
    private static func column(at offset: Int, in line: String) -> Int {
        let all = separators(in: line)
        let before = all.filter { $0 < offset }.count
        let leads = row(of: line).leads
        return max(before - (leads ? 1 : 0), 0)
    }

    private static func isDelimiter(_ cells: [String]) -> Bool {
        !cells.isEmpty
            && cells.allSatisfy { cell in
                let dashes = cell.drop { $0 == ":" }.prefix { $0 == "-" }
                let rest = cell.drop { $0 == ":" }.dropFirst(dashes.count)
                return !dashes.isEmpty && (rest.isEmpty || rest == ":") && cell.prefix { $0 == ":" }.count <= 1
            }
    }

    private static func alignment(_ cell: String) -> Alignment {
        switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
        case (true, true): return .center
        case (true, false): return .left
        case (false, true): return .right
        case (false, false): return .none
        }
    }

    // MARK: - Writing it back

    /// The table as text, and where `focus` is in it (counted from the
    /// table's start): the cell's words, or a caret in an empty cell.
    static func render(_ table: Table, lineBreak: String, focus: Focus?) -> (text: String, selection: NSRange) {
        let rows = [table.header] + table.body
        // Three is the narrowest line of dashes, `---`.
        let widths = (0..<table.width).map { column in
            max(rows.map { displayWidth($0[column]) }.max() ?? 0, 3)
        }
        var lines: [String] = []
        var selection = NSRange(location: 0, length: 0)
        var length = 0
        func add(_ line: String) {
            lines.append(line)
            length += (line as NSString).length + (lineBreak as NSString).length
        }
        for (index, row) in rows.enumerated() {
            var line = table.indent + "|"
            for (column, cell) in row.enumerated() {
                let space = widths[column] - displayWidth(cell)
                var before = 0
                switch table.alignments[column] {
                case .right: before = space
                case .center: before = space / 2
                case .none, .left: break
                }
                // An empty cell keeps the caret at its left edge whatever the alignment.
                if cell.isEmpty { before = 0 }
                line += " " + String(repeating: " ", count: before)
                if let focus, focus.column == column, focus.row == (index == 0 ? 0 : index + 1) {
                    selection = NSRange(location: length + (line as NSString).length, length: (cell as NSString).length)
                }
                line += cell + String(repeating: " ", count: space - before) + " |"
            }
            add(line)
            if index == 0 {
                let dashes = table.alignments.enumerated().map { column, alignment -> String in
                    let first = alignment == .center || alignment == .left ? ":" : "-"
                    let last = alignment == .center || alignment == .right ? ":" : "-"
                    return first + String(repeating: "-", count: widths[column] - 2) + last
                }
                add(table.indent + "| " + dashes.joined(separator: " | ") + " |")
            }
        }
        return (lines.joined(separator: lineBreak), selection)
    }

    /// The columns a string takes in a fixed-width face, as Prettier counts
    /// them for a table: two for an East Asian wide or fullwidth character
    /// and for an emoji, none for a combining mark, one otherwise.
    static func displayWidth(_ string: String) -> Int {
        var width = 0
        for character in string {
            let scalars = character.unicodeScalars
            guard let first = scalars.first else { continue }
            // A keycap (a digit, `#` or `*` with U+20E3) is an emoji too.
            if first.properties.isEmojiPresentation || (first.properties.isEmoji && scalars.count > 1 && first.value > 0x39)
                || scalars.contains(where: { $0.value == 0x20E3 })
            {
                width += 2
                continue
            }
            for scalar in scalars {
                let value = scalar.value
                if value <= 0x1F || (0x7F...0x9F).contains(value) || (0x300...0x36F).contains(value) { continue }
                width += isWide(value) ? 2 : 1
            }
        }
        return width
    }

    /// East Asian Wide and Fullwidth (Unicode's EastAsianWidth W and F).
    private static func isWide(_ value: UInt32) -> Bool {
        guard value >= 0x1100 else { return false }
        return wideRanges.contains { $0.contains(value) }
    }

    private static let wideRanges: [ClosedRange<UInt32>] = [
        0x1100...0x115F, 0x2329...0x232A, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
        0xA000...0xA4CF, 0xA960...0xA97F, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE10...0xFE19, 0xFE30...0xFE6F,
        0xFF01...0xFF60, 0xFFE0...0xFFE6, 0x16FE0...0x18AFF, 0x1B000...0x1B2FF, 0x1F200...0x1F2FF,
        0x20000...0x2FFFD, 0x30000...0x3FFFD,
    ]

    /// The smallest replacement that turns the old table into `new`: the
    /// text both share at the two ends stays untouched, so a move from one
    /// cell to the next in a tidy table changes nothing but the selection,
    /// and an undo steps back over only what was rewritten.
    private static func minimal(old range: NSRange, in text: NSString, new: String, selection: NSRange) -> Edit {
        let old = text.substring(with: range) as NSString
        let fresh = new as NSString
        var head = 0
        let limit = min(old.length, fresh.length)
        while head < limit, old.character(at: head) == fresh.character(at: head) { head += 1 }
        var tail = 0
        while tail < limit - head, old.character(at: old.length - 1 - tail) == fresh.character(at: fresh.length - 1 - tail) { tail += 1 }
        // Never cut between the two halves of a character outside the BMP.
        while head > 0, UTF16.isLeadSurrogate(old.character(at: head - 1)) { head -= 1 }
        while tail > 0, UTF16.isTrailSurrogate(old.character(at: old.length - tail)) { tail -= 1 }
        return Edit(
            range: NSRange(location: range.location + head, length: old.length - head - tail),
            replacement: fresh.substring(with: NSRange(location: head, length: fresh.length - head - tail)),
            selection: NSRange(location: range.location + selection.location, length: selection.length))
    }
}
