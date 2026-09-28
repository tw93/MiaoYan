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
    enum Layout {
        case all
        case listAndNote
        case noteOnly
    }

    private(set) var sidebarRows: [SidebarRow] = []
    private(set) var notes: [Note] = []
    private(set) var sections: [NoteSection] = []
    /// Plain-text openings for list rows, read off the main thread on demand.
    private(set) var snippets: [URL: String] = [:]
    private(set) var layout = Layout.all
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
            refreshNotes(keepSelection: false)
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
            guard let url = selectedNoteURL, url != oldValue else { return }
            UserDefaultsManagement.lastSelectedURL = url
        }
    }

    var selectedNote: Note? {
        guard let url = selectedNoteURL else { return nil }
        return notes.first { $0.url == url }
    }

    @ObservationIgnored private let storage = AppEnvironment.current.storage
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init() {
        selectedNoteURL = UserDefaultsManagement.lastSelectedURL
        if UserDefaultsManagement.preview {
            editorMode = .preview
        } else if UserDefaultsManagement.splitViewMode {
            editorMode = .split
        }
        // A presentation is never resumed at launch, as in the storyboard window.
        UserDefaultsManagement.presentation = false
        reload()
        editor.onContentChange = { [weak self] in self?.scheduleContentRevision() }
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
        sidebarRows = Sidebar().getList().compactMap { item -> SidebarRow? in
            guard let item = item as? SidebarItem else { return nil }
            switch item.type {
            case .All:
                return SidebarRow(id: .all, title: item.getName(), kind: .All)
            case .Trash:
                return SidebarRow(id: .trash, title: item.getName(), kind: .Trash)
            case .Category:
                guard let project = item.project, project.showInSidebar else { return nil }
                return SidebarRow(id: .project(project.url), title: item.getName(), kind: .Category)
            }
        }
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

    /// Presentation shows only the preview, full screen, at the presentation
    /// font size; the window controller handles the full-screen half.
    func setPresenting(_ presenting: Bool) {
        guard presenting != isPresenting, selectedNote != nil || !presenting else { return }
        if presenting {
            modeBeforePresenting = editorMode
            layoutBeforePresenting = layout
            UserDefaultsManagement.presentation = true
            editorMode = .preview
            layout = .noteOnly
            isPresenting = true
        } else {
            UserDefaultsManagement.presentation = false
            isPresenting = false
            layout = layoutBeforePresenting
            editorMode = modeBeforePresenting
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
