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
        FileManager.default.fileExists(atPath: url.path) && storage.allowedExtensions.contains(url.pathExtension) && storage.isValidUTI(url: url) && pathList.contains(url.deletingLastPathComponent().path)
    }

    private func importNote(_ url: URL) {
        let processedURL = url

        // Check if note already exists
        if let existingNote = storage.getBy(url: processedURL) {
            Task { @MainActor [weak self] in
                self?.handleExistingNote(existingNote)
            }
            return
        }

        // Validate project exists
        guard storage.getProjectBy(url: processedURL) != nil else { return }

        // Create and setup new note
        guard let note = storage.initNote(url: processedURL) else { return }
        note.load()
        note.loadModifiedLocalAt()
        storage.add(note)

        // Update UI
        Task { @MainActor [weak self] in
            self?.updateUIForNewNote(note)
        }

        // Handle special readme file
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
        guard let fsContent = note.getContent() else { return }

        let memoryContent = note.content.attributedSubstring(from: NSRange(0..<note.content.length))
        let contentChanged = fsContent.string != memoryContent.string

        guard contentChanged else { return }

        note.content = NSMutableAttributedString(attributedString: fsContent)
        delegate?.notesTableView.reloadRow(note: note)

        if EditTextView.note == note {
            delegate?.refillEditArea()
        }
    }

    public func restart() {
        watcher?.stop()
        start()
    }
}
