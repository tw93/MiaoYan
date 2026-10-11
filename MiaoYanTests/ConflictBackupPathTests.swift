import XCTest

@testable import MiaoYan

/// Conflict backups live in a hidden folder inside the storage root, where
/// the file watcher sees them; it must skip them rather than report each one
/// as a missing note.
final class ConflictBackupPathTests: XCTestCase {
    @MainActor
    func testRecognizesBackupsAndLeavesNotesAlone() {
        let root = URL(fileURLWithPath: "/Users/me/Notes")
        XCTAssertTrue(FileSystemEventManager.isConflictBackup(root.appendingPathComponent(".miaoyan-conflicts/Work-Plan-2026-10-11T15-05-39Z.md")))
        XCTAssertFalse(FileSystemEventManager.isConflictBackup(root.appendingPathComponent("Work/Plan.md")))
        XCTAssertFalse(FileSystemEventManager.isConflictBackup(root.appendingPathComponent("Work/miaoyan-conflicts.md")))
    }
}
