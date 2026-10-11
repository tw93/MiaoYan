import XCTest

@testable import MiaoYan

/// Renaming a folder moves everything under it; every registered subfolder
/// and every note below must follow, or their saves hit a path that is gone.
final class StorageRelocationTests: XCTestCase {

    @MainActor
    func testRenamingAFolderMovesItsSubfoldersAndTheirNotes() {
        let base = URL(fileURLWithPath: "/tmp/miaoyan-relocate-\(UUID().uuidString)")
        let storage = Storage(loadsLibrary: false)
        let work = Project(url: base.appendingPathComponent("Work"), label: "Work")
        let year = Project(url: base.appendingPathComponent("Work/2024"), label: "2024", parent: work)
        let other = Project(url: base.appendingPathComponent("Workshop"), label: "Workshop")
        _ = storage.add(project: work)
        _ = storage.add(project: year)
        _ = storage.add(project: other)
        let top = Note(url: base.appendingPathComponent("Work/a.md"), with: work)
        let deep = Note(url: base.appendingPathComponent("Work/2024/b.md"), with: year)
        let outside = Note(url: base.appendingPathComponent("Workshop/c.md"), with: other)
        [top, deep, outside].forEach(storage.add)

        storage.relocateFolder(work, to: base.appendingPathComponent("Jobs"))

        XCTAssertEqual(work.url.path, base.appendingPathComponent("Jobs").path)
        XCTAssertEqual(work.label, "Jobs")
        XCTAssertEqual(year.url.path, base.appendingPathComponent("Jobs/2024").path)
        XCTAssertEqual(top.url.path, base.appendingPathComponent("Jobs/a.md").path)
        XCTAssertEqual(deep.url.path, base.appendingPathComponent("Jobs/2024/b.md").path)
        XCTAssertEqual(outside.url.path, base.appendingPathComponent("Workshop/c.md").path, "a sibling sharing the name prefix stays put")
        XCTAssertTrue(storage.getProjects().contains(work), "the renamed folder is still registered")
    }
}
