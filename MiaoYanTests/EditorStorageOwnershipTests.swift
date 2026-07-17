import XCTest

@testable import MiaoYan

/// Regression coverage for #543 "文件内容被错误替换": in preview-family modes
/// `EditTextView.note` follows the list selection while `textStorage` keeps the
/// previously edited note's bytes (fill() returns before the editor branch).
/// Whole-buffer persists that trusted `EditTextView.note` then wrote note X's
/// full text into note Y's file. `saveTextStorageContent` must refuse any save
/// whose target is not the storage owner recorded by `publishStorage`.
final class EditorStorageOwnershipTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiaoYanOwnershipTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    @MainActor
    private func makeNote(_ name: String, body: String) -> Note {
        let url = tempDir.appendingPathComponent(name)
        try? body.write(to: url, atomically: true, encoding: .utf8)
        let project = Project(url: tempDir, label: "test", isRoot: true)
        let note = Note(url: url, with: project)
        note.content = NSMutableAttributedString(string: body)
        return note
    }

    @MainActor
    func testRefusesCrossNoteWholeBufferSave() {
        let noteA = makeNote("a.md", body: "AAA original")
        let noteB = makeNote("b.md", body: "BBB original")
        let editor = EditTextView(frame: .zero)

        // Simulate the preview-mode desync: buffer holds B while a save
        // targets A (Cmd+S / window-close / duplicate after a list switch).
        editor.publishStorage(NSAttributedString(string: "BBB original"), owner: noteB)
        editor.saveTextStorageContent(to: noteA)

        XCTAssertEqual(noteA.content.string, "AAA original", "cross-note save must be refused, not overwrite the target")
        XCTAssertEqual(noteB.content.string, "BBB original", "the buffer owner must stay untouched")
    }

    @MainActor
    func testAllowsSaveWhenOwnerMatches() {
        let noteB = makeNote("b.md", body: "BBB original")
        let editor = EditTextView(frame: .zero)

        editor.publishStorage(NSAttributedString(string: "BBB edited"), owner: noteB)
        editor.saveTextStorageContent(to: noteB)

        XCTAssertEqual(noteB.content.string, "BBB edited")
    }

    @MainActor
    func testAllowsSaveToDifferentInstanceWithSameURL() {
        // Ownership is keyed by file identity, not object identity, so a
        // reloaded Note instance for the same file must still be writable.
        let noteB1 = makeNote("b.md", body: "BBB original")
        let noteB2 = makeNote("b.md", body: "BBB original")
        let editor = EditTextView(frame: .zero)

        editor.publishStorage(NSAttributedString(string: "BBB edited"), owner: noteB1)
        editor.saveTextStorageContent(to: noteB2)

        XCTAssertEqual(noteB2.content.string, "BBB edited")
    }

    @MainActor
    func testRefusesSaveFromClearedBuffer() {
        let noteA = makeNote("a.md", body: "AAA original")
        let editor = EditTextView(frame: .zero)

        editor.publishStorage(NSAttributedString(), owner: nil)
        editor.saveTextStorageContent(to: noteA)

        XCTAssertEqual(noteA.content.string, "AAA original", "an ownerless (cleared) buffer must never be persisted")
    }

    @MainActor
    func testUploadPlaceholdersAreUniquePerUpload() {
        // A shared "![](uploading...)" literal let one upload's completion
        // match a placeholder in a different note's buffer and cross-write
        // full contents between files (#543).
        let first = ClipboardManager.makeUploadPlaceholder()
        let second = ClipboardManager.makeUploadPlaceholder()

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.hasPrefix("![](uploading-"))
        XCTAssertTrue(first.hasSuffix("...)"))
    }
}
