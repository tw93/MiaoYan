import XCTest

@testable import MiaoYanCore

final class UnusedAttachmentsTests: XCTestCase {
    private var root: URL!
    private let old = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
            .appendingPathComponent("UnusedAttachments-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, _ path: String, date: Date? = nil) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        let date = date ?? old
        try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
    }

    private func unused(in library: URL? = nil, before cutoff: Date = .distantFuture) -> [String]? {
        let library = library ?? root!
        return UnusedAttachments.find(in: library, changedBefore: cutoff)?
            .map { String($0.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1)) }.sorted()
    }

    func testOnlyFilesNoNoteLinksAreOffered() throws {
        try write("# Note\n\n![](/i/used.png) [r](files/used.pdf)\n", "Work/note.md")
        try write("# Deep\n\n![](../i/deep.png)\n", "Work/Deep/sub.md")
        try write("# Top\n\n<img src=\"i/top.png\">\n", "top.md")
        for path in ["Work/i/used.png", "Work/i/deep.png", "Work/i/unused.png", "Work/files/used.pdf", "Work/files/unused.pdf", "i/top.png"] {
            try write("x", path)
        }
        XCTAssertEqual(unused(), ["Work/files/unused.pdf", "Work/i/unused.png"])
    }

    func testATrashedNoteKeepsItsFilesByNameAndTheTrashIsNotCleaned() throws {
        try write("# Gone\n\n![](/i/kept.png)\n", "Trash/gone.md")
        try write("x", "Work/i/kept.png")
        try write("x", "Trash/i/inside.png")
        // A link to the Trash elsewhere must not make its notes live.
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Work/TL"), withDestinationURL: root.appendingPathComponent("Trash"))
        XCTAssertEqual(unused(), [])
    }

    func testARecentFileIsNotOffered() throws {
        try write("# Note\n", "Work/note.md")
        try write("x", "Work/i/old.png")
        try write("x", "Work/i/new.png", date: Date())
        XCTAssertEqual(unused(before: Date().addingTimeInterval(-86_400)), ["Work/i/old.png"])
    }

    func testAnythingUnreadableCleansNothing() throws {
        try write("# Note\n", "Work/note.md")
        try write("x", "Work/i/a.png")
        try write("x", "Work/.cloud.md.icloud")
        XCTAssertNil(unused(), "a note iCloud keeps only online")
        try FileManager.default.removeItem(at: root.appendingPathComponent("Work/.cloud.md.icloud"))
        XCTAssertEqual(unused(), ["Work/i/a.png"])

        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Gone"), withDestinationURL: URL(fileURLWithPath: "/nonexistent/folder"))
        XCTAssertNil(unused(), "a folder link whose target is gone")
        try FileManager.default.removeItem(at: root.appendingPathComponent("Gone"))

        XCTAssertNil(UnusedAttachments.find(in: root, changedBefore: .distantFuture) { _ in throw CocoaError(.fileReadNoPermission) })
    }

    func testWithNoAttachmentFoldersAnUnreadableNoteIsNoFailure() throws {
        try write("# Note\n", "Work/note.md")
        try write("x", "Work/.cloud.md.icloud")
        XCTAssertEqual(unused(), [])
    }

    /// Every iPhone library is under /private/var; standardizing a link
    /// there dropped the prefix and every file looked unused.
    func testALibraryUnderPrivateKeepsItsLinks() throws {
        try write("# Note\n\n![](i/a.png)\n", "Work/note.md")
        try write("# Deep\n\n![](../i/b.png)\n", "Work/Deep/sub.md")
        try write("x", "Work/i/a.png")
        try write("x", "Work/i/b.png")
        try write("x", "Work/i/c.png")
        let privateRoot = URL(fileURLWithPath: root.path.hasPrefix("/private/") ? root.path : "/private" + root.path)
        XCTAssertEqual(unused(in: privateRoot), ["Work/i/c.png"])
    }

    func testAScanTellsADownloadingNoteFromAnUnreadableOne() throws {
        try write("# Note\n", "Work/note.md")
        try write("x", "Work/i/a.png")
        try write("x", "Work/.cloud.md.icloud")
        XCTAssertEqual(UnusedAttachments.scan(in: root, changedBefore: .distantFuture), .downloading)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Work/.cloud.md.icloud"))
        XCTAssertEqual(
            UnusedAttachments.scan(in: root, changedBefore: .distantFuture) { _ in throw CocoaError(.fileReadNoPermission) },
            .unreadable)
        guard case .found(let files) = UnusedAttachments.scan(in: root, changedBefore: .distantFuture) else {
            return XCTFail("a readable library is scanned")
        }
        XCTAssertEqual(files.map(\.lastPathComponent), ["a.png"])
    }
}
