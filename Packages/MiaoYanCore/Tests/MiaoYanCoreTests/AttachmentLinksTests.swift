import XCTest

@testable import MiaoYanCore

final class AttachmentLinksTests: XCTestCase {
    func testLinksReadEveryFormANoteWritesAFileIn() {
        let text = """
            ![](/i/a.png) ![](<i/my photo.png>) <img src="i/b c.png"> <img src=i/d.png>
            [Report](/files/report(1).pdf) [Spec](files/spec.pdf#page=3) ![](i/e\\_f.png)
            [ref]: <files/ref doc.pdf>
            ![](https://example.com/i/remote.png) ![](data:image/png;base64,AAAA)
            ![](i/caf%C3%A9.png)
            """
        let links = AttachmentLinks.links(in: text)
        for expected in [
            "/i/a.png", "i/my photo.png", "i/b c.png", "i/d.png", "/files/report(1).pdf", "files/spec.pdf",
            "i/e_f.png", "files/ref doc.pdf", "i/café.png",
        ] {
            XCTAssertTrue(links.contains(expected), "missing \(expected) in \(links.sorted())")
        }
        XCTAssertFalse(links.contains("https://example.com/i/remote.png"))
        XCTAssertFalse(links.contains { $0.hasPrefix("data:") })
    }

    func testResolveKeepsEachLinkInsideItsBound() {
        let library = "/lib"
        let folder = "/lib/Work"
        let sub = "/lib/Work/Deep"
        XCTAssertEqual(AttachmentLinks.resolve("/i/a.png", folder: folder, noteDirectory: folder, library: library), "/lib/Work/i/a.png")
        XCTAssertEqual(AttachmentLinks.resolve("./i/a.png", folder: folder, noteDirectory: folder, library: library), "/lib/Work/i/a.png")
        XCTAssertEqual(AttachmentLinks.resolve("files/a.pdf", folder: folder, noteDirectory: folder, library: library), "/lib/Work/files/a.pdf")
        // A note one folder down reaches its parent's i/ with ../.
        XCTAssertEqual(AttachmentLinks.resolve("../i/a.png", folder: sub, noteDirectory: sub, library: library), "/lib/Work/i/a.png")
        XCTAssertNil(AttachmentLinks.resolve("/../../etc/a.png", folder: folder, noteDirectory: folder, library: library))
        XCTAssertNil(AttachmentLinks.resolve("../../outside/a.png", folder: folder, noteDirectory: folder, library: library))
        XCTAssertNil(AttachmentLinks.resolve("", folder: folder, noteDirectory: folder, library: library))
    }

    func testPathsResolveAgainstTheNotesOwnDirectory() {
        let paths = AttachmentLinks.paths(
            in: "![](/i/a.png) [x](../files/b.pdf) ![](https://x.com/i/c.png)", noteDirectory: "/lib/Work/Deep", library: "/lib")
        XCTAssertTrue(paths.contains("/lib/Work/Deep/i/a.png"))
        XCTAssertTrue(paths.contains("/lib/Work/files/b.pdf"))
        // The bare-path pattern also reads `/i/c.png` inside a remote URL;
        // an extra entry only keeps a file, never trashes one.
        XCTAssertTrue(paths.contains("/lib/Work/Deep/i/c.png"))
    }

    /// `standardizingPath` drops a leading `/private` from a path that
    /// exists, and every library on an iPhone (the iCloud container, a folder
    /// picked in Files) is under `/private/var`: compared against the folder
    /// as given, every link to an existing file fell outside it and its file
    /// was offered as unused.
    func testALibraryUnderPrivateKeepsItsLinks() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
            .appendingPathComponent("AttachmentLinks-\(UUID().uuidString)")
        let work = base.appendingPathComponent("Work")
        try FileManager.default.createDirectory(at: work.appendingPathComponent("Deep"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: work.appendingPathComponent("i"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: work.appendingPathComponent("files"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try Data("PNG".utf8).write(to: work.appendingPathComponent("i/a.png"))
        try Data("PDF".utf8).write(to: work.appendingPathComponent("files/b.pdf"))
        // The temporary folder is under /private/var on every Apple system.
        let folder = work.path.hasPrefix("/private/") ? work.path : "/private" + work.path
        let library = (folder as NSString).deletingLastPathComponent
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder + "/i/a.png"))

        for link in ["i/a.png", "/i/a.png", "files/b.pdf"] {
            XCTAssertNotNil(AttachmentLinks.resolve(link, folder: folder, noteDirectory: folder, library: library), link)
        }
        let deep = folder + "/Deep"
        XCTAssertNotNil(AttachmentLinks.resolve("../i/a.png", folder: deep, noteDirectory: deep, library: library))
        XCTAssertNil(AttachmentLinks.resolve("../../../etc/hosts", folder: deep, noteDirectory: deep, library: library))
    }
}
