import XCTest

@testable import MiaoYan

final class ImportScanTests: XCTestCase {

    private var tempDir: URL!
    private let extensions = ["md", "markdown", "txt"]

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiaoYanImportScanTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeFile(_ relativePath: String) {
        let url = tempDir.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
    }

    @MainActor
    func testRecursiveFolderScanFindsMarkdown() {
        makeFile("a.md")
        makeFile("sub/b.markdown")
        makeFile("sub/deep/c.txt")
        makeFile("sub/deep/skip.png")

        let files = ViewController.collectImportableFiles(from: [tempDir], allowedExtensions: extensions)
        XCTAssertEqual(files.map(\.lastPathComponent).sorted(), ["a.md", "b.markdown", "c.txt"])
    }

    @MainActor
    func testAttachmentAndTrashFoldersSkipped() {
        makeFile("keep.md")
        makeFile("i/image-note.md")
        makeFile("files/attach.md")
        makeFile(".Trash/deleted.md")

        let files = ViewController.collectImportableFiles(from: [tempDir], allowedExtensions: extensions)
        XCTAssertEqual(files.map(\.lastPathComponent), ["keep.md"])
    }

    @MainActor
    func testDirectFileSelectionFiltersByExtension() {
        makeFile("doc.md")
        makeFile("word.docx")

        let files = ViewController.collectImportableFiles(
            from: [tempDir.appendingPathComponent("doc.md"), tempDir.appendingPathComponent("word.docx")],
            allowedExtensions: extensions)
        XCTAssertEqual(files.map(\.lastPathComponent), ["doc.md"])
    }

    @MainActor
    func testFolderPlusInnerFileDeduplicated() {
        makeFile("one.md")

        let files = ViewController.collectImportableFiles(
            from: [tempDir, tempDir.appendingPathComponent("one.md")], allowedExtensions: extensions)
        XCTAssertEqual(files.count, 1)
    }

    /// A copy that failed partway, under a name that was free, left the part
    /// it had copied in the library: a text bundle copied up to the file it
    /// could not read, which the library listed as a note.
    @MainActor
    func testAnImportThatFailsPartwayLeavesNothingBehind() throws {
        let bundle = tempDir.appendingPathComponent("source/plan.textbundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try "# Plan\n".write(to: bundle.appendingPathComponent("text.md"), atomically: true, encoding: .utf8)
        let unreadable = bundle.appendingPathComponent("unreadable.png")
        try Data([0]).write(to: unreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path) }
        let work = tempDir.appendingPathComponent("Work", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        XCTAssertNil(ViewController.importCopy(of: bundle, into: Project(url: work, label: "Work")), "the copy failed")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: work.path), [], "no part of it is left")

        // What is cleared went to the Trash: `existed` is read before the
        // copy, and a file another writer put there meanwhile must stay
        // recoverable. That race cannot be staged here, so the source holds it.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Controllers/ViewController+Action.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "static func importCopy(of url: URL, into project: Project) -> URL? {"))
        let end = try XCTUnwrap(source.range(of: "\n    }\n", range: start.upperBound..<source.endIndex))
        let body = source[start.upperBound..<end.lowerBound]
        XCTAssertTrue(body.contains("try manager.trashItem(at: destination, resultingItemURL: nil)"), "the partial copy goes to the Trash")
        XCTAssertFalse(body.contains("removeItem("), "nothing is removed for good")
    }
}
