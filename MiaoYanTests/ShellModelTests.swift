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

    // MARK: - List commands

    /// NotesTableView.insertNew: the copy is listed and the original stays
    /// selected; the shell used to open the copy.
    @MainActor
    func testDuplicateKeepsTheOriginalSelected() async throws {
        try await withShellLibrary(["first", "open"]) { model, _, notes in
            let open = notes[1]
            model.clickNote(open, modifiers: [])

            model.duplicate([open])
            for _ in 0..<100 where model.notes.count < 3 { await Task.yield() }

            XCTAssertEqual(model.notes.count, 3, "the copy is listed")
            XCTAssertEqual(model.selectedNoteURL, open.url)
            XCTAssertEqual(model.selectedNotes.map(\.url), [open.url])
        }
    }

    /// NotesTableView.rightMouseDown: a row outside the selection becomes
    /// the selection; a row inside a multiple selection keeps all of it.
    @MainActor
    func testRightClickSelectsTheClickedRowUnlessItIsSelected() async throws {
        try await withShellLibrary(["one", "two", "three"]) { model, _, notes in
            model.clickNote(notes[0], modifiers: [])
            model.clickNote(notes[1], modifiers: .command)

            model.selectForMenu(notes[1])
            XCTAssertEqual(Set(model.selectedNotes.map(\.url)), [notes[0].url, notes[1].url])
            XCTAssertEqual(model.selectedNoteURL, notes[0].url)

            model.selectForMenu(notes[2])
            XCTAssertEqual(model.selectedNotes.map(\.url), [notes[2].url])
            XCTAssertEqual(model.focusRequest, .list)
        }
    }

    /// The storyboard window's searchAndCreate: the hidden list comes back
    /// and the field takes the keys once it is on screen; an open field
    /// holding a query is focused again.
    @MainActor
    func testSearchShortcutRevealsTheListAndFocusesTheField() async throws {
        try await withShellLibrary(["one"]) { model, _, _ in
            if model.layout != .noteOnly { model.toggleNoteList() }
            model.focusSearch()
            XCTAssertEqual(model.layout, .listAndNote)
            XCTAssertTrue(model.isSearchOpen)
            XCTAssertNil(model.focusRequest, "the list column is still opening")
            model.layoutDidSettle()
            XCTAssertEqual(model.focusRequest, .search)

            model.focusRequest = nil
            model.searchText = "one"
            model.focusSearch()
            XCTAssertEqual(model.focusRequest, .search)
        }
    }

    /// The list says which folder it shows, so it can put back that folder's
    /// scroll place, and whether it shows search results there instead.
    @MainActor
    func testListContentFollowsTheFolderAndTheSearch() async throws {
        try await withShellLibrary(["alpha", "beta"]) { model, folder, _ in
            XCTAssertEqual(model.listContent, .init(scope: .project(folder.url), isSearch: false))
            model.searchText = "alpha"
            for _ in 0..<50 where model.listContent?.isSearch != true { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertEqual(model.listContent, .init(scope: .project(folder.url), isSearch: true))
            XCTAssertEqual(model.notes.count, 1)
        }
    }

    /// A shell model showing a temporary folder that holds a note per name,
    /// in that order; the preferences it writes are put back afterwards.
    @MainActor
    private func withShellLibrary(_ names: [String], _ body: (ShellModel, Project, [Note]) async throws -> Void) async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanShellList-\(UUID().uuidString)")
        let rootURL = base.appendingPathComponent("Library", isDirectory: true)
        let folderURL = rootURL.appendingPathComponent("Work", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        for name in names {
            try name.write(to: folderURL.appendingPathComponent("\(name).md"), atomically: true, encoding: .utf8)
        }
        let storage = AppEnvironment.current.storage
        let root = Project(url: rootURL, isRoot: true, isDefault: true)
        _ = storage.add(project: root)
        let defaults = UserDefaults.standard
        let keys = ["ShellScope", "ShellLayout"]
        let previous = keys.map { defaults.object(forKey: $0) }
        let previousSelected = UserDefaultsManagement.lastSelectedURL
        let previousProject = UserDefaultsManagement.lastProjectPath
        let previousSort = UserDefaultsManagement.sort
        let previousDirection = UserDefaultsManagement.sortDirection
        UserDefaultsManagement.sort = .title
        UserDefaultsManagement.sortDirection = false
        defer {
            for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) }
            UserDefaultsManagement.lastSelectedURL = previousSelected
            UserDefaultsManagement.lastProjectPath = previousProject
            UserDefaultsManagement.sort = previousSort
            UserDefaultsManagement.sortDirection = previousDirection
            for project in storage.getProjects() where project.url.path.hasPrefix(rootURL.path) {
                defaults.removeObject(forKey: project.url.path)
                storage.removeBy(project: project)
            }
            try? FileManager.default.removeItem(at: base)
        }
        let folder = try XCTUnwrap(storage.getChildProjects(project: root).first { $0.url.path == folderURL.path })
        storage.loadMissingNotes(for: folder)
        let notes = try names.map { try XCTUnwrap(storage.getBy(url: folderURL.appendingPathComponent("\($0).md"))) }
        let model = ShellModel()
        model.scope = .project(folder.url)
        model.reload()
        for _ in 0..<100 where model.notes.count < names.count || model.listContent?.scope != model.scope {
            await Task.yield()
        }
        XCTAssertEqual(model.notes.count, names.count)
        try await body(model, folder, notes)
    }

    private func urls(_ count: Int) -> [URL] {
        (0..<count).map { URL(fileURLWithPath: "/tmp/note-\($0).md") }
    }
}
