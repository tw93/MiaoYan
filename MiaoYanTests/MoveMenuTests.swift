import XCTest

@testable import MiaoYan

/// The Move menu lists every folder as the sidebar nests them (#579): one
/// flat list made same-named subfolders under different parents impossible
/// to tell apart, and missed subfolders the sidebar had never opened.
final class MoveMenuTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanMoveMenu-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: base)
        super.tearDown()
    }

    /// A library whose folders each hold a note, since a folder with no note
    /// and no folder is an attachment folder to the sidebar.
    @MainActor
    private func library(_ folders: [String]) throws -> (Storage, Project) {
        let rootURL = base.appendingPathComponent("Library", isDirectory: true)
        for folder in folders {
            let url = rootURL.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try "# note".write(to: url.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
        }
        let storage = Storage(loadsLibrary: false)
        let root = Project(url: rootURL, isRoot: true, isDefault: true)
        _ = storage.add(project: root)
        addTeardownBlock { @MainActor in
            for project in storage.getProjects() {
                UserDefaults.standard.removeObject(forKey: project.url.path)
                storage.removeBy(project: project)
            }
        }
        return (storage, root)
    }

    private func names(_ entries: [Storage.FolderTreeEntry]) -> [String] {
        entries.map { String(repeating: "  ", count: $0.depth) + $0.project.label }
    }

    @MainActor
    func testFolderTreeListsEveryFolderUnderItsParentInSidebarOrder() throws {
        let (storage, root) = try library(["Work", "Work/2024", "Work/2024/Q1", "Work/Archive", "Life", "Life/Archive", "i"])
        // The sidebar's top-level order is the user's, not the alphabet's.
        let topLevel = ["Work", "Life"].compactMap { name in storage.subfolders(of: root).first { $0.label == name } }

        let tree = storage.folderTree(under: topLevel)

        XCTAssertEqual(names(tree), ["Work", "  2024", "    Q1", "  Archive", "Life", "  Archive"])
    }

    @MainActor
    func testFolderTreeListsAFolderReachedTwiceThroughASymlinkOnce() throws {
        let (storage, root) = try library(["Work", "Work/Notes"])
        let loop = root.url.appendingPathComponent("Work/Notes/Back")
        try FileManager.default.createSymbolicLink(at: loop, withDestinationURL: root.url.appendingPathComponent("Work"))
        let work = try XCTUnwrap(storage.subfolders(of: root).first { $0.label == "Work" })

        let tree = storage.folderTree(under: [work])

        XCTAssertEqual(names(tree), ["Work", "  Notes"])
    }

    @MainActor
    func testFolderTreeStopsAtTheDeepestIndentAMenuShows() throws {
        let (storage, root) = try library(["A", "A/B", "A/B/C"])
        let top = try XCTUnwrap(storage.subfolders(of: root).first)

        XCTAssertEqual(names(storage.folderTree(under: [top], maxDepth: 1)), ["A", "  B"])
    }

    @MainActor
    func testMenuIndentsEachFolderAndOnlyGreysOutTheFolderEveryNoteIsIn() throws {
        let (storage, root) = try library(["Work", "Work/Archive", "Life"])
        let folders = storage.subfolders(of: root)
        let work = try XCTUnwrap(folders.first { $0.label == "Work" })
        let life = try XCTUnwrap(folders.first { $0.label == "Life" })
        let tree = storage.folderTree(under: [work, life])
        let archive = try XCTUnwrap(tree.first { $0.project.label == "Archive" }?.project)

        let note = Note(url: archive.url.appendingPathComponent("note.md"), with: archive)
        let items = MoveMenuFiller.items(for: [note], destinations: ([root], tree), target: nil)

        XCTAssertEqual(items.map(\.title), [root.label, "", "Work", "Archive", "Life"])
        XCTAssertTrue(items[1].isSeparatorItem)
        XCTAssertEqual(items.map(\.indentationLevel), [0, 0, 0, 1, 0])
        XCTAssertEqual(items.filter { !$0.isSeparatorItem }.map(\.isEnabled), [true, true, false, true])
        XCTAssertTrue(items.allSatisfy { $0.tag == MoveMenuFiller.itemTag })
        XCTAssertTrue(items[3].representedObject as? Project === archive)

        let other = Note(url: life.url.appendingPathComponent("note.md"), with: life)
        let mixed = MoveMenuFiller.items(for: [note, other], destinations: ([root], tree), target: nil)
        XCTAssertTrue(mixed.filter { !$0.isSeparatorItem }.allSatisfy(\.isEnabled), "a note from another folder can still go to either")
    }

    @available(macOS 14, *)
    @MainActor
    func testShellNestsTheTreeAsTheSidebarDoes() throws {
        let (storage, root) = try library(["Work", "Work/2024", "Work/2024/Q1", "Work/Archive", "Life"])
        let folders = storage.subfolders(of: root)
        let tree = storage.folderTree(under: ["Work", "Life"].compactMap { name in folders.first { $0.label == name } })

        let nested = ShellModel.nest(tree)

        func shape(_ folders: [ShellModel.MoveFolder]) -> String {
            folders.map { $0.children.isEmpty ? $0.project.label : "\($0.project.label)(\(shape($0.children)))" }.joined(separator: " ")
        }
        XCTAssertEqual(shape(nested), "Work(2024(Q1) Archive) Life")
    }
}
