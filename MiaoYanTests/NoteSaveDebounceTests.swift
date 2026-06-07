import XCTest

@testable import MiaoYan

/// Regression coverage for V3.5.1+ fix `cb46c987` "durable saves": the 1.5s
/// debounce window between `save(content:)` and the actual disk write is a
/// real data-loss surface. `flushPendingSave` must drain the queued work item
/// synchronously so app-lifecycle hooks (`applicationWillTerminate`,
/// window-will-close, resign-key) cannot exit with unsaved keystrokes.
final class NoteSaveDebounceTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiaoYanNoteSaveTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    @MainActor
    func testHasPendingSaveIsFalseOnFreshNote() {
        let url = tempDir.appendingPathComponent("fresh.md")
        let project = Project(url: tempDir, label: "test", isRoot: true)
        let note = Note(url: url, with: project)

        XCTAssertFalse(note.hasPendingSave, "a brand-new Note has no debounced work item")
    }

    @MainActor
    func testSaveContentSchedulesDebouncedWorkItem() {
        let url = tempDir.appendingPathComponent("scheduled.md")
        let project = Project(url: tempDir, label: "test", isRoot: true)
        let note = Note(url: url, with: project)

        note.save(attributed: NSAttributedString(string: "draft body"))

        XCTAssertTrue(
            note.hasPendingSave,
            "save(attributed:) routes through debounceSave and must mark the note as pending")
    }

    @MainActor
    func testFlushPendingSaveClearsTheWorkItem() {
        let url = tempDir.appendingPathComponent("flushed.md")
        let project = Project(url: tempDir, label: "test", isRoot: true)
        let note = Note(url: url, with: project)

        note.save(attributed: NSAttributedString(string: "first content"))
        XCTAssertTrue(note.hasPendingSave)

        note.flushPendingSave(globalStorage: false)

        XCTAssertFalse(
            note.hasPendingSave,
            "flushPendingSave must drain (or clear) the debounced work item synchronously")
    }
}
