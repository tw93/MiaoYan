import XCTest

@testable import MiaoYan

/// Folder dates must be read fresh from the same long-lived URL, or a change
/// on disk never shows and the rescan that depends on it is skipped.
final class ModificationDateCacheTests: XCTestCase {
    func testSameURLSeesANewerFolderDate() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try XCTUnwrap(Storage.contentModifiedAt(folder))
        Thread.sleep(forTimeInterval: 0.05)
        try "note".write(to: folder.appendingPathComponent("new.md"), atomically: true, encoding: .utf8)
        let second = try XCTUnwrap(Storage.contentModifiedAt(folder))
        XCTAssertNotEqual(first, second)
    }
}
