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
