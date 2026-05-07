import Foundation

@MainActor
class FileSystemEventManager {
    private let storage: Storage
    private weak var delegate: ViewController?
    private var watcher: FileWatcher?
    private var observedFolders: [String] {
        storage.getProjectPaths()
    }

    init(storage: Storage, delegate: ViewController) {
        self.storage = storage
        self.delegate = delegate
    }

    public func start() {
        watcher = FileWatcher(observedFolders)
        watcher?.callback = { [weak self] event in
            Task { @MainActor in
                self?.handleFileSystemEvent(event)
            }
        }
        watcher?.start()
    }

    private func handleFileSystemEvent(_ event: FileWatcherEvent) {
        do {
            guard !UserDataService.instance.fsUpdatesDisabled else { return }

            guard let url = createURL(from: event.path) else {
                throw FileSystemError.invalidPath(event.path)
            }

            guard isValidFileType(url) else { return }

            let processedURL = url

            switch (
                event.fileRemoved || event.dirRemoved,
                event.fileRenamed || event.dirRenamed,
                event.fileCreated,
                event.fileChange
            ) {
            case (true, _, _, _):
                try handleFileRemoval(url: url)
            case (_, true, _, _):
                try handleFileMove(url: url)
            case (_, _, true, _):
                try handleFileCreation(url: processedURL)
            case (_, _, _, true):
                try handleFileChange(url: processedURL)
            default:
                break
            }
        } catch {
            AppDelegate.trackError(error, context: "FileSystemEventManager.handleEvent")
        }
    }

    enum FileSystemError: Error, LocalizedError {
        case invalidPath(String)
        case noteNotFound(URL)
        case importFailed(URL)
        case updateFailed(URL)

        var errorDescription: String? {
            switch self {
            case .invalidPath(let path):
                return "Invalid file path: \(path)"
            case .noteNotFound(let url):
                return "Note not found: \(url.lastPathComponent)"
            case .importFailed(let url):
                return "Failed to import note: \(url.lastPathComponent)"
            case .updateFailed(let url):
                return "Failed to update note: \(url.lastPathComponent)"
            }
        }
    }

    private func createURL(from path: String) -> URL? {
        guard let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "file://" + encodedPath)
    }

    private func isValidFileType(_ url: URL) -> Bool {
        storage.allowedExtensions.contains(url.pathExtension) && storage.isValidUTI(url: url)
    }

    private func handleFileRemoval(url: URL) throws {
        guard let note = storage.getBy(url: url) else {
            throw FileSystemError.noteNotFound(url)
        }
        removeNote(note: note)
    }

    private func handleFileMove(url: URL) throws {
        moveHandler(url: url, pathList: observedFolders)
    }

    private func handleFileCreation(url: URL) throws {
        guard checkFile(url: url, pathList: observedFolders) else {
            throw FileSystemError.importFailed(url)
        }
        importNote(url)
    }

    private func handleFileChange(url: URL) throws {
        guard let note = storage.getBy(url: url) else {
            throw FileSystemError.noteNotFound(url)
        }

        Task { @MainActor [weak self] in
            self?.reloadNote(note: note)
        }
    }

    private func moveHandler(url: URL, pathList: [String]) {
        let fileExistsInFS = checkFile(url: url, pathList: pathList)

        guard let note = storage.getBy(url: url) else {
            if fileExistsInFS {
                importNote(url)
            }
            return
        }

        if fileExistsInFS {
            Task { @MainActor [weak self] in
                self?.renameNote(note: note)
            }
        } else {
            removeNote(note: note)
        }
    }

    private func checkFile(url: URL, pathList: [String]) -> Bool {
        let parentPath = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        let resolvedPathList = pathList.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        return FileManager.default.fileExists(atPath: url.path)
            && storage.allowedExtensions.contains(url.pathExtension)
            && storage.isValidUTI(url: url)
            && resolvedPathList.contains(parentPath)
    }

    private func importNote(_ url: URL) {
        let processedURL = url

        if let existingNote = storage.getBy(url: processedURL) {
            Task { @MainActor [weak self] in
                self?.handleExistingNote(existingNote)
            }
            return
        }

        guard storage.getProjectBy(url: processedURL) != nil else { return }

        guard let note = storage.initNote(url: processedURL) else { return }
        note.load()
        note.loadModifiedLocalAt()
        storage.add(note)

        Task { @MainActor [weak self] in
            self?.updateUIForNewNote(note)
        }

        if note.name == "MiaoYan - Readme.md" {
            Task { @MainActor [weak self] in
                self?.handleReadmeFile(note)
            }
        }
    }

    @MainActor
    private func handleExistingNote(_ note: Note) {
        guard note.url == UserDataService.instance.focusOnImport else { return }

        delegate?.updateTable {
            self.delegate?.notesTableView.setSelected(note: note)
            UserDataService.instance.focusOnImport = nil
        }
    }

    @MainActor
    private func updateUIForNewNote(_ note: Note) {
        if let focusURL = UserDataService.instance.focusOnImport,
            let focusNote = storage.getBy(url: focusURL)
        {
            delegate?.updateTable {
                self.delegate?.notesTableView.setSelected(note: focusNote)
                UserDataService.instance.focusOnImport = nil
                self.delegate?.reloadSideBar()
            }
        } else {
            if !note.isTrash() {
                delegate?.notesTableView.insertNew(note: note)
            }
            delegate?.reloadSideBar()
        }
    }

    @MainActor
    private func handleReadmeFile(_ note: Note) {
        delegate?.updateTable {
            self.delegate?.notesTableView.selectRow(0)
            note.addPin()
            self.delegate?.reloadSideBar()
        }
    }

    @MainActor
    private func renameNote(note: Note) {
        if note.url == UserDataService.instance.focusOnImport {
            delegate?.updateTable {
                self.delegate?.notesTableView.setSelected(note: note)
                UserDataService.instance.focusOnImport = nil
            }
        } else {
            reloadNote(note: note)
        }
    }

    private func removeNote(note: Note) {
        storage.removeNotes(notes: [note], fsRemove: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self,
                    let delegate = self.delegate,
                    delegate.notesTableView.numberOfRows > 0
                else {
                    return
                }
                delegate.notesTableView.removeByNotes(notes: [note])
            }
        }
    }

    @MainActor
    private func reloadNote(note: Note) {
        // Skip reload while a debounced save is pending: the disk content
        // we'd read might be from before our save lands. Re-check shortly
        // after the save fires so a real external change is not lost.
        if note.hasPendingSave {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.recheckNote(note)
                }
            }
            return
        }

        guard let fsContent = note.getContent() else { return }

        let memoryContent = note.content.attributedSubstring(from: NSRange(0..<note.content.length))
        let contentChanged = fsContent.string != memoryContent.string

        guard contentChanged else { return }

        // Conflict-aware path for the active editor:
        // If this note is open and its editor body diverges from what we are
        // about to overwrite with disk content, write a backup so the user's
        // in-progress text is not silently destroyed by an external sync /
        // editor.
        if EditTextView.note == note,
            let editArea = delegate?.editArea
        {
            let editorString = editArea.string
            if editorString != fsContent.string {
                writeConflictBackup(for: note, editorContent: editorString)
                delegate?.toast(
                    message: I18n.str("External change detected. Local copy backed up~"),
                    style: .failure
                )
            }
        }

        note.content = NSMutableAttributedString(attributedString: fsContent)
        // The per-note UndoManager (Views/EditTextView.swift undo policy) is
        // tied to textStorage edits made within MiaoYan. After we replace
        // note.content with the disk version, any action still on that
        // manager points at pre-external-change state. Cmd-Z would happily
        // pop that state back into the editor, and the next debounced save
        // would write it to disk, silently undoing the external change. Wipe
        // the manager so undo can only target edits made *after* the merge.
        note.undoManager.removeAllActions()
        delegate?.notesTableView.reloadRow(note: note)

        if EditTextView.note == note {
            delegate?.refillEditArea(suppressSave: true)
        }
    }

    private func writeConflictBackup(for note: Note, editorContent: String) {
        // Conflicts must NOT live under the note's project directory:
        // the project is in `observedFolders` so FSEvents would re-fire for
        // our own write and import the backup as a brand-new note (with a
        // hideous .myNote-conflict-2026-... title cluttering the sidebar).
        // Instead route every project's conflicts to a single hidden
        // sibling of the storage root, which is never registered as a
        // project and therefore never observed.
        guard let storageRoot = UserDefaultsManagement.storageUrl else {
            let err = NSError(
                domain: "com.tw93.miaoyan.conflict",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "storageUrl unavailable, conflict backup skipped"])
            AppDelegate.trackError(err, context: "FileSystemEventManager.writeConflictBackup")
            return
        }

        let conflictsRoot = storageRoot.appendingPathComponent(".miaoyan-conflicts", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: conflictsRoot, withIntermediateDirectories: true)
        } catch {
            AppDelegate.trackError(error, context: "FileSystemEventManager.writeConflictBackup.createDir")
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let projectName = note.project.url.lastPathComponent
        let safeProject = projectName.replacingOccurrences(of: "/", with: "_")
        let base = note.url.deletingPathExtension().lastPathComponent
        let safeBase = base.replacingOccurrences(of: "/", with: "_")
        let backupURL = conflictsRoot.appendingPathComponent(
            "\(safeProject)-\(safeBase)-\(timestamp).\(note.url.pathExtension)")
        do {
            try editorContent.write(to: backupURL, atomically: true, encoding: .utf8)
            pruneOldConflictBackups(in: conflictsRoot)
        } catch {
            AppDelegate.trackError(error, context: "FileSystemEventManager.writeConflictBackup")
        }
    }

    /// Cap the conflict-backup directory so heavy sync setups (many small
    /// conflicts a day) don't grow the folder unboundedly. Retain the most
    /// recent N entries unconditionally, plus anything younger than `maxAge`.
    /// All other entries are removed best-effort.
    private func pruneOldConflictBackups(in directory: URL) {
        let keepCount = 100
        let maxAge: TimeInterval = 30 * 24 * 60 * 60  // 30 days

        let resourceKeys: [URLResourceKey] = [.contentModificationDateKey]
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles])
        else { return }

        struct Entry {
            let url: URL
            let mtime: Date
        }
        let entries: [Entry] = files.compactMap { url in
            guard
                let values = try? url.resourceValues(forKeys: Set(resourceKeys)),
                let mtime = values.contentModificationDate
            else { return nil }
            return Entry(url: url, mtime: mtime)
        }
        let sorted = entries.sorted { $0.mtime > $1.mtime }
        let cutoff = Date().addingTimeInterval(-maxAge)

        for (idx, entry) in sorted.enumerated() {
            // Always keep the newest `keepCount` entries.
            if idx < keepCount { continue }
            // For older entries beyond the cap, only delete those past
            // maxAge so a one-time burst of conflicts isn't immediately
            // pruned in the same session.
            if entry.mtime < cutoff {
                try? FileManager.default.removeItem(at: entry.url)
            }
        }
    }

    @MainActor
    public func recheckNote(_ note: Note) {
        reloadNote(note: note)
    }

    public func restart() {
        watcher?.stop()
        start()
    }
}
