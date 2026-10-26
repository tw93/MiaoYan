import XCTest

@testable import MiaoYan

/// Exercises the pure-string ingestion path of `WikilinkIndex.updateNote`,
/// which does not require `Note`/`Storage` bootstrapping. This is what runs
/// during live editing and is the regression surface most worth covering.
@MainActor
final class WikilinkIndexTests: XCTestCase {

    private var index: WikilinkIndex { WikilinkIndex.shared }

    // XCTestCase's setUp/tearDown across Swift 6.1's strict concurrency
    // are awkward: the sync variants are nonisolated (can't touch the
    // @MainActor index), and `super.setUp()` in the async variants flags
    // XCTestCase as non-Sendable. Sidestep both by cleaning the shared
    // index inline at the start of each test instead.
    private func resetIndex() {
        for title in ["A", "B", "C", "D"] {
            // removeNote on a non-existent title is a no-op, so this is
            // safe even on a fresh index.
            index.removeNote(title: title)
        }
    }

    func testUpdateNoteRecordsOutlinks() {
        resetIndex()
        index.updateNote(title: "A", content: "see [[B]] and [[C]]")

        XCTAssertEqual(Set(index.getOutlinks(for: "A")), Set(["B", "C"]))
    }

    func testBacklinksReverseUpdateNote() {
        resetIndex()
        index.updateNote(title: "A", content: "links to [[B]]")
        index.updateNote(title: "C", content: "also links to [[B]]")

        XCTAssertEqual(Set(index.getBacklinks(for: "B")), Set(["A", "C"]))
    }

    func testUpdateNoteReplacesPreviousOutlinks() {
        resetIndex()
        index.updateNote(title: "A", content: "[[B]]")
        index.updateNote(title: "A", content: "[[C]]")

        XCTAssertEqual(index.getOutlinks(for: "A"), ["C"])
        XCTAssertTrue(index.getBacklinks(for: "B").isEmpty, "stale backlink to B should be cleared")
        XCTAssertEqual(index.getBacklinks(for: "C"), ["A"])
    }

    func testRemoveNoteClearsBothDirections() {
        resetIndex()
        index.updateNote(title: "A", content: "[[B]]")
        index.removeNote(title: "A")

        XCTAssertTrue(index.getOutlinks(for: "A").isEmpty)
        XCTAssertTrue(index.getBacklinks(for: "B").isEmpty)
    }

    func testWhitespaceInsideBracketsIsTrimmed() {
        resetIndex()
        index.updateNote(title: "A", content: "[[  B  ]]")

        XCTAssertEqual(index.getOutlinks(for: "A"), ["B"])
    }

    func testEmptyContentYieldsNoLinks() {
        resetIndex()
        index.updateNote(title: "A", content: "no wikilinks here")

        XCTAssertTrue(index.getOutlinks(for: "A").isEmpty)
    }

    func testMultipleOccurrencesOfSameLinkAreDeduped() {
        resetIndex()
        index.updateNote(title: "A", content: "[[B]] then [[B]] then [[B]]")

        XCTAssertEqual(index.getOutlinks(for: "A"), ["B"])
    }

    /// Show Info read backlinks from the listed notes' loaded text, which is
    /// empty for every note not opened yet. The rebuild reads them from disk.
    func testBacklinksComeFromNotesThatWereNeverOpened() async throws {
        resetIndex()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanLinks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "See [[B]] for details.".write(to: dir.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
        let storage = Storage(loadsLibrary: false)
        let project = Project(url: dir, label: "links")
        let note = Note(url: dir.appendingPathComponent("A.md"), with: project)
        note.title = "A"
        storage.add(note)
        XCTAssertFalse(note.isContentLoaded)

        index.rebuildFromAllNotes(in: storage)
        for _ in 0..<100 where index.getBacklinks(for: "B").isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(index.getBacklinks(for: "B"), ["A"])
        resetIndex()
    }

    /// Storage lists only the root's and first-level folders' notes until a
    /// deeper folder is opened, so backlinks from deeper notes were missing.
    /// Trash and attachment folders still do not count.
    func testBacklinksComeFromNotesAtAnyDepth() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanDeepLinks-\(UUID().uuidString)")
        let manager = FileManager.default
        defer { try? manager.removeItem(at: base) }
        let deep = base.appendingPathComponent("Work/2024/Q1", isDirectory: true)
        let trash = base.appendingPathComponent("Trash", isDirectory: true)
        let images = base.appendingPathComponent("Work/i", isDirectory: true)
        for dir in [deep, trash, images] {
            try manager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try "# Root".write(to: base.appendingPathComponent("Root.md"), atomically: true, encoding: .utf8)
        try "Back to [[Root]].".write(to: deep.appendingPathComponent("Deep.md"), atomically: true, encoding: .utf8)
        try "Old [[Root]] link.".write(to: trash.appendingPathComponent("Deleted.md"), atomically: true, encoding: .utf8)
        try "Stray [[Root]] link.".write(to: images.appendingPathComponent("Stray.md"), atomically: true, encoding: .utf8)

        let storage = Storage(loadsLibrary: false)
        let root = Project(url: base, isRoot: true)
        _ = storage.add(project: root)
        _ = storage.add(project: Project(url: trash, isTrash: true))
        let rootNote = Note(url: base.appendingPathComponent("Root.md"), with: root)
        rootNote.title = "Root"
        storage.add(rootNote)

        index.rebuildFromAllNotes(in: storage)
        for _ in 0..<100 where index.getBacklinks(for: "Root").isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(index.getBacklinks(for: "Root"), ["Deep"])
        index.rebuild(entries: [])
    }

    /// The editor gives `[[`, the title and `]]` different fonts and colours,
    /// so the link is three attribute runs; the preview showed the title once
    /// per run until the whole link was read as one.
    func testPreviewConvertsAHighlightedWikilinkOnce() {
        let content = NSMutableAttributedString(string: "See [[Welcome]].")
        content.addAttribute(.foregroundColor, value: NSColor.gray, range: NSRange(location: 4, length: 2))
        content.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: NSRange(location: 6, length: 7))
        content.addAttribute(.foregroundColor, value: NSColor.gray, range: NSRange(location: 13, length: 2))
        content.addAttribute(.link, value: "miaoyan://goto/Welcome", range: NSRange(location: 6, length: 7))

        let converted = NotesTextProcessor.convertAppLinks(in: content).string

        XCTAssertEqual(converted, "See [Welcome](miaoyan://goto/Welcome).")
    }
}
