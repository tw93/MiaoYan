import XCTest

@testable import MiaoYan

/// A disk change to a note outside the listed folder must leave the list
/// alone: reloading the whole table for it dropped the selection every time
/// iCloud touched a note in another folder.
final class NotesTableReloadTests: XCTestCase {
    private final class CountingTable: NotesTableView {
        var fullReloads = 0
        override func reloadData() {
            fullReloads += 1
            super.reloadData()
        }
    }

    @MainActor
    func testReloadingAnUnlistedNoteLeavesTheTableAlone() {
        let base = URL(fileURLWithPath: "/tmp/miaoyan-reload-\(UUID().uuidString)")
        let project = Project(url: base, label: "reload", isRoot: true)
        let listed = Note(url: base.appendingPathComponent("listed.md"), with: project)
        let elsewhere = Note(url: base.appendingPathComponent("elsewhere.md"), with: project)
        let table = CountingTable(frame: .zero)
        table.noteList = [listed]
        table.fullReloads = 0

        table.reloadRow(note: elsewhere)

        XCTAssertEqual(table.fullReloads, 0)
    }
}
