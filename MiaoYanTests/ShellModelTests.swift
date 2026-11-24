import XCTest

@testable import MiaoYan

/// The SwiftUI shell's list and sidebar rules that must match the storyboard
/// window: which note opens after notes leave the list, how a remembered
/// subfolder is found at launch, and how a dragged folder reorders the
/// sidebar. Move's folders are in `MoveMenuTests`.
@available(macOS 14, *)
final class ShellModelTests: XCTestCase {

    // MARK: - Reload bursts

    /// Fifty disk events in a burst list the folders once; the last note
    /// asked for is selected and every completion still runs, in order.
    @MainActor
    func testReloadBurstIsOneReloadWithEveryCompletion() {
        let url = FileManager.default.temporaryDirectory
        let project = Project(url: url, label: "test", isRoot: true)
        let first = Note(url: url.appendingPathComponent("a.md"), with: project)
        let last = Note(url: url.appendingPathComponent("b.md"), with: project)
        var reloads: [(Note?, Int)] = []
        var order: [Int] = []
        let done = expectation(description: "reload")
        let coalescer = ShellReloadCoalescer(window: 0.05) { note, completions in
            reloads.append((note, completions.count))
            for completion in completions { completion() }
            done.fulfill()
        }
        for index in 0..<50 {
            let note: Note? = index == 0 ? first : (index == 49 ? last : nil)
            coalescer.request(selecting: note) { order.append(index) }
        }
        XCTAssertTrue(reloads.isEmpty, "nothing runs inside the caller's turn")
        wait(for: [done], timeout: 2)
        XCTAssertEqual(reloads.count, 1)
        XCTAssertTrue(reloads.first?.0 === last)
        XCTAssertEqual(order, Array(0..<50))

        // The welcome note's completion selects the first row; a note asked
        // for after it is selected again once that has run (2026-11-22).
        var selected: [String] = []
        let burst = expectation(description: "welcome then import")
        let ordered = ShellReloadCoalescer(window: 0.01, select: { selected.append($0.url.lastPathComponent) }) { _, completions in
            for completion in completions { completion() }
            burst.fulfill()
        }
        ordered.request(selecting: nil) { selected.append("first row") }
        ordered.request(selecting: last) { selected.append("imported done") }
        wait(for: [burst], timeout: 2)
        XCTAssertEqual(selected, ["first row", "b.md", "imported done"])

        // A later burst gets its own reload.
        let again = expectation(description: "second")
        let second = ShellReloadCoalescer(window: 0.01) { _, _ in again.fulfill() }
        second.request(selecting: nil, completion: nil)
        wait(for: [again], timeout: 2)
        XCTAssertFalse(second.isScheduled)
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

    /// A note with damaged UTF-8 opens read-only, and Duplicate used to skip
    /// it without a word. It is copied with the bad bytes as U+FFFD, and the
    /// original file keeps its bytes.
    @MainActor
    func testDuplicateCopiesADamagedNoteAndLeavesItsFile() async throws {
        try await withShellLibrary(["damaged"]) { model, _, notes in
            let damaged = notes[0]
            var bytes = Data("# 你好世界".utf8)
            bytes.append(0xFF)
            bytes.append(Data("\n".utf8))
            try bytes.write(to: damaged.url)
            damaged.forceReload()
            XCTAssertTrue(damaged.loadFailed)

            model.duplicate([damaged])
            for _ in 0..<100 where model.notes.count < 2 { await Task.yield() }

            XCTAssertEqual(model.notes.count, 2, "the copy is listed")
            let copy = try XCTUnwrap(model.notes.first { $0.url != damaged.url })
            XCTAssertEqual(try String(contentsOf: copy.url, encoding: .utf8), "# 你好世界\u{FFFD}\n")
            XCTAssertEqual(try Data(contentsOf: damaged.url), bytes, "the original keeps its bytes")
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

    /// The header's mode buttons reached these while an export drove the
    /// preview itself, so a click midway captured the wrong pane.
    @MainActor
    func testModeSwitchesWaitForAnExport() {
        let previousPreview = UserDefaultsManagement.preview
        let previousSplit = UserDefaultsManagement.splitViewMode
        defer {
            UserDefaultsManagement.preview = previousPreview
            UserDefaultsManagement.splitViewMode = previousSplit
        }
        let model = ShellModel()
        let mode = model.editorMode
        model.isExporting = true

        model.togglePreview()
        model.toggleSplit()

        XCTAssertEqual(model.editorMode, mode)
    }

    /// The folders give way to the split preview, come back once it closes,
    /// and leave a choice made by hand alone.
    @MainActor
    func testTheFoldersGiveWayToTheSplitPreview() {
        let defaults = UserDefaults.standard
        let previousLayout = defaults.string(forKey: "ShellLayout")
        let previousPreview = UserDefaultsManagement.preview
        let previousSplit = UserDefaultsManagement.splitViewMode
        defer {
            defaults.set(previousLayout, forKey: "ShellLayout")
            UserDefaultsManagement.preview = previousPreview
            UserDefaultsManagement.splitViewMode = previousSplit
        }
        defaults.set("all", forKey: "ShellLayout")
        UserDefaultsManagement.preview = false
        UserDefaultsManagement.splitViewMode = false
        let model = ShellModel()

        XCTAssertEqual(model.layout, .all)
        model.toggleSplit()
        XCTAssertEqual(model.editorMode, .split)
        XCTAssertEqual(model.layout, .listAndNote)
        XCTAssertEqual(defaults.string(forKey: "ShellLayout"), "all", "giving way is not the saved layout")
        model.toggleSplit()
        XCTAssertEqual(model.layout, .all)

        // Shown again by hand in split, the folders stay.
        model.toggleSplit()
        model.toggleSidebar()
        XCTAssertEqual(model.layout, .all)
        model.toggleSplit()
        XCTAssertEqual(model.layout, .all)

        // Hidden by hand before, they stay hidden after.
        model.toggleSidebar()
        model.toggleSplit()
        model.toggleSplit()
        XCTAssertEqual(model.layout, .listAndNote)
    }

    /// A presentation started from split saved the layout split had hidden
    /// the folders in, so they never came back, not after split nor on the
    /// next launch (2026-11-22).
    @MainActor
    func testAPresentationFromSplitGivesTheFoldersBackAfterSplit() async throws {
        try await withShellLibrary(["deck"]) { model, _, notes in
            let previousPreview = UserDefaultsManagement.preview
            let previousSplit = UserDefaultsManagement.splitViewMode
            let previousPresentation = UserDefaultsManagement.presentation
            defer {
                UserDefaultsManagement.preview = previousPreview
                UserDefaultsManagement.splitViewMode = previousSplit
                UserDefaultsManagement.presentation = previousPresentation
            }
            UserDefaults.standard.set("all", forKey: "ShellLayout")
            model.clickNote(notes[0], modifiers: [])
            if model.layout != .all { model.toggleSidebar() }
            if model.editorMode == .split { model.toggleSplit() }

            model.toggleSplit()
            XCTAssertEqual(model.layout, .listAndNote)
            model.setPresenting(true)
            model.setPresenting(false)
            XCTAssertEqual(model.editorMode, .split)
            XCTAssertEqual(model.layout, .listAndNote, "split still holds the folders back")
            XCTAssertEqual(UserDefaults.standard.string(forKey: "ShellLayout"), "all", "the hidden layout is not saved")

            model.toggleSplit()
            XCTAssertEqual(model.layout, .all)
        }
    }

    /// Leaving preview put the editor back by a ratio of its scroll range,
    /// which first laid out the whole note (about 250 ms on a 1 MB note).
    /// It now goes back to the source line that was at the top, as the
    /// storyboard window does since 4ffec20d, laying out only as far as that
    /// line and one screen below it.
    @MainActor
    func testLeavingPreviewPutsTheEditorBackOnItsLineWithoutLayingOutTheNote() async throws {
        try await withShellLibrary(["long"]) { model, _, notes in
            let previousPreview = UserDefaultsManagement.preview
            let previousSplit = UserDefaultsManagement.splitViewMode
            defer {
                UserDefaultsManagement.preview = previousPreview
                UserDefaultsManagement.splitViewMode = previousSplit
            }
            let note = notes[0]
            let body = (1...3000).map { "Paragraph \($0) of a note long enough that laying all of it out shows." }.joined(separator: "\n\n")
            try body.write(to: note.url, atomically: true, encoding: .utf8)
            note.forceReload()
            note.loadModifiedLocalAt()
            model.clickNote(note, modifiers: [])
            if model.editorMode != .edit { model.setMode(.edit) }

            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let editor = model.editor
            editor.container.frame = window.contentLayoutRect
            window.contentView = editor.container
            editor.show(note)
            for _ in 0..<200 where editor.textView.storageNote !== note { await Task.yield() }
            XCTAssertTrue(editor.textView.storageNote === note)
            window.contentView?.layoutSubtreeIfNeeded()
            let textView = editor.textView
            let starts = ShellSplitMath.lineStarts(of: textView.string)
            let line = 400
            // Laid out to a few screens past the line, as a reader scrolling there would.
            let layout = try XCTUnwrap(textView.layoutManager)
            layout.ensureLayout(forCharacterRange: NSRange(location: 0, length: starts[line + 200]))
            let y = try XCTUnwrap(textView.documentY(ofSourceLine: line, fraction: 0, lineStarts: starts))
            editor.scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: y))
            editor.scrollView.reflectScrolledClipView(editor.scrollView.contentView)
            let before = try XCTUnwrap(textView.sourceLine(atDocumentY: editor.scrollView.contentView.bounds.origin.y, lineStarts: starts))
            XCTAssertEqual(before.line, line)

            model.setMode(.preview)
            // Away from the window the editor's layout is thrown out (a new
            // width, a font change), as after any change made in preview.
            let length = (textView.string as NSString).length
            layout.invalidateLayout(forCharacterRange: NSRange(location: 0, length: length), actualCharacterRange: nil)
            model.setMode(.edit)
            model.editorDidAppear()

            let after = try XCTUnwrap(textView.sourceLine(atDocumentY: editor.scrollView.contentView.bounds.origin.y, lineStarts: starts))
            XCTAssertEqual(after.line, before.line, "the editor opens on the line it showed")
            XCTAssertEqual(after.fraction, before.fraction, accuracy: 0.01)
            XCTAssertLessThan(layout.firstUnlaidCharacterIndex(), length / 2, "only the part above the line and one screen is laid out")
        }
    }

    private func urls(_ count: Int) -> [URL] {
        (0..<count).map { URL(fileURLWithPath: "/tmp/note-\($0).md") }
    }
}
