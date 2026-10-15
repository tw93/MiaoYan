import XCTest

@testable import MiaoYan

/// The SwiftUI shell's editor column against the storyboard window's rules.
final class ShellEditorParityTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanShellEditorTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    @MainActor
    private func makeLoadedNote(_ name: String, body: String) -> Note {
        let url = tempDir.appendingPathComponent(name)
        try? body.write(to: url, atomically: true, encoding: .utf8)
        let project = Project(url: tempDir, label: "test", isRoot: true)
        let note = Note(url: url, with: project)
        note.content = NSMutableAttributedString(string: body)
        note.markContentAsLoaded()
        note.loadModifiedLocalAt()
        return note
    }

    /// A task ticked in the preview is saved to the note while the editor is
    /// off screen. Coming back, the editor must show the tick, or the next
    /// keystroke saves the old buffer over it.
    @available(macOS 14, *)
    @MainActor
    func testTaskTickedInPreviewSurvivesTheNextKeystroke() {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let note = makeLoadedNote("tasks.md", body: "- [ ] buy milk")
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)
        XCTAssertEqual(controller.textView.string, "- [ ] buy milk")

        // HandlerCheckbox's path when no editor is in the window.
        note.save(content: NSMutableAttributedString(string: "- [x] buy milk"))
        controller.show(note)

        XCTAssertEqual(controller.textView.string, "- [x] buy milk")
        XCTAssertTrue(controller.textView.storageNote === note, "the refill keeps the buffer's owner (#543)")
        let end = (controller.textView.string as NSString).length
        controller.textView.insertText("!", replacementRange: NSRange(location: end, length: 0))
        XCTAssertEqual(note.content.string, "- [x] buy milk!")
    }

    @available(macOS 14, *)
    @MainActor
    func testShowLeavesAnUnchangedBufferAlone() {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let note = makeLoadedNote("same.md", body: "line one\nline two")
        let controller = ShellEditorController()
        controller.show(note)
        controller.textView.setSelectedRange(NSRange(location: 5, length: 3))
        controller.show(note)
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 5, length: 3))
    }

    func testPreviewDelayMatchesTheStoryboardEditor() {
        XCTAssertEqual(ShellSplitMath.previewDelay(forReplacement: "a"), 0.15)
        XCTAssertEqual(ShellSplitMath.previewDelay(forReplacement: nil), 0.15)
        XCTAssertEqual(ShellSplitMath.previewDelay(forReplacement: ""), 0.15)
        XCTAssertEqual(ShellSplitMath.previewDelay(forReplacement: "\n"), 0)
        XCTAssertEqual(ShellSplitMath.previewDelay(forReplacement: "\r\n"), 0)
        XCTAssertEqual(ShellSplitMath.previewDelay(forReplacement: "pasted"), 0)
        // One composed CJK character is one key.
        XCTAssertEqual(ShellSplitMath.previewDelay(forReplacement: "\u{4E2D}"), 0.15)
    }

    func testScrollSyncLinesSkipTheFrontmatter() {
        let text = "---\ntitle: a\n---\n# Heading\n\nbody"
        let starts = ShellSplitMath.lineStarts(of: text)
        XCTAssertEqual(starts, [0, 4, 13, 17, 27, 28])
        let frontmatter = 3
        // The heading is the body's first line.
        XCTAssertEqual(ShellSplitMath.bodyLine(atCharacter: 17, lineStarts: starts, frontmatterLines: frontmatter), 1)
        XCTAssertEqual(ShellSplitMath.bodyLine(atCharacter: 30, lineStarts: starts, frontmatterLines: frontmatter), 3)
        // Inside the frontmatter clamps to the first body line.
        XCTAssertEqual(ShellSplitMath.bodyLine(atCharacter: 5, lineStarts: starts, frontmatterLines: frontmatter), 1)
        // And back: body line 1 is buffer line 3 (0-based).
        let back = ShellSplitMath.bufferLine(forPreviewLine: 1.5, frontmatterLines: frontmatter)
        XCTAssertEqual(back.line, 3)
        XCTAssertEqual(back.fraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(ShellSplitMath.bufferLine(forPreviewLine: 3, frontmatterLines: 0).line, 2)
    }

    func testSplitPaneWidthFollowsEditorContentSplitView() {
        // First use: half, at most 600pt.
        XCTAssertEqual(ShellSplitMath.editorWidth(total: 800, savedRatio: 0), 400)
        XCTAssertEqual(ShellSplitMath.editorWidth(total: 1600, savedRatio: 0), 600)
        // A saved ratio, kept 200pt from either edge and under 1200pt.
        XCTAssertEqual(ShellSplitMath.editorWidth(total: 1000, savedRatio: 0.3), 300)
        XCTAssertEqual(ShellSplitMath.editorWidth(total: 1000, savedRatio: 0.05), 200)
        XCTAssertEqual(ShellSplitMath.editorWidth(total: 1000, savedRatio: 0.95), 800)
        XCTAssertEqual(ShellSplitMath.editorWidth(total: 3000, savedRatio: 0.9), 1200)
        // Never wider than the split itself.
        XCTAssertLessThanOrEqual(ShellSplitMath.editorWidth(total: 150, savedRatio: 0.5), 150)
    }

    @available(macOS 14, *)
    func testPastedTitleLineBreaksBecomeSpaces() {
        XCTAssertEqual(ShellModel.singleLineTitle("plain"), "plain")
        XCTAssertEqual(ShellModel.singleLineTitle("one\ntwo"), "one two")
        XCTAssertEqual(ShellModel.singleLineTitle("one\r\ntwo\rthree"), "one two three")
    }

    func testRelaunchFromTheShellReopensTheShell() {
        let path = "'/Applications/MiaoYan.app'"
        XCTAssertEqual(
            AppDelegate.relaunchCommand(quotedAppPath: path, intoShell: false),
            "sleep 0.7; /usr/bin/open -n -a '/Applications/MiaoYan.app'")
        XCTAssertEqual(
            AppDelegate.relaunchCommand(quotedAppPath: path, intoShell: true),
            "sleep 0.7; /usr/bin/open -n -a '/Applications/MiaoYan.app' --args -MiaoYanShell YES")
    }
}
