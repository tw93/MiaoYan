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
        XCTAssertTrue(note.needsSave)
    }

    @MainActor
    func testFlushPendingSaveClearsTheWorkItem() {
        let url = tempDir.appendingPathComponent("flushed.md")
        let project = Project(url: tempDir, label: "test", isRoot: true)
        let note = Note(url: url, with: project)

        note.save(attributed: NSAttributedString(string: "first content"))
        XCTAssertTrue(note.hasPendingSave)

        XCTAssertTrue(note.flushPendingSave(globalStorage: false))

        XCTAssertFalse(
            note.hasPendingSave,
            "flushPendingSave must drain (or clear) the debounced work item synchronously")
        XCTAssertFalse(note.needsSave)
    }

    /// A note whose file exists but cannot be read opens as an empty buffer.
    /// Switching away used to save that empty buffer over the real file.
    @MainActor
    func testUnreadableNoteIsNeverOverwrittenByItsEmptyBuffer() throws {
        let url = tempDir.appendingPathComponent("unreadable.md")
        try "the real body".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }

        let project = Project(url: tempDir, label: "test", isRoot: true)
        let note = Note(url: url, with: project)
        note.load()
        XCTAssertTrue(note.loadFailed, "an existing file that cannot be read is a failed load")

        // The file becomes reachable again (back online), so only the guard
        // stands between the empty buffer and the real text.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        note.save(content: NSMutableAttributedString(string: ""))
        _ = note.flushPendingSave(globalStorage: false)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "the real body")
    }

    /// File events are paused while typing, so a sync that lands then never
    /// reaches a resident note. Opening it must pick the new text up.
    @MainActor
    func testResidentNoteRereadsAFileChangedElsewhere() async throws {
        let url = tempDir.appendingPathComponent("synced.md")
        try "old".write(to: url, atomically: true, encoding: .utf8)
        let project = Project(url: tempDir, label: "test", isRoot: true)
        let note = Note(url: url, with: project)
        note.load()
        note.loadModifiedLocalAt()

        try "from the other Mac".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)

        XCTAssertTrue(note.invalidateIfChangedOnDisk())
        await note.ensureContentLoadedAsync()
        XCTAssertEqual(note.content.string, "from the other Mac")
        XCTAssertFalse(note.invalidateIfChangedOnDisk(), "the reread records the new modification date")
    }

    @MainActor
    func testLocalEditsWinOverAReloadUntilSaved() throws {
        let url = tempDir.appendingPathComponent("editing.md")
        try "old".write(to: url, atomically: true, encoding: .utf8)
        let project = Project(url: tempDir, label: "test", isRoot: true)
        let note = Note(url: url, with: project)
        note.load()
        note.loadModifiedLocalAt()
        note.save(content: NSMutableAttributedString(string: "typed here"))

        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)

        XCTAssertFalse(note.invalidateIfChangedOnDisk(), "a pending local edit is never replaced by a silent reload")
        XCTAssertEqual(note.content.string, "typed here")
    }

    /// Reload from Disk must not be undone by the save that was still
    /// waiting when it ran.
    @MainActor
    func testReloadDropsTheSaveThatWasStillWaiting() async throws {
        let url = tempDir.appendingPathComponent("reload.md")
        try "on disk".write(to: url, atomically: true, encoding: .utf8)
        let project = Project(url: tempDir, label: "test", isRoot: true)
        let note = Note(url: url, with: project)
        note.load()
        note.save(content: NSMutableAttributedString(string: "stale buffer"))
        XCTAssertTrue(note.needsSave)

        note.discardPendingSave()
        note.forceReload()
        // Let the debounce timer fire on its own: it holds the text from when
        // it was queued, so a flush (which writes current content) hides it.
        try await Task.sleep(nanoseconds: 2_000_000_000)

        XCTAssertFalse(note.needsSave)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "on disk")
        XCTAssertEqual(note.content.string, "on disk")
    }

    /// History is filed by path; a rename or move must take it along.
    @MainActor
    func testVersionHistoryFollowsTheNoteToItsNewPath() async throws {
        let oldURL = tempDir.appendingPathComponent("before-\(UUID().uuidString).md")
        let newURL = tempDir.appendingPathComponent("after-\(UUID().uuidString).md")
        try "first draft".write(to: oldURL, atomically: true, encoding: .utf8)
        let project = Project(url: tempDir, label: "test", isRoot: true)
        let note = Note(url: oldURL, with: project)
        note.load()
        let manager = NoteVersionManager.shared
        manager.saveVersionIfNeeded(for: note, force: true)
        manager.waitForPendingWork()
        XCTAssertTrue(manager.hasVersions(for: note))

        try FileManager.default.moveItem(at: oldURL, to: newURL)
        note.overwrite(url: newURL)
        manager.waitForPendingWork()

        XCTAssertTrue(manager.hasVersions(for: note), "the history moved with the note")
        let stale = Note(url: oldURL, with: project)
        XCTAssertFalse(manager.hasVersions(for: stale), "nothing is left under the old path")
        manager.removeVersions(for: note)
        manager.waitForPendingWork()
    }

    /// Deleting files the history under the Trash path; undoing the delete
    /// must bring it back, or the restored note shows none.
    @MainActor
    func testUndoingADeleteBringsTheHistoryBack() throws {
        let original = tempDir.appendingPathComponent("kept-\(UUID().uuidString).md")
        let trashed = tempDir.appendingPathComponent("trashed-\(UUID().uuidString).md")
        try "draft".write(to: trashed, atomically: true, encoding: .utf8)
        let project = Project(url: tempDir, label: "test", isRoot: true)
        let inTrash = Note(url: trashed, with: project)
        inTrash.load()
        let manager = NoteVersionManager.shared
        manager.saveVersionIfNeeded(for: inTrash, force: true)
        manager.waitForPendingWork()
        XCTAssertTrue(manager.hasVersions(for: inTrash))

        let table = NotesTableView(frame: .zero)
        table.storage = Storage(loadsLibrary: false)
        table.unDelete([trashed: original])
        manager.waitForPendingWork()

        let restored = Note(url: original, with: project)
        XCTAssertTrue(manager.hasVersions(for: restored), "the history came back with the note")
        XCTAssertFalse(manager.hasVersions(for: inTrash), "nothing is left under the Trash path")
        manager.removeVersions(for: restored)
        manager.waitForPendingWork()
    }

    @MainActor
    func testMissingFileIsNotAFailedLoad() {
        let url = tempDir.appendingPathComponent("not-yet-written.md")
        let project = Project(url: tempDir, label: "test", isRoot: true)
        let note = Note(url: url, with: project)
        note.load()
        XCTAssertFalse(note.loadFailed, "a note whose file does not exist yet must stay writable")
    }

    @MainActor
    func testExternallyRemovedNoteCannotBeRecreatedByPendingSave() async throws {
        let url = tempDir.appendingPathComponent("externally-removed.md")
        try "original".write(to: url, atomically: true, encoding: .utf8)

        let project = Project(url: tempDir, label: "test", isRoot: true)
        let storage = Storage()
        let note = Note(url: url, with: project)
        note.sharedStorage = storage
        storage.add(note)

        note.save(attributed: NSAttributedString(string: "pending edit"))
        try FileManager.default.removeItem(at: url)
        storage.removeNotes(notes: [note], fsRemove: false) { _ in }

        let debounceFinished = expectation(description: "debounced save window elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            debounceFinished.fulfill()
        }
        await fulfillment(of: [debounceFinished], timeout: 2.5)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "a pending save must not recreate a note after the watcher removed it")
        XCTAssertFalse(
            storage.noteList.contains(where: { $0 === note }),
            "a retired note must not add itself back to Storage")
    }

    @MainActor
    func testAtomicSwapRefusesMissingDestination() throws {
        let noteURL = tempDir.appendingPathComponent("missing-during-save.md")
        let replacementURL = tempDir.appendingPathComponent("replacement.md")
        try "original".write(to: noteURL, atomically: true, encoding: .utf8)
        try "replacement".write(to: replacementURL, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: noteURL)

        XCTAssertThrowsError(
            try Note.swapExistingFile(at: noteURL, with: replacementURL)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: noteURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacementURL.path))
    }

    @MainActor
    func testMissingLoadedNoteCannotBeRecreatedBeforeWatcherRetiresIt() async throws {
        let url = tempDir.appendingPathComponent("missing-before-watcher.md")
        let quarantineURL = tempDir.appendingPathComponent("quarantined.md")
        try "original".write(to: url, atomically: true, encoding: .utf8)

        let project = Project(url: tempDir, label: "test", isRoot: true)
        let note = Note(url: url, with: project)
        note.save(attributed: NSAttributedString(string: "pending edit"))
        try FileManager.default.moveItem(at: url, to: quarantineURL)

        let debounceFinished = expectation(description: "debounced save window elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            debounceFinished.fulfill()
        }
        await fulfillment(of: [debounceFinished], timeout: 2.5)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "a save sink must fail closed while the watcher is still processing a missing file")
        XCTAssertTrue(note.needsSave, "the unsaved edit remains retryable if the file returns")
        XCTAssertFalse(note.flushPendingSave(globalStorage: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testTrashReconciliationRetiresAFileMissingFromDisk() throws {
        let url = tempDir.appendingPathComponent("missing-trash-note.md")
        let quarantineURL = tempDir.appendingPathComponent("quarantined-trash-note.md")
        try "trash content".write(to: url, atomically: true, encoding: .utf8)

        let project = Project(url: tempDir, label: "Trash", isTrash: true)
        let storage = Storage()
        let note = Note(url: url, with: project)
        note.sharedStorage = storage
        storage.add(note)
        try FileManager.default.moveItem(at: url, to: quarantineURL)

        storage.retireMissingNotes(in: project)

        XCTAssertFalse(storage.noteList.contains(where: { $0 === note }))
        note.save(attributed: NSAttributedString(string: "late editor callback"))
        XCTAssertFalse(note.flushPendingSave(globalStorage: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testRemovedTrashMarkerIsHiddenOnlyWhileInsideTrash() throws {
        let url = tempDir.appendingPathComponent("recoverable-system-trash-note.md")
        try "recoverable content".write(to: url, atomically: true, encoding: .utf8)

        let trashProject = Project(url: tempDir, label: "Trash", isTrash: true)
        let regularProject = Project(url: tempDir, label: "Restored")

        XCTAssertFalse(Storage.shouldHideRemovedTrashItem(at: url, in: trashProject))
        try url.setExtendedAttribute(
            data: Data([1]),
            forName: AppIdentifier.removedFromTrashKey)

        XCTAssertTrue(Storage.shouldHideRemovedTrashItem(at: url, in: trashProject))
        XCTAssertFalse(
            Storage.shouldHideRemovedTrashItem(at: url, in: regularProject),
            "Finder recovery into a normal project must make the note visible again")

        let storage = Storage()
        _ = storage.add(project: trashProject)
        XCTAssertNil(
            storage.initNote(url: url),
            "the file watcher must not re-import a marked system Trash item")
        let note = Note(url: url, with: trashProject)
        note.sharedStorage = storage
        storage.add(note)
        storage.retireMissingNotes(in: trashProject)

        XCTAssertFalse(storage.noteList.contains(where: { $0 === note }))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path),
            "hiding from MiaoYan Trash must preserve Finder recoverability")
        note.save(attributed: NSAttributedString(string: "late callback"))
        XCTAssertFalse(note.flushPendingSave(globalStorage: false))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "recoverable content")
    }

    @MainActor
    func testExplicitRemovalFlushesLatestContentAndRejectsLateSave() throws {
        let sourceURL = tempDir.appendingPathComponent("to-delete.md")
        let trashURL = tempDir.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashURL, withIntermediateDirectories: true)
        try "original".write(to: sourceURL, atomically: true, encoding: .utf8)

        let storage = Storage()
        if let existingTrash = storage.getDefaultTrash() {
            storage.removeBy(project: existingTrash)
        }
        _ = storage.add(project: Project(url: trashURL, isTrash: true))

        let previousStorage = Storage.instance
        Storage.instance = storage
        defer { Storage.instance = previousStorage }

        let project = Project(url: tempDir, label: "test", isRoot: true)
        let note = Note(url: sourceURL, with: project)
        note.sharedStorage = storage
        storage.add(note)
        note.save(attributed: NSAttributedString(string: "latest edit"))

        var removedURLs: [URL: URL]?
        var removedNotes = [Note]()
        storage.removeNotes(
            notes: [note],
            didRemove: { removedNotes = $0 }
        ) { removedURLs = $0 }

        let movedURL = try XCTUnwrap(removedURLs?.keys.first)
        XCTAssertEqual(removedNotes.count, 1)
        XCTAssertTrue(removedNotes.first === note)
        XCTAssertEqual(try String(contentsOf: movedURL, encoding: .utf8), "latest edit")
        XCTAssertFalse(note.hasPendingSave)
        XCTAssertFalse(storage.noteList.contains(where: { $0 === note }))

        note.save(attributed: NSAttributedString(string: "late callback"))
        note.flushPendingSave(globalStorage: false)

        XCTAssertEqual(
            try String(contentsOf: movedURL, encoding: .utf8),
            "latest edit",
            "callbacks holding the removed Note must not mutate its Trash copy")
    }

    @MainActor
    func testFailedRemovalKeepsTheNoteWritable() throws {
        let sourceURL = tempDir.appendingPathComponent("failed-delete.md")
        try "original".write(to: sourceURL, atomically: true, encoding: .utf8)

        let storage = Storage()
        if let existingTrash = storage.getDefaultTrash() {
            storage.removeBy(project: existingTrash)
        }
        let missingTrashURL = tempDir.appendingPathComponent("missing/Trash", isDirectory: true)
        _ = storage.add(project: Project(url: missingTrashURL, isTrash: true))

        let previousStorage = Storage.instance
        Storage.instance = storage
        defer { Storage.instance = previousStorage }

        let project = Project(url: tempDir, label: "test", isRoot: true)
        let note = Note(url: sourceURL, with: project)
        note.sharedStorage = storage
        storage.add(note)
        note.save(attributed: NSAttributedString(string: "latest before failure"))

        var failedCount = 0
        var removedNotes = [Note]()
        storage.removeNotes(
            notes: [note],
            partialFailure: { failedCount = $0 },
            didRemove: { removedNotes = $0 }
        ) { _ in }

        XCTAssertEqual(failedCount, 1)
        XCTAssertTrue(removedNotes.isEmpty)
        XCTAssertTrue(storage.noteList.contains(where: { $0 === note }))
        XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), "latest before failure")

        note.save(attributed: NSAttributedString(string: "edit after failure"))
        note.flushPendingSave(globalStorage: false)
        XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), "edit after failure")
    }

    @MainActor
    func testCaseOnlyRenameKeepsTheNewNameAndOtherNotesBlockRenames() throws {
        let project = Project(url: tempDir, label: "test", isRoot: true)
        let url = tempDir.appendingPathComponent("weekly.md")
        try "body".write(to: url, atomically: true, encoding: .utf8)
        try "other".write(to: tempDir.appendingPathComponent("Other.md"), atomically: true, encoding: .utf8)
        let note = Note(url: url, with: project)

        XCTAssertTrue(note.renameFile(to: "Weekly"))
        let names = try FileManager.default.contentsOfDirectory(atPath: tempDir.path).sorted()
        XCTAssertEqual(names, ["Other.md", "Weekly.md"], "a case-only rename must not fall back to a unique name")
        XCTAssertEqual(note.url.lastPathComponent, "Weekly.md")

        XCTAssertFalse(note.renameFile(to: "Other"), "an existing note is never renamed over")
        XCTAssertEqual(try String(contentsOf: tempDir.appendingPathComponent("Other.md"), encoding: .utf8), "other")
    }

    /// A title of spaces trimmed to an empty file name, which resolved to the
    /// folder's own path plus `.md` and moved the note out of its folder.
    @MainActor
    func testATitleOfSpacesLeavesTheNoteWhereItIs() throws {
        let folder = tempDir.appendingPathComponent("Work")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Plan.md")
        try "body".write(to: url, atomically: true, encoding: .utf8)
        let note = Note(url: url, with: Project(url: folder, label: "Work"))

        XCTAssertFalse(note.renameFile(to: "   "))
        XCTAssertEqual(note.url.lastPathComponent, "Plan.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("Work.md").path))
    }

    /// Backlinks were rebuilt only at launch: a renamed note kept listing its
    /// links under the old title, a removed one kept appearing as a backlink,
    /// and a body changed by another device never reached the index.
    @MainActor
    func testBacklinksFollowRenameRemovalAndDiskReloads() throws {
        let index = WikilinkIndex.shared
        let project = Project(url: tempDir, label: "test", isRoot: true)
        let url = tempDir.appendingPathComponent("Source.md")
        try "see [[Target]]".write(to: url, atomically: true, encoding: .utf8)
        let note = Note(url: url, with: project)
        note.load()
        XCTAssertEqual(index.getBacklinks(for: "Target"), ["Source"])

        XCTAssertTrue(note.renameFile(to: "Renamed"))
        XCTAssertEqual(index.getBacklinks(for: "Target"), ["Renamed"])

        try "now [[Elsewhere]]".write(to: note.url, atomically: true, encoding: .utf8)
        note.forceReload()
        XCTAssertTrue(index.getBacklinks(for: "Target").isEmpty)
        XCTAssertEqual(index.getBacklinks(for: "Elsewhere"), ["Renamed"])

        note.retireAfterRemoval()
        XCTAssertTrue(index.getBacklinks(for: "Elsewhere").isEmpty)
    }

    /// A note in a folder whose group the user cannot set (wheel, as under
    /// /private/tmp) saved its text and then reported "Save Failed" while
    /// putting the old owner and group back.
    @MainActor
    func testSaveInAWheelGroupFolderSucceedsAndKeepsTheCreationDate() throws {
        let dir = URL(fileURLWithPath: "/private/tmp/MiaoYanWheel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("wheel.md")
        try "old".write(to: url, atomically: false, encoding: .utf8)
        let group = try FileManager.default.attributesOfItem(atPath: url.path)[.groupOwnerAccountName] as? String
        try XCTSkipUnless(group == "wheel", "needs a file whose group is wheel")
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path)

        let project = Project(url: dir, label: "wheel", isRoot: true)
        let note = Note(url: url, with: project)
        note.load()
        note.save(content: NSMutableAttributedString(string: "new"))
        XCTAssertTrue(note.flushPendingSave(globalStorage: false))

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.creationDate] as? Date, created)
    }
}
