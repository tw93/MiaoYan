import MiaoYanCore
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
        storage.findOrphanAttachments(changedBefore: .distantFuture) { urls in
            result = urls
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 10)

        let names = Set((result ?? []).map(\.lastPathComponent))
        XCTAssertNotNil(result)
        XCTAssertFalse(names.contains("used.png"), "an image a note references is not unused, loaded or not")
        XCTAssertTrue(names.contains("unused.png"), "an image nothing references is still found")
    }

    /// A subfolder note reaching its parent's `i/` and `files/` through `../`
    /// resolved outside its own folder, so those files were called unused and
    /// moved to the Trash. Paths are bounded by the library instead.
    @MainActor
    func testParentFolderAttachmentsReachedWithDotDotAreNotOrphans() async throws {
        let manager = FileManager.default
        let library = tempDir.appendingPathComponent("Library", isDirectory: true)
        let sub = library.appendingPathComponent("Sub", isDirectory: true)
        for folder in ["i", "files", "Sub/i"] {
            try manager.createDirectory(at: library.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for file in ["i/x.png", "i/y.png", "files/a.pdf", "i/unused.png", "Sub/i/own.png"] {
            try Data([0x89]).write(to: library.appendingPathComponent(file))
        }
        let body = "# Sub\n\n<img src=\"../i/x.png\">\n\n[a](../files/a.pdf)\n\n![](../i/y.png)\n\n![](/i/own.png)\n"
        try body.write(to: sub.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)

        let storage = Storage(loadsLibrary: false)
        let root = Project(url: library, label: "root")
        _ = storage.add(project: root)
        let subProject = try XCTUnwrap(storage.subfolders(of: root).first { $0.label == "Sub" })

        let done = expectation(description: "orphan scan")
        var result: [URL]?
        storage.findOrphanAttachments(changedBefore: .distantFuture) { urls in
            result = urls
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 10)

        let orphans = Set((result ?? []).map { $0.resolvingSymlinksInPath().path })
        XCTAssertNotNil(result)
        for used in ["i/x.png", "i/y.png", "files/a.pdf", "Sub/i/own.png"] {
            XCTAssertFalse(orphans.contains(library.appendingPathComponent(used).path), "\(used) is referenced from Sub/note.md")
        }
        XCTAssertTrue(orphans.contains(library.appendingPathComponent("i/unused.png").path), "an unreferenced file is still found")

        let note = Note(url: subProject.url.appendingPathComponent("note.md"), with: subProject)
        XCTAssertEqual(
            note.getReferencedAttachmentPaths(in: "<img src=\"../i/x.png\">"), [root.url.appendingPathComponent("i/x.png").path])
        let escaping = note.getReferencedAttachmentPaths(in: "<img src=\"../../i/out.png\">")
        XCTAssertTrue(escaping.isEmpty, "a path leaving the library is not resolved: \(escaping)")
    }

    /// Trash notes are listed only once the Trash is opened, and the scan
    /// skipped the Trash folder, so an image only a trashed note used was
    /// cleaned and the note came back from the Trash without it.
    @MainActor
    func testImagesOfUnopenedTrashNotesAreKept() async throws {
        let manager = FileManager.default
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        let trash = tempDir.appendingPathComponent(".Trash", isDirectory: true)
        try manager.createDirectory(at: work.appendingPathComponent("i"), withIntermediateDirectories: true)
        try manager.createDirectory(at: trash, withIntermediateDirectories: true)
        try "# Kept\n".write(to: work.appendingPathComponent("kept.md"), atomically: true, encoding: .utf8)
        try "# Old\n\n![](/i/old.png)\n".write(to: trash.appendingPathComponent("old.md"), atomically: true, encoding: .utf8)
        try Data([0x89]).write(to: work.appendingPathComponent("i/old.png"))
        try Data([0x89]).write(to: work.appendingPathComponent("i/unused.png"))

        let storage = Storage(loadsLibrary: false)
        let root = Project(url: tempDir, label: "root")
        _ = storage.add(project: root)
        _ = storage.add(project: Project(url: trash, isTrash: true))
        _ = storage.subfolders(of: root)
        XCTAssertTrue(storage.getAllTrash().isEmpty, "the Trash has not been opened")

        let done = expectation(description: "orphan scan")
        var result: [URL]?
        storage.findOrphanAttachments(changedBefore: .distantFuture) { urls in
            result = urls
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 10)

        let names = Set((result ?? []).map(\.lastPathComponent))
        XCTAssertFalse(names.contains("old.png"), "a trashed note can still be restored with its image")
        XCTAssertTrue(names.contains("unused.png"))
    }

    /// Only notes directly inside a folder with an `i/` were counted, so a
    /// note one folder down reaching that `i/` with `../`, in a folder with
    /// no `i/` of its own and not opened this run, lost its image.
    @MainActor
    func testANoteInASubfolderWithoutItsOwnImagesKeepsItsParentsImage() async throws {
        let manager = FileManager.default
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        try manager.createDirectory(at: work.appendingPathComponent("i"), withIntermediateDirectories: true)
        try manager.createDirectory(at: work.appendingPathComponent("2026"), withIntermediateDirectories: true)
        try "# Q1\n\n![](../i/chart.png)\n".write(to: work.appendingPathComponent("2026/Q1.md"), atomically: true, encoding: .utf8)
        try Data([0x89]).write(to: work.appendingPathComponent("i/chart.png"))
        try Data([0x89]).write(to: work.appendingPathComponent("i/unused.png"))

        let storage = Storage(loadsLibrary: false)
        let root = Project(url: tempDir, label: "root")
        _ = storage.add(project: root)
        for folder in storage.subfolders(of: root) {
            _ = storage.subfolders(of: folder)
        }

        let result = await orphans(in: storage)

        let names = Set((result ?? []).map(\.lastPathComponent))
        XCTAssertNotNil(result)
        XCTAssertFalse(names.contains("chart.png"), "Work/2026/Q1.md uses it through ../i/")
        XCTAssertTrue(names.contains("unused.png"), "an image nothing references is still found")
    }

    /// The walk below a folder follows symlinked folders, each directory
    /// once, so a link back up the tree ends the walk instead of looping.
    @MainActor
    func testALinkBackUpTheTreeIsWalkedOnce() async throws {
        let manager = FileManager.default
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        let year = work.appendingPathComponent("2026", isDirectory: true)
        try manager.createDirectory(at: work.appendingPathComponent("i"), withIntermediateDirectories: true)
        try manager.createDirectory(at: year, withIntermediateDirectories: true)
        try manager.createSymbolicLink(at: year.appendingPathComponent("back"), withDestinationURL: work)
        try "# Q1\n\n![](../i/chart.png)\n".write(to: year.appendingPathComponent("Q1.md"), atomically: true, encoding: .utf8)
        try Data([0x89]).write(to: work.appendingPathComponent("i/chart.png"))
        try Data([0x89]).write(to: work.appendingPathComponent("i/unused.png"))

        let storage = Storage(loadsLibrary: false)
        _ = storage.add(project: Project(url: work, label: "Work"))

        let result = await orphans(in: storage)

        let names = Set((result ?? []).map(\.lastPathComponent))
        XCTAssertNotNil(result)
        XCTAssertFalse(names.contains("chart.png"))
        XCTAssertTrue(names.contains("unused.png"))
    }

    /// A folder below one whose images are scanned that cannot be listed
    /// hides its notes, so nothing is reported, as for an unreadable note.
    @MainActor
    func testAFolderThatCannotBeListedReportsNothing() async throws {
        let manager = FileManager.default
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        let locked = work.appendingPathComponent("Locked", isDirectory: true)
        try manager.createDirectory(at: work.appendingPathComponent("i"), withIntermediateDirectories: true)
        try manager.createDirectory(at: locked, withIntermediateDirectories: true)
        try "# Hidden\n\n![](../i/used.png)\n".write(to: locked.appendingPathComponent("hidden.md"), atomically: true, encoding: .utf8)
        try Data([0x89]).write(to: work.appendingPathComponent("i/used.png"))
        try manager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let storage = Storage(loadsLibrary: false)
        _ = storage.add(project: Project(url: work, label: "Work"))

        let result = await orphans(in: storage)
        XCTAssertNil(result, "the notes in Locked could not be counted")
    }

    /// A note iCloud keeps only online (`.Q2.md.icloud`) cannot be read, so
    /// the images it may use are not offered for cleaning.
    @MainActor
    func testANoteKeptOnlyInICloudReportsNothing() async throws {
        let manager = FileManager.default
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        try manager.createDirectory(at: work.appendingPathComponent("i"), withIntermediateDirectories: true)
        try manager.createDirectory(at: work.appendingPathComponent("2026"), withIntermediateDirectories: true)
        try Data([0x62, 0x70]).write(to: work.appendingPathComponent("2026/.Q2.md.icloud"))
        try Data([0x89]).write(to: work.appendingPathComponent("i/chart.png"))

        let storage = Storage(loadsLibrary: false)
        _ = storage.add(project: Project(url: work, label: "Work"))

        let result = await orphans(in: storage)
        XCTAssertNil(result, "Q2.md may use chart.png and cannot be read")
    }

    /// A linked folder whose target is gone (an unmounted drive) hides its
    /// notes, so nothing is reported; a broken link to an image is no folder
    /// and does not stop the scan.
    @MainActor
    func testABrokenFolderLinkReportsNothingAndABrokenImageLinkDoesNot() async throws {
        let manager = FileManager.default
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        try manager.createDirectory(at: work.appendingPathComponent("i"), withIntermediateDirectories: true)
        try Data([0x89]).write(to: work.appendingPathComponent("i/unused.png"))
        try manager.createSymbolicLink(
            at: work.appendingPathComponent("old.png"), withDestinationURL: tempDir.appendingPathComponent("gone.png"))

        let storage = Storage(loadsLibrary: false)
        _ = storage.add(project: Project(url: work, label: "Work"))
        let withImageLink = await orphans(in: storage)
        XCTAssertEqual(withImageLink.map { Set($0.map(\.lastPathComponent)) }, ["unused.png"])

        try manager.createSymbolicLink(
            at: work.appendingPathComponent("Archive"), withDestinationURL: tempDir.appendingPathComponent("Volumes/Ext/Archive"))
        let withFolderLink = await orphans(in: storage)
        XCTAssertNil(withFolderLink, "the notes behind Archive could not be counted")
    }

    /// Only folders with an `i/` of their own, and the folders below them,
    /// had their notes read. A note in a folder never opened, with no `i/`
    /// anywhere above it, pointing at another folder's image with `../`,
    /// went unread, and that image was offered for the Trash (2026-11-22).
    @MainActor
    func testANoteUnderFoldersWithNoImagesKeepsAnotherFoldersImage() async throws {
        let manager = FileManager.default
        let library = tempDir.appendingPathComponent("Lib", isDirectory: true)
        try manager.createDirectory(at: library.appendingPathComponent("A/B"), withIntermediateDirectories: true)
        try manager.createDirectory(at: library.appendingPathComponent("Other/i"), withIntermediateDirectories: true)
        try "# B\n\n![](../../Other/i/x.png)\n".write(to: library.appendingPathComponent("A/B/n.md"), atomically: true, encoding: .utf8)
        try Data([0x89]).write(to: library.appendingPathComponent("Other/i/x.png"))
        try Data([0x89]).write(to: library.appendingPathComponent("Other/i/unused.png"))

        let storage = Storage(loadsLibrary: false)
        let root = Project(url: library, label: "root")
        _ = storage.add(project: root)
        // A and Other are registered, B is never opened.
        _ = storage.subfolders(of: root)

        let names = await orphans(in: storage).map { Set($0.map(\.lastPathComponent)) }
        XCTAssertEqual(names, ["unused.png"], "A/B/n.md uses x.png")
    }

    /// The Trash was read one level deep, skipping hidden files and any
    /// folder it could not list, so a trashed folder's note lost its image
    /// and an iCloud-only note there counted for nothing (2026-11-22).
    @MainActor
    func testTheTrashIsReadToTheBottomAndAnICloudNoteThereReportsNothing() async throws {
        let manager = FileManager.default
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        let trash = tempDir.appendingPathComponent(".Trash", isDirectory: true)
        try manager.createDirectory(at: work.appendingPathComponent("i"), withIntermediateDirectories: true)
        try manager.createDirectory(at: trash.appendingPathComponent("Trip"), withIntermediateDirectories: true)
        try "# Old\n\n![](/i/old.png)\n".write(to: trash.appendingPathComponent("Trip/old.md"), atomically: true, encoding: .utf8)
        try Data([0x89]).write(to: work.appendingPathComponent("i/old.png"))
        try Data([0x89]).write(to: work.appendingPathComponent("i/unused.png"))

        let storage = Storage(loadsLibrary: false)
        let root = Project(url: tempDir, label: "root")
        _ = storage.add(project: root)
        _ = storage.add(project: Project(url: trash, isTrash: true))
        _ = storage.subfolders(of: root)

        let names = await orphans(in: storage).map { Set($0.map(\.lastPathComponent)) }
        XCTAssertEqual(names, ["unused.png"], "the note in the trashed Trip folder can come back with old.png")

        try Data([0x62, 0x70]).write(to: trash.appendingPathComponent(".Q3.md.icloud"))
        let withPlaceholder = await orphans(in: storage)
        XCTAssertNil(withPlaceholder, "Q3.md in the Trash may use unused.png and cannot be read")
    }

    /// The library's Trash is registered before the first delete makes it,
    /// and a library with no `i/` or `files/` has nothing to clean: neither
    /// may turn the scan into "some notes could not be read" (2026-11-22).
    @MainActor
    func testAMissingTrashAndALibraryWithoutAttachmentsReportNoFailure() async throws {
        let manager = FileManager.default
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        try manager.createDirectory(at: work.appendingPathComponent("2026"), withIntermediateDirectories: true)
        try "# Kept\n".write(to: work.appendingPathComponent("kept.md"), atomically: true, encoding: .utf8)
        try Data([0x62, 0x70]).write(to: work.appendingPathComponent("2026/.Q2.md.icloud"))

        let storage = Storage(loadsLibrary: false)
        _ = storage.add(project: Project(url: work, label: "Work"))
        _ = storage.add(project: Project(url: tempDir.appendingPathComponent(".Trash", isDirectory: true), isTrash: true))
        let withoutAttachments = await orphans(in: storage)
        XCTAssertEqual(withoutAttachments, [], "no i/ anywhere: nothing to clean, nothing to read")

        try manager.removeItem(at: work.appendingPathComponent("2026/.Q2.md.icloud"))
        try manager.createDirectory(at: work.appendingPathComponent("i"), withIntermediateDirectories: true)
        try Data([0x89]).write(to: work.appendingPathComponent("i/unused.png"))
        let withMissingTrash = await orphans(in: storage)
        XCTAssertEqual(withMissingTrash.map { Set($0.map(\.lastPathComponent)) }, ["unused.png"], "a Trash not made yet holds no notes")
    }

    /// A file is offered only once it is a day old: an image pasted while
    /// the scan or its confirmation ran, or one that arrived from iCloud
    /// before the note linking it, was offered and trashed (2026-11-22).
    @MainActor
    func testARecentAttachmentIsNotOfferedYet() async throws {
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        try FileManager.default.createDirectory(at: work.appendingPathComponent("i"), withIntermediateDirectories: true)
        try "# Note\n".write(to: work.appendingPathComponent("n.md"), atomically: true, encoding: .utf8)
        let old = work.appendingPathComponent("i/old.png")
        try Data([0x89]).write(to: old)
        let lastWeek = Date().addingTimeInterval(-7 * 86_400)
        try FileManager.default.setAttributes([.creationDate: lastWeek, .modificationDate: lastWeek], ofItemAtPath: old.path)
        try Data([0x89]).write(to: work.appendingPathComponent("i/new.png"))
        let storage = Storage(loadsLibrary: false)
        let root = Project(url: tempDir, label: "root")
        _ = storage.add(project: root)

        _ = storage.subfolders(of: root)
        let found = await orphans(in: storage, changedBefore: Date().addingTimeInterval(-86_400))
        XCTAssertEqual(found.map { Set($0.map(\.lastPathComponent)) }, ["old.png"])
    }

    /// The disk ignores case, so `Photo.PNG` shows `photo.png`, and the link
    /// keeps it in every form a note writes (a review on 2026-11-22 thought
    /// the path compare missed this; it does not).
    @MainActor
    func testALinkThatDiffersOnlyInCaseKeepsItsImage() async throws {
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        try FileManager.default.createDirectory(at: work.appendingPathComponent("i"), withIntermediateDirectories: true)
        try "# Note\n\n![](/i/Photo.PNG)\n\n<img src=\"i/Chart.PNG\"> [plan](files/Plan.PDF)\n".write(to: work.appendingPathComponent("n.md"), atomically: true, encoding: .utf8)
        try Data([0x89]).write(to: work.appendingPathComponent("i/photo.png"))
        try Data([0x89]).write(to: work.appendingPathComponent("i/chart.png"))
        try FileManager.default.createDirectory(at: work.appendingPathComponent("files"), withIntermediateDirectories: true)
        try Data([0x25]).write(to: work.appendingPathComponent("files/plan.pdf"))
        try Data([0x89]).write(to: work.appendingPathComponent("i/unused.png"))
        let storage = Storage(loadsLibrary: false)
        let root = Project(url: tempDir, label: "root")
        _ = storage.add(project: root)

        _ = storage.subfolders(of: root)
        let found = await orphans(in: storage)
        XCTAssertEqual(found.map { Set($0.map(\.lastPathComponent)) }, ["unused.png"])
    }

    /// A trashed note's `../` link resolves outside the Trash, so its file
    /// was not kept by name and the note came back without it.
    @MainActor
    func testATrashedNotesRelativeLinksKeepTheirFiles() async throws {
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        let trash = tempDir.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: work.appendingPathComponent("files"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: work.appendingPathComponent("i"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try "# Kept\n".write(to: work.appendingPathComponent("kept.md"), atomically: true, encoding: .utf8)
        try "# Old\n\n[a](../files/a.pdf) <img src=\"../i/x.png\">\n".write(to: trash.appendingPathComponent("old.md"), atomically: true, encoding: .utf8)
        try Data([0x25]).write(to: work.appendingPathComponent("files/a.pdf"))
        try Data([0x89]).write(to: work.appendingPathComponent("i/x.png"))
        try Data([0x89]).write(to: work.appendingPathComponent("i/unused.png"))
        let storage = Storage(loadsLibrary: false)
        let root = Project(url: tempDir, label: "root")
        _ = storage.add(project: root)
        _ = storage.add(project: Project(url: trash, isTrash: true))

        _ = storage.subfolders(of: root)
        let found = await orphans(in: storage)
        XCTAssertEqual(found.map { Set($0.map(\.lastPathComponent)) }, ["unused.png"])
    }

    /// A `<…>` destination may hold spaces and a quoted `src` value is read
    /// whole, but the links were cut at the space (`i/my`) or kept the
    /// closing `>` (`i/a.png>`), so those images were offered as unused
    /// while the preview still showed them (audit 2026-11-24).
    @MainActor
    func testLinkTargetsWithSpacesOrAngleBracketsKeepTheirFiles() async throws {
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: work.appendingPathComponent("i"), withIntermediateDirectories: true)
        try manager.createDirectory(at: work.appendingPathComponent("files"), withIntermediateDirectories: true)
        let shapes: [(link: String, file: String)] = [
            ("![](<i/my photo.png>)", "i/my photo.png"),
            ("![](<i/a.png>)", "i/a.png"),
            ("![]( <i/padded.png> \"title\")", "i/padded.png"),
            ("<img src=\"i/double quoted.png\">", "i/double quoted.png"),
            ("<img src='i/single quoted.png'>", "i/single quoted.png"),
            ("<img src=i/bare.png>", "i/bare.png"),
            ("[doc](<files/My Doc.pdf>)", "files/My Doc.pdf"),
            ("<a href=\"files/Plan B.pdf\">plan</a>", "files/Plan B.pdf"),
            ("![pic][ref]\n\n[ref]: <i/ref pic.png>", "i/ref pic.png"),
        ]
        let note = Note(url: work.appendingPathComponent("n.md"), with: Project(url: work, label: "Work"))
        for shape in shapes {
            let expected = work.appendingPathComponent(shape.file).path
            XCTAssertTrue(note.getReferencedAttachmentPaths(in: shape.link).contains(expected), "\(shape.link) refers to \(shape.file)")
            try Data([0x89]).write(to: work.appendingPathComponent(shape.file))
        }
        try Data([0x89]).write(to: work.appendingPathComponent("i/unused.png"))
        try ("# Note\n\n" + shapes.map(\.link).joined(separator: "\n\n") + "\n").write(
            to: work.appendingPathComponent("n.md"), atomically: true, encoding: .utf8)
        let storage = Storage(loadsLibrary: false)
        let root = Project(url: tempDir, label: "root")
        _ = storage.add(project: root)

        _ = storage.subfolders(of: root)
        let found = await orphans(in: storage)
        XCTAssertEqual(found.map { Set($0.map(\.lastPathComponent)) }, ["unused.png"])
    }

    /// A query or fragment is not part of the file name: `spec.pdf#page=3`
    /// and `a.png?v=2` named no file, so both were offered as unused.
    @MainActor
    func testALinkWithAQueryOrFragmentKeepsItsFile() async throws {
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: work.appendingPathComponent("i"), withIntermediateDirectories: true)
        try manager.createDirectory(at: work.appendingPathComponent("files"), withIntermediateDirectories: true)
        let shapes: [(link: String, file: String)] = [
            ("[spec](files/spec.pdf#page=3)", "files/spec.pdf"),
            ("<img src=\"i/a.png?v=2\">", "i/a.png"),
            ("![](/i/b.png#center)", "i/b.png"),
            ("![](<i/my c.png?x=1>)", "i/my c.png"),
        ]
        let note = Note(url: work.appendingPathComponent("n.md"), with: Project(url: work, label: "Work"))
        for shape in shapes {
            let expected = work.appendingPathComponent(shape.file).path
            XCTAssertTrue(note.getReferencedAttachmentPaths(in: shape.link).contains(expected), "\(shape.link) refers to \(shape.file)")
            try Data([0x89]).write(to: work.appendingPathComponent(shape.file))
        }
        try Data([0x89]).write(to: work.appendingPathComponent("i/unused.png"))
        try ("# Note\n\n" + shapes.map(\.link).joined(separator: "\n\n") + "\n").write(
            to: work.appendingPathComponent("n.md"), atomically: true, encoding: .utf8)
        let storage = Storage(loadsLibrary: false)
        let root = Project(url: tempDir, label: "root")
        _ = storage.add(project: root)

        _ = storage.subfolders(of: root)
        let found = await orphans(in: storage)
        XCTAssertEqual(found.map { Set($0.map(\.lastPathComponent)) }, ["unused.png"])

        let trash = Project(url: tempDir.appendingPathComponent(".Trash", isDirectory: true), isTrash: true)
        let trashed = Note(url: trash.url.appendingPathComponent("old.md"), with: trash)
        let names = trashed.referencedAttachmentNames(in: "[s](../files/spec.pdf#page=3) <img src=\"../i/a.png?v=2\">")
        XCTAssertTrue(names.isSuperset(of: ["spec.pdf", "a.png"]), "\(names)")
    }

    /// The fallback pattern stops at `(` and `'` and keeps a backslash, so
    /// `files/report(1).pdf` read as `files/report(1`, `files/Tom's.pdf` as
    /// `files/Tom`, and `i/a\_b.png` named no file.
    @MainActor
    func testALinkWithParenthesesAnApostropheOrAnEscapeKeepsItsFile() async throws {
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: work.appendingPathComponent("i"), withIntermediateDirectories: true)
        try manager.createDirectory(at: work.appendingPathComponent("files"), withIntermediateDirectories: true)
        let shapes: [(link: String, file: String)] = [
            ("[r](files/report(1).pdf)", "files/report(1).pdf"),
            ("[q](files/Tom's.pdf)", "files/Tom's.pdf"),
            ("![](i/a\\_b.png)", "i/a_b.png"),
            ("![](/i/shot(2).png \"title\")", "i/shot(2).png"),
            ("[1]: files/ref(2).pdf", "files/ref(2).pdf"),
            ("[2]: files/Ann's.pdf \"title\"", "files/Ann's.pdf"),
            ("<a href=files/Bo's.pdf>b</a>", "files/Bo's.pdf"),
        ]
        let note = Note(url: work.appendingPathComponent("n.md"), with: Project(url: work, label: "Work"))
        for shape in shapes {
            let expected = work.appendingPathComponent(shape.file).path
            XCTAssertTrue(note.getReferencedAttachmentPaths(in: shape.link).contains(expected), "\(shape.link) refers to \(shape.file)")
            try Data([0x89]).write(to: work.appendingPathComponent(shape.file))
        }
        try Data([0x89]).write(to: work.appendingPathComponent("i/unused.png"))
        try ("# Note\n\n" + shapes.map(\.link).joined(separator: "\n\n") + "\n").write(
            to: work.appendingPathComponent("n.md"), atomically: true, encoding: .utf8)
        let storage = Storage(loadsLibrary: false)
        let root = Project(url: tempDir, label: "root")
        _ = storage.add(project: root)

        _ = storage.subfolders(of: root)
        let found = await orphans(in: storage)
        XCTAssertEqual(found.map { Set($0.map(\.lastPathComponent)) }, ["unused.png"])

        let trash = Project(url: tempDir.appendingPathComponent(".Trash", isDirectory: true), isTrash: true)
        let trashed = Note(url: trash.url.appendingPathComponent("old.md"), with: trash)
        let names = trashed.referencedAttachmentNames(in: "[r](../files/report(1).pdf) [q](../files/Tom's.pdf) ![](../i/a\\_b.png)")
        XCTAssertTrue(names.isSuperset(of: ["report(1).pdf", "Tom's.pdf", "a_b.png"]), "\(names)")
    }

    /// A trashed note keeps its files by name; the names came from the same
    /// cut links, so `<../i/my photo.png>` kept a file called `my`.
    @MainActor
    func testATrashedNotesLinkWithASpaceKeepsItsFileByName() {
        let trash = Project(url: tempDir.appendingPathComponent(".Trash", isDirectory: true), isTrash: true)
        let note = Note(url: trash.url.appendingPathComponent("old.md"), with: trash)
        let names = note.referencedAttachmentNames(in: "![](<../i/my photo.png>) <img src=\"../i/our trip.png\">")
        XCTAssertTrue(names.contains("my photo.png"), "\(names)")
        XCTAssertTrue(names.contains("our trip.png"), "\(names)")
    }

    /// iCloud keeps a file it has not downloaded as `.photo.png.icloud`;
    /// the check looked for `photo.png.icloud`, so a pasted image could take
    /// the name of one still arriving.
    @MainActor
    func testAPastedImageDoesNotTakeTheNameOfAFileStillInICloud() throws {
        let images = tempDir.appendingPathComponent("i", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let source = tempDir.appendingPathComponent("photo.png")
        XCTAssertEqual(ImagesProcessor.getFileName(from: source, to: images), "photo.png", "a free name is kept")

        try Data([0x62, 0x70]).write(to: images.appendingPathComponent(".photo.png.icloud"))
        let name = try XCTUnwrap(ImagesProcessor.getFileName(from: source, to: images))
        XCTAssertNotEqual(name, "photo.png", "photo.png is taken by a file iCloud has not downloaded yet")
        XCTAssertEqual((name as NSString).pathExtension, "png")
    }

    /// The Mac has put a dropped video or PDF in `files/` and linked it as an
    /// image since it first took files; the preview read `/files/` from the
    /// disk's root and drew "image not found" for both. A video now plays and
    /// any other file is a link that opens the file beside the note.
    func testAVideoInFilesPlaysAndAnotherFileIsALinkToIt() throws {
        let files = tempDir.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        try Data([0]).write(to: files.appendingPathComponent("clip.mov"))
        try Data([0]).write(to: files.appendingPathComponent("合同-v2.pdf"))
        try Data([0]).write(to: files.appendingPathComponent("shot.png"))

        let html = try XCTUnwrap(
            renderMarkdownHTML(
                markdown: "![](/files/clip.mov)\n\n![](/files/合同-v2.pdf)\n\n[合同 v2.pdf](/files/合同-v2.pdf)\n\n![](/files/shot.png)",
                useGithubLineBreak: false))
        XCTAssertTrue(html.contains("<video src=\"/files/clip.mov\" controls></video>"), html)
        XCTAssertTrue(html.contains("<a href=\"/files/%E5%90%88%E5%90%8C-v2.pdf\">合同-v2.pdf</a>"), html)

        let processed = HtmlManager.processImages(in: html, imagesStorage: tempDir)
        XCTAssertFalse(processed.contains("Image Not Found"), processed)
        XCTAssertNotNil(processed.range(of: #"<video [^>]*src="miaoyan-file://[^"]*/files/clip\.mov""#, options: .regularExpression), processed)
        XCTAssertNotNil(processed.range(of: #"<img [^>]*src="miaoyan-file://[^"]*/files/shot\.png""#, options: .regularExpression), processed)

        let clicked = try XCTUnwrap(URL(string: "file:///files/%E5%90%88%E5%90%8C-v2.pdf"))
        XCTAssertEqual(
            HtmlManager.noteAttachmentURL(for: clicked, noteFolder: tempDir)?.lastPathComponent, "合同-v2.pdf")
        XCTAssertNil(HtmlManager.noteAttachmentURL(for: URL(fileURLWithPath: "/files/../../etc/hosts"), noteFolder: tempDir))
        XCTAssertNil(HtmlManager.noteAttachmentURL(for: URL(fileURLWithPath: "/files/missing.pdf"), noteFolder: tempDir))
    }

    /// A paste whose image could not be written still got its link, a
    /// broken image in the note.
    /// The hidden name a copy runs under carried the file's own name plus
    /// a UUID, 46 characters more, so a name near APFS's 255 characters (a
    /// 224-character CJK name here) failed as too long where the file itself
    /// fits. APFS counts characters, not UTF-8 bytes: 80 CJK characters, 244
    /// bytes, copied fine through the old name too.
    func testAFileWithALongCJKNameIsCopied() throws {
        let source = tempDir.appendingPathComponent("source.pdf")
        try Data("%PDF-1.4".utf8).write(to: source)
        let files = tempDir.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let name = String(repeating: "\u{5408}", count: 220) + ".pdf"
        XCTAssertEqual(name.count, 224, "a name APFS takes")
        let destination = files.appendingPathComponent(name)

        XCTAssertNoThrow(try ImagesProcessor.copyAttachment(from: source, to: destination))
        XCTAssertEqual(try Data(contentsOf: destination), Data("%PDF-1.4".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: files.path), [name], "no partial copy is left")
    }

    /// Quitting waited only for folder moves, so a quit while a dropped file
    /// was being copied left the saved link with no file. It waits for the
    /// copies too, up to a cap, so quit never hangs on one.
    @MainActor
    func testQuittingWaitsForAFileStillBeingCopied() async throws {
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let note = Note(url: work.appendingPathComponent("n.md"), with: Project(url: work, label: "Work"))
        let storage = Storage(loadsLibrary: false)
        var replies = 0
        XCTAssertEqual(AppDelegate.terminationReply(storage: storage) { replies += 1 }, .terminateNow, "nothing under way")

        let copying = try XCTUnwrap(ImagesProcessor.reserveAttachment(for: URL(fileURLWithPath: "/tmp/Plan.pdf"), note: note))
        XCTAssertEqual(AppDelegate.terminationReply(storage: storage) { replies += 1 }, .terminateLater)
        XCTAssertEqual(replies, 0, "the copy is still under way")
        ImagesProcessor.releaseAttachment(copying.destination)
        XCTAssertEqual(replies, 1, "the quit goes on once the copy ends")

        let stuck = try XCTUnwrap(ImagesProcessor.reserveAttachment(for: URL(fileURLWithPath: "/tmp/clip.mov"), note: note))
        defer { ImagesProcessor.releaseAttachment(stuck.destination) }
        let capped = expectation(description: "the quit goes on after the cap")
        XCTAssertEqual(AppDelegate.terminationReply(storage: storage, copyCap: 0.2) { capped.fulfill() }, .terminateLater)
        await fulfillment(of: [capped], timeout: 5)
    }

    /// A copy runs through a hidden `.<UUID>.partial` beside its file; one a
    /// crash left there was skipped as hidden by Clean Unused Attachments and
    /// stayed forever. It is offered like any unused file, the old
    /// `.<name>.<UUID>.partial` form too, except in a folder a copy is
    /// being written into now. Other hidden files are still left alone.
    @MainActor
    func testAPartialCopyLeftByACrashIsOfferedUnlessACopyIsUnderWay() async throws {
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: work.appendingPathComponent("i"), withIntermediateDirectories: true)
        try manager.createDirectory(at: work.appendingPathComponent("files"), withIntermediateDirectories: true)
        try "# Note\n\n![](/i/used.png)\n".write(to: work.appendingPathComponent("n.md"), atomically: true, encoding: .utf8)
        try Data([1]).write(to: work.appendingPathComponent("i/used.png"))
        let partials = [
            "files/.\(UUID().uuidString).partial", "files/.Report.pdf.\(UUID().uuidString).partial", "i/.\(UUID().uuidString).partial",
        ]
        for name in partials + ["files/.keep", "files/.notes.partial"] {
            try Data([0]).write(to: work.appendingPathComponent(name))
        }
        let storage = Storage(loadsLibrary: false)
        let root = Project(url: tempDir, label: "root")
        _ = storage.add(project: root)
        _ = storage.subfolders(of: root)

        let found = await orphans(in: storage)
        XCTAssertEqual(found.map { Set($0.map(\.lastPathComponent)) }, Set(partials.map { ($0 as NSString).lastPathComponent }))

        let note = Note(url: work.appendingPathComponent("n.md"), with: Project(url: work, label: "Work"))
        let copying = try XCTUnwrap(ImagesProcessor.reserveAttachment(for: URL(fileURLWithPath: "/tmp/Report.pdf"), note: note))
        defer { ImagesProcessor.releaseAttachment(copying.destination) }
        let whileCopying = await orphans(in: storage)
        XCTAssertEqual(
            whileCopying.map { Set($0.map(\.lastPathComponent)) }, [(partials[2] as NSString).lastPathComponent],
            "files/ is being copied into, so its partial copies stay")
    }

    @MainActor
    func testAnImageThatCannotBeWrittenGetsNoLink() throws {
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        let images = work.appendingPathComponent("i", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: images.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: images.path) }
        let note = Note(url: work.appendingPathComponent("n.md"), with: Project(url: work, label: "Work"))

        let link = ImagesProcessor.writeFile(data: Data([0x89]), note: note, ext: "png")
        XCTAssertNil(link, "no file was written, so there is nothing to link")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: images.path), [])
    }

    /// An import whose copy failed still returned a URL, and the import
    /// focused a note that was not there.
    @MainActor
    func testAnImportThatCannotBeCopiedReturnsNothing() throws {
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let project = Project(url: work, label: "Work")
        let source = tempDir.appendingPathComponent("plan.md")
        try "# Plan\n".write(to: source, atomically: true, encoding: .utf8)

        XCTAssertEqual(ViewController.importCopy(of: source, into: project)?.lastPathComponent, "plan.md")
        XCTAssertEqual(ViewController.importCopy(of: source, into: project)?.lastPathComponent, "plan Copy.md", "a taken name gets Copy")
        XCTAssertEqual(ViewController.importCopy(of: source, into: project)?.lastPathComponent, "plan Copy 2.md")

        let missing = tempDir.appendingPathComponent("gone.md")
        XCTAssertNil(ViewController.importCopy(of: missing, into: project), "nothing was copied")
        XCTAssertEqual(
            Set(try FileManager.default.contentsOfDirectory(atPath: work.path)), ["plan.md", "plan Copy.md", "plan Copy 2.md"])
    }

    /// A taken name does not always fail as "file exists": a locked file
    /// there fails as a permission error, and the import gave up instead
    /// of trying the next "Copy" name.
    @MainActor
    func testAnImportOverALockedFileTakesTheNextName() throws {
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let source = tempDir.appendingPathComponent("plan.md")
        try "# Plan\n".write(to: source, atomically: true, encoding: .utf8)
        let locked = work.appendingPathComponent("plan.md")
        try "# Old plan\n".write(to: locked, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: locked.path) }

        let copy = ViewController.importCopy(of: source, into: Project(url: work, label: "Work"))
        XCTAssertEqual(copy?.lastPathComponent, "plan Copy.md")
        XCTAssertEqual(try String(contentsOf: locked, encoding: .utf8), "# Old plan\n", "the locked file is untouched")
    }

    /// A folder that cannot be written takes no copy under any name, and
    /// the search for a free name ends.
    @MainActor
    func testAnImportIntoAFolderThatCannotBeWrittenReturnsNothing() throws {
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let source = tempDir.appendingPathComponent("plan.md")
        try "# Plan\n".write(to: source, atomically: true, encoding: .utf8)
        try "# Old plan\n".write(to: work.appendingPathComponent("plan.md"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: work.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: work.path) }
        let project = Project(url: work, label: "Work")

        XCTAssertNil(ViewController.importCopy(of: source, into: project), "plan.md is taken and plan Copy.md cannot be made")
        let fresh = tempDir.appendingPathComponent("fresh.md")
        try "# Fresh\n".write(to: fresh, atomically: true, encoding: .utf8)
        XCTAssertNil(ViewController.importCopy(of: fresh, into: project))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: work.path), ["plan.md"])
    }

    @MainActor
    private func orphans(in storage: Storage, changedBefore cutoff: Date = .distantFuture) async -> [URL]? {
        let done = expectation(description: "orphan scan")
        var result: [URL]?
        storage.findOrphanAttachments(changedBefore: cutoff) { urls in
            result = urls
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 10)
        return result
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

    /// The launch scan stopped registering folders once 100 were known, so
    /// a library with more top-level folders lost the rest of their notes.
    @MainActor
    func testEveryTopLevelFolderIsRegistered() throws {
        let manager = FileManager.default
        let library = tempDir.appendingPathComponent("Library", isDirectory: true)
        for index in 0..<130 {
            let folder = library.appendingPathComponent(String(format: "Folder %03d", index), isDirectory: true)
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try "note".write(to: folder.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
        }

        let storage = Storage(loadsLibrary: false)
        let root = Project(url: library, isRoot: true)
        _ = storage.add(project: root)

        XCTAssertEqual(storage.getChildProjects(project: root).count, 130)
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

    // MARK: - One rule for which folder a file goes in

    /// The Mac decided `i/` or `files/` by UTType, the iPhone by the shared
    /// `AttachmentFile` list, and they disagreed on PSD, ICO, ICNS and RAW:
    /// the Mac put them in `i/` as images (maintainer, 2026-11-25: follow the
    /// shared rule).
    @MainActor
    func testTheMacSortsAttachmentsByTheSharedRule() throws {
        let expected: [String: String] = [
            "png": "/i/", "HEIC": "/i/", "jpeg": "/i/",
            "psd": "/files/", "ico": "/files/", "icns": "/files/", "cr2": "/files/", "dng": "/files/",
            "mov": "/files/", "mp4": "/files/", "pdf": "/files/",
        ]
        for (ext, prefix) in expected {
            let url = URL(fileURLWithPath: "/tmp/source.\(ext)")
            XCTAssertEqual(NotesTextProcessor.getAttachPrefix(url: url), prefix, ext)
            XCTAssertEqual(AttachmentFile.folder(for: AttachmentFile.kind(ofExtension: ext)), String(prefix.dropFirst().dropLast()), ext)
        }
        XCTAssertEqual(NotesTextProcessor.getAttachPrefix(), "/i/", "a pasted picture has no URL")

        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let note = Note(url: work.appendingPathComponent("n.md"), with: Project(url: work, label: "Work"))
        let psd = try XCTUnwrap(ImagesProcessor.writeFile(data: Data([1]), url: URL(fileURLWithPath: "/tmp/Layers.psd"), note: note))
        XCTAssertEqual(psd, "/files/Layers.psd")
        let raw = try XCTUnwrap(ImagesProcessor.writeFile(data: Data([2]), url: URL(fileURLWithPath: "/tmp/IMG_1.CR2"), note: note))
        XCTAssertEqual(raw, "/files/IMG_1.CR2")
        let png = try XCTUnwrap(ImagesProcessor.writeFile(data: Data([3]), url: URL(fileURLWithPath: "/tmp/Shot.png"), note: note))
        XCTAssertEqual(png, "/i/Shot.png")
    }

    /// Moving a note re-sorted every file by kind, so `![](/i/logo.ico)`,
    /// drawn as an image, became `/files/logo.ico`, shown as a link, and a
    /// PSD an older build kept in `i/` went to `files/`. A link that names
    /// `i/` or `files/` keeps that folder (maintainer, 2026-11-25); only a
    /// link outside them, `assets/b.png`, is sorted by the shared rule.
    @MainActor
    func testMovingANoteKeepsTheFolderItsLinkNames() throws {
        let folders = try makeFolders()
        let (from, to, noteURL) = (folders.from, folders.to, folders.noteURL)
        let manager = FileManager.default
        for folder in ["files", "assets"] {
            try manager.createDirectory(at: from.url.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try Data([7, 7]).write(to: from.url.appendingPathComponent("i/Layers.psd"))
        try Data([5]).write(to: from.url.appendingPathComponent("i/logo.ico"))
        try Data([6]).write(to: from.url.appendingPathComponent("files/cover.png"))
        try Data([8]).write(to: from.url.appendingPathComponent("assets/b.png"))
        try """
        # Trip

        ![](/i/Shot%201.png)

        ![](/i/Layers.psd)

        ![](i/logo.ico)

        ![](/files/cover.png)

        ![](assets/b.png)

        """.write(to: noteURL, atomically: true, encoding: .utf8)
        let note = Note(url: noteURL, with: from)

        note.move(toProject: to)

        XCTAssertEqual(try Data(contentsOf: to.url.appendingPathComponent("i/Layers.psd")), Data([7, 7]))
        XCTAssertEqual(try Data(contentsOf: to.url.appendingPathComponent("i/logo.ico")), Data([5]))
        XCTAssertEqual(try Data(contentsOf: to.url.appendingPathComponent("files/cover.png")), Data([6]))
        XCTAssertEqual(try Data(contentsOf: to.url.appendingPathComponent("i/b.png")), Data([8]), "outside i/ and files/, sorted by kind")
        XCTAssertFalse(manager.fileExists(atPath: to.url.appendingPathComponent("files").appendingPathComponent("Layers.psd").path))
        let text = try String(contentsOf: to.url.appendingPathComponent("trip.md"), encoding: .utf8)
        XCTAssertEqual(
            text,
            """
            # Trip

            ![](/i/Shot%201.png)

            ![](/i/Layers.psd)

            ![](/i/logo.ico)

            ![](/files/cover.png)

            ![](/i/b.png)

            """)
    }

    /// A dropped file is written as a link, `[Report v2.pdf](/files/Report-v2.pdf)`,
    /// and moving its note carried only what reads as an image: the PDF stayed
    /// in the old folder and the moved note's link pointed nowhere. A file
    /// whose name is taken in the destination gets a fresh one and the link,
    /// its title kept, follows.
    @MainActor
    func testMovingANoteCarriesTheFilesItLinks() throws {
        let folders = try makeFolders()
        let (from, to, noteURL) = (folders.from, folders.to, folders.noteURL)
        let manager = FileManager.default
        try manager.createDirectory(at: from.url.appendingPathComponent("files"), withIntermediateDirectories: true)
        try manager.createDirectory(at: to.url.appendingPathComponent("files"), withIntermediateDirectories: true)
        try Data([1, 2]).write(to: from.url.appendingPathComponent("files/Report-v2.pdf"))
        try Data([3]).write(to: from.url.appendingPathComponent("files/memo.txt"))
        try Data([9]).write(to: to.url.appendingPathComponent("files/memo.txt"))
        try "# Trip\n\n[Report v2.pdf](/files/Report-v2.pdf)\n\n[memo.txt](/files/memo.txt \"memo\")\n"
            .write(to: noteURL, atomically: true, encoding: .utf8)
        let note = Note(url: noteURL, with: from)

        note.move(toProject: to)

        XCTAssertEqual(try Data(contentsOf: to.url.appendingPathComponent("files/Report-v2.pdf")), Data([1, 2]))
        XCTAssertTrue(manager.fileExists(atPath: from.url.appendingPathComponent("files/Report-v2.pdf").path), "the original stays")
        XCTAssertEqual(try Data(contentsOf: to.url.appendingPathComponent("files/memo.txt")), Data([9]), "the other file is left alone")
        let text = try String(contentsOf: to.url.appendingPathComponent("trip.md"), encoding: .utf8)
        XCTAssertTrue(text.contains("[Report v2.pdf](/files/Report-v2.pdf)"), text)
        let memo = try XCTUnwrap(text.range(of: #"\[memo\.txt\]\(/files/([^ )]+) "memo"\)"#, options: .regularExpression), text)
        let name = String(text[memo].dropFirst("[memo.txt](/files/".count).prefix { $0 != " " })
        XCTAssertNotEqual(name, "memo.txt")
        XCTAssertEqual(try Data(contentsOf: to.url.appendingPathComponent("files").appendingPathComponent(name)), Data([3]))
    }

    /// The links were rewritten one after another over the text: `assets/b.png`
    /// landed as `/i/b.png`, the note's own `/i/b.png` then clashed with it and
    /// got a new name, and both links were pointed at that one file.
    @MainActor
    func testTwoLinksThatLandOnOneNameKeepTheirOwnFiles() throws {
        let folders = try makeFolders()
        let (from, to, noteURL) = (folders.from, folders.to, folders.noteURL)
        let manager = FileManager.default
        try manager.createDirectory(at: from.url.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try Data([1]).write(to: from.url.appendingPathComponent("assets/b.png"))
        try Data([2]).write(to: from.url.appendingPathComponent("i/b.png"))
        try "# Trip\n\n![](assets/b.png)\n\n![](/i/b.png)\n".write(to: noteURL, atomically: true, encoding: .utf8)
        let note = Note(url: noteURL, with: from)

        note.move(toProject: to)

        let text = try String(contentsOf: to.url.appendingPathComponent("trip.md"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"\]\((/i/[^)]+)\)"#)
        let links = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range(at: 1)) }
        XCTAssertEqual(links.count, 2, text)
        XCTAssertEqual(Set(links).count, 2, "each link keeps a file of its own: \(text)")
        let files = try links.map { try Data(contentsOf: to.url.appendingPathComponent($0)) }
        XCTAssertEqual(files, [Data([1]), Data([2])], "in order, the assets image and the note's own")
    }
}
