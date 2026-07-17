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
}
