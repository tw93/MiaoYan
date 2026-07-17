import XCTest

@testable import MiaoYan

/// `Note.cleanMetaData` must hide any leading YAML frontmatter fence from the
/// preview, not only blocks that contain a `title:` key, and must stay in sync
/// with the iOS reader's `MobileHtmlRenderer.stripFrontmatter` semantics.
final class NoteFrontmatterTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiaoYanFrontmatterTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    @MainActor
    private func makeNote() -> Note {
        let project = Project(url: tempDir, label: "test", isRoot: true)
        return Note(url: tempDir.appendingPathComponent("fm.md"), with: project)
    }

    @MainActor
    func testStripsFrontmatterWithTitleKey() {
        let content = "---\ntitle: Hello\ndate: 2026-07-13\n---\nBody text"
        XCTAssertEqual(makeNote().cleanMetaData(content: content), "Body text")
    }

    @MainActor
    func testStripsFrontmatterWithoutTitleKey() {
        let content = "---\ntags: [ai, notes]\ndraft: true\n---\nBody text"
        XCTAssertEqual(makeNote().cleanMetaData(content: content), "Body text")
    }

    @MainActor
    func testKeepsContentWithoutOpeningFence() {
        let content = "# Heading\n\n---\n\nafter a rule"
        XCTAssertEqual(makeNote().cleanMetaData(content: content), content)
    }

    @MainActor
    func testKeepsContentWithUnclosedFence() {
        let content = "---\nkey: value\nno closing fence"
        XCTAssertEqual(makeNote().cleanMetaData(content: content), content)
    }

    @MainActor
    func testClosingFenceMustBeOwnLine() {
        let content = "---\nkey: value\n----\nstill inside"
        XCTAssertEqual(makeNote().cleanMetaData(content: content), content)
    }

    @MainActor
    func testFrontmatterOnlyDocumentBecomesEmpty() {
        let content = "---\nkey: value\n---"
        XCTAssertEqual(makeNote().cleanMetaData(content: content), "")
    }

    @MainActor
    func testCRLFOpeningFence() {
        let content = "---\r\nkey: value\r\n---\r\nBody"
        XCTAssertEqual(makeNote().cleanMetaData(content: content), "Body")
    }
}
