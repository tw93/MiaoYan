import SwiftUI

/// Middle column of the iPad split layout: the note list for whatever the
/// sidebar has selected, plus an always-available scoped search. Selecting
/// a row drives the detail column via `selectedNote`.
struct PadContentColumn: View {
    let root: URL
    let sidebarSelection: SidebarItem
    @Binding var selectedNote: NoteFile?

    @ObservedObject private var syncManager = CloudSyncManager.shared
    @State private var notes: [NoteFile] = []
    @State private var hasLoadedOnce = false
    @State private var loadTask: Task<Void, Never>?
    @State private var previewPrefetchTask: Task<Void, Never>?

    @State private var searchQuery = ""
    @State private var searchResults: [NoteFile] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    @State private var showNewNote = false
    /// Bumped on every load request. A load only commits its result if its
    /// captured generation still matches — so a stale folder's in-flight
    /// load can't overwrite a newer selection, and a burst of iCloud
    /// revision updates can't leave the list stuck on "Loading…".
    @State private var loadGeneration = 0

    /// Survives view re-creation within the scene (e.g. an iPad
    /// compact↔regular size-class flip) so the open note is restored.
    @SceneStorage("pad.selectedNoteID") private var selectedNoteID = ""

    private var isSearchingActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var visibleNotes: [NoteFile] {
        isSearchingActive ? searchResults : notes
    }

    var body: some View {
        List {
            if isSearchingActive {
                searchSection
            } else {
                noteSections
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(MobileTheme.paper)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(MobileTheme.paper, for: .navigationBar)
        .searchable(text: $searchQuery, prompt: "Search notes")
        .tint(MobileTheme.accent)
        .toolbar {
            if canCreateNote {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showNewNote = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel(Text("New note"))
                }
            }
        }
        .refreshable {
            let selection = sidebarSelection
            let loaded = await fetchNotes(for: selection)
            guard selection == sidebarSelection else { return }
            notes = loaded
            hasLoadedOnce = true
            if case .recent = selection {
                prefetchInitialPreviews(for: loaded)
            }
            resolveSelectionIfNeeded()
        }
        .sheet(isPresented: $showNewNote, onDismiss: { triggerLoad() }) {
            NewNoteView(folder: currentFolder)
        }
        .onAppear { triggerLoad() }
        .onChange(of: sidebarSelection) {
            // Clear immediately so the previous folder's notes can't linger
            // on screen while the new folder loads.
            searchQuery = ""
            searchResults = []
            isSearching = false
            notes = []
            hasLoadedOnce = false
            previewPrefetchTask?.cancel()
            // Drop the previous folder's selection so the detail column
            // doesn't keep rendering a note that isn't in the new folder.
            selectedNote = nil
            selectedNoteID = ""
            triggerLoad()
        }
        .onChange(of: searchQuery) { _, newValue in runSearch(newValue) }
        .onChange(of: syncManager.revision) { triggerLoad() }
        .onDisappear {
            loadTask?.cancel()
            previewPrefetchTask?.cancel()
            searchTask?.cancel()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var noteSections: some View {
        if hasLoadedOnce && notes.isEmpty {
            emptyState(
                systemImage: "tray",
                title: "No notes here",
                message: "Notes in this location will appear here.")
        } else if !hasLoadedOnce && notes.isEmpty {
            InlineLoadingHint(text: "Loading notes…")
                .plainRow()
        } else {
            let pinned = notes.filter(\.isPinned)
            let others = notes.filter { !$0.isPinned }
            if !pinned.isEmpty {
                Section("Pinned") {
                    ForEach(pinned) { noteRow($0) }
                }
                Section("Notes") {
                    ForEach(others) { noteRow($0) }
                }
            } else {
                Section {
                    ForEach(others) { noteRow($0) }
                }
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        if isSearching && searchResults.isEmpty {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small).tint(MobileTheme.accent)
                Text("Searching…")
                    .font(MobileTheme.font(.subheadline))
                    .foregroundStyle(MobileTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .plainRow()
        } else if searchResults.isEmpty {
            emptyState(
                systemImage: "doc.text.magnifyingglass",
                title: "No matches",
                message: "Nothing matched \u{201C}\(searchQuery)\u{201D}.")
        } else {
            Section {
                ForEach(searchResults) { noteRow($0) }
            }
        }
    }

    private func emptyState(systemImage: String, title: String, message: String) -> some View {
        MobileEmptyContentView(systemImage: systemImage, title: title, message: message)
            .padding(.horizontal, MobileTheme.pagePadding)
            .padding(.top, 12)
            .plainRow()
    }

    private func noteRow(_ note: NoteFile) -> some View {
        let snapshotRoot: URL? = {
            if case .recent = sidebarSelection { return root }
            return nil
        }()
        let isSelected = selectedNote?.id == note.id
        return NoteCard(note: note, snapshotRoot: snapshotRoot)
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: MobileTheme.cardRadius + 5, style: .continuous)
                    .fill(isSelected ? MobileTheme.accent.opacity(0.08) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MobileTheme.cardRadius + 5, style: .continuous)
                    .strokeBorder(isSelected ? MobileTheme.accent.opacity(0.24) : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: MobileTheme.cardRadius + 5, style: .continuous))
            .onTapGesture {
                Haptics.tap()
                selectedNote = note
                selectedNoteID = note.id
            }
            .tag(note.id)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(
                    top: 6, leading: MobileTheme.pagePadding,
                    bottom: 6, trailing: MobileTheme.pagePadding)
            )
    }

    // MARK: - Selection

    private func resolveSelectionIfNeeded() {
        guard selectedNote == nil, !selectedNoteID.isEmpty else { return }
        if let note = notes.first(where: { $0.id == selectedNoteID }) {
            selectedNote = note
        }
    }

    // MARK: - Scope

    private var canCreateNote: Bool {
        if case .trash = sidebarSelection { return false }
        return true
    }

    private func scopeURL(for selection: SidebarItem) -> URL {
        switch selection {
        case .recent, .allNotes: return root
        case .folder(let url): return url
        case .trash: return root.appendingPathComponent("Trash")
        }
    }

    private func isRecursive(_ selection: SidebarItem) -> Bool {
        switch selection {
        case .folder: return false
        case .recent, .allNotes, .trash: return true
        }
    }

    private var title: String {
        switch sidebarSelection {
        case .recent: return "Notes"
        case .allNotes: return "All Notes"
        case .trash: return "Trash"
        case .folder(let url): return url.lastPathComponent
        }
    }

    private var currentFolder: FolderItem {
        let isVirtualAll: Bool
        if case .folder = sidebarSelection {
            isVirtualAll = false
        } else {
            isVirtualAll = true
        }
        return FolderItem(
            url: scopeURL(for: sidebarSelection),
            name: title,
            noteCount: notes.count,
            isVirtualAll: isVirtualAll)
    }

    // MARK: - Loading

    private func triggerLoad() {
        loadGeneration += 1
        let generation = loadGeneration
        let selection = sidebarSelection
        loadTask?.cancel()
        loadTask = Task {
            let loaded = await fetchNotes(for: selection)
            // Only the newest request commits; stale ones (folder switched,
            // or superseded by a later revision update) are discarded.
            guard generation == loadGeneration else { return }
            notes = loaded
            hasLoadedOnce = true
            if case .recent = selection, !loaded.isEmpty {
                RecentNotesCache.shared.save(loaded, for: root)
                prefetchInitialPreviews(for: loaded)
            }
            resolveSelectionIfNeeded()
        }
    }

    private func fetchNotes(for selection: SidebarItem) async -> [NoteFile] {
        switch selection {
        case .recent:
            let loaded = await NoteFileStore.recentNotes(in: root)
            return RecentNotesCache.shared.hydratePreviews(loaded, for: root)
        default:
            return await NoteFileStore.notes(
                in: scopeURL(for: selection), recursive: isRecursive(selection))
        }
    }

    private func prefetchInitialPreviews(for loaded: [NoteFile]) {
        previewPrefetchTask?.cancel()
        let candidates = NotePreviewPrefetcher.candidates(from: loaded)
        guard !candidates.isEmpty else { return }

        previewPrefetchTask = Task {
            for note in candidates {
                guard !Task.isCancelled else { return }
                guard let preview = await NotePreviewPrefetcher.preview(for: note) else { continue }
                guard !Task.isCancelled else { return }
                RecentNotesCache.shared.storePreview(preview, for: note, root: root)
                guard
                    let index = notes.firstIndex(where: {
                        $0.id == note.id && $0.modifiedDate == note.modifiedDate
                    }),
                    notes[index].preview.isEmpty
                else { continue }
                notes[index].preview = preview
            }
        }
    }

    private func runSearch(_ newValue: String) {
        searchTask?.cancel()
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isSearching = false
            searchResults = []
            return
        }
        isSearching = true
        let scope = scopeURL(for: sidebarSelection)
        searchTask = Task {
            do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
            guard !Task.isCancelled else { return }
            let outcome = await NoteFileStore.search(query: trimmed, in: scope)
            guard !Task.isCancelled else { return }
            searchResults = outcome.hits.map { $0.0 }
            isSearching = false
        }
    }

    // MARK: - Actions

}

extension View {
    /// Strips the default List row chrome so a card sits flush on paper.
    fileprivate func plainRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
    }
}
