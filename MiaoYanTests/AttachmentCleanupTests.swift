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
}
