import AppKit
import XCTest

@testable import MiaoYan

/// A long list item wrapped under the dash, so the item's own words lost
/// their left edge (reader feedback 2026-11-17).
final class ListHangingIndentTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanHanging-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private let long = "words that keep going well past the edge of a narrow editor so the item has to wrap onto more lines"

    private var body: String {
        """
        Prose \(long)

        - \(long)
        12. \(long)
        - [ ] \(long)
          - \(long)

        ```
        - \(long)
        ```
        """
    }

    @available(macOS 14, *)
    @MainActor
    private func show(_ text: String) throws -> EditTextView {
        let url = tempDir.appendingPathComponent("list-\(UUID().uuidString).md")
        try text.write(to: url, atomically: true, encoding: .utf8)
        let note = Note(url: url, with: Project(url: tempDir, label: "test", isRoot: true))
        note.content = NSMutableAttributedString(string: text)
        note.markContentAsLoaded()
        note.loadModifiedLocalAt()
        addTeardownBlock { @MainActor in note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.textView.frame = NSRect(x: 0, y: 0, width: 320, height: 900)
        controller.show(note)
        return controller.textView
    }

    /// Where a paragraph's first glyph, its text after the marker and its
    /// second line start.
    private struct Edges {
        let start: CGFloat
        let text: CGFloat
        let wrapped: CGFloat
    }

    /// Where the glyph of a character is drawn, and the x where the line
    /// after the first line of its paragraph starts.
    @MainActor
    private func edges(of words: String, startingAt marker: String, in editor: EditTextView, occurrence: Int = 0) throws -> Edges {
        let manager = try XCTUnwrap(editor.layoutManager)
        manager.ensureLayout(for: try XCTUnwrap(editor.textContainer))
        let string = editor.string as NSString
        var search = NSRange(location: 0, length: string.length)
        var found = NSRange(location: NSNotFound, length: 0)
        for _ in 0...occurrence {
            found = string.range(of: marker + words, range: search)
            XCTAssertNotEqual(found.location, NSNotFound)
            search = NSRange(location: NSMaxRange(found), length: string.length - NSMaxRange(found))
        }
        func x(_ character: Int) -> CGFloat {
            let glyph = manager.glyphIndexForCharacter(at: character)
            return manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minX + manager.location(forGlyphAt: glyph).x
        }
        let textStart = found.location + (marker as NSString).length
        var firstLine = NSRange()
        manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: textStart), effectiveRange: &firstLine)
        let secondLineCharacter = manager.characterIndexForGlyph(at: NSMaxRange(firstLine))
        XCTAssertLessThan(secondLineCharacter, NSMaxRange(found), "the item wraps")
        return Edges(start: x(found.location), text: x(textStart), wrapped: x(secondLineCharacter))
    }

    @available(macOS 14, *)
    @MainActor
    func testAWrappedListItemLinesUpUnderItsOwnWords() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        let editor = try show(body)

        for marker in ["- ", "12. ", "- [ ] ", "  - "] {
            let item = try edges(of: long, startingAt: marker, in: editor, occurrence: 0)
            XCTAssertEqual(item.wrapped, item.text, accuracy: 1, "\(marker.debugDescription) wraps under its words")
            XCTAssertGreaterThan(item.wrapped, item.start + 4, "\(marker.debugDescription) does not wrap to the left edge")
        }
        let prose = try edges(of: long, startingAt: "Prose ", in: editor)
        XCTAssertEqual(prose.wrapped, prose.start, accuracy: 0.5, "prose still wraps to the left edge")
        let code = try edges(of: long, startingAt: "- ", in: editor, occurrence: 2)
        XCTAssertEqual(code.wrapped, code.start, accuracy: 0.5, "a dash inside a code block is not a list")
        XCTAssertEqual(editor.string, body, "not a character changes")
    }

    /// Past twenty code blocks the .codeBlock attribute is missing while typing,
    /// so the fence itself must say a dash line is code.
    @available(macOS 14, *)
    @MainActor
    func testADashInsideAFenceInALongNoteIsNotAList() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        let text = (0..<30).map { _ in "```\n- \(long)\n```\n" }.joined(separator: "\n") + "\n- \(long)\n"
        let editor = try show(text)
        for occurrence in [0, 12, 29] {
            let code = try edges(of: long, startingAt: "- ", in: editor, occurrence: occurrence)
            XCTAssertEqual(code.wrapped, code.start, accuracy: 0.5, "dash \(occurrence) is inside a fence")
        }
        let item = try edges(of: long, startingAt: "- ", in: editor, occurrence: 30)
        XCTAssertEqual(item.wrapped, item.text, accuracy: 1, "a dash after the last fence is a list")
    }

    @available(macOS 14, *)
    @MainActor
    func testAnItemThatStopsBeingOneWrapsToTheEdgeAgain() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        let text = "- \(long)\n"
        let editor = try show(text)
        let before = try edges(of: long, startingAt: "- ", in: editor)
        XCTAssertEqual(before.wrapped, before.text, accuracy: 1)

        editor.insertText("", replacementRange: NSRange(location: 0, length: 2))
        let prose = try edges(of: long, startingAt: "", in: editor)
        XCTAssertEqual(prose.wrapped, prose.start, accuracy: 0.5, "without its dash the line is prose")

        editor.insertText("- ", replacementRange: NSRange(location: 0, length: 0))
        let again = try edges(of: long, startingAt: "- ", in: editor)
        XCTAssertEqual(again.wrapped, again.text, accuracy: 1, "typing the dash back indents it again")
    }
}
