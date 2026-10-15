import XCTest

@testable import MiaoYan

/// The SwiftUI shell's list and sidebar rules that must match the storyboard
/// window: where Move can send a note, which note opens after notes leave
/// the list, how a remembered subfolder is found at launch, and how a
/// dragged folder reorders the sidebar.
@available(macOS 14, *)
final class ShellModelTests: XCTestCase {

    // MARK: - Move targets

    @MainActor
    func testMoveTargetsListEveryFolderButTheNotesOwnAndTheTrash() {
        let base = URL(fileURLWithPath: "/tmp/MiaoYanShellMove-\(UUID().uuidString)")
        let root = Project(url: base, isRoot: true, isDefault: true)
        let work = Project(url: base.appendingPathComponent("Work"), parent: root)
        let nested = Project(url: work.url.appendingPathComponent("Nested"), parent: work)
        let archive = Project(url: base.appendingPathComponent("Archive"), parent: root)
        let trash = Project(url: base.appendingPathComponent(".Trash"), isTrash: true)

        let targets = ShellModel.moveTargets(excluding: work, in: [root, work, nested, archive, trash])

        XCTAssertEqual(targets.map(\.url.path), [root, nested, archive].map(\.url.path))
    }

    // MARK: - Selection after notes leave the list

    @MainActor
    func testOpenNoteRemovedOpensTheNoteNowAtItsRow() {
        let list = urls(5)
        let next = ShellModel.selection(afterRemoving: [list[1], list[2]], from: list, selected: list[2])
        XCTAssertEqual(next, list[3])
    }

    @MainActor
    func testRemovingTheLastRowsOpensTheNewLastNote() {
        let list = urls(4)
        let next = ShellModel.selection(afterRemoving: [list[3]], from: list, selected: list[3])
        XCTAssertEqual(next, list[2])
    }

    @MainActor
    func testOpenNoteThatStaysKeepsTheSelection() {
        let list = urls(4)
        let next = ShellModel.selection(afterRemoving: [list[0]], from: list, selected: list[2])
        XCTAssertEqual(next, list[2])
    }

    @MainActor
    func testRemovingEveryNoteLeavesNothingOpen() {
        let list = urls(2)
        XCTAssertNil(ShellModel.selection(afterRemoving: Set(list), from: list, selected: list[0]))
    }

    // MARK: - Launch restore

    @MainActor
    func testRememberedSubfolderIsFoundThroughItsCollapsedParents() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanShellRestore-\(UUID().uuidString)")
        let rootURL = base.appendingPathComponent("Library", isDirectory: true)
        let deepURL = rootURL.appendingPathComponent("Work/Nested/Deep", isDirectory: true)
        try FileManager.default.createDirectory(at: deepURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootURL.appendingPathComponent("Workshop"), withIntermediateDirectories: true)
        // Folders holding no notes and no folders are attachment folders to
        // the sidebar; give each one a note.
        for folder in ["Work", "Work/Nested", "Work/Nested/Deep", "Workshop"] {
            try "# note".write(to: rootURL.appendingPathComponent("\(folder)/note.md"), atomically: true, encoding: .utf8)
        }
        let storage = Storage(loadsLibrary: false)
        let root = Project(url: rootURL, isRoot: true, isDefault: true)
        _ = storage.add(project: root)
        defer {
            for project in storage.getProjects() where project.url.path.hasPrefix(root.url.path) {
                UserDefaults.standard.removeObject(forKey: project.url.path)
                storage.removeBy(project: project)
            }
            try? FileManager.default.removeItem(at: base)
        }
        let topLevel = storage.getChildProjects(project: root)
        let deepPath = deepURL.resolvingSymlinksInPath().path

        let chain = try XCTUnwrap(ShellModel.folderChain(toPath: deepPath, topLevel: topLevel, storage: storage))

        XCTAssertEqual(chain.map(\.url.lastPathComponent), ["Work", "Nested", "Deep"])
        XCTAssertEqual(chain.last?.url.path, deepPath)
        // "Workshop" shares the prefix "Work" but is not an ancestor.
        XCTAssertNil(ShellModel.folderChain(toPath: root.url.path + "/Work/Missing", topLevel: topLevel, storage: storage))
    }

    // MARK: - Folder order

    @MainActor
    func testDraggedFolderTakesTheTargetsPlace() {
        let order = ["/a", "/b", "/c", "/d"]
        XCTAssertEqual(ShellModel.reorderedFolders(order, moving: "/a", onto: "/c"), ["/b", "/c", "/a", "/d"])
        XCTAssertEqual(ShellModel.reorderedFolders(order, moving: "/d", onto: "/b"), ["/a", "/d", "/b", "/c"])
        XCTAssertNil(ShellModel.reorderedFolders(order, moving: "/a", onto: "/a"))
        XCTAssertNil(ShellModel.reorderedFolders(order, moving: "/x", onto: "/a"))
    }

    private func urls(_ count: Int) -> [URL] {
        (0..<count).map { URL(fileURLWithPath: "/tmp/note-\($0).md") }
    }
}
