import Carbon.HIToolbox
import MiaoYanCore
import XCTest

@testable import MiaoYan

/// Tables in the editor: Tab, Shift-Tab and Return move between cells and
/// rows, the Table menu adds and removes them, and what the keys write is
/// what Format writes.
final class TableEditingTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanTable-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    @MainActor
    private func makeEditor(_ body: String, caretAfter marker: String) throws -> EditTextView {
        let url = tempDir.appendingPathComponent("table-\(UUID().uuidString).md")
        try body.write(to: url, atomically: true, encoding: .utf8)
        let note = Note(url: url, with: Project(url: tempDir, label: "test", isRoot: true))
        note.content = NSMutableAttributedString(string: body)
        EditTextView.note = note
        let editor = EditTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        editor.isShellHosted = true
        editor.publishStorage(NSAttributedString(string: body), owner: note)
        let found = (body as NSString).range(of: marker)
        XCTAssertNotEqual(found.location, NSNotFound)
        editor.setSelectedRange(NSRange(location: NSMaxRange(found), length: 0))
        return editor
    }

    @MainActor
    private func press(_ key: Int, shift: Bool = false, in editor: EditTextView) throws {
        let characters = key == kVK_Return ? "\r" : "\t"
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [], timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(key)))
        editor.keyDown(with: event)
    }

    @MainActor
    private func selected(_ editor: EditTextView) -> String {
        (editor.string as NSString).substring(with: editor.selectedRange())
    }

    private let table = """
        | Name  | Price |
        | ----- | ----- |
        | Apple | 3     |
        | Pear  | 12    |
        """

    /// Tab in a table row indented the whole row by two spaces, and Return
    /// broke the row in two.
    @MainActor
    func testTabAndReturnMoveThroughATableInsteadOfIndentingAndBreakingIt() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        let editor = try makeEditor(table, caretAfter: "App")

        try press(kVK_Tab, in: editor)
        XCTAssertEqual(editor.string, table, "a tidy table is not rewritten")
        XCTAssertEqual(selected(editor), "3")
        try press(kVK_Tab, in: editor)
        XCTAssertEqual(selected(editor), "Pear")
        try press(kVK_Tab, shift: true, in: editor)
        XCTAssertEqual(selected(editor), "3")

        try press(kVK_Return, in: editor)
        XCTAssertEqual(selected(editor), "Pear")
        try press(kVK_Return, in: editor)
        XCTAssertEqual(editor.string, table + "\n|       |       |", "Return on the last row adds one")
        try press(kVK_Return, in: editor)
        XCTAssertEqual(editor.string, table + "\n", "and on that row left empty, leaves the table")
        XCTAssertEqual(editor.selectedRange().location, (editor.string as NSString).length)
    }

    @MainActor
    func testTabOutsideATableStillIndents() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        let editor = try makeEditor("- item\n\na | b in a sentence", caretAfter: "- item")
        try press(kVK_Tab, in: editor)
        XCTAssertEqual(editor.string, "  - item\n\na | b in a sentence")
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        try press(kVK_Return, in: editor)
        XCTAssertEqual(editor.string, "  - item\n\na | b in a sentence\n")
    }

    @MainActor
    func testShiftReturnInATableIsStillAPlainLineBreak() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        let editor = try makeEditor(table, caretAfter: "| 12    |")
        try press(kVK_Return, shift: true, in: editor)
        XCTAssertEqual(editor.string, table + "\n")
    }

    /// One step of undo takes back one table key, and the table with it.
    @available(macOS 14, *)
    @MainActor
    func testATableKeyIsOneUndoStep() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let rough = "|Name|Price|\n|-|-|\n|Apple|3|"
        let url = tempDir.appendingPathComponent("undo.md")
        try rough.write(to: url, atomically: true, encoding: .utf8)
        let note = Note(url: url, with: Project(url: tempDir, label: "test", isRoot: true))
        note.content = NSMutableAttributedString(string: rough)
        note.markContentAsLoaded()
        note.loadModifiedLocalAt()
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)
        let editor = controller.textView
        editor.setSelectedRange(NSRange(location: NSMaxRange((rough as NSString).range(of: "App")), length: 0))
        let manager = try XCTUnwrap(editor.undoManager)

        try press(kVK_Tab, in: editor)
        XCTAssertEqual(editor.string, "| Name  | Price |\n| ----- | ----- |\n| Apple | 3     |")
        manager.undo()
        XCTAssertEqual(editor.string, rough)
    }

    @MainActor
    func testTheTableMenuIsOnOnlyWhereItCanAct() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        let editor = try makeEditor(table + "\n\nprose", caretAfter: "App")
        func item(_ selector: Selector) -> NSMenuItem { NSMenuItem(title: "", action: selector, keyEquivalent: "") }
        for selector in EditTextView.tableCommands.keys {
            XCTAssertTrue(editor.validateMenuItem(item(selector)), "\(selector) in a body row")
        }
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        XCTAssertFalse(editor.validateMenuItem(item(#selector(EditTextView.deleteTableRow(_:)))), "the header is not a row to delete")
        XCTAssertTrue(editor.validateMenuItem(item(#selector(EditTextView.insertTableRowBelow(_:)))))
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        for selector in EditTextView.tableCommands.keys {
            XCTAssertFalse(editor.validateMenuItem(item(selector)), "\(selector) in prose")
        }

        editor.setSelectedRange(NSRange(location: (table as NSString).range(of: "App").location, length: 0))
        editor.insertTableColumnRight(self)
        XCTAssertTrue(editor.string.hasPrefix("| Name  |     | Price |\n| ----- | --- | ----- |\n| Apple |     | 3     |"))
        editor.deleteTableColumn(self)
        editor.alignTableColumnRight(self)
        XCTAssertTrue(editor.string.hasPrefix("| Name  | Price |\n| ----- | ----: |\n| Apple |     3 |\n| Pear  |    12 |"), editor.string)
    }

    /// The keys and Format agree, or every Format after a Tab would shuffle
    /// the table's spaces and every Tab after a Format shuffle them back.
    func testFormatLeavesATableTheKeysTidiedAsItIs() async throws {
        let rough = """
            |\u{540D}\u{79F0}|Price|Note|
            |:-|-:|:-:|
            |\u{82F9}\u{679C}\u{6C41}|3|\u{1F600} ok|
            |Pear \u{FF08}\u{68A8}\u{FF09}|12|caf\u{E9}|
            |\u{30AB}\u{30BF}\u{30AB}\u{30CA}|1000||
            """
        let source = rough as NSString
        let edit = try XCTUnwrap(TableEditing.edit(.align(.left), in: source, selection: NSRange(location: 2, length: 0)))
        let tidied = source.replacingCharacters(in: edit.range, with: edit.replacement)
        XCTAssertNotEqual(tidied, rough)
        let formatted = try await MarkdownFormatWorker().format(content: tidied + "\n", cursor: 0).formattedString
        XCTAssertEqual(formatted, tidied + "\n")
    }

    func testTheTableMenuIsInTheStoryboardAndEveryLanguage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let localization = root.appendingPathComponent("Resources/Localization")
        let storyboard = try String(contentsOf: localization.appendingPathComponent("Base.lproj/Main.storyboard"), encoding: .utf8)
        let ids = [
            "Tbl-Mn-Itm", "Tbl-Mn-Sub", "TbR-Ab-Itm", "TbR-Bl-Itm", "TbC-Lf-Itm", "TbC-Rt-Itm", "TbR-Dl-Itm", "TbC-Dl-Itm", "TbA-Lf-Itm",
            "TbA-Ct-Itm", "TbA-Rt-Itm",
        ]
        for id in ids { XCTAssertTrue(storyboard.contains("id=\"\(id)\""), id) }
        let selectors = [
            "insertTableRowAbove:", "insertTableRowBelow:", "insertTableColumnLeft:", "insertTableColumnRight:", "deleteTableRow:",
            "deleteTableColumn:", "alignTableColumnLeft:", "alignTableColumnCenter:", "alignTableColumnRight:",
        ]
        for selector in selectors {
            XCTAssertTrue(storyboard.contains("<action selector=\"\(selector)\" target=\"Ady-hI-5gd\""), "\(selector) goes to the first responder")
            XCTAssertTrue(EditTextView.instancesRespond(to: Selector(selector)), selector)
        }
        for language in ["es", "ja", "zh-Hans", "zh-Hant"] {
            let strings = try String(contentsOf: localization.appendingPathComponent("\(language).lproj/Main.strings"), encoding: .utf8)
            for id in ids { XCTAssertTrue(strings.contains("\"\(id).title\" = \""), "\(language) \(id)") }
        }
    }

    // MARK: - Columns lined up on screen

    private let ragged = """
        Before the table.

        | Name | Price | Note |
        | :-- | --: | :-: |
        | Apple | 3 | **fresh** |
        | \u{897F}\u{74DC} | 1200 | `code` and more words |
        | Fig | 12 | \u{597D} |

        After the table.
        """

    @MainActor
    private func makeNote(_ body: String) -> Note {
        let url = tempDir.appendingPathComponent("columns-\(UUID().uuidString).md")
        try? body.write(to: url, atomically: true, encoding: .utf8)
        let note = Note(url: url, with: Project(url: tempDir, label: "test", isRoot: true))
        note.content = NSMutableAttributedString(string: body)
        note.markContentAsLoaded()
        note.loadModifiedLocalAt()
        return note
    }

    /// Where each pipe of each table row is drawn, by column: the x of its
    /// glyph in the laid-out text.
    @MainActor
    private func pipeColumns(in editor: EditTextView) throws -> [[CGFloat]] {
        let manager = try XCTUnwrap(editor.layoutManager)
        let container = try XCTUnwrap(editor.textContainer)
        manager.ensureLayout(for: container)
        let text = editor.string as NSString
        var columns: [[CGFloat]] = []
        var lines = 0
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byLines) { line, range, _, _ in
            guard let line, line.hasPrefix("|") else { return }
            lines += 1
            var column = 0
            for (offset, unit) in line.utf16.enumerated() where unit == 0x7C {
                let glyph = manager.glyphIndexForCharacter(at: range.location + offset)
                let x = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minX + manager.location(forGlyphAt: glyph).x
                if columns.count <= column { columns.append([]) }
                columns[column].append(x)
                column += 1
            }
        }
        XCTAssertTrue(columns.allSatisfy { $0.count == lines }, "every row has every pipe")
        return columns
    }

    private func spread(_ values: [CGFloat]) -> CGFloat { (values.max() ?? 0) - (values.min() ?? 0) }

    /// The editor's face is proportional: the spaces that pad a cell in the
    /// file left the pipes of a column up to a word apart on screen.
    @available(macOS 14, *)
    @MainActor
    func testTheColumnsOfATableLineUpOnScreen() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        let note = makeNote(ragged)
        defer { note.discardPendingSave() }

        let controller = ShellEditorController()
        controller.textView.frame = NSRect(x: 0, y: 0, width: 1200, height: 600)
        controller.show(note)
        let editor = controller.textView
        let storage = try XCTUnwrap(editor.textStorage)
        let aligned = try pipeColumns(in: editor)
        XCTAssertEqual(aligned.count, 4)
        for (column, xs) in aligned.enumerated() {
            XCTAssertLessThan(spread(xs), 0.5, "the pipes of column \(column) stand under each other")
        }
        XCTAssertEqual(editor.string, ragged, "not a character of the note changes")

        // The pipes and the line of dashes are in the markup colour, the words are not.
        let text = editor.string as NSString
        func isQuiet(_ offset: Int) -> Bool { storage.attribute(TableColumnAligner.quietKey, at: offset, effectiveRange: nil) != nil }
        XCTAssertTrue(isQuiet(text.range(of: "| Name").location))
        XCTAssertTrue(isQuiet(text.range(of: "--:").location))
        XCTAssertFalse(isQuiet(text.range(of: "Name").location))
        XCTAssertFalse(isQuiet(text.range(of: "Before").location))

        // With the plain spacing back, the same pipes are a word apart.
        storage.addAttribute(.kern, value: UserDefaultsManagement.editorLetterSpacing, range: NSRange(location: 0, length: storage.length))
        XCTAssertGreaterThan(spread(try pipeColumns(in: editor)[1]), 8, "as typed the second pipes are far apart")
    }

    /// Typing in a cell moves its whole column, and a table that stops being
    /// one gets the spacing of plain text back.
    @available(macOS 14, *)
    @MainActor
    func testTheColumnsFollowTheTypingAndLetGoOfABrokenTable() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        let note = makeNote(ragged)
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.textView.frame = NSRect(x: 0, y: 0, width: 1200, height: 600)
        controller.show(note)
        let editor = controller.textView
        let storage = try XCTUnwrap(editor.textStorage)
        let before = try pipeColumns(in: editor)

        let fig = (editor.string as NSString).range(of: "Fig")
        editor.insertText(" and a much longer name", replacementRange: NSRange(location: NSMaxRange(fig), length: 0))
        let after = try pipeColumns(in: editor)
        XCTAssertGreaterThan(after[1][0] - before[1][0], 40, "the header's second pipe moved with the longest cell")
        for xs in after { XCTAssertLessThan(spread(xs), 0.5) }

        func widened() -> Int {
            var count = 0
            storage.enumerateAttribute(TableColumnAligner.widenedKey, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if value != nil { count += range.length }
            }
            return count
        }
        XCTAssertGreaterThan(widened(), 0)

        // Without its line of dashes the rows are plain lines again.
        let dashes = (editor.string as NSString).range(of: "| :-- | --: | :-: |")
        editor.insertText("not a rule", replacementRange: dashes)
        XCTAssertEqual(widened(), 0)
        var quiet = 0
        storage.enumerateAttribute(TableColumnAligner.quietKey, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if value != nil { quiet += range.length }
        }
        XCTAssertEqual(quiet, 0, "and their pipes the colour of the text")
        let pipe = (editor.string as NSString).range(of: "| Fig").location
        let colour = try XCTUnwrap(storage.attribute(.foregroundColor, at: pipe, effectiveRange: nil) as? NSColor)
        let word = try XCTUnwrap(storage.attribute(.foregroundColor, at: pipe + 2, effectiveRange: nil) as? NSColor)
        XCTAssertEqual(colour.usingColorSpace(.sRGB), word.usingColorSpace(.sRGB))
        let spacing = UserDefaultsManagement.editorLetterSpacing
        storage.enumerateAttribute(.kern, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            XCTAssertEqual((value as? NSNumber)?.doubleValue ?? 0, spacing, accuracy: 0.001, "at \(range)")
        }
    }

    /// The characters drawn as part of a table: the spaces given another
    /// width and the pipes and dashes given the markup colour.
    @MainActor
    private func drawnAsTable(_ editor: EditTextView, in range: NSRange? = nil) -> Int {
        guard let storage = editor.textStorage else { return 0 }
        var count = 0
        for key in [TableColumnAligner.widenedKey, TableColumnAligner.quietKey] {
            storage.enumerateAttribute(key, in: range ?? NSRange(location: 0, length: storage.length)) { value, range, _ in
                if value != nil { count += range.length }
            }
        }
        return count
    }

    /// A line break typed at the end of a row parts the rows under it from
    /// their line of dashes. They kept their spacing and grey pipes: the
    /// pass stopped at the new empty line (found in review before it shipped).
    @available(macOS 14, *)
    @MainActor
    func testRowsPartedFromTheirLineOfDashesArePlainLinesAgain() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        let note = makeNote("| a | b |\n| - | - |\n| long cell | d |\n| e | f |\n| g | h |\n\nend")
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.textView.frame = NSRect(x: 0, y: 0, width: 1200, height: 600)
        controller.show(note)
        let editor = controller.textView
        func row(_ words: String) -> NSRange { (editor.string as NSString).range(of: words) }
        XCTAssertGreaterThan(drawnAsTable(editor, in: row("| g | h |")), 0)

        editor.insertText("\n", replacementRange: NSRange(location: NSMaxRange(row("| long cell | d |")), length: 0))
        XCTAssertEqual(editor.string, "| a | b |\n| - | - |\n| long cell | d |\n\n| e | f |\n| g | h |\n\nend")
        XCTAssertEqual(drawnAsTable(editor, in: row("| e | f |")), 0)
        XCTAssertEqual(drawnAsTable(editor, in: row("| g | h |")), 0)
        XCTAssertGreaterThan(drawnAsTable(editor, in: row("| long cell | d |")), 0, "the rows above are a table still")
    }

    /// What the whole note is read as when it opens, a keystroke reads it
    /// as too: rows inside a formula or a fence of tildes lined up on the
    /// first character typed and fell back on the next opening, while the
    /// keystroke asked the highlighter's code blocks, which are the closed
    /// fences of backticks only (found in review before it shipped).
    @available(macOS 14, *)
    @MainActor
    func testOnlyAMarkdownTableOutsideCodeIsDrawnAsOne() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        let rows = "| a | b |\n| - | - |\n| long cell | d |\n"
        for body in ["$$\n" + rows + "$$\n", "~~~\n" + rows + "~~~\n", "```\n" + rows] {
            let note = makeNote(body)
            defer { note.discardPendingSave() }
            let controller = ShellEditorController()
            controller.textView.frame = NSRect(x: 0, y: 0, width: 1200, height: 600)
            controller.show(note)
            let editor = controller.textView
            XCTAssertEqual(drawnAsTable(editor), 0, "\(body.debugDescription) on opening")
            let cell = (editor.string as NSString).range(of: "long cell")
            editor.insertText("x", replacementRange: NSRange(location: NSMaxRange(cell), length: 0))
            XCTAssertEqual(drawnAsTable(editor), 0, "\(body.debugDescription) after a keystroke")
        }
        let note = makeNote(rows)
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)
        XCTAssertGreaterThan(drawnAsTable(controller.textView), 0, "the same rows in a Markdown note are")
    }

    /// Every row of a table is measured again when one changes, and a prose
    /// keystroke only looks at the lines beside it.
    @available(macOS 14, *)
    @MainActor
    func testTypingInALongTableAndBesideItStaysQuick() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        let rows = (0..<200).map { "| row \($0) | \u{4E2D}\u{6587} \($0 * 7) | some words here | `code` | **bold** |" }
        let body = "Prose above.\n\n| A | B | C | D | E |\n| - | - | - | - | - |\n" + rows.joined(separator: "\n") + "\n\nProse below."
        let note = makeNote(body)
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.textView.frame = NSRect(x: 0, y: 0, width: 1200, height: 600)
        controller.show(note)
        let editor = controller.textView
        for xs in try pipeColumns(in: editor) { XCTAssertLessThan(spread(xs), 0.5) }

        func average(typingAfter marker: String) -> TimeInterval {
            var at = NSMaxRange((editor.string as NSString).range(of: marker))
            let start = Date()
            for _ in 0..<20 {
                editor.insertText("x", replacementRange: NSRange(location: at, length: 0))
                at += 1
            }
            return Date().timeIntervalSince(start) / 20
        }
        let inTable = average(typingAfter: "row 100")
        let inProse = average(typingAfter: "Prose above")
        // 27 ms and 0.6 ms in a Debug build on an M-series Mac (2026-11-21);
        // the limits leave room for a slow CI runner and catch a pass that
        // grows with the square of the rows or reads the whole note.
        XCTAssertLessThan(inTable, 0.25)
        XCTAssertLessThan(inProse, 0.02)
        for xs in try pipeColumns(in: editor) { XCTAssertLessThan(spread(xs), 0.5) }

        // Rows far below a line of dashes that is typed over are plain
        // lines again too, where the highlighter does not reach.
        let storage = try XCTUnwrap(editor.textStorage)
        editor.insertText("no rule", replacementRange: (editor.string as NSString).range(of: "| - | - | - | - | - |"))
        let far = (editor.string as NSString).range(of: "| row 150").location
        XCTAssertNil(storage.attribute(TableColumnAligner.quietKey, at: far, effectiveRange: nil))
        XCTAssertNil(storage.attribute(TableColumnAligner.widenedKey, at: far + 1, effectiveRange: nil))
        let pipe = try XCTUnwrap(storage.attribute(.foregroundColor, at: far, effectiveRange: nil) as? NSColor)
        let word = try XCTUnwrap(storage.attribute(.foregroundColor, at: far + 2, effectiveRange: nil) as? NSColor)
        XCTAssertEqual(pipe.usingColorSpace(.sRGB), word.usingColorSpace(.sRGB))
    }

    /// The first header is selected and the rows under it are as wide as the
    /// headers, in every language's words.
    @MainActor
    func testTheTableTemplateIsTidyInEveryLanguage() throws {
        for code in ["en", "zh-Hans", "zh-Hant", "ja", "es"] {
            I18n.overrideBundle = try XCTUnwrap(Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)))
            defer { I18n.overrideBundle = nil }
            let template = try XCTUnwrap(ShortcutTemplateManager.shared.getTemplate(for: "table"))
            let text = template.content as NSString
            let lines = template.content.components(separatedBy: "\n")
            XCTAssertEqual(lines.count, 4, code)
            let again = try XCTUnwrap(TableEditing.edit(.align(.none), in: text, selection: NSRange(location: 2, length: 0)))
            XCTAssertTrue(again.range.length == 0 && again.replacement.isEmpty, "\(code): already as the keys write it")
            XCTAssertEqual(text.substring(with: NSRange(location: template.cursorOffset, length: template.cursorLength)), I18n.str("Column 1"), code)
        }
        I18n.overrideBundle = try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)))
        defer { I18n.overrideBundle = nil }
        XCTAssertEqual(
            ShortcutTemplateManager.shared.getTemplate(for: "table")?.content,
            "| Column 1 | Column 2 | Column 3 |\n| -------- | -------- | -------- |\n|          |          |          |\n|          |          |          |")
        for key in ["table", "markmap", "mermaid", "plantuml", "fold", "task"] {
            let content = try XCTUnwrap(ShortcutTemplateManager.shared.getTemplate(for: key)).content
            XCTAssertNil(content.unicodeScalars.first { $0.value >= 0x2E80 }, "/\(key) in English holds no Chinese word")
        }
        I18n.overrideBundle = try XCTUnwrap(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj").flatMap(Bundle.init(path:)))
        XCTAssertEqual(
            ShortcutTemplateManager.shared.getTemplate(for: "table")?.content,
            "| \u{5217}1 | \u{5217}2 | \u{5217}3 |\n| --- | --- | --- |\n|     |     |     |\n|     |     |     |", "the Chinese template is the one it always was")
        XCTAssertEqual(ShortcutTemplateManager.shared.getTemplate(for: "task")?.content, "- [ ] \u{5F85}\u{5B8C}\u{6210}\u{4EFB}\u{52A1}1\n- [ ] \u{5F85}\u{5B8C}\u{6210}\u{4EFB}\u{52A1}2\n- [x] \u{5DF2}\u{5B8C}\u{6210}\u{4EFB}\u{52A1}")
    }
}
