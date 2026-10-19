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

    /// Folders showing their subfolders, kept across launches as the
    /// storyboard outline's autosaveExpandedItems keeps them.
    var expandedFolders: Set<URL> = [] {
        didSet {
            guard expandedFolders != oldValue, !isSingleMode else { return }
            UserDefaults.standard.set(expandedFolders.map(\.path).sorted(), forKey: Self.expandedKey)
        }
    }

    private static let expandedKey = "ShellExpandedFolders"
    /// Where the storyboard outline autosaves its expanded folder paths; the
    /// first shell launch starts from it.
    private static let storyboardExpandedKey = "NSOutlineView Items SidebarOutlineView"

    private static func storedExpandedFolders() -> Set<URL> {
        let defaults = UserDefaults.standard
        let stored = defaults.array(forKey: expandedKey) ?? defaults.array(forKey: storyboardExpandedKey) ?? []
        return Set(stored.compactMap { $0 as? String }.map { URL(fileURLWithPath: $0) })
    }

    /// Matched by path: restored URLs and storage's folder URLs can differ in
    /// a trailing slash.
    func isExpanded(_ url: URL) -> Bool {
        expandedFolders.contains { $0.path == url.path }
    }

    /// Collapsing a folder whose subfolder is chosen chooses the folder.
    func toggleExpanded(_ url: URL) {
        let expanded = expandedFolders.filter { $0.path == url.path }
        if !expanded.isEmpty {
            expandedFolders.subtract(expanded)
            if case .project(let chosen) = scope, chosen.path.hasPrefix(url.path.hasSuffix("/") ? url.path : url.path + "/") {
                scope = .project(url)
            }
        } else {
            expandedFolders.insert(url)
        }
        reload()
    }

    /// Right and left arrows open and close the chosen folder; left on a
    /// closed subfolder chooses its parent, as in the storyboard outline.
    func setChosenFolderExpanded(_ expanded: Bool) {
        guard case .project(let url) = scope, let index = sidebarRows.firstIndex(where: { $0.id == scope }) else { return }
        if sidebarRows[index].hasChildren, isExpanded(url) != expanded {
            toggleExpanded(url)
        } else if !expanded, let parent = Self.parentRow(of: index, in: sidebarRows) {
            scope = parent.id
        }
    }

    /// The row a subfolder's row sits under; nil for a top-level row.
    static func parentRow(of index: Int, in rows: [SidebarRow]) -> SidebarRow? {
        let depth = rows[index].depth
        guard depth > 0 else { return nil }
        return rows[..<index].last { $0.depth == depth - 1 }
    }

    /// Expands the folders above `path` and returns its folder, so a
    /// remembered subfolder comes back as the storyboard sidebar's
    /// `revealRow(forProjectPath:)` brings it back.
    @discardableResult
    func revealFolder(atPath path: String) -> Project? {
        let topLevel = Sidebar().getList().compactMap { item -> Project? in
            guard let item = item as? SidebarItem, item.type == .Category else { return nil }
            return item.project
        }
        guard let chain = Self.folderChain(toPath: path, topLevel: topLevel, storage: storage) else { return nil }
        for ancestor in chain.dropLast() where !isExpanded(ancestor.url) {
            expandedFolders.insert(ancestor.url)
        }
        return chain.last
    }

    /// The folders from a top-level one down to the one at `path`, listing
    /// subfolders as the sidebar does; nil when no folder has that path.
    static func folderChain(toPath path: String, topLevel: [Project], storage: Storage) -> [Project]? {
        var level = topLevel
        var chain: [Project] = []
        while true {
            let candidates = level.filter { path == $0.url.path || path.hasPrefix($0.url.path + "/") }
            guard let next = candidates.max(by: { $0.url.path.count < $1.url.path.count }) else { return nil }
            chain.append(next)
            if next.url.path == path { return chain }
            level = storage.subfolders(of: next)
        }
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
    /// The wordmark over the sidebar rows, which is not a row of its own.
    private(set) var brandTitle = ""
    private(set) var notes: [Note] = []
    private(set) var sections: [NoteSection] = []
    /// Plain-text openings for list rows, read off the main thread on demand.
    var snippets: [URL: String] = [:]
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
            // Preview leaves the split setting alone, so leaving it returns
            // to split when split was on, as in the storyboard window.
            if editorMode != .preview {
                UserDefaultsManagement.splitViewMode = editorMode == .split
            }
            editor.attachSplitPreview(editorMode == .split ? preview : nil)
        }
    }
    /// Bumped when the open note changed outside the editor (disk, version
    /// restore); the preview re-renders in place. Typing reaches the split
    /// preview through the editor controller.
    private(set) var contentRevision = 0
    private(set) var isPresenting = false
    @ObservationIgnored private var modeBeforePresenting = EditorMode.preview
    @ObservationIgnored private var layoutBeforePresenting = Layout.all
    @ObservationIgnored let editor = ShellEditorController()
    /// Where toasts appear; set by the window's split controller.
    @ObservationIgnored weak var host: NSViewController?
    @ObservationIgnored private var isUnfolding = false
    @ObservationIgnored private var pendingSnippets: Set<URL> = []

    var scope: Scope = .all {
        didSet {
            guard scope != oldValue else { return }
            // A folder without the open note would close it under an export.
            if isExporting, !isRestoringSelection {
                isRestoringSelection = true
                scope = oldValue
                isRestoringSelection = false
                host?.toast(message: I18n.str("Switching notes is disabled during export~"), style: .failure)
                return
            }
            if !isSingleMode {
                UserDefaults.standard.set(scope.storedValue, forKey: Self.scopeKey)
                // Shared with the storyboard window, which writes it the same way.
                if case .project(let url) = scope {
                    UserDefaultsManagement.lastProjectPath = url.path
                } else {
                    UserDefaultsManagement.lastProjectPath = nil
                }
            }
            extraSelectedURLs = []
            // The open note stays open when the new folder lists it
            // (ensureNoteSelection(preferLastSelected:)); otherwise the first.
            refreshNotes(keepSelection: true)
        }
    }

    /// The folder and layout come back at the next launch, as the storyboard
    /// window's sidebar row and collapsed columns do.
    private static let scopeKey = "ShellScope"
    private static let layoutKey = "ShellLayout"

    private func storedScope() -> Scope {
        let path: String?
        switch UserDefaults.standard.string(forKey: Self.scopeKey) {
        case "trash": return .trash
        case "all": return .all
        // First shell launch: start on the folder the storyboard window left.
        case nil: path = UserDefaultsManagement.lastProjectPath
        case let stored?: path = stored
        }
        guard let path, let project = revealFolder(atPath: path) else { return .all }
        return .project(project.url)
    }

    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleRefresh()
        }
    }

    var selectedNoteURL: URL? {
        didSet {
            // An export takes its file name and body from the open note, so
            // the storyboard list refuses to switch until it is written.
            if isExporting, selectedNoteURL != oldValue, !isRestoringSelection {
                isRestoringSelection = true
                selectedNoteURL = oldValue
                isRestoringSelection = false
                host?.toast(message: I18n.str("Switching notes is disabled during export~"), style: .failure)
                return
            }
            // Moving the selection any other way (arrows, new note, a link)
            // ends a multiple selection, as in the storyboard list.
            if !isExtendingSelection, selectedNoteURL != oldValue { extraSelectedURLs = [] }
            guard let url = selectedNoteURL, url != oldValue else { return }
            UserDefaultsManagement.lastSelectedURL = url
        }
    }

    /// Notes selected besides the open one, by Command- or Shift-click. The
    /// open note stays the one the editor and preview show.
    var extraSelectedURLs: Set<URL> = []
    @ObservationIgnored private var isExtendingSelection = false
    @ObservationIgnored private var isRestoringSelection = false

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

    /// The row under the pointer, so a right-click knows which note it hit.
    @ObservationIgnored var hoveredNoteURL: URL?

    /// A right-click on a row selects it before its menu opens, keeping a
    /// multiple selection it is part of, and the list takes the keys, as
    /// NotesTableView.rightMouseDown does.
    func selectForMenu(_ note: Note) {
        if !isSelected(note), !isExporting { selectedNoteURL = note.url }
        focusRequest = .list
    }

    var selectedNote: Note? {
        guard let url = selectedNoteURL else { return nil }
        return notes.first { $0.url == url }
    }

    @ObservationIgnored let storage = AppEnvironment.current.storage
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init() {
        selectedNoteURL = UserDefaultsManagement.lastSelectedURL
        expandedFolders = Self.storedExpandedFolders()
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
        editor.onContentChange = { [weak self] in
            self?.scheduleSavedNoteRefresh()
        }
        editor.onFormattingChange = { [weak self] formatting in
            self?.isFormatting = formatting
        }
        editor.onShow = { [weak self] in
            self?.editorDidAppear()
        }
        editor.searchQuery = { [weak self] in
            self?.searchText ?? ""
        }
    }

    @ObservationIgnored private var savedRefreshTask: Task<Void, Never>?

    /// The list row of a note edited here follows its save: a new opening,
    /// a new date, and the place and date group the storyboard list moves
    /// it to. Checked after the 1.5s save debounce, again while it waits.
    private func scheduleSavedNoteRefresh() {
        guard let url = EditTextView.note?.url else { return }
        savedRefreshTask?.cancel()
        savedRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            if let note = self.storage.getBy(url: url), note.needsSave {
                self.scheduleSavedNoteRefresh()
                return
            }
            // The new opening replaces the old one only when it differs.
            // Clearing it first emptied the row and refilled it a moment
            // later, so the list flickered while typing elsewhere in the note.
            let text = await Task.detached(priority: .utility) { NotePreview.text(at: url) ?? "" }.value
            guard !Task.isCancelled else { return }
            if self.snippets[url] != text { self.snippets[url] = text }
            // A search keeps its result order, as in the storyboard list.
            if self.searchText.isEmpty { self.refreshNotes(keepSelection: true) }
        }
    }

    /// Backlinks cover every note; the index reads unloaded bodies itself.
    private func rebuildLinkIndex() {
        AppEnvironment.current.wikilinkIndex.rebuildFromAllNotes(in: storage)
    }

    /// Whether a collapsed folder has subfolders, from the last scan.
    @ObservationIgnored private var hasChildrenCache: [URL: Bool] = [:]
    @ObservationIgnored private var childScanTask: Task<Void, Never>?

    /// Rebuilds the sidebar from storage, then the list. Only expanded
    /// folders are listed on the main thread; whether a collapsed one has
    /// subfolders is checked off it, since every disk event reloads.
    func reload() {
        var rows: [SidebarRow] = []
        var collapsed: [URL] = []
        func addFolder(_ project: Project, title: String, depth: Int) {
            guard isExpanded(project.url) else {
                collapsed.append(project.url)
                rows.append(
                    SidebarRow(
                        id: .project(project.url), title: title, kind: .Category, depth: depth,
                        hasChildren: hasChildrenCache[project.url] ?? false))
                return
            }
            let children = storage.subfolders(of: project)
            hasChildrenCache[project.url] = !children.isEmpty
            rows.append(SidebarRow(id: .project(project.url), title: title, kind: .Category, depth: depth, hasChildren: !children.isEmpty))
            for child in children {
                addFolder(child, title: child.label, depth: depth + 1)
            }
        }
        for item in Sidebar().getList() {
            guard let item = item as? SidebarItem else { continue }
            switch item.type {
            case .Brand:
                brandTitle = item.getName()
            case .All:
                rows.append(SidebarRow(id: .all, title: item.getName(), kind: .All))
            case .Trash:
                rows.append(SidebarRow(id: .trash, title: item.getName(), kind: .Trash))
            case .Category:
                // The storyboard sidebar lists every folder; the legacy
                // showInSidebar flag is not honoured there either.
                guard let project = item.project else { continue }
                addFolder(project, title: item.getName(), depth: 0)
            }
        }
        sidebarRows = rows
        scanForSubfolders(collapsed)
        if !sidebarRows.contains(where: { $0.id == scope }) {
            scope = .all
        }
        refreshNotes(keepSelection: true)
    }

    /// Fills in the chevrons of collapsed folders once the disk is read.
    private func scanForSubfolders(_ urls: [URL]) {
        childScanTask?.cancel()
        guard !urls.isEmpty else { return }
        let extensions = storage.allowedExtensions
        childScanTask = Task { [weak self] in
            let flags = await Task.detached(priority: .utility) {
                urls.reduce(into: [URL: Bool]()) { $0[$1] = ShellModel.hasSubfolder(at: $1, allowedExtensions: extensions) }
            }.value
            guard !Task.isCancelled, let self else { return }
            self.hasChildrenCache.merge(flags) { $1 }
            let updated = self.sidebarRows.map { row -> SidebarRow in
                guard case .project(let url) = row.id, let flag = flags[url] else { return row }
                var row = row
                row.hasChildren = flag
                return row
            }
            if updated != self.sidebarRows { self.sidebarRows = updated }
        }
    }

    /// `Storage.subfolders(of:)`'s filter without creating projects, so it
    /// can run off the main thread: a visible, non-package directory that is
    /// not an attachment folder.
    nonisolated private static func hasSubfolder(at url: URL, allowedExtensions: [String]) -> Bool {
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: options) else {
            return false
        }
        let skipFolders: Set<String> = [".cache", "i", ".Trash", "files"]
        for case let child as URL in enumerator {
            let name = child.lastPathComponent
            guard !skipFolders.contains(name), !name.hasPrefix("."),
                let values = try? child.resourceValues(forKeys: Set(keys)),
                values.isDirectory == true, values.isPackage == false,
                !Storage.isHiddenAssetsFolder(child, allowedExtensions: allowedExtensions),
                !isAttachmentOnlyFolder(child, allowedExtensions: allowedExtensions)
            else { continue }
            return true
        }
        return false
    }

    /// `Storage.isAttachmentOnlyFolder(url:)`, for the scan above.
    nonisolated private static func isAttachmentOnlyFolder(_ url: URL, allowedExtensions: [String]) -> Bool {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: options) else {
            return false
        }
        var hasFile = false
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { return false }
            if allowedExtensions.contains(fileURL.pathExtension.lowercased()) { return false }
            hasFile = true
        }
        return hasFile
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
        commitPendingRename()
        editor.cleanTypography(in: host)
    }

    /// The list's heading: the chosen folder's name.
    var scopeTitle: String {
        // The brand row already says MiaoYan beside the list.
        if scope == .all { return I18n.str("All Notes") }
        return sidebarRows.first { $0.id == scope }?.title ?? ""
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

    /// Leaving preview returns to split when split was on.
    private var modeAfterPreview: EditorMode {
        UserDefaultsManagement.splitViewMode ? .split : .edit
    }

    func togglePreview() {
        guard !isPresenting else { return }
        setMode(editorMode == .preview ? modeAfterPreview : .preview)
    }

    /// From preview, the storyboard window flips split and leaves preview
    /// into whichever mode that gives.
    func toggleSplit() {
        guard !isPresenting else { return }
        if editorMode == .preview {
            setMode(modeAfterPreview == .split ? .edit : .split)
        } else {
            setMode(editorMode == .split ? .edit : .split)
        }
    }

    /// What preview does once its page is ready: scroll to the line being
    /// edited (with Preview Location "Editing") and take focus.
    private struct PreviewEntry {
        var line: CGFloat?
        var ratio: CGFloat?
    }

    /// The editor's place when preview opened, put back when it closes on
    /// the same note.
    private struct EditorPlace {
        let url: URL
        let selection: NSRange
        let ratio: CGFloat
    }

    @ObservationIgnored private var pendingPreviewEntry: PreviewEntry?
    @ObservationIgnored private var editorPlaceBeforePreview: EditorPlace?
    /// Run once the editor is back on screen after a mode change.
    @ObservationIgnored private var editorAppearAction: (() -> Void)?

    /// The storyboard window's enablePreview / disablePreview and split
    /// toggles: find bars close, a title being typed is kept, and focus,
    /// scroll and selection carry across.
    func setMode(_ mode: EditorMode) {
        guard mode != editorMode else { return }
        commitPendingRename()
        closeFindBars()
        let wasPreview = editorMode == .preview
        if mode == .preview {
            var entry = PreviewEntry()
            if let note = selectedNote, editor.textView.storageNote === note, editor.textView.window != nil {
                entry.line = editor.topBodyLine()
                entry.ratio = editor.scrollRatio
                editorPlaceBeforePreview = EditorPlace(url: note.url, selection: editor.textView.selectedRange(), ratio: editor.scrollRatio)
            } else {
                editorPlaceBeforePreview = nil
            }
            pendingPreviewEntry = entry
            editorAppearAction = nil
        } else {
            let place = wasPreview ? editorPlaceBeforePreview : nil
            editorPlaceBeforePreview = nil
            pendingPreviewEntry = nil
            editorAppearAction = { [weak self] in self?.restoreEditor(place, restoreCursor: wasPreview) }
        }
        editorMode = mode
    }

    private func restoreEditor(_ place: EditorPlace?, restoreCursor: Bool) {
        guard editorMode != .preview, !isPresenting, let note = selectedNote else { return }
        let textView = editor.textView
        if let place, place.url == note.url, textView.storageNote === note {
            let length = (textView.string as NSString).length
            let location = min(max(place.selection.location, 0), length)
            textView.setSelectedRange(NSRange(location: location, length: min(place.selection.length, length - location)))
            editor.setScrollRatio(place.ratio)
        } else if restoreCursor {
            textView.restoreCursorPosition()
        }
        if !isRenaming { focusEditor() }
    }

    func editorDidAppear() {
        guard let action = editorAppearAction else { return }
        editorAppearAction = nil
        action()
    }

    /// Called once a preview has started loading its note.
    func previewDidLoad(_ view: MPreviewView) {
        if let line = previewLineBeforeReload {
            previewLineBeforeReload = nil
            if view === preview, editorMode == .preview {
                view.runWhenPreviewReady { [weak view] in view?.scrollToLine(line) }
            }
        }
        guard let entry = pendingPreviewEntry, view === preview, editorMode == .preview else { return }
        pendingPreviewEntry = nil
        let scrolls = UserDefaultsManagement.previewLocation == "Editing" && !isExporting
        view.runWhenPreviewReady { [weak view] in
            guard let view else { return }
            if scrolls, let line = entry.line {
                view.scrollToLine(line, fallbackRatio: entry.ratio)
            }
            view.window?.makeFirstResponder(view)
        }
    }

    private func closeFindBars() {
        if editor.textView.isSearchBarVisible { editor.textView.hideSearchBar(restoreFocus: false) }
        if let preview, preview.isSearchBarVisible { preview.hideSearchBar() }
    }

    /// Whether Format is running; its button dims and a click cancels it.
    private(set) var isFormatting = false

    func format() {
        guard let host else { return }
        guard editorMode != .preview else {
            host.toast(message: I18n.str("Format is only possible after exiting preview mode~"), style: .failure)
            return
        }
        commitPendingRename()
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
            commitPendingRename()
            closeFindBars()
            modeBeforePresenting = editorMode
            layoutBeforePresenting = layout
            pendingPreviewEntry = nil
            editorAppearAction = nil
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
            // A PPT export opens the deck only to print it.
            if !UserDefaultsManagement.isOnExportPPT {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self, self.isPresenting else { return }
                    self.host?.toast(message: I18n.str("Press ESC key to exit~"))
                }
            }
        } else {
            closeFindBars()
            UserDefaultsManagement.presentation = false
            UserDefaultsManagement.magicPPT = false
            isPresenting = false
            isPPT = false
            layout = layoutBeforePresenting
            // The keyboard goes back to the editor, or to the preview when
            // that was the mode before.
            if modeBeforePresenting == .preview {
                pendingPreviewEntry = PreviewEntry()
            } else {
                editorAppearAction = { [weak self] in self?.restoreEditor(nil, restoreCursor: false) }
            }
            editorMode = modeBeforePresenting
            previewStyleRevision &+= 1
        }
    }

    /// The storyboard window's PPT entry: when the preview follows the editing
    /// position, open on the slide the cursor is in, and give the deck focus
    /// so the arrow keys and space turn pages.
    private func openDeckAtCursor() {
        // The buffer may still hold another note (#543); its cursor says
        // nothing about this deck.
        var slide = 0
        if let note = selectedNote, editor.textView.storageNote === note {
            let text = editor.textView.string
            let cursor = max(min(editor.textView.selectedRange().location, text.count) - 1, 0)
            slide = text.prefix(cursor).components(separatedBy: "---").count - 1
        }
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
    /// What the title field holds, and the note it was started for: a
    /// commit never applies one note's draft to another.
    var renameDraft = ""
    @ObservationIgnored private var renameDraftURL: URL?

    /// The title field opened: start from the note's title.
    func beginRenameDraft() {
        renameDraft = selectedNote?.getTitleWithoutLabel() ?? ""
        renameDraftURL = renamingNoteURL
    }

    /// Renames the note after what the title field holds and closes it; the
    /// storyboard window's saveTitleSafely, run before mode changes and
    /// Format so a title being typed is not lost.
    func commitPendingRename() {
        guard let url = renamingNoteURL else { return }
        renamingNoteURL = nil
        guard renameDraftURL == url, let note = storage.getBy(url: url) else { return }
        renameDraftURL = nil
        rename(note, to: renameDraft)
    }

    /// A title is one line: pasted line breaks become spaces, as in the
    /// storyboard window's title field.
    nonisolated static func singleLineTitle(_ title: String) -> String {
        guard title.contains(where: \.isNewline) else { return title }
        return title.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).joined(separator: " ")
    }

    /// The preview currently on screen, for commands that act on it (TOC).
    /// The split preview also scrolls with the editor.
    @ObservationIgnored weak var preview: MPreviewView? {
        didSet {
            editor.attachSplitPreview(editorMode == .split ? preview : nil)
        }
    }

    enum FocusTarget {
        case sidebar
        case list
        /// The list's search field, opened if it is closed.
        case search
    }

    /// A SwiftUI column keyboard commands move focus to; that column takes
    /// focus and clears the request.
    var focusRequest: FocusTarget?
    /// A focus request waiting for a hidden column to open.
    @ObservationIgnored private var focusAfterLayout: FocusTarget?

    /// ⌘/, the storyboard window's searchAndCreate: the list comes back if it
    /// is hidden and the search field takes the keys, also when it is
    /// already open or holds a query.
    func focusSearch() {
        guard !isPresenting else { return }
        guard layout == .noteOnly else {
            focusRequest = .search
            return
        }
        isSearchOpen = true
        focusAfterLayout = .search
        toggleNoteList()
    }

    /// The window has finished opening or closing columns.
    func layoutDidSettle() {
        guard let target = focusAfterLayout else { return }
        focusAfterLayout = nil
        focusRequest = target
    }

    /// Puts the cursor in the editor when it is on screen.
    func focusEditor() {
        guard editorMode != .preview, !isPresenting, let window = editor.textView.window else { return }
        window.makeFirstResponder(editor.textView)
    }

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

    /// Moves the selected notes to the Trash, recoverable as everywhere else,
    /// and opens their neighbour. Inside the Trash it moves them on to the
    /// system Trash after the storyboard window's confirmation.
    func deleteSelectedNote() {
        // The note being exported stays until its file is written.
        guard !isPresenting, !isExporting, let note = selectedNote else { return }
        let removing = selectedNotes
        guard note.isTrash() else {
            remove(removing.filter { !$0.isTrash() }, undoable: true)
            return
        }
        guard let window = host?.view.window else { return }
        MiaoYanAlert.confirm(
            message: String(format: I18n.str("Are you sure you want to move %d note(s) to the system Trash?"), removing.count),
            informativeText: I18n.str("The note(s) will be moved to the system Trash and can be recovered."),
            confirmTitle: I18n.str("Move to Trash"),
            for: window
        ) { [weak self] confirmed in
            if confirmed { self?.remove(removing) }
        }
    }

    /// Notes dropped on the Trash row.
    func moveToTrash(_ moving: [Note]) {
        guard !isPresenting, !isExporting else { return }
        remove(moving.filter { !$0.isTrash() })
    }

    /// Undo for the list: Edit ▸ Undo after a delete puts the notes back, as
    /// the storyboard window's `notesListUndoManager` does. The editor's own
    /// undo comes from the note through the text view's delegate.
    @ObservationIgnored let notesUndoManager = UndoManager()

    private func remove(_ removing: [Note], undoable: Bool = false) {
        guard !removing.isEmpty else { return }
        let listed = notes.map(\.url)
        let open = selectedNoteURL
        let removed = Set(removing.map(\.url))
        storage.removeNotes(
            notes: removing,
            partialFailure: { [weak self] count in
                Task { @MainActor in
                    self?.host?.toast(
                        message: String(format: I18n.str("Failed to move %d note(s) to Trash~"), count), style: .failure)
                }
            }
        ) { [weak self] urls in
            Task { @MainActor in
                guard let self else { return }
                // A drop on the Trash can take notes other than the open one.
                self.selectedNoteURL = Self.selection(afterRemoving: removed, from: listed, selected: open)
                // The list is empty: the editor lets the removed note go, as
                // the storyboard window's delete does.
                let held = [self.editor.textView.storageNote, EditTextView.note].compactMap { $0?.url }
                if self.selectedNoteURL == nil, held.contains(where: removed.contains) {
                    self.editor.clear()
                }
                // The Trash row comes and goes with its notes; once it is
                // gone, All Notes is chosen, as in the storyboard sidebar.
                self.reload()
                if undoable, let urls, !urls.isEmpty {
                    self.notesUndoManager.registerUndo(withTarget: self) { model in
                        MainActor.assumeIsolated { model.restoreDeleted(urls) }
                    }
                    self.notesUndoManager.setActionName(I18n.str("Delete"))
                    // The storyboard list keeps focus after a delete, where
                    // Command-Z brings the notes back.
                    self.focusRequest = .list
                }
            }
        }
    }

    /// The note to open once `removed` leave the list: the open one when it
    /// stays, else the one now at the first removed row, as the storyboard
    /// list reselects after a delete or a move out of the folder.
    static func selection(afterRemoving removed: Set<URL>, from list: [URL], selected: URL?) -> URL? {
        guard let selected, removed.contains(selected) else { return selected }
        let index = list.firstIndex { removed.contains($0) } ?? 0
        let remaining = list.filter { !removed.contains($0) }
        return remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)]
    }

    /// Moves deleted notes back from the Trash (`NotesTableView.unDelete`).
    /// They are listed here at once instead of waiting for the file watcher.
    func restoreDeleted(_ urls: [URL: URL]) {
        var restored: URL?
        for (trashed, original) in urls {
            do {
                try FileManager.default.moveItem(at: trashed, to: original)
            } catch {
                // The note stays where it is, listed in the Trash.
                AppDelegate.trackError(error, context: "ShellModel.restoreDeleted")
                continue
            }
            // Deleting filed the history under the Trash path; bring it back.
            AppEnvironment.current.versionManager.moveVersions(from: trashed, to: original)
            if let note = storage.getBy(url: trashed) {
                storage.removeBy(note: note)
            }
            if storage.getBy(url: original) == nil, let note = storage.initNote(url: original) {
                note.load()
                note.loadModifiedLocalAt()
                storage.add(note)
            }
            restored = original
        }
        guard let restored else { return }
        // Open it only where it is listed; elsewhere the detail would go blank.
        refreshNow { [weak self] in
            guard let self, self.notes.contains(where: { $0.url == restored }) else { return }
            self.selectedNoteURL = restored
        }
    }

    /// Renames the open note's file after `title`; false when that name is taken.
    @discardableResult
    func rename(_ note: Note, to title: String) -> Bool {
        let title = title.trimmingCharacters(in: .newlines)
        guard !title.isEmpty, title != note.getFileName() else { return true }
        // A rename committed because another note was clicked keeps that
        // note selected.
        let wasSelected = selectedNoteURL == note.url
        guard note.renameFile(to: title) else {
            MiaoYanAlert.show(
                message: I18n.str("Please change the title"),
                informativeText: String(format: I18n.str("This %@ under this folder already exists!"), title),
                for: host?.view.window)
            return false
        }
        if wasSelected { selectedNoteURL = note.url }
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
    /// The folder stays as it is, as in the storyboard window's importNotes;
    /// only a note already in the library takes the list to its folder.
    func importNotes(_ urls: [URL], into project: Project? = nil) {
        var target: URL?
        var existing: Note?
        for url in urls {
            if let note = storage.getBy(url: url) {
                target = note.url
                existing = note
                continue
            }
            let copy = ViewController.copyFile(url, into: project ?? storage.getMainProject())
            guard storage.getBy(url: copy) == nil, let note = storage.initNote(url: copy) else { continue }
            note.load()
            note.loadModifiedLocalAt()
            storage.add(note)
            target = note.url
            existing = nil
        }
        searchText = ""
        isSearchOpen = false
        if let existing, existing.url == target, !notes.contains(where: { $0 === existing }) {
            if existing.isTrash() {
                scope = .trash
            } else if !existing.project.isRoot, revealFolder(atPath: existing.project.url.path) != nil {
                scope = .project(existing.project.url)
                reload()
            } else {
                scope = .all
            }
        }
        refreshNow(selecting: target)
    }

    /// Finder files dropped on the list (into the chosen folder) or on a
    /// folder row: the Markdown files, and those inside dropped folders,
    /// imported as File ▸ Import does. Notes already in the library, such
    /// as a row dragged out of this list, are left alone, and so are the
    /// library's own folders dragged from the sidebar. On a folder row
    /// (`keepingFolders`) a dropped Finder folder becomes a subfolder of the
    /// same name holding its files, as the storyboard sidebar's
    /// handleDirectoryDrop does.
    func importDropped(_ urls: [URL], into project: Project?, keepingFolders: Bool = false) -> Bool {
        var fresh = urls.filter { url in
            url.isFileURL && storage.getBy(url: url) == nil
                && !storage.getProjects().contains {
                    $0.url.resolvingSymlinksInPath().path == url.resolvingSymlinksInPath().path
                }
        }
        guard !isPresenting, !fresh.isEmpty else { return false }
        if keepingFolders, let project {
            let folders = fresh.filter { FileManager.default.directoryExists(atUrl: $0) }
            for folder in folders {
                importFolder(folder, into: project)
            }
            fresh.removeAll { url in folders.contains(url) }
            guard !fresh.isEmpty else { return true }
        }
        let extensions = storage.allowedExtensions
        let dropped = fresh
        // A dropped folder can be huge; only the scan leaves the main thread.
        Task { [weak self] in
            let files = await Task.detached(priority: .userInitiated) {
                ViewController.collectImportableFiles(from: dropped, allowedExtensions: extensions)
            }.value
            guard let self else { return }
            guard !files.isEmpty else {
                self.host?.toast(message: I18n.str("No importable Markdown files found~"), style: .failure)
                return
            }
            self.importNotes(files, into: project)
        }
        return true
    }

    private func importFolder(_ url: URL, into parent: Project) {
        let folder = Project(url: parent.url.appendingPathComponent(url.lastPathComponent, isDirectory: true), parent: parent)
        folder.create()
        _ = storage.add(project: folder)
        for item in storage.readDirectory(url) {
            let copy = ViewController.copyFile(item.url, into: folder)
            guard storage.getBy(url: copy) == nil, let note = storage.initNote(url: copy) else { continue }
            note.load()
            note.loadModifiedLocalAt()
            storage.add(note)
        }
        hasChildrenCache[parent.url] = true
        onFoldersChanged?()
        reload()
    }

    /// The folder new and imported notes go into from the list.
    var dropProject: Project? {
        guard case .project = scope else { return nil }
        return targetProject
    }

    /// Shows only `url`: a file with the notes beside it, or a folder.
    func openSingle(_ url: URL, siblingFiles: [URL]? = nil) {
        // Storage is swapped out below; the open note's edits land first.
        flushEdits()
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
        flushEdits()
        UserDefaultsManagement.clearSingleMode()
        storage.reconfigureForLibrary()
        isSingleMode = false
        switchStorage(selecting: librarySelection, scope: storedScope())
    }

    /// Writes the editor's text and every debounced save now. A save waits
    /// 1.5s after the last key, so quitting, closing the window, switching
    /// apps or swapping storage inside that window would otherwise lose the
    /// last edits; the storyboard window does the same through its
    /// ViewController.
    func flushEdits() {
        copyLiveEditorBuffer()
        storage.flushPendingSaves()
    }

    /// Writes the editor buffer back to its note only while the editor is on
    /// screen. In preview it is off the window and may be older than the note:
    /// a task ticked in the preview changes the note, not the buffer, and
    /// copying the buffer back then undid the tick. Typing already saves on
    /// every change, so a hidden editor has nothing newer to give.
    private func copyLiveEditorBuffer() {
        guard let owner = editor.textView.storageNote, editor.textView.window != nil else { return }
        editor.textView.saveTextStorageContent(to: owner)
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
    /// The sidebar row under the pointer, which a right-click chooses before
    /// its menu opens, as the storyboard sidebar selects the clicked row.
    @ObservationIgnored var hoveredSidebarRow: Scope?
    /// Called after folders change on disk, so the file watcher can follow.
    @ObservationIgnored var onFoldersChanged: (() -> Void)?

    // MARK: - Note utilities

    /// Bumped when the preview's stylesheet changes (font size, font face),
    /// so the preview reloads instead of patching its content.
    var previewStyleRevision = 0
    /// The source line the preview showed before a stylesheet reload.
    @ObservationIgnored private var previewLineBeforeReload: CGFloat?

    /// A stylesheet change reloads the preview page, which opens at the top.
    /// In preview mode the reader's line is read first and put back once the
    /// page is ready; the split preview follows the editor instead.
    private func reloadPreviewKeepingPlace() {
        guard editorMode == .preview, !isPresenting, let preview else {
            previewStyleRevision &+= 1
            return
        }
        let script = "window.__miaoyanSync ? window.__miaoyanSync.lineForScroll(window.pageYOffset || 0) : -1"
        preview.evaluateJavaScript(script) { [weak self] result, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let line = (result as? NSNumber)?.doubleValue, line > 0 {
                    self.previewLineBeforeReload = CGFloat(line)
                }
                self.previewStyleRevision &+= 1
            }
        }
    }

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
        reloadPreviewKeepingPlace()
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

    /// Chosen faces that were not installed when last checked.
    @ObservationIgnored private var missingChosenFonts = FontCatalog.missingChosenFonts()

    /// The installed fonts changed. ViewController's rule: a chosen face that
    /// was missing (TsangerJinKai02 picked before it is installed) takes over
    /// at once; unrelated installs change nothing. This window re-renders
    /// itself only, since the storyboard window's observer does its own.
    func installedFontsDidChange() {
        let missing = FontCatalog.missingChosenFonts()
        let appeared = !missingChosenFonts.subtracting(missing).isEmpty
        missingChosenFonts = missing
        guard appeared else { return }
        NotesTextProcessor.hl = nil
        NotesTextProcessor.refreshFonts()
        applyEditorSettings()
        // The interface face is stored under the same name before and after.
        interfaceRevision &+= 1
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
    /// Every one of `notes`, as the storyboard window duplicates the whole
    /// selection; the copies are listed and the selection stays on the
    /// originals (NotesTableView.insertNew).
    func duplicate(_ originals: [Note]) {
        var copied = false
        for note in originals where !note.isTrash() {
            guard let name = note.getDupeName() else { continue }
            if note === EditTextView.note {
                copyLiveEditorBuffer()
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
            // A successful save adds the copy to storage.
            copy.save()
            copied = true
        }
        guard copied else { return }
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

    /// One path a line, for every selected note, as the storyboard's copyPath.
    func copyNotePaths(_ copying: [Note]) {
        guard !copying.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copying.map(\.url.path).joined(separator: "\n"), forType: .string)
        host?.toast(message: I18n.str("Path is successfully copied~"), style: .success)
    }

    func revealInFinder(_ revealing: [Note]) {
        guard !revealing.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(revealing.map(\.url))
    }

    /// Command-S: the editor's text and every debounced save written now,
    /// with "Saved~" only when something was waiting, as the storyboard
    /// window's handler does.
    func saveNow() {
        copyLiveEditorBuffer()
        let hadUnsavedChanges = storage.noteList.contains { $0.needsSave }
        let allSaved = storage.flushPendingSaves()
        if hadUnsavedChanges, allSaved {
            host?.toast(message: I18n.str("Saved~"), style: .success)
        }
    }

    /// Command-A in the list.
    func selectAllNotes() {
        guard let first = notes.first else { return }
        if selectedNoteURL == nil { selectedNoteURL = first.url }
        extraSelectedURLs = Set(notes.map(\.url)).subtracting([selectedNoteURL].compactMap { $0 })
    }

    // MARK: - Search field keys

    /// Return in the search field opens the note in the editor when its
    /// title starts with the query (SearchTextField's insertNewline).
    func searchFieldReturn() {
        let query = searchText.lowercased()
        guard !query.isEmpty, let note = selectedNote, note.title.lowercased().starts(with: query) else { return }
        focusEditor()
    }

    /// Command-Return makes a note named after the query.
    func createNoteFromSearch() {
        createNote(name: searchText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A query also becomes the system find string, so Command-G finds it in
    /// other apps and in the editor (SearchTextField.updatePasteboard).
    private static func writeFindPasteboard(_ text: String) {
        let pasteboard = NSPasteboard(name: .find)
        pasteboard.declareTypes([.textFinderOptions, .string], owner: nil)
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Columns

    /// A divider dragged until a column collapsed, or back open: the layout
    /// follows, so the toggles and the next launch agree with what is shown.
    /// Hiding the list hides the folders too, as in the storyboard window.
    func syncLayout(sidebarCollapsed: Bool, listCollapsed: Bool) {
        guard !isPresenting else { return }
        let shown: Layout = listCollapsed ? .noteOnly : sidebarCollapsed ? .listAndNote : .all
        if shown != layout { layout = shown }
    }

    /// A two-finger swipe left hides the folders, then the list; a swipe
    /// right brings the list back, then the folders (ViewController's swipe).
    func swipeColumns(left: Bool) {
        guard !isPresenting else { return }
        switch (left, layout) {
        case (true, .all): layout = .listAndNote
        case (true, .listAndNote): layout = .noteOnly
        case (false, .noteOnly): layout = .listAndNote
        case (false, .listAndNote): layout = .all
        default: break
        }
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

    // MARK: - Export state

    var isExporting = false
    @ObservationIgnored var restoreEditAfterExport = false
    @ObservationIgnored var leavePPTAfterExport = false

    /// Where the open note's row sits in the list, in the list's own
    /// coordinates, for menus that pop at it.
    @ObservationIgnored var selectedRowFrame: CGRect?

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
            guard !Task.isCancelled, let self else { return }
            if !self.searchText.isEmpty { Self.writeFindPasteboard(self.searchText) }
            await self.computeNotes(keepSelection: true)
        }
    }

    func refreshNotes(keepSelection: Bool) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.computeNotes(keepSelection: keepSelection)
        }
    }

    /// What the list was last filled with: a folder's notes, or a search in
    /// it. The list puts back a folder's scroll place when it returns to it.
    struct ListContent: Equatable {
        let scope: Scope
        let isSearch: Bool
    }

    private(set) var listContent: ListContent?

    private func computeNotes(keepSelection: Bool) async {
        let listedScope = scope
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
        let content = ListContent(scope: listedScope, isSearch: !terms.isEmpty)
        if listContent != content { listContent = content }
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
    func scopeProjects() -> ([Project], SidebarItemType) {
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

    static func isInScope(_ note: Note, projects: [Project], type: SidebarItemType) -> Bool {
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
