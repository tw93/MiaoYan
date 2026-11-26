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
}
