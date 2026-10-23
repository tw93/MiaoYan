import AppKit
import MiaoYanCore

/// Folder commands for the shell sidebar: new, move, rename, delete, order.
@available(macOS 14, *)
extension ShellModel {
    var folders: [Project] {
        sidebarRows.compactMap { row in
            guard case .project(let url) = row.id else { return nil }
            return storage.getProjects().first { $0.url == url }
        }
    }

    var selectedFolder: Project? {
        guard case .project(let url) = scope else { return nil }
        return storage.getProjects().first { $0.url == url }
    }

    /// The storyboard window's New Folder and New Subfolder: a name sheet,
    /// then a folder under `parent`, or under the notes root.
    func promptNewFolder(parent: Project? = nil) {
        guard let window = host?.view.window else { return }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        field.focusRingType = .none
        field.placeholderString = I18n.str("Project name")
        let alert = MiaoYanAlert.make(
            message: I18n.str("New project"), style: .informational, buttons: [I18n.str("Add"), I18n.str("Cancel")])
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        MiaoYanAlert.softenTitle(of: alert)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.createFolder(named: field.stringValue, parent: parent)
        }
        DispatchQueue.main.async { field.becomeFirstResponder() }
    }

    func createFolder(named name: String, parent chosenParent: Project? = nil) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let parent = chosenParent ?? storage.getMainProject()
        // A new subfolder shows at once: a collapsed parent opens.
        if chosenParent != nil, !parent.isRoot, !isExpanded(parent.url) {
            expandedFolders.insert(parent.url)
        }
        let url = parent.url.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            MiaoYanAlert.show(message: error.localizedDescription, style: .warning, for: host?.view.window)
            return
        }
        _ = storage.add(project: Project(url: url, parent: parent))
        onFoldersChanged?()
        reload()
        scope = .project(url)
    }

    func promptMoveFolder(_ project: Project) {
        guard let window = host?.view.window, !project.isRoot, !project.isDefault, !project.isTrash else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = project.getParent().url
        panel.prompt = I18n.str("Move")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.moveFolder(project, to: destination)
                } catch {
                    AppDelegate.trackError(error, context: "ShellModel.moveFolder")
                    MiaoYanAlert.show(message: I18n.str(error.localizedDescription), style: .warning, for: window)
                }
            }
        }
    }

    func moveFolder(_ project: Project, to destination: URL) async throws {
        let oldURL = project.url
        let chosenFolder = selectedFolder
        let selected = selectedNotes
        let openNote = selectedNote
        let expanded = expandedFolders
        try await storage.moveFolder(project, to: destination)
        let moved = { Self.relocated($0, from: oldURL.path, to: project.url.path) }
        expandedFolders = Set(expanded.map(moved))
        var parent = project.parent
        while let folder = parent, !folder.isRoot {
            expandedFolders.insert(folder.url)
            parent = folder.parent
        }
        snippets.removeAll()
        if let chosenFolder { scope = .project(chosenFolder.url) }
        reload()
        selectedNoteURL = openNote?.url ?? selectedNoteURL.map(moved)
        extraSelectedURLs = Set(selected.filter { $0 !== openNote }.map(\.url))
        onFoldersChanged?()
    }

    /// Renames the folder on disk and moves its notes' URLs with it, as the
    /// storyboard sidebar does. Open subfolders stay open and a chosen one
    /// stays chosen, as after a move.
    func renameFolder(_ project: Project, to name: String) {
        renamingFolderURL = nil
        let oldURL = project.url
        let chosenFolder = selectedFolder
        let selected = selectedNotes
        let openNote = selectedNote
        let expanded = expandedFolders
        do {
            guard try storage.renameFolder(project, to: name) != nil else { return }
        } catch {
            MiaoYanAlert.show(message: I18n.str(error.localizedDescription), style: .warning, for: host?.view.window)
            return
        }
        let moved = { Self.relocated($0, from: oldURL.path, to: project.url.path) }
        expandedFolders = Set(expanded.map(moved))
        if let chosenFolder { scope = .project(chosenFolder.url) }
        onFoldersChanged?()
        reload()
        selectedNoteURL = openNote?.url ?? selectedNoteURL.map(moved)
        extraSelectedURLs = Set(selected.filter { $0 !== openNote }.map(\.url))
    }

    /// `url` under the folder's new path when it is the folder at `oldPath`
    /// or inside it; any other URL as it is.
    static func relocated(_ url: URL, from oldPath: String, to newPath: String) -> URL {
        guard url.path == oldPath || url.path.hasPrefix(oldPath + "/") else { return url }
        return URL(fileURLWithPath: newPath + url.path.dropFirst(oldPath.count))
    }

    /// Moves the folder and everything in it to the Trash after the same
    /// confirmation the storyboard sidebar asks for.
    func confirmDeleteFolder(_ project: Project) {
        guard !project.isDefault, !project.isRoot, !isExporting, let window = host?.view.window else { return }
        MiaoYanAlert.confirm(
            message: String(format: I18n.str("Move the folder \u{201C}%@\u{201D} and everything in it to the Trash?"), project.label),
            confirmTitle: I18n.str("Move to Trash"),
            for: window
        ) { [weak self] confirmed in
            guard confirmed, let self, let trashURL = self.storage.trashItem(url: project.url) else { return }
            do {
                try FileManager.default.moveItem(at: project.url, to: trashURL)
            } catch {
                AppDelegate.trackError(error, context: "ShellModel.deleteFolder.moveItem")
                return
            }
            self.storage.removeBy(project: project)
            self.onFoldersChanged?()
            // The storyboard sidebar clears the search with the folder.
            self.searchText = ""
            self.isSearchOpen = false
            if self.scope == .project(project.url) { self.scope = .all }
            self.reload()
        }
    }

    /// Moves notes into `project` with their attachments, the storyboard
    /// window's Move command and drag onto a folder.
    /// Notes that leave the list open their neighbour, as the storyboard's
    /// `move(notes:project:)` reselects the row at the same index.
    func move(_ moving: [Note], to project: Project) {
        guard !isPresenting, !isExporting else { return }
        let listed = notes.map(\.url)
        let open = selectedNoteURL
        let (projects, type) = scopeProjects()
        var gone = Set<URL>()
        var openAfter = open
        for note in moving where note.project != project {
            let oldURL = note.url
            note.move(toProject: project)
            note.invalidateCache()
            if oldURL == open { openAfter = note.url }
            if !Self.isInScope(note, projects: projects, type: type) { gone.insert(oldURL) }
        }
        if let open, gone.contains(open) {
            selectedNoteURL = Self.selection(afterRemoving: gone, from: listed, selected: open)
        } else {
            selectedNoteURL = openAfter
        }
        refreshNotes(keepSelection: true)
    }

    /// The storyboard's Move submenu: every folder storage knows, root and
    /// unexpanded subfolders included, except the note's own and the Trash.
    static func moveTargets(excluding current: Project, in projects: [Project]) -> [Project] {
        projects.filter { $0 != current && !$0.isTrash }
    }

    func moveTargets(for note: Note) -> [Project] {
        Self.moveTargets(excluding: note.project, in: storage.getProjects())
    }

    // MARK: - Folder order

    /// Top-level folders, in the order the sidebar shows them.
    private var topLevelFolderPaths: [String] {
        sidebarRows.compactMap { row in
            guard row.depth == 0, row.kind == .Category, case .project(let url) = row.id else { return nil }
            return url.path
        }
    }

    func isTopLevelFolder(_ url: URL) -> Bool {
        Self.listedPath(of: url, in: topLevelFolderPaths) != nil
    }

    /// The listed path `url` points at. A dragged folder arrives resolved
    /// while a library reached through a symlink lists unresolved paths, so
    /// both sides are resolved before they are compared.
    static func listedPath(of url: URL, in paths: [String]) -> String? {
        let resolved = url.resolvingSymlinksInPath().path
        return paths.first { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == resolved }
    }

    /// A top-level folder dragged onto another takes its place, saved under
    /// the storyboard sidebar's `SidebarProjectOrder` so both windows agree.
    @discardableResult
    func reorderFolder(_ source: URL, onto target: URL) -> Bool {
        let paths = topLevelFolderPaths
        guard let source = Self.listedPath(of: source, in: paths), let target = Self.listedPath(of: target, in: paths),
            let order = Self.reorderedFolders(paths, moving: source, onto: target)
        else { return false }
        UserDefaults.standard.set(order, forKey: "SidebarProjectOrder")
        reload()
        return true
    }

    static func reorderedFolders(_ paths: [String], moving source: String, onto target: String) -> [String]? {
        guard source != target, let from = paths.firstIndex(of: source), let to = paths.firstIndex(of: target) else { return nil }
        var order = paths
        order.remove(at: from)
        order.insert(source, at: to)
        return order
    }
}
