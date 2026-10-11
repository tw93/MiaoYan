import AppKit
import MiaoYanCore
import Observation

/// State behind the SwiftUI shell: which folder is chosen, what the list
/// shows and which note is open. It reads the same `Storage` the AppKit
/// window reads and scopes, searches and sorts notes by the same rules.
@available(macOS 14, *)
@MainActor
@Observable
final class ShellModel {
    enum Scope: Hashable {
        case all
        case project(URL)
        case trash
    }

    struct SidebarRow: Identifiable, Hashable {
        let id: Scope
        let title: String
        let kind: SidebarItemType
        /// How deep a subfolder sits under its top-level folder.
        var depth = 0
        var hasChildren = false
    }

    /// Folders showing their subfolders, as the storyboard outline keeps
    /// rows expanded while the app runs.
    private(set) var expandedFolders: Set<URL> = []

    /// Collapsing a folder whose subfolder is chosen chooses the folder.
    func toggleExpanded(_ url: URL) {
        if expandedFolders.remove(url) != nil {
            if case .project(let chosen) = scope, chosen.path.hasPrefix(url.path.hasSuffix("/") ? url.path : url.path + "/") {
                scope = .project(url)
            }
        } else {
            expandedFolders.insert(url)
        }
        reload()
    }

    /// Right and left arrows open and close the chosen folder.
    func setChosenFolderExpanded(_ expanded: Bool) {
        guard case .project(let url) = scope,
            sidebarRows.first(where: { $0.id == scope })?.hasChildren == true,
            expandedFolders.contains(url) != expanded
        else { return }
        toggleExpanded(url)
    }

    /// A run of notes under one date heading; `title` is nil for pinned
    /// notes and for lists that are not sorted by date.
    struct NoteSection: Identifiable {
        let id: String
        let title: String?
        let notes: [Note]
    }

    enum EditorMode {
        case edit
        case preview
        case split
    }

    /// The old window's list button cycles through the same three layouts:
    /// hide the folders, then the list, then bring them back in reverse.
    enum Layout: String {
        case all
        case listAndNote
        case noteOnly
    }

    private(set) var sidebarRows: [SidebarRow] = []
    private(set) var notes: [Note] = []
    private(set) var sections: [NoteSection] = []
    /// Plain-text openings for list rows, read off the main thread on demand.
    private(set) var snippets: [URL: String] = [:]
    private(set) var layout = Layout.all {
        didSet {
            // A presentation's note-only layout is not the user's.
            guard !isPresenting else { return }
            UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutKey)
        }
    }
    /// What the note column shows: the editor, the preview, or both. Kept
    /// in the same preferences the storyboard window restores its mode from.
    private(set) var editorMode = EditorMode.edit {
        didSet {
            UserDefaultsManagement.preview = editorMode == .preview
            UserDefaultsManagement.splitViewMode = editorMode == .split
        }
    }
    /// Bumped after each edit lands in the note; a visible preview follows it.
    private(set) var contentRevision = 0
    private(set) var isPresenting = false
    @ObservationIgnored private var modeBeforePresenting = EditorMode.preview
    @ObservationIgnored private var layoutBeforePresenting = Layout.all
    @ObservationIgnored let editor = ShellEditorController()
    /// Where toasts appear; set by the window's split controller.
    @ObservationIgnored weak var host: NSViewController?
    @ObservationIgnored private var previewTimer: Timer?
    @ObservationIgnored private var isUnfolding = false
    @ObservationIgnored private var pendingSnippets: Set<URL> = []

    var scope: Scope = .all {
        didSet {
            guard scope != oldValue else { return }
            if !isSingleMode { UserDefaults.standard.set(scope.storedValue, forKey: Self.scopeKey) }
            refreshNotes(keepSelection: false)
        }
    }

    /// The folder and layout come back at the next launch, as the storyboard
    /// window's sidebar row and collapsed columns do.
    private static let scopeKey = "ShellScope"
    private static let layoutKey = "ShellLayout"

    private func storedScope() -> Scope {
        // First shell launch: start on the folder the storyboard window left.
        if UserDefaults.standard.string(forKey: Self.scopeKey) == nil,
            let path = UserDefaultsManagement.lastProjectPath,
            let project = storage.getProjects().first(where: { $0.url.path == path })
        {
            return .project(project.url)
        }
        switch UserDefaults.standard.string(forKey: Self.scopeKey) {
        case "trash": return .trash
        case let path? where path != "all":
            return storage.getProjects().first { $0.url.path == path }.map { .project($0.url) } ?? .all
        default: return .all
        }
    }

    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleRefresh()
        }
    }

    var selectedNoteURL: URL? {
        didSet {
            // Moving the selection any other way (arrows, new note, a link)
            // ends a multiple selection, as in the storyboard list.
            if !isExtendingSelection, selectedNoteURL != oldValue { extraSelectedURLs = [] }
            guard let url = selectedNoteURL, url != oldValue else { return }
            UserDefaultsManagement.lastSelectedURL = url
        }
    }

    /// Notes selected besides the open one, by Command- or Shift-click. The
    /// open note stays the one the editor and preview show.
    private(set) var extraSelectedURLs: Set<URL> = []
    @ObservationIgnored private var isExtendingSelection = false

    func isSelected(_ note: Note) -> Bool {
        note.url == selectedNoteURL || extraSelectedURLs.contains(note.url)
    }

    /// The open note plus any others selected with it, in list order.
    var selectedNotes: [Note] {
        notes.filter { isSelected($0) }
    }

    /// A click in the list: plain selects one note, Command adds or removes
    /// it, Shift selects the run from the open note to it.
    func clickNote(_ note: Note, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift), let anchor = notes.firstIndex(where: { $0.url == selectedNoteURL }),
            let target = notes.firstIndex(where: { $0 === note })
        {
            let run = notes[min(anchor, target)...max(anchor, target)].map(\.url)
            extraSelectedURLs = Set(run).subtracting([selectedNoteURL].compactMap { $0 })
            return
        }
        if modifiers.contains(.command), selectedNoteURL != nil {
            if note.url == selectedNoteURL {
                // Removing the open note opens another selected one instead.
                guard let next = notes.first(where: { extraSelectedURLs.contains($0.url) }) else { return }
                isExtendingSelection = true
                selectedNoteURL = next.url
                isExtendingSelection = false
                extraSelectedURLs.remove(next.url)
            } else if extraSelectedURLs.contains(note.url) {
                extraSelectedURLs.remove(note.url)
            } else {
                extraSelectedURLs.insert(note.url)
            }
            return
        }
        selectedNoteURL = note.url
        extraSelectedURLs = []
    }

    /// What a context-menu command acts on: the whole selection when the
    /// clicked note is part of it, otherwise just that note.
    func notesForMenu(on note: Note) -> [Note] {
        isSelected(note) ? selectedNotes : [note]
    }

    var selectedNote: Note? {
        guard let url = selectedNoteURL else { return nil }
        return notes.first { $0.url == url }
    }

    @ObservationIgnored private let storage = AppEnvironment.current.storage
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init() {
        selectedNoteURL = UserDefaultsManagement.lastSelectedURL
        scope = storedScope()
        layout = UserDefaults.standard.string(forKey: Self.layoutKey).flatMap(Layout.init(rawValue:)) ?? .all
        if UserDefaultsManagement.preview {
            editorMode = .preview
        } else if UserDefaultsManagement.splitViewMode {
            editorMode = .split
        }
        // A presentation is never resumed at launch, as in the storyboard window.
        UserDefaultsManagement.presentation = false
        UserDefaultsManagement.magicPPT = false
        reload()
        rebuildLinkIndex()
        editor.onContentChange = { [weak self] in self?.scheduleContentRevision() }
    }

    /// Backlinks cover every note; the index reads unloaded bodies itself.
    private func rebuildLinkIndex() {
        AppEnvironment.current.wikilinkIndex.rebuildFromAllNotes(in: storage)
    }

    /// The preview re-renders at most this often while typing, by the same
    /// document-length tiers the storyboard window uses.
    private func scheduleContentRevision() {
        previewTimer?.invalidate()
        guard editorMode == .split, let note = EditTextView.note else { return }
        let lines = note.content.string.utf8.reduce(1) { $1 == 10 ? $0 + 1 : $0 }
        let delay: TimeInterval = lines < 500 ? 0.3 : lines < 1500 ? 0.6 : 1.0
        previewTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.contentRevision &+= 1 }
        }
    }

    /// Rebuilds the sidebar from storage, then the list.
    func reload() {
        var rows: [SidebarRow] = []
        func addFolder(_ project: Project, title: String, depth: Int) {
            let children = storage.subfolders(of: project)
            rows.append(SidebarRow(id: .project(project.url), title: title, kind: .Category, depth: depth, hasChildren: !children.isEmpty))
            guard expandedFolders.contains(project.url) else { return }
            for child in children {
                addFolder(child, title: child.label, depth: depth + 1)
            }
        }
        for item in Sidebar().getList() {
            guard let item = item as? SidebarItem else { continue }
            switch item.type {
            case .All:
                rows.append(SidebarRow(id: .all, title: item.getName(), kind: .All))
            case .Trash:
                rows.append(SidebarRow(id: .trash, title: item.getName(), kind: .Trash))
            case .Category:
                guard let project = item.project, project.showInSidebar else { continue }
                addFolder(project, title: item.getName(), depth: 0)
            }
        }
        sidebarRows = rows
        if !sidebarRows.contains(where: { $0.id == scope }) {
            scope = .all
        }
        refreshNotes(keepSelection: true)
    }

    func selectNext(_ offset: Int) {
        guard !notes.isEmpty else { return }
        let current = notes.firstIndex { $0.url == selectedNoteURL } ?? (offset > 0 ? -1 : notes.count)
        let next = min(max(current + offset, 0), notes.count - 1)
        selectedNoteURL = notes[next].url
    }

    func cycleLayout() {
        guard !isPresenting else { return }
        switch layout {
        case .all:
            layout = .listAndNote
            isUnfolding = false
        case .listAndNote:
            layout = isUnfolding ? .all : .noteOnly
            isUnfolding = false
        case .noteOnly:
            layout = .listAndNote
            isUnfolding = true
        }
    }

    /// ⌘1: the folders column on or off.
    func toggleSidebar() {
        guard !isPresenting else { return }
        layout = layout == .all ? .listAndNote : .all
    }

    /// ⌘2: the note list on or off; showing it again keeps the folders hidden.
    func toggleNoteList() {
        guard !isPresenting else { return }
        layout = layout == .noteOnly ? .listAndNote : .noteOnly
    }

    func cleanTypography() {
        guard let host else { return }
        guard editorMode != .preview else {
            host.toast(message: I18n.str("Format is only possible after exiting preview mode~"), style: .failure)
            return
        }
        editor.cleanTypography(in: host)
    }

    /// The list's heading: the chosen folder's name.
    var scopeTitle: String {
        sidebarRows.first { $0.id == scope }?.title ?? ""
    }

    /// Bear-style dates: today and yesterday by name with the time, this
    /// year's by month and day, older ones with the year.
    static func rowDate(for note: Note) -> String {
        let date =
            (UserDefaultsManagement.sort == .creationDate || note.project.sortBy == .creationDate
                ? note.creationDate : nil) ?? note.modifiedLocalAt
        let calendar = Calendar.current
        if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) {
            return relativeFormatter.string(from: date)
        }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return monthDayFormatter.string(from: date)
        }
        return fullDateFormatter.string(from: date)
    }

    private static let displayLocale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")

    private static let relativeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter
    }()

    func togglePreview() {
        guard !isPresenting else { return }
        editorMode = editorMode == .preview ? .edit : .preview
    }

    func toggleSplit() {
        guard !isPresenting else { return }
        editorMode = editorMode == .split ? .edit : .split
    }

    func format() {
        guard let host else { return }
        guard editorMode != .preview else {
            host.toast(message: I18n.str("Format is only possible after exiting preview mode~"), style: .failure)
            return
        }
        editor.format(in: host)
    }

    /// Whether the running presentation is a MiaoYan PPT deck.
    private(set) var isPPT = false

    /// Presentation shows only the preview, full screen, at the presentation
    /// font size; `ppt` renders the note as a Reveal.js deck split on `---`
    /// instead. The window controller handles the full-screen half.
    func setPresenting(_ presenting: Bool, ppt: Bool = false) {
        guard presenting != isPresenting, selectedNote != nil || !presenting else { return }
        if presenting {
            if ppt {
                guard let note = selectedNote else { return }
                note.ensureContentLoaded()
                guard note.content.string.contains("---") else {
                    host?.toast(message: I18n.str("No delimiter --- identification, Cannot use MiaoYan PPT~"), style: .failure)
                    return
                }
            }
            modeBeforePresenting = editorMode
            layoutBeforePresenting = layout
            // Preview, presentation and PPT are one stored mode, and switching
            // the column to preview writes "preview"; set the presentation
            // mode after it or the preview write replaces it.
            editorMode = .preview
            if ppt {
                UserDefaultsManagement.magicPPT = true
            } else {
                UserDefaultsManagement.presentation = true
            }
            isPPT = ppt
            isPresenting = true
            layout = .noteOnly
            // The stylesheet (presentation size, deck template) changed.
            previewStyleRevision &+= 1
            if ppt { openDeckAtCursor() }
        } else {
            UserDefaultsManagement.presentation = false
            UserDefaultsManagement.magicPPT = false
            isPresenting = false
            isPPT = false
            layout = layoutBeforePresenting
            editorMode = modeBeforePresenting
            previewStyleRevision &+= 1
        }
    }

    /// The storyboard window's PPT entry: when the preview follows the editing
    /// position, open on the slide the cursor is in, and give the deck focus
    /// so the arrow keys and space turn pages.
    private func openDeckAtCursor() {
        let text = editor.textView.string
        let cursor = max(min(editor.textView.selectedRange().location, text.count) - 1, 0)
        let slide = text.prefix(cursor).components(separatedBy: "---").count - 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let preview = self?.preview else { return }
            preview.runWhenPreviewReady {
                if UserDefaultsManagement.previewLocation == "Editing", slide > 0 {
                    preview.slideTo(index: slide)
                }
                preview.window?.makeFirstResponder(preview)
            }
        }
    }

    // MARK: - Note commands

    /// The list's search field is open; menu search and new-note flows open it.
    var isSearchOpen = false
    /// The note whose title is being edited. Tied to that note, not to a flag:
    /// a flag was cleared by the selection change that new-note and the
    /// context menu's Rename make just before opening the field, and the
    /// commit then renamed whatever was selected by then.
    var renamingNoteURL: URL?
    /// The note header's title is an editable field.
    var isRenaming: Bool {
        get { renamingNoteURL != nil && renamingNoteURL == selectedNoteURL }
        set { renamingNoteURL = newValue ? selectedNoteURL : nil }
    }
    /// The preview currently on screen, for commands that act on it (TOC).
    @ObservationIgnored weak var preview: MPreviewView?

    /// The folder a new note goes into: the chosen folder, else the root.
    private var targetProject: Project? {
        if case .project(let url) = scope, let project = storage.getProjects().first(where: { $0.url == url }) {
            return project
        }
        return storage.getRootProject() ?? storage.getProjects().first
    }

    /// A new empty note in the chosen folder, opened in the editor with its
    /// title ready to type.
    /// `miaoyan://make` passes a name and text; the title is then already set.
    func createNote(name: String = "", content: String = "") {
        if isPresenting, !name.isEmpty || !content.isEmpty { setPresenting(false) }
        guard !isPresenting, let project = targetProject else { return }
        let note = Note(name: name, project: project)
        note.content = NSMutableAttributedString(string: content)
        note.save()
        searchText = ""
        isSearchOpen = false
        if scope == .trash { scope = .all }
        if editorMode == .preview { editorMode = .edit }
        selectedNoteURL = note.url
        refreshNotes(keepSelection: true)
        isRenaming = name.isEmpty
    }

    /// Attachments no note refers to, moved to the Trash after a confirm.
    func cleanUnusedAttachments() {
        storage.findOrphanAttachments { [weak self] orphans in
            guard let self, let host = self.host else { return }
            guard let orphans else {
                host.toast(message: I18n.str("Some notes could not be read, so no attachments were cleaned"), style: .failure)
                return
            }
            guard !orphans.isEmpty else {
                host.toast(message: I18n.str("No orphan attachments found"))
                return
            }
            MiaoYanAlert.confirm(
                message: I18n.str("Clean Orphan Attachments"),
                informativeText: String(format: I18n.str("Detected %d unused attachment(s). Move them to Trash?"), orphans.count),
                confirmTitle: I18n.str("Clean"),
                for: host.view.window
            ) { confirmed in
                guard confirmed else { return }
                let result = self.storage.removeAttachments(urls: orphans)
                if !result.removed.isEmpty {
                    NSSound(named: "Pop")?.play()
                    host.toast(message: String(format: I18n.str("Removed %d unused attachment(s)"), result.removed.count), style: .success)
                }
                if !result.failed.isEmpty {
                    MiaoYanAlert.show(
                        message: I18n.str("Some attachments could not be removed"),
                        informativeText: I18n.str("Please try again"),
                        style: .warning,
                        for: host.view.window
                    )
                }
            }
        }
    }

    // MARK: - Links

    /// A wikilink or `miaoyan://goto/<title>`: the note with that title. Two
    /// or more are listed as search results; none is reported.
    func openNote(titled title: String) {
        let matches = storage.noteList.filter { $0.title == title && !$0.isTrash() }
        guard matches.count == 1, let note = matches.first else {
            if matches.isEmpty {
                host?.toast(message: I18n.str("Please make sure your title exists~"), style: .failure)
            } else {
                search(for: title)
                host?.toast(message: I18n.str("Found that there are multiple titles of this~"), style: .failure)
            }
            return
        }
        if isPresenting { setPresenting(false) }
        searchText = ""
        isSearchOpen = false
        if !notes.contains(where: { $0 === note }) { scope = .all }
        refreshNow(selecting: note.url)
    }

    /// `miaoyan://find/<query>`: the search field opened on that query.
    func search(for query: String) {
        if scope == .trash { scope = .all }
        isSearchOpen = true
        searchText = query
    }

    /// Moves the open note to the Trash, recoverable as everywhere else, and
    /// opens its neighbour.
    func deleteSelectedNote() {
        guard !isPresenting, let note = selectedNote, !note.isTrash() else { return }
        let index = notes.firstIndex { $0 === note } ?? 0
        let removing = selectedNotes.filter { !$0.isTrash() }
        storage.removeNotes(
            notes: removing,
            partialFailure: { [weak self] count in
                Task { @MainActor in
                    self?.host?.toast(
                        message: String(format: I18n.str("Failed to move %d note(s) to Trash~"), count), style: .failure)
                }
            }
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let remaining = self.notes.filter { candidate in !removing.contains { $0 === candidate } }
                self.selectedNoteURL = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].url
                self.refreshNotes(keepSelection: true)
            }
        }
    }

    /// Renames the open note's file after `title`; false when that name is taken.
    @discardableResult
    func rename(_ note: Note, to title: String) -> Bool {
        let title = title.trimmingCharacters(in: .newlines)
        guard !title.isEmpty, title != note.getFileName() else { return true }
        guard note.renameFile(to: title) else {
            MiaoYanAlert.show(
                message: I18n.str("Please change the title"),
                informativeText: String(format: I18n.str("This %@ under this folder already exists!"), title),
                for: host?.view.window)
            return false
        }
        selectedNoteURL = note.url
        refreshNotes(keepSelection: true)
        return true
    }

    /// Pins or unpins the note, or every selected note when it is part of a
    /// multiple selection, all to the clicked note's new state.
    func togglePin(_ note: Note) {
        let group = notesForMenu(on: note)
        let pin = !note.isPinned
        for each in group where each.isPinned != pin {
            each.togglePin()
        }
        refreshNotes(keepSelection: true)
    }

    func setSort(_ sort: SortBy) {
        UserDefaultsManagement.sort = sort
        refreshNotes(keepSelection: true)
    }

    func setSortDescending(_ descending: Bool) {
        UserDefaultsManagement.sortDirection = descending
        refreshNotes(keepSelection: true)
    }

    /// Re-reads the list, keeping the open note, and runs `completion` once
    /// the new list is in place.
    func refreshNow(selecting url: URL? = nil, completion: (() -> Void)? = nil) {
        if let url { selectedNoteURL = url }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.computeNotes(keepSelection: true)
            completion?()
        }
    }

    /// A note changed on disk: drop its cached opening and redraw.
    func noteChangedOnDisk(_ note: Note) {
        snippets[note.url] = nil
        if selectedNoteURL == note.url {
            contentRevision &+= 1
        }
    }

    // MARK: - Import and single-file mode

    /// Set while the window shows one opened file or folder instead of the
    /// library.
    private(set) var isSingleMode = false
    /// The library note to come back to; the editor records every note it
    /// opens as the last selected one, single-mode files included.
    @ObservationIgnored private var librarySelection: URL?

    /// Copies picked files into the main folder and opens the last one; a
    /// file already in the library is opened instead. The copies are added
    /// to storage here: an APFS clone reaches the file watcher as a change,
    /// not a creation, so it would never list them.
    func importNotes(_ urls: [URL]) {
        var target: URL?
        for url in urls {
            if let note = storage.getBy(url: url) {
                target = note.url
                continue
            }
            let copy = ViewController.copyFile(url, into: storage.getMainProject())
            guard storage.getBy(url: copy) == nil, let note = storage.initNote(url: copy) else { continue }
            note.load()
            note.loadModifiedLocalAt()
            storage.add(note)
            target = note.url
        }
        searchText = ""
        isSearchOpen = false
        scope = .all
        refreshNow(selecting: target)
    }

    /// Shows only `url`: a file with the notes beside it, or a folder.
    func openSingle(_ url: URL, siblingFiles: [URL]? = nil) {
        if !isSingleMode { librarySelection = selectedNoteURL }
        UserDefaultsManagement.beginSingleMode(for: url)
        storage.reconfigureForSingleMode(originalFileURL: url, siblingFiles: siblingFiles)
        isSingleMode = true
        let file = FileManager.default.directoryExists(atUrl: url) ? nil : url.resolvingSymlinksInPath()
        switchStorage(selecting: file)
        host?.toast(message: I18n.str("In single open mode, Exit with Command+Shift+W ~"))
    }

    /// Back to the library, on the note that was open before.
    func closeSingle() {
        guard isSingleMode else { return }
        UserDefaultsManagement.clearSingleMode()
        storage.reconfigureForLibrary()
        isSingleMode = false
        switchStorage(selecting: librarySelection, scope: storedScope())
    }

    private func switchStorage(selecting url: URL?, scope newScope: Scope = .all) {
        if isPresenting { setPresenting(false) }
        searchText = ""
        isSearchOpen = false
        snippets.removeAll()
        selectedNoteURL = url
        scope = newScope
        reload()
        rebuildLinkIndex()
        onFoldersChanged?()
    }

    // MARK: - Folders

    /// The folder whose name is being edited in the sidebar.
    var renamingFolderURL: URL?
    /// Called after folders change on disk, so the file watcher can follow.
    @ObservationIgnored var onFoldersChanged: (() -> Void)?

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
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.createFolder(named: field.stringValue, parent: parent)
        }
        DispatchQueue.main.async { field.becomeFirstResponder() }
    }

    func createFolder(named name: String, parent: Project? = nil) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let parent = parent ?? storage.getMainProject()
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

    /// Renames the folder on disk and moves its notes' URLs with it, as the
    /// storyboard sidebar does.
    func renameFolder(_ project: Project, to name: String) {
        renamingFolderURL = nil
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != project.url.lastPathComponent else { return }
        let oldURL = project.url
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            MiaoYanAlert.show(message: error.localizedDescription, style: .warning, for: host?.view.window)
            return
        }
        storage.relocateFolder(project, to: newURL)
        onFoldersChanged?()
        let wasSelected = scope == .project(oldURL)
        reload()
        if wasSelected { scope = .project(newURL) }
    }

    /// Moves the folder and everything in it to the Trash after the same
    /// confirmation the storyboard sidebar asks for.
    func confirmDeleteFolder(_ project: Project) {
        guard !project.isDefault, !project.isRoot, let window = host?.view.window else { return }
        MiaoYanAlert.confirm(
            message: String(format: I18n.str("Are you sure you want to remove project \"%@\" and all files inside?"), project.label),
            informativeText: I18n.str("This action cannot be undone."),
            confirmTitle: I18n.str("Remove"),
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
            if self.scope == .project(project.url) { self.scope = .all }
            self.reload()
        }
    }

    /// Moves notes into `project` with their attachments, the storyboard
    /// window's Move command and drag onto a folder.
    func move(_ moving: [Note], to project: Project) {
        let open = selectedNote
        for note in moving where note.project != project {
            note.move(toProject: project)
            note.invalidateCache()
        }
        if let open, moving.contains(where: { $0 === open }) {
            selectedNoteURL = open.url
        }
        refreshNotes(keepSelection: true)
    }

    // MARK: - Note utilities

    /// Bumped when the preview's stylesheet changes (font size, font face),
    /// so the preview reloads instead of patching its content.
    private(set) var previewStyleRevision = 0

    /// Editor and preview fonts changed: re-render both with the new sizes.
    /// Bumped when the interface font changes, which the sidebar and list
    /// read straight from UserDefaults; they rebuild on it. Other settings
    /// leave it alone, since a rebuild also resets the list's scroll.
    var interfaceRevision = 0
    @ObservationIgnored private var interfaceFont = UserDefaultsManagement.windowFontName

    func applyEditorSettings() {
        if let note = EditTextView.note, editor.textView.storageNote === note {
            editor.reload(note)
        }
        previewStyleRevision &+= 1
        if UserDefaultsManagement.windowFontName != interfaceFont {
            interfaceFont = UserDefaultsManagement.windowFontName
            interfaceRevision &+= 1
        }
        // Settings writes splitViewMode directly when there is no
        // ViewController; follow it, or the next mode toggle overwrote it.
        if UserDefaultsManagement.splitViewMode, editorMode == .edit {
            editorMode = .split
        } else if !UserDefaultsManagement.splitViewMode, editorMode == .split {
            editorMode = .edit
        }
    }

    /// ⌘+ / ⌘- / ⌘0, the storyboard window's zoom: editor and preview move
    /// together within 12...28 and the new size is announced.
    func adjustFontSize(by delta: Int?) {
        let range = 12...28
        if let delta {
            let size = min(max(UserDefaultsManagement.fontSize + delta, range.lowerBound), range.upperBound)
            guard size != UserDefaultsManagement.fontSize else { return }
            UserDefaultsManagement.fontSize = size
            UserDefaultsManagement.previewFontSize = min(
                max(UserDefaultsManagement.previewFontSize + delta, range.lowerBound), range.upperBound)
        } else {
            guard
                UserDefaultsManagement.fontSize != UserDefaultsManagement.DefaultFontSize
                    || UserDefaultsManagement.previewFontSize != UserDefaultsManagement.DefaultPreviewFontSize
            else { return }
            UserDefaultsManagement.fontSize = UserDefaultsManagement.DefaultFontSize
            UserDefaultsManagement.previewFontSize = UserDefaultsManagement.DefaultPreviewFontSize
        }
        NotesTextProcessor.hl = nil
        NotesTextProcessor.refreshFonts()
        applyEditorSettings()
        host?.toast(message: String(format: I18n.str("Font size: %d"), UserDefaultsManagement.fontSize), style: .info)
    }

    /// The storyboard window's Duplicate: the note's current text (unsaved
    /// edits included) and its images, next to it under a free name.
    func duplicateSelectedNote() {
        guard let note = selectedNote, let name = note.getDupeName() else { return }
        if note === EditTextView.note, editor.textView.storageNote === note {
            editor.textView.saveTextStorageContent(to: note)
        }
        _ = note.flushPendingSave()
        if !note.isContentLoaded { note.ensureContentLoaded() }
        let copy = Note(name: name, project: note.project, type: note.type)
        copy.content = NSMutableAttributedString(attributedString: note.content)
        if note.type == .markdown, note.container == .none {
            for image in note.getAllImages() {
                copy.relocateAttachment(from: image.url, imagePath: image.path, to: note.project)
            }
        }
        copy.save()
        storage.add(copy)
        selectedNoteURL = copy.url
        refreshNotes(keepSelection: true)
    }

    /// Reads the open note back from disk, asking first when the editor holds
    /// changes the file does not have.
    func reloadSelectedNote() {
        guard let note = selectedNote else { return }
        note.ensureContentLoaded()
        let reload = { [weak self] in
            guard let self else { return }
            note.discardPendingSave()
            note.forceReload()
            note.loadModifiedLocalAt()
            if self.editor.textView.storageNote === note {
                self.editor.reload(note)
            }
            self.noteChangedOnDisk(note)
            self.host?.toast(message: I18n.str("Note reloaded~"), style: .success)
        }
        let editorHasOther = note.needsSave
        guard editorHasOther, let window = host?.view.window else {
            reload()
            return
        }
        MiaoYanAlert.confirm(
            message: I18n.str("Reload Note"),
            informativeText: I18n.str("You have unsaved changes. Reload will discard them."),
            confirmTitle: I18n.str("Reload"),
            for: window
        ) { confirmed in
            if confirmed { reload() }
        }
    }

    func copyNoteURL() {
        guard let note = selectedNote, let title = note.title.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("miaoyan://goto/\(title)", forType: .string)
        host?.toast(message: I18n.str("URL is successfully copied, Use it anywhere~"), style: .success)
    }

    func copyNotePath() {
        guard let note = selectedNote else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.url.path, forType: .string)
        host?.toast(message: I18n.str("Path is successfully copied~"), style: .success)
    }

    // MARK: - Version history

    /// Snapshots the open note if it changed, then shows its versions as a
    /// sheet; a restore reloads the editor and preview here.
    func showVersionHistory() {
        guard let note = selectedNote, !note.isTrash(), let host else { return }
        AppEnvironment.current.versionManager.saveVersionIfNeeded(for: note, force: false) { [weak self, weak host] in
            let controller = VersionHistoryViewController(note: note)
            controller.onRestored = { note, message in
                guard let self else { return }
                if self.editor.textView.storageNote === note {
                    self.editor.reload(note)
                }
                self.noteChangedOnDisk(note)
                self.contentRevision &+= 1
                self.host?.toast(message: message, style: .success)
            }
            host?.presentAsSheet(controller)
        }
    }

    // MARK: - Export

    enum ExportFormat {
        case pdf
        case image
        case html
        /// The Reveal.js deck, one slide a page.
        case ppt
    }

    private(set) var isExporting = false
    @ObservationIgnored private var restoreEditAfterExport = false

    /// Every format is produced by the preview view (PDF and image capture its
    /// rendering), so an export from the editor shows the preview first and
    /// returns to the editor after, as the storyboard window does.
    func export(_ format: ExportFormat) {
        guard !isExporting, selectedNote != nil else { return }
        if format == .ppt {
            exportDeck()
            return
        }
        isExporting = true
        let needsPreview = editorMode == .edit
        if needsPreview {
            restoreEditAfterExport = true
            editorMode = .preview
        }
        let delay: TimeInterval = needsPreview || format != .html ? 1.0 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard let preview = self.preview else {
                self.host?.toast(message: I18n.str("Export failed"), style: .failure)
                self.finishExport()
                return
            }
            switch format {
            case .pdf: preview.exportPdf()
            case .image: preview.exportImage()
            case .html: MPreviewView.exportHtml()
            case .ppt: break
            }
        }
    }

    @ObservationIgnored private var leavePPTAfterExport = false

    /// The deck prints from PPT mode, as the storyboard window's export does:
    /// the note opens as slides, is saved as a PDF, and closes again unless
    /// it was already showing as slides.
    private func exportDeck() {
        let wasPPT = isPPT
        guard wasPPT || !isPresenting else { return }
        // ppt.html lays the deck out one slide a page only when it is rendered
        // with this set; the export clears it once the PDF is made.
        UserDefaultsManagement.isOnExportPPT = true
        if wasPPT {
            previewStyleRevision &+= 1
        } else {
            setPresenting(true, ppt: true)
            // Without a --- separator setPresenting has said so and stayed put.
            guard isPPT else {
                UserDefaultsManagement.isOnExportPPT = false
                return
            }
        }
        isExporting = true
        leavePPTAfterExport = !wasPPT
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            guard let preview = self.preview else {
                UserDefaultsManagement.isOnExportPPT = false
                self.host?.toast(message: I18n.str("Export failed"), style: .failure)
                self.finishPPTExport()
                self.finishExport()
                return
            }
            preview.exportPPTOptimized()
        }
    }

    /// Called once the deck is printed, before the file is written.
    func finishPPTExport() {
        guard leavePPTAfterExport else { return }
        leavePPTAfterExport = false
        setPresenting(false)
    }

    func finishExport() {
        isExporting = false
        if restoreEditAfterExport {
            restoreEditAfterExport = false
            editorMode = .edit
        }
    }

    func snippet(for note: Note) -> String? {
        if let text = snippets[note.url] { return text }
        guard !pendingSnippets.contains(note.url) else { return nil }
        pendingSnippets.insert(note.url)
        let url = note.url
        Task { [weak self] in
            let text = await Task.detached(priority: .utility) { NotePreview.text(at: url) ?? "" }.value
            self?.snippets[url] = text
            self?.pendingSnippets.remove(url)
        }
        return nil
    }

    func selectNextScope(_ offset: Int) {
        guard let current = sidebarRows.firstIndex(where: { $0.id == scope }) else { return }
        let next = min(max(current + offset, 0), sidebarRows.count - 1)
        scope = sidebarRows[next].id
    }

    // MARK: - List

    /// Typing waits a beat so each keystroke does not start a disk scan.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await self?.computeNotes(keepSelection: true)
        }
    }

    private func refreshNotes(keepSelection: Bool) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.computeNotes(keepSelection: keepSelection)
        }
    }

    private func computeNotes(keepSelection: Bool) async {
        let (projects, type) = scopeProjects()
        for project in projects {
            if project.isTrash {
                storage.retireMissingNotes(in: project)
            }
            storage.loadMissingNotes(for: project)
        }

        let scoped = storage.noteList.filter { Self.isInScope($0, projects: projects, type: type) }
        let terms = searchText.lowercased().split(separator: " ").map(String.init)

        let ordered: [Note]
        if terms.isEmpty {
            ordered = storage.sortNotes(noteList: scoped, filter: "", project: projects.first)
        } else {
            let candidates = scoped.enumerated().map { index, note in
                let title = (note.title.isEmpty ? note.url.deletingPathExtension().lastPathComponent : note.title).lowercased()
                let needsBody = !terms.allSatisfy { title.contains($0) }
                return NoteSearchCandidate(
                    index: index,
                    title: title,
                    url: note.url,
                    loadedText: needsBody && note.isContentLoaded ? note.content.string : nil
                )
            }
            let matches = await Task.detached(priority: .userInitiated) {
                NoteContentMatcher.match(candidates, terms: terms, limit: 100, isCancelled: { Task.isCancelled })
            }.value
            guard !Task.isCancelled else { return }
            ordered =
                matches
                .sorted { first, second in
                    if first.priority != second.priority { return first.priority > second.priority }
                    return scoped[first.index].modifiedLocalAt > scoped[second.index].modifiedLocalAt
                }
                .map { scoped[$0.index] }
        }

        guard !Task.isCancelled else { return }
        notes = ordered
        sections = terms.isEmpty ? Self.group(ordered) : [NoteSection(id: "results", title: nil, notes: ordered)]
        if !(keepSelection && ordered.contains(where: { $0.url == selectedNoteURL })) {
            selectedNoteURL = ordered.first?.url
        }
    }

    /// Notes' grouping: pinned first, then Today, Yesterday, the months of
    /// this year and earlier years. Only a list sorted by date is grouped.
    private static func group(_ notes: [Note]) -> [NoteSection] {
        let sort = UserDefaultsManagement.sort
        guard sort == .modificationDate || sort == .creationDate else {
            return [NoteSection(id: "all", title: nil, notes: notes)]
        }
        let calendar = Calendar.current
        let now = Date()
        let locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        let relative = DateFormatter()
        relative.locale = locale
        relative.dateStyle = .medium
        relative.timeStyle = .none
        relative.doesRelativeDateFormatting = true
        let month = DateFormatter()
        month.locale = locale
        month.setLocalizedDateFormatFromTemplate("MMMM")

        var sections: [NoteSection] = []
        var currentID: String?
        var currentTitle: String?
        var currentNotes: [Note] = []
        func flush() {
            if let currentID { sections.append(NoteSection(id: currentID, title: currentTitle, notes: currentNotes)) }
        }
        for note in notes {
            let key: (id: String, title: String?)
            if note.isPinned {
                key = ("pinned", nil)
            } else {
                let date = (sort == .creationDate ? note.creationDate : nil) ?? note.modifiedLocalAt
                if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) {
                    let day = calendar.startOfDay(for: date)
                    key = ("day-\(day.timeIntervalSince1970)", relative.string(from: date))
                } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
                    let number = calendar.component(.month, from: date)
                    key = ("month-\(number)", month.string(from: date))
                } else {
                    let year = calendar.component(.year, from: date)
                    key = ("year-\(year)", String(year))
                }
            }
            if currentID == key.id {
                currentNotes.append(note)
            } else {
                flush()
                currentID = key.id
                currentTitle = key.title
                currentNotes = [note]
            }
        }
        flush()
        return sections
    }

    /// The folders a scope covers, as the AppKit sidebar hands them to the list.
    private func scopeProjects() -> ([Project], SidebarItemType) {
        switch scope {
        case .all:
            return (storage.getRootProject().map { [$0] } ?? [], .All)
        case .trash:
            return (storage.getDefaultTrash().map { [$0] } ?? [], .Trash)
        case .project(let url):
            let project = storage.getProjects().first { $0.url == url }
            return (project.map { [$0] } ?? [], .Category)
        }
    }

    private static func isInScope(_ note: Note, projects: [Project], type: SidebarItemType) -> Bool {
        guard !note.name.isEmpty else { return false }
        guard type == .Trash ? note.isTrash() : !note.isTrash() else { return false }
        if type == .Trash { return true }
        if projects.contains(where: { note.project.isDescendant(of: $0) }) { return true }
        return type == .All && note.project.showInCommon
    }
}

@available(macOS 14, *)
extension ShellModel.Scope {
    /// "all", "trash" or a folder's path.
    var storedValue: String {
        switch self {
        case .all: return "all"
        case .trash: return "trash"
        case .project(let url): return url.path
        }
    }
}
