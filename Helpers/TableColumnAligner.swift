import AppKit
import CoreText
import MiaoYanCore

/// Draws a Markdown table as a table in the editor without changing a
/// character of it. The editor's face is proportional, so the spaces that
/// pad a cell in the file do not put the next pipe where the row above has
/// it. Here every column takes the width of its widest cell, the spaces
/// around each cell are drawn narrower or wider until the pipes stand under
/// each other, and the pipes and the line of dashes take the quiet markup
/// colour, as `#` and `**` do (maintainer's pick of two drawn candidates,
/// 2026-11-21). Only the `.kern` and the colour of those characters change,
/// and neither reaches the file.
@MainActor
enum TableColumnAligner {
    /// On the characters whose spacing was changed, so a later pass can
    /// hand it back.
    static let widenedKey = NSAttributedString.Key("com.tw93.miaoyan.tableColumnSpace")
    /// On the pipes and dashes given the markup colour; its value is the
    /// colour object they were given, which tells a pipe still wearing it
    /// from one the highlighter has coloured again since.
    static let quietKey = NSAttributedString.Key("com.tw93.miaoyan.tableMarkup")

    /// What a pass wants drawn: the extra spacing of each character, by
    /// offset, and the runs of pipes and dashes in the markup colour.
    private struct Plan {
        var spacing: [Int: CGFloat] = [:]
        var quiet: [NSRange] = []
    }

    /// A table longer than this is left as typed: its rows are gone over
    /// again when one of them changes.
    static let longestTable = 300

    /// Every table of the note. `editing` is true inside the storage's own
    /// editing pass, where the changes join the edit being processed.
    static func alignAll(in storage: NSTextStorage, editing: Bool = false) {
        let whole = NSRange(location: 0, length: storage.length)
        let text = storage.mutableString
        var plan = Plan()
        if isOn, text.range(of: "|", options: .literal).location != NSNotFound {
            for layout in TableEditing.layouts(in: text) { draw(layout, in: storage, into: &plan) }
        }
        guard !plan.quiet.isEmpty || holdsMarks(storage, in: whole) else { return }
        if !editing { storage.beginEditing() }
        commit(plan, in: whole, to: storage)
        if !editing { storage.endEditing() }
    }

    /// The tables on and beside the lines of `edited`, from inside the
    /// storage's editing pass. A keystroke in a table costs its own rows; one
    /// in prose costs a look at the lines above and below.
    static func align(around edited: NSRange, in storage: NSTextStorage) {
        let text = storage.mutableString
        guard text.length > 0 else { return }
        let location = min(max(edited.location, 0), text.length)
        var range = text.paragraphRange(for: NSRange(location: location, length: min(edited.length, text.length - location)))
        func hasPipe(_ range: NSRange) -> Bool { text.range(of: "|", options: .literal, range: range).location != NSNotFound }
        func above() -> NSRange? { range.location > 0 ? text.paragraphRange(for: NSRange(location: range.location - 1, length: 0)) : nil }
        func below() -> NSRange? {
            guard NSMaxRange(range) < text.length else { return nil }
            let next = text.paragraphRange(for: NSRange(location: NSMaxRange(range), length: 0))
            return next.length > 0 ? next : nil
        }
        // Over the lines with a pipe on both sides. Past the longest table
        // nothing is drawn as one, so the walk goes on only while it finds
        // lines still drawn that way, which a table that has just grown past
        // the limit leaves behind: a keystroke in a table of thousands of
        // rows does not read them all.
        var lines = 1
        func grow(_ next: () -> NSRange?) {
            while let line = next(), hasPipe(line), lines <= longestTable + 8 || holdsMarks(storage, in: line) {
                range = NSUnionRange(range, line)
                lines += 1
            }
        }
        grow(above)
        grow(below)
        // A line break typed at the end of a row parts the rows under it
        // from their line of dashes: they are plain lines now, one line
        // without a pipe away from the edit. A table that merely stands
        // under the edited paragraph is told from them by its second line,
        // dashes drawn as markup, and left alone: prose typed above a table
        // must not go over the table on every keystroke. One such step, not
        // a chain of them through every table of the note.
        if let gap = below(), !hasPipe(gap), NSMaxRange(gap) < text.length {
            let first = text.paragraphRange(for: NSRange(location: NSMaxRange(gap), length: 0))
            var isWhole = false
            if NSMaxRange(first) < text.length {
                let second = text.paragraphRange(for: NSRange(location: NSMaxRange(first), length: 0))
                let dash = text.range(of: "-", options: .literal, range: second).location
                isWhole = dash != NSNotFound && storage.attribute(quietKey, at: dash, effectiveRange: nil) != nil
            }
            if first.length > 0, !isWhole, holdsMarks(storage, in: first) {
                range = NSUnionRange(range, first)
                grow(below)
            }
        }
        var plan = Plan()
        if isOn, hasPipe(range), lines <= longestTable + 8 {
            for layout in TableEditing.layouts(in: text, lines: range) { draw(layout, in: storage, into: &plan) }
        }
        guard !plan.quiet.isEmpty || holdsMarks(storage, in: range) else { return }
        commit(plan, in: range, to: storage)
    }

    /// The editor's frame changed. A table is drawn aligned only while the
    /// whole of it fits on a line, so when the width is another one each is
    /// looked at again, once the width has settled. The frame also changes
    /// with every line typed, which is why the width is compared first.
    static func widthChanged(of storage: NSTextStorage) {
        let width = room(in: storage) ?? 0
        guard abs(width - (lastRoom.object(forKey: storage)?.doubleValue ?? 0)) > 0.5 else { return }
        lastRoom.setObject(NSNumber(value: Double(width)), forKey: storage)
        NSObject.cancelPreviousPerformRequests(withTarget: storage, selector: #selector(NSTextStorage.alignTableColumns), object: nil)
        storage.perform(#selector(NSTextStorage.alignTableColumns), with: nil, afterDelay: 0.12)
    }

    private static let lastRoom = NSMapTable<NSTextStorage, NSNumber>.weakToStrongObjects()

    /// A long note in the simplified highlighting keeps its tables as typed.
    private static var isOn: Bool { !NotesTextProcessor.shouldUseSimplifiedHighlighting }

    private static func holdsMarks(_ storage: NSTextStorage, in range: NSRange) -> Bool {
        var found = false
        for key in [quietKey, widenedKey] where !found {
            storage.enumerateAttribute(key, in: range, options: .longestEffectiveRangeNotRequired) { value, _, stop in
                guard value != nil else { return }
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    /// Makes the spacing and the markup colour in `affected` what `plan`
    /// asks and plain everywhere else, touching only what differs: a
    /// keystroke that leaves the columns as wide as they were leaves the
    /// other rows alone.
    private static func commit(_ whole: Plan, in affected: NSRange, to storage: NSTextStorage) {
        quieten(whole.quiet, in: affected, of: storage)
        let plan = whole.spacing
        let spacing = UserDefaultsManagement.editorLetterSpacing
        var stale = IndexSet()
        storage.enumerateAttribute(widenedKey, in: affected) { value, range, _ in
            if value != nil, let marked = Range(range) { stale.insert(integersIn: marked) }
        }
        let offsets = plan.keys.filter { abs(plan[$0] ?? 0) > 0.01 }.sorted()
        var index = 0
        while index < offsets.count {
            let first = offsets[index]
            let extra = plan[first] ?? 0
            var count = 1
            while index + count < offsets.count, offsets[index + count] == first + count, abs((plan[first + count] ?? 0) - extra) < 0.001 { count += 1 }
            index += count
            let range = NSRange(location: first, length: count)
            stale.remove(integersIn: first..<first + count)
            var same = NSRange(location: 0, length: 0)
            let now = (storage.attribute(.kern, at: first, longestEffectiveRange: &same, in: range) as? NSNumber)?.doubleValue
            var marked = NSRange(location: 0, length: 0)
            let isMarked = storage.attribute(widenedKey, at: first, longestEffectiveRange: &marked, in: range) != nil
            if let now, abs(now - (spacing + Double(extra))) < 0.001, same.length == count, isMarked, marked.length == count { continue }
            storage.addAttribute(.kern, value: spacing + Double(extra), range: range)
            storage.addAttribute(widenedKey, value: true, range: range)
        }
        for run in stale.rangeView {
            let range = NSRange(run)
            storage.removeAttribute(widenedKey, range: range)
            if spacing != 0 {
                storage.addAttribute(.kern, value: spacing, range: range)
            } else {
                storage.removeAttribute(.kern, range: range)
            }
        }
    }

    private static func quieten(_ runs: [NSRange], in affected: NSRange, of storage: NSTextStorage) {
        var stale = IndexSet()
        storage.enumerateAttribute(quietKey, in: affected) { value, range, _ in
            if value != nil, let marked = Range(range) { stale.insert(integersIn: marked) }
        }
        let colour = NotesTextProcessor.syntaxColor
        for run in runs {
            if let range = Range(run) { stale.remove(integersIn: range) }
            var marked = NSRange(location: 0, length: 0)
            var coloured = NSRange(location: 0, length: 0)
            let mark = storage.attribute(quietKey, at: run.location, longestEffectiveRange: &marked, in: run) as AnyObject?
            let now = storage.attribute(.foregroundColor, at: run.location, longestEffectiveRange: &coloured, in: run) as AnyObject?
            if let mark, mark === now, marked.length == run.length, coloured.length == run.length { continue }
            storage.addAttribute(.foregroundColor, value: colour, range: run)
            storage.addAttribute(quietKey, value: colour, range: run)
        }
        // No longer part of a table: back to the text colour where the
        // highlighter has not been over it since.
        var back: [NSRange] = []
        for run in stale.rangeView {
            storage.enumerateAttribute(quietKey, in: NSRange(run)) { mark, range, _ in
                storage.enumerateAttribute(.foregroundColor, in: range) { now, coloured, _ in
                    if let mark, mark as AnyObject === now as AnyObject { back.append(coloured) }
                }
            }
        }
        for range in back { storage.addAttribute(.foregroundColor, value: NotesTextProcessor.fontColor, range: range) }
        for run in stale.rangeView { storage.removeAttribute(quietKey, range: NSRange(run)) }
    }

    /// One cell as it stands in its row: the pipe that opens it, the spaces
    /// after the pipe, the words, the spaces before the next pipe, and how
    /// wide each is drawn with plain spacing.
    private struct Cell {
        var pipe: Int?
        var lead: NSRange
        var content: NSRange
        var trail: NSRange
        var pipeWidth: CGFloat
        var leadWidth: CGFloat
        var contentWidth: CGFloat
        var trailWidth: CGFloat
    }

    /// The offsets that part a cell: its pipe, the first space after it, the
    /// first and the last of its words, and the next cell's pipe.
    private struct Part {
        let pipe: Int?
        let start: Int
        let leadEnd: Int
        let trailStart: Int
        let end: Int
    }

    /// Where the cells of a row start, as it is drawn with plain spacing,
    /// kept by the row's own styled text: a keystroke changes one row of a
    /// table, and the others need not be set in type again to be measured.
    private final class Measured {
        let starts: [CGFloat]
        init(_ starts: [CGFloat]) { self.starts = starts }
    }

    private static let measured: NSCache<NSAttributedString, Measured> = {
        let cache = NSCache<NSAttributedString, Measured>()
        cache.countLimit = 2000
        return cache
    }()

    private static func cells(of row: [Int], in storage: NSTextStorage, spacing: Double) -> [Cell] {
        guard let first = row.first, let last = row.last, row.count > 1 else { return [] }
        let text = storage.mutableString
        // Every offset the widths below are read at, in order.
        var marks: [Int] = []
        var parts: [Part] = []
        for column in 0..<row.count - 1 {
            let hasPipe = text.character(at: row[column]) == 0x7C
            let start = row[column] + (hasPipe ? 1 : 0)
            let end = row[column + 1]
            var leadEnd = start
            while leadEnd < end, text.character(at: leadEnd) == 0x20 { leadEnd += 1 }
            var trailStart = end
            while trailStart > leadEnd, text.character(at: trailStart - 1) == 0x20 { trailStart -= 1 }
            parts.append(Part(pipe: hasPipe ? row[column] : nil, start: start, leadEnd: leadEnd, trailStart: trailStart, end: end))
            marks += [row[column], start, leadEnd, trailStart, end]
        }
        let plain = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: NSRange(location: first, length: last - first + 1)))
        plain.addAttribute(.kern, value: spacing, range: NSRange(location: 0, length: plain.length))
        plain.removeAttribute(widenedKey, range: NSRange(location: 0, length: plain.length))
        let starts: [CGFloat]
        if let known = measured.object(forKey: plain), known.starts.count == marks.count {
            starts = known.starts
        } else {
            let line = CTLineCreateWithAttributedString(plain)
            starts = marks.map { CTLineGetOffsetForStringIndex(line, $0 - first, nil) }
            measured.setObject(Measured(starts), forKey: NSAttributedString(attributedString: plain))
        }
        return parts.enumerated().map { column, part in
            let x = starts
            let base = column * 5
            return Cell(
                pipe: part.pipe,
                lead: NSRange(location: part.start, length: part.leadEnd - part.start),
                content: NSRange(location: part.leadEnd, length: part.trailStart - part.leadEnd),
                trail: NSRange(location: part.trailStart, length: part.end - part.trailStart),
                pipeWidth: x[base + 1] - x[base], leadWidth: x[base + 2] - x[base + 1],
                contentWidth: x[base + 3] - x[base + 2], trailWidth: x[base + 4] - x[base + 3])
        }
    }

    /// Adds `layout` to `plan`: its pipes and dashes in the markup colour,
    /// and the extra spacing that lines its columns up. The spacing is left
    /// out, and the table drawn as typed, when it is wider than the editor
    /// (every row would wrap) or holds a tab stop or an image, which the
    /// layout places by its own rules. A table past `longestTable` gets
    /// neither.
    private static func draw(_ layout: TableEditing.Layout, in storage: NSTextStorage, into plan: inout Plan) {
        let text = storage.mutableString
        guard layout.rows.count <= longestTable, !layout.alignments.isEmpty else { return }
        for (index, row) in layout.rows.enumerated() {
            if index == 1, let first = row.first, let last = row.last {
                plan.quiet.append(NSRange(location: first, length: last - first + 1))
            } else {
                for offset in row where text.character(at: offset) == 0x7C { plan.quiet.append(NSRange(location: offset, length: 1)) }
            }
        }
        guard text.range(of: "\t", options: .literal, range: layout.range).location == NSNotFound, !storage.containsAttachments(in: layout.range) else { return }

        let spacing = UserDefaultsManagement.editorLetterSpacing
        let face: [NSAttributedString.Key: Any] = [.font: NotesTextProcessor.font, .kern: spacing]
        let space = (" " as NSString).size(withAttributes: face).width
        let rows = layout.rows.map { cells(of: $0, in: storage, spacing: spacing) }
        // A column is as wide as its widest cell, and no narrower than `---`.
        var widths = [CGFloat](repeating: ("---" as NSString).size(withAttributes: face).width, count: layout.alignments.count)
        var pipes = [CGFloat](repeating: 0, count: layout.alignments.count)
        for (index, row) in rows.enumerated() {
            for (column, cell) in row.enumerated() {
                if index != 1 { widths[column] = max(widths[column], cell.contentWidth) }
                pipes[column] = max(pipes[column], cell.pipeWidth)
            }
        }
        let whole = zip(widths, pipes).reduce(0) { $0 + $1.0 + $1.1 + 2 * space } + (pipes.first ?? 0)
        if let room = room(in: storage), whole > room { return }

        var extra: [Int: CGFloat] = [:]
        func add(_ width: CGFloat, over range: NSRange) {
            for offset in range.location..<NSMaxRange(range) { extra[offset, default: 0] += width / CGFloat(range.length) }
        }
        for (index, row) in rows.enumerated() {
            for (column, cell) in row.enumerated() {
                let total = pipes[column] + 2 * space + widths[column]
                var content = cell.contentWidth
                var before: CGFloat = 0
                if index == 1, content > widths[column], cell.content.length > 1 {
                    // More dashes than the column is wide are drawn closer.
                    add(widths[column] - content, over: NSRange(location: cell.content.location, length: cell.content.length - 1))
                    content = widths[column]
                } else if cell.content.length > 0 {
                    // The dashes stand where the column's words do: `--:` to the right.
                    switch layout.alignments[column] {
                    case .right: before = widths[column] - content
                    case .center: before = (widths[column] - content) / 2
                    case .left, .none: break
                    }
                }
                let last = NSMaxRange(cell.content) - 1
                let closes = cell.trail.length > 0 || (cell.content.length > 0 && text.rangeOfComposedCharacterSequence(at: last).length == 1)
                // What stands before the words: the spaces after the pipe, or
                // the pipe itself. A cell with nothing to carry the space
                // after its words takes all of it before them.
                var lead = cell.lead.length > 0 || cell.pipe != nil ? space + before : 0
                if !closes, lead > 0 { lead = total - cell.pipeWidth - content }
                if cell.lead.length > 0 {
                    add(lead - cell.leadWidth, over: cell.lead)
                } else if let pipe = cell.pipe {
                    extra[pipe, default: 0] += lead
                }
                let rest = total - cell.pipeWidth - lead - content
                if cell.trail.length > 0 {
                    add(rest - cell.trailWidth, over: cell.trail)
                } else if closes {
                    extra[last, default: 0] += rest
                }
            }
        }
        plan.spacing.merge(extra) { $0 + $1 }
    }

    /// The width a line of the editor holds, when it is on screen.
    private static func room(in storage: NSTextStorage) -> CGFloat? {
        guard let container = storage.layoutManagers.first?.textContainers.first, container.size.width > 0, container.size.width < 100_000 else { return nil }
        return container.size.width - 2 * container.lineFragmentPadding
    }
}

extension NSTextStorage {
    @MainActor @objc fileprivate func alignTableColumns() {
        TableColumnAligner.alignAll(in: self)
    }
}

extension EditTextView {
    /// Tables are looked at again when the editor's width changes. Called
    /// once, where the editor is set up.
    func followWidthForTables() {
        postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(tableWidthMayHaveChanged), name: NSView.frameDidChangeNotification, object: self)
    }

    @objc private func tableWidthMayHaveChanged() {
        guard let storage = textStorage else { return }
        TableColumnAligner.widthChanged(of: storage)
    }
}
