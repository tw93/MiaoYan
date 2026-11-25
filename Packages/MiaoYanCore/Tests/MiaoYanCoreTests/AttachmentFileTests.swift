import Foundation
import XCTest

@testable import MiaoYanCore

final class AttachmentFileTests: XCTestCase {
    func testImagesGoInIAndEverythingElseInFiles() {
        XCTAssertEqual(AttachmentFile.kind(ofExtension: "JPG"), .image)
        XCTAssertEqual(AttachmentFile.kind(ofExtension: "MOV"), .video)
        XCTAssertEqual(AttachmentFile.kind(ofExtension: "mp4"), .video)
        XCTAssertEqual(AttachmentFile.kind(ofExtension: "pdf"), .file)
        XCTAssertEqual(AttachmentFile.kind(ofExtension: ""), .file)
        XCTAssertEqual(AttachmentFile.folder(for: .image), "i")
        XCTAssertEqual(AttachmentFile.folder(for: .video), "files")
        XCTAssertEqual(AttachmentFile.folder(for: .file), "files")
    }

    /// The name the Mac has always given a dropped file, so a link written
    /// on either device needs no escaping.
    func testANameKeepsLettersAndDigitsAndJoinsTheRestWithOneDash() {
        XCTAssertEqual(AttachmentFile.normalizedName("合同 v2 (final).pdf", fallbackExtension: "bin"), "合同-v2-final.pdf")
        XCTAssertEqual(AttachmentFile.normalizedName("IMG_1234.MOV", fallbackExtension: "mov"), "IMG_1234.MOV")
        XCTAssertEqual(AttachmentFile.normalizedName("notes", fallbackExtension: "txt"), "notes.txt")
        let blank = AttachmentFile.normalizedName("()).zip", fallbackExtension: "bin")
        XCTAssertTrue(blank.hasSuffix(".zip"))
        XCTAssertEqual(blank.count, 36 + 4, "a name with nothing left is a UUID")
    }

    func testAFileIsALinkNamedAsPickedAndAVideoIsWrittenAsAnImage() {
        XCTAssertEqual(
            AttachmentFile.markdown(path: "/files/合同-v2.pdf", kind: .file, title: "合同 v2.pdf"),
            "[合同 v2.pdf](/files/合同-v2.pdf)")
        XCTAssertEqual(
            AttachmentFile.markdown(path: "/files/a.pdf", kind: .file, title: "[draft] a\\b.pdf"),
            #"[\[draft\] a\\b.pdf](/files/a.pdf)"#)
        XCTAssertEqual(AttachmentFile.markdown(path: "/files/a.pdf", kind: .file, title: ""), "[a.pdf](/files/a.pdf)")
        XCTAssertEqual(AttachmentFile.markdown(path: "/files/clip.mov", kind: .video, title: "clip.mov"), "![](/files/clip.mov)")
        XCTAssertEqual(AttachmentFile.markdown(path: "/i/a.jpg", kind: .image, title: ""), "![](/i/a.jpg)")
    }

    func testReferencesFindBothFoldersInEveryShapeOnce() {
        let text = """
            ![](/i/a.png) [合同](/files/合同-v2.pdf) <video src="/files/clip.mov"></video>
            [again](/files/合同-v2.pdf) ![](</i/b%20c.png>) ![](https://x.com/i/d.png) [](/elsewhere/e.pdf)
            """
        let found = AttachmentFile.references(in: text).map { "\($0.folder)/\($0.name)" }
        XCTAssertEqual(found, ["i/a.png", "files/合同-v2.pdf", "files/clip.mov", "i/b%20c.png"])
    }
}
