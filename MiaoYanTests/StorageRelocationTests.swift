import XCTest

@testable import MiaoYan

/// Renaming a folder moves everything under it; every registered subfolder
/// and every note below must follow, or their saves hit a path that is gone.
final class StorageRelocationTests: XCTestCase {

    @MainActor
    private func withMoveLibrary(storage suppliedStorage: Storage? = nil, _ body: (Storage, Project, Project, URL) async throws -> Void) async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanFolderMove-\(UUID().uuidString)")
        let rootURL = base.appendingPathComponent("Library", isDirectory: true)
        let sourceURL = rootURL.appendingPathComponent("Work", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL.appendingPathComponent("Nested"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootURL.appendingPathComponent("Archive"), withIntermediateDirectories: true)
        let storage = suppliedStorage ?? Storage(loadsLibrary: false)
        let root = Project(url: rootURL, isRoot: true, isDefault: true)
        _ = storage.add(project: root)
        let source = try XCTUnwrap(storage.getChildProjects(project: root).first { $0.url.path == sourceURL.path })
        _ = storage.subfolders(of: source)
        defer {
            let projects = storage.getProjects().filter { $0.url.path.hasPrefix(rootURL.path) }
            for project in projects {
                UserDefaults.standard.removeObject(forKey: project.url.path)
                storage.removeBy(project: project)
            }
            try? FileManager.default.removeItem(at: base)
        }
        try await body(storage, root, source, base)
    }

    @MainActor
    func testMovingFolderPreservesNotesAttachmentsHistoryAndSettings() async throws {
        try await withMoveLibrary { storage, root, source, _ in
            let nested = try XCTUnwrap(storage.getChildProjects(project: source).first)
            let url = nested.url.appendingPathComponent("note.md")
            try "unchanged body".write(to: url, atomically: true, encoding: .utf8)
            let note = Note(url: url, with: nested)
            note.content = NSMutableAttributedString(string: "unchanged body")
            storage.add(note)
            let editor = EditTextView(frame: .zero)
            editor.publishStorage(note.content, owner: note)
            let image = nested.url.appendingPathComponent("i/image.png")
            try FileManager.default.createDirectory(at: image.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: image)
            source.showInCommon = false
            source.saveSettings()
            nested.saveSettings()
            let oldSource = source.url
            let oldNested = nested.url
            let previousSelected = UserDefaultsManagement.lastSelectedURL
            let previousProject = UserDefaultsManagement.lastProjectPath
            UserDefaultsManagement.lastSelectedURL = note.url
            UserDefaultsManagement.lastProjectPath = nested.url.path
            let versions = AppEnvironment.current.versionManager
            versions.saveVersionIfNeeded(for: note, force: true)
            versions.waitForPendingWork()
            XCTAssertTrue(versions.hasVersions(for: note))
            defer {
                UserDefaultsManagement.lastSelectedURL = previousSelected
                UserDefaultsManagement.lastProjectPath = previousProject
                versions.removeVersions(for: note)
                versions.waitForPendingWork()
            }

            try await storage.moveFolder(source, to: root.url.appendingPathComponent("Archive"))
            versions.waitForPendingWork()

            let expected = root.url.appendingPathComponent("Archive/Work/Nested/note.md")
            XCTAssertEqual(note.url.path, expected.path)
            XCTAssertTrue(storage.getBy(url: expected) === note)
            XCTAssertTrue(editor.storageNote === note)
            XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "unchanged body")
            XCTAssertEqual(try Data(contentsOf: expected.deletingLastPathComponent().appendingPathComponent("i/image.png")), Data([1, 2, 3]))
            XCTAssertEqual(source.parent?.url.path, root.url.appendingPathComponent("Archive").path)
            XCTAssertTrue(nested.parent === source)
            XCTAssertTrue(note.project === nested)
            XCTAssertFalse(FileManager.default.fileExists(atPath: oldSource.path))
            XCTAssertNil(UserDefaults.standard.object(forKey: oldSource.path))
            XCTAssertNil(UserDefaults.standard.object(forKey: oldNested.path))
            XCTAssertEqual(UserDefaults.standard.dictionary(forKey: source.url.path)?["showInCommon"] as? Bool, false)
            XCTAssertEqual(UserDefaultsManagement.lastSelectedURL?.path, expected.path)
            XCTAssertEqual(UserDefaultsManagement.lastProjectPath, nested.url.path)
            XCTAssertEqual(versions.versions(for: note).count, 1)
            XCTAssertEqual(try String(contentsOf: XCTUnwrap(versions.versions(for: note).first?.url), encoding: .utf8), "unchanged body")
            XCTAssertFalse(storage.isMovingFolder)
        }
    }

    @MainActor
    func testPromotingFolderToLibraryRootUpdatesParent() async throws {
        try await withMoveLibrary { storage, root, source, _ in
            let nested = try XCTUnwrap(storage.getChildProjects(project: source).first)
            try await storage.moveFolder(nested, to: root.url)
            XCTAssertEqual(nested.url.path, root.url.appendingPathComponent("Nested").path)
            XCTAssertTrue(nested.parent === root)
            XCTAssertTrue(storage.getChildProjects(project: root).contains { $0 === nested })
            XCTAssertFalse(storage.getChildProjects(project: source).contains { $0 === nested })
        }
    }

    @MainActor
    func testMovingToCurrentParentDoesNothing() async throws {
        try await withMoveLibrary { storage, root, source, _ in
            let before = source.url
            try await storage.moveFolder(source, to: root.url)
            XCTAssertEqual(source.url, before)
            XCTAssertTrue(FileManager.default.fileExists(atPath: before.path))
            XCTAssertTrue(source.parent === root)
        }
    }

    @MainActor
    func testMovedFolderTreeKeepsRegisteredInstanceAndCanMoveAgain() async throws {
        try await withMoveLibrary { storage, root, source, _ in
            try await storage.moveFolder(source, to: root.url.appendingPathComponent("Archive"))
            let parent = try XCTUnwrap(source.parent)
            let rowProject = try XCTUnwrap(storage.subfolders(of: parent).first { $0.url.path == source.url.path })
            XCTAssertTrue(rowProject === source, "a sidebar refresh must not return an unregistered twin")
            try await storage.moveFolder(rowProject, to: root.url)
            XCTAssertEqual(source.url.path, root.url.appendingPathComponent("Work").path)
            XCTAssertTrue(source.parent === root)
        }
    }

    @MainActor
    func testReloadingMovedFolderKeepsOneInstanceOfEachNote() async throws {
        try await withMoveLibrary { storage, root, source, _ in
            let originalURL = source.url.appendingPathComponent("open.md")
            try "open note".write(to: originalURL, atomically: true, encoding: .utf8)
            storage.loadMissingNotes(for: source)
            let open = try XCTUnwrap(storage.getBy(url: originalURL))
            try await storage.moveFolder(source, to: root.url.appendingPathComponent("Archive"))
            try "new external note".write(to: source.url.appendingPathComponent("new.md"), atomically: true, encoding: .utf8)

            storage.loadMissingNotes(for: source)

            XCTAssertEqual(storage.noteList.count, 2)
            XCTAssertEqual(storage.noteList.filter { $0.url.path == open.url.path }.count, 1)
            XCTAssertTrue(storage.getBy(url: open.url) === open)
        }
    }

    @MainActor
    func testMovingFolderFlushesPendingSave() async throws {
        try await withMoveLibrary { storage, root, source, _ in
            let url = source.url.appendingPathComponent("pending.md")
            try "old body".write(to: url, atomically: true, encoding: .utf8)
            let note = Note(url: url, with: source)
            storage.add(note)
            note.save(attributed: NSAttributedString(string: "new body"))
            XCTAssertTrue(note.needsSave)
            try await storage.moveFolder(source, to: root.url.appendingPathComponent("Archive"))
            XCTAssertFalse(note.needsSave)
            XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "new body")
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            AppEnvironment.current.versionManager.removeVersions(for: note)
        }
    }

    @MainActor
    func testFolderMoveRejectsItselfDescendantsAndDestinationAliases() async throws {
        try await withMoveLibrary { storage, root, source, _ in
            let alias = root.url.appendingPathComponent("Alias")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source.url.appendingPathComponent("Nested"))
            for destination in [source.url, source.url.appendingPathComponent("Nested"), alias] {
                do {
                    try await storage.moveFolder(source, to: destination)
                    XCTFail("a folder cannot move into itself through any path")
                } catch {
                    XCTAssertEqual(error as? Storage.FolderMoveError, .descendant)
                }
                XCTAssertTrue(source.parent === root)
                XCTAssertTrue(FileManager.default.fileExists(atPath: source.url.path))
                XCTAssertFalse(storage.isMovingFolder)
            }
        }
    }

    @MainActor
    func testFolderMoveRejectsConflictWithoutOverwriting() async throws {
        try await withMoveLibrary { storage, root, source, _ in
            let destination = root.url.appendingPathComponent("Archive")
            let conflict = destination.appendingPathComponent("Work")
            try FileManager.default.createDirectory(at: conflict, withIntermediateDirectories: true)
            let sentinel = conflict.appendingPathComponent("keep.md")
            try "keep me".write(to: sentinel, atomically: true, encoding: .utf8)
            do {
                try await storage.moveFolder(source, to: destination)
                XCTFail("a destination with the same name must be preserved")
            } catch {
                XCTAssertEqual(error as? Storage.FolderMoveError, .conflict)
            }
            XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "keep me")
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.url.path))
            XCTAssertTrue(source.parent === root)
        }
    }

    @MainActor
    func testFolderMoveRejectsOutsideLibraryAndSymlinkEscape() async throws {
        try await withMoveLibrary { storage, root, source, base in
            let outside = base.appendingPathComponent("Outside")
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            let alias = root.url.appendingPathComponent("Escape")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: outside)
            for destination in [outside, alias] {
                do {
                    try await storage.moveFolder(source, to: destination)
                    XCTFail("a destination outside the library must not be accepted")
                } catch {
                    XCTAssertEqual(error as? Storage.FolderMoveError, .invalidDestination)
                }
            }
            XCTAssertTrue(source.parent === root)
            XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("Work").path))
        }
    }

    @MainActor
    func testFolderMoveRejectsProtectedDestinationsAndLibraryRoot() async throws {
        try await withMoveLibrary { storage, root, source, _ in
            for name in ["i", "files", ".Trash", ".hidden"] {
                let destination = root.url.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                do {
                    try await storage.moveFolder(source, to: destination)
                    XCTFail("protected folders must not become note destinations")
                } catch {
                    XCTAssertEqual(error as? Storage.FolderMoveError, .invalidDestination)
                }
            }
            do {
                try await storage.moveFolder(root, to: source.url)
                XCTFail("the library root must never be moved")
            } catch {
                XCTAssertEqual(error as? Storage.FolderMoveError, .protectedFolder)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.url.path))
        }
    }

    @MainActor
    func testFolderMoveRejectsFinderHiddenDestination() async throws {
        try await withMoveLibrary { storage, root, source, _ in
            var hidden = root.url.appendingPathComponent("HiddenByFinder")
            try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isHidden = true
            try hidden.setResourceValues(values)
            XCTAssertEqual(try hidden.resourceValues(forKeys: [.isHiddenKey]).isHidden, true)
            do {
                try await storage.moveFolder(source, to: hidden)
                XCTFail("a Finder-hidden destination must be rejected even without a dot prefix")
            } catch {
                XCTAssertEqual(error as? Storage.FolderMoveError, .invalidDestination)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.url.path))
        }
    }

    @MainActor
    func testFailedPendingSaveLeavesFolderAtOriginalPath() async throws {
        try await withMoveLibrary { storage, root, source, _ in
            let url = source.url.appendingPathComponent("missing.md")
            try "original".write(to: url, atomically: true, encoding: .utf8)
            let note = Note(url: url, with: source)
            storage.add(note)
            note.save(attributed: NSAttributedString(string: "pending content"))
            try FileManager.default.removeItem(at: url)
            let oldURL = source.url
            do {
                try await storage.moveFolder(source, to: root.url.appendingPathComponent("Archive"))
                XCTFail("a failed save must stop the directory move")
            } catch {
                XCTAssertEqual(error as? Storage.FolderMoveError, .unsavedChanges)
            }
            XCTAssertEqual(source.url, oldURL)
            XCTAssertTrue(source.parent === root)
            XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))
            XCTAssertTrue(note.needsSave)
            note.discardPendingSave()
        }
    }

    @MainActor
    func testSaveDuringRelocationKeepsNewContentUntilFinalPath() async throws {
        try await withMoveLibrary { storage, root, source, _ in
            let oldURL = source.url.appendingPathComponent("editing.md")
            try "original".write(to: oldURL, atomically: true, encoding: .utf8)
            let note = Note(url: oldURL, with: source)
            storage.add(note)
            note.isMovingWithFolder = true
            defer { note.isMovingWithFolder = false; note.discardPendingSave() }
            note.save(attributed: NSAttributedString(string: "edited during move"))
            XCTAssertFalse(note.flushPendingSave(globalStorage: false))
            XCTAssertEqual(try String(contentsOf: oldURL, encoding: .utf8), "original")
            XCTAssertTrue(note.needsSave)

            let target = root.url.appendingPathComponent("Archive/Work")
            try FileManager.default.moveItem(at: source.url, to: target)
            storage.relocateFolder(source, to: target)
            note.isMovingWithFolder = false
            XCTAssertTrue(note.flushPendingSave(globalStorage: false))
            XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "edited during move")
            XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
            AppEnvironment.current.versionManager.removeVersions(for: note)
        }
    }

    @available(macOS 14, *)
    @MainActor
    func testShellFolderMovePreservesOpenNoteInMultipleSelection() async throws {
        try await withMoveLibrary(storage: AppEnvironment.current.storage) { storage, root, source, _ in
            let previousSort = UserDefaultsManagement.sort
            let previousDirection = UserDefaultsManagement.sortDirection
            UserDefaultsManagement.sort = .title
            UserDefaultsManagement.sortDirection = false
            defer {
                UserDefaultsManagement.sort = previousSort
                UserDefaultsManagement.sortDirection = previousDirection
            }
            let firstURL = source.url.appendingPathComponent("first.md")
            let openURL = source.url.appendingPathComponent("open.md")
            try "first".write(to: firstURL, atomically: true, encoding: .utf8)
            try "open".write(to: openURL, atomically: true, encoding: .utf8)
            storage.loadMissingNotes(for: source)
            let first = try XCTUnwrap(storage.getBy(url: firstURL))
            let open = try XCTUnwrap(storage.getBy(url: openURL))
            let previousSelected = UserDefaultsManagement.lastSelectedURL
            let previousScope = UserDefaults.standard.object(forKey: "ShellScope")
            defer {
                UserDefaultsManagement.lastSelectedURL = previousSelected
                UserDefaults.standard.set(previousScope, forKey: "ShellScope")
            }
            let model = ShellModel()
            model.scope = .project(source.url)
            model.reload()
            for _ in 0..<100 where model.notes.count < 2 { await Task.yield() }
            XCTAssertEqual(model.notes.count, 2)
            model.clickNote(open, modifiers: [])
            model.clickNote(first, modifiers: .command)
            XCTAssertTrue(model.selectedNote === open)
            XCTAssertTrue(model.selectedNotes.first === first)

            try await model.moveFolder(source, to: root.url.appendingPathComponent("Archive"))
            for _ in 0..<100 where model.notes.count < 2 { await Task.yield() }

            XCTAssertEqual(model.selectedNoteURL?.path, open.url.path)
            XCTAssertTrue(model.selectedNote === open)
            XCTAssertTrue(model.isSelected(first))
            XCTAssertTrue(model.isSelected(open))
            XCTAssertEqual(model.scope, .project(source.url))
        }
    }

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

    @MainActor
    func testRenamingAFolderKeepsItsSettingsAndRejectsBadNames() async throws {
        try await withMoveLibrary { storage, _, source, _ in
            let nested = try XCTUnwrap(storage.getChildProjects(project: source).first)
            source.showInCommon = false
            source.saveSettings()
            let previousSelected = UserDefaultsManagement.lastSelectedURL
            let previousProject = UserDefaultsManagement.lastProjectPath
            defer {
                UserDefaultsManagement.lastSelectedURL = previousSelected
                UserDefaultsManagement.lastProjectPath = previousProject
            }
            let selected = nested.url.appendingPathComponent("note.md")
            UserDefaultsManagement.lastSelectedURL = selected
            UserDefaultsManagement.lastProjectPath = nested.url.path
            let oldPath = source.url.path

            XCTAssertNil(try storage.renameFolder(source, to: "  "))
            XCTAssertNil(try storage.renameFolder(source, to: source.url.lastPathComponent))
            XCTAssertNil(try storage.renameFolder(source, to: "Archive/Work"))
            XCTAssertEqual(source.url.path, oldPath)

            let renamed = try XCTUnwrap(try storage.renameFolder(source, to: " Jobs "))
            XCTAssertEqual(renamed.lastPathComponent, "Jobs")
            XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
            XCTAssertNil(UserDefaults.standard.object(forKey: oldPath))
            source.showInCommon = true
            source.loadSettings()
            XCTAssertFalse(source.showInCommon, "per-folder settings follow the new path")
            XCTAssertEqual(UserDefaultsManagement.lastSelectedURL?.path, renamed.appendingPathComponent("Nested/note.md").path)
            XCTAssertEqual(UserDefaultsManagement.lastProjectPath, renamed.appendingPathComponent("Nested").path)
        }
    }
}
