import XCTest

@testable import MiaoYan

/// Clean Unused Attachments scans the `i/` folder of every registered folder,
/// and the sidebar registers subfolders before their notes are loaded. Images
/// those unloaded notes reference must never be reported as unused.
final class AttachmentCleanupTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiaoYanAttachmentTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    @MainActor
    func testImagesOfNotesInUnopenedSubfoldersAreNotOrphans() async throws {
        let manager = FileManager.default
        let year = tempDir.appendingPathComponent("Work/2024", isDirectory: true)
        let images = year.appendingPathComponent("i", isDirectory: true)
        try manager.createDirectory(at: images, withIntermediateDirectories: true)
        try "# Plan\n\n![](/i/used.png)\n".write(to: year.appendingPathComponent("plan.MD"), atomically: true, encoding: .utf8)
        try Data([0x89]).write(to: images.appendingPathComponent("used.png"))
        try Data([0x89]).write(to: images.appendingPathComponent("unused.png"))

        let storage = Storage(loadsLibrary: false)
        let root = Project(url: tempDir, label: "root")
        _ = storage.add(project: root)
        // What the sidebar does while drawing expandable rows: folders get
        // registered, their notes stay unloaded.
        for work in storage.subfolders(of: root) {
            _ = storage.subfolders(of: work)
        }

        let done = expectation(description: "orphan scan")
        var result: [URL]?
        storage.findOrphanAttachments { urls in
            result = urls
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 10)

        let names = Set((result ?? []).map(\.lastPathComponent))
        XCTAssertNotNil(result)
        XCTAssertFalse(names.contains("used.png"), "an image a note references is not unused, loaded or not")
        XCTAssertTrue(names.contains("unused.png"), "an image nothing references is still found")
    }

    // MARK: - Which folders are listed

    /// `assets` is hidden as an image folder, but a folder of notes that
    /// happens to carry the name must still be listed.
    @MainActor
    func testAssetsFolderIsListedOnlyWhenItHoldsNotes() throws {
        let manager = FileManager.default
        let notes = tempDir.appendingPathComponent("Notes/assets", isDirectory: true)
        let media = tempDir.appendingPathComponent("Site/assets/img", isDirectory: true)
        try manager.createDirectory(at: notes, withIntermediateDirectories: true)
        try manager.createDirectory(at: media, withIntermediateDirectories: true)
        try "# Idea\n".write(to: notes.appendingPathComponent("idea.md"), atomically: true, encoding: .utf8)
        try Data([0x89]).write(to: media.appendingPathComponent("logo.png"))

        let storage = Storage(loadsLibrary: false)
        let root = Project(url: tempDir, label: "root")
        _ = storage.add(project: root)
        let folders = storage.subfolders(of: root)
        let notesFolder = try XCTUnwrap(folders.first { $0.label == "Notes" })
        let siteFolder = try XCTUnwrap(folders.first { $0.label == "Site" })

        XCTAssertEqual(storage.subfolders(of: notesFolder).map(\.label), ["assets"], "a folder of notes named assets is listed")
        XCTAssertTrue(storage.subfolders(of: siteFolder).isEmpty, "an assets folder of images stays hidden")
        XCTAssertEqual(storage.getSubFolders(url: notesFolder.url)?.map { $0.lastPathComponent }, ["assets"])
        XCTAssertEqual(storage.getSubFolders(url: siteFolder.url)?.count, 0)
    }

    // MARK: - Moving a note carries its images

    private struct Folders {
        let from: Project
        let to: Project
        let noteURL: URL
    }

    @MainActor
    private func makeFolders() throws -> Folders {
        let manager = FileManager.default
        let from = tempDir.appendingPathComponent("From", isDirectory: true)
        let to = tempDir.appendingPathComponent("To", isDirectory: true)
        try manager.createDirectory(at: from.appendingPathComponent("i"), withIntermediateDirectories: true)
        try manager.createDirectory(at: to, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: from.appendingPathComponent("i/Shot 1.png"))
        let noteURL = from.appendingPathComponent("trip.md")
        try "# Trip\n\n![](/i/Shot%201.png)\n".write(to: noteURL, atomically: true, encoding: .utf8)
        return Folders(from: Project(url: from, label: "From"), to: Project(url: to, label: "To"), noteURL: noteURL)
    }

    @MainActor
    func testMovingAnUnopenedNoteCopiesItsImagesUnderTheirOwnNames() throws {
        let folders = try makeFolders()
        let (from, to) = (folders.from, folders.to)
        let note = Note(url: folders.noteURL, with: from)
        XCTAssertFalse(note.isContentLoaded, "the note was never opened")

        note.move(toProject: to)

        let moved = to.url.appendingPathComponent("i/Shot 1.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path), "the image travels with the note, name unchanged")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: from.url.appendingPathComponent("i/Shot 1.png").path),
            "the original stays for any other note that shares it")
        let text = try String(contentsOf: to.url.appendingPathComponent("trip.md"), encoding: .utf8)
        XCTAssertTrue(text.contains("](/i/Shot%201.png)"), "the link still points at the copy")
    }

    @MainActor
    func testAClashingImageNameGetsANewNameAndTheLinkFollows() throws {
        let folders = try makeFolders()
        let (from, to, noteURL) = (folders.from, folders.to, folders.noteURL)
        try FileManager.default.createDirectory(at: to.url.appendingPathComponent("i"), withIntermediateDirectories: true)
        try Data([9, 9]).write(to: to.url.appendingPathComponent("i/Shot 1.png"))
        let note = Note(url: noteURL, with: from)

        note.move(toProject: to)

        let text = try String(contentsOf: to.url.appendingPathComponent("trip.md"), encoding: .utf8)
        XCTAssertFalse(text.contains("](/i/Shot%201.png)"), "the clashing file in the destination is not the note's image")
        let link = try XCTUnwrap(text.range(of: #"\]\((/i/[^)]+)\)"#, options: .regularExpression)).lowerBound
        let path = String(text[link...].dropFirst(2).prefix { $0 != ")" }).removingPercentEncoding ?? ""
        let copied = to.url.appendingPathComponent(path)
        XCTAssertEqual(try Data(contentsOf: copied), Data([1, 2, 3]), "the renamed copy holds the note's own image")
    }
}
