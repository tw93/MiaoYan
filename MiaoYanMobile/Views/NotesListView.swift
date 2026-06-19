import SwiftUI

struct NotesListView: View {
    let folder: FolderItem
    @State private var notes: [NoteFile] = []
    @State private var hasLoadedOnce = false
    @State private var showNewNote = false
    @State private var loadTask: Task<Void, Never>?
    @State private var isReloading = false
    @State private var pendingReload = false
    @ObservedObject private var syncManager = CloudSyncManager.shared

    var body: some View {
        // Always mount the real list shell; the parent FolderListView owns
        // the syncing view. See RecentNotesView for the full rationale.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(folder.name)
                        .font(MobileTheme.editorialFont(size: 32, weight: .semibold))
                        .foregroundStyle(MobileTheme.ink)
                    Text("\(notes.count) notes")
                        .font(MobileTheme.font(.subheadline, weight: .medium))
                        .foregroundStyle(MobileTheme.secondaryInk)
                }
                .padding(.horizontal, MobileTheme.pagePadding)
                .padding(.top, 22)

                if hasLoadedOnce && notes.isEmpty {
                    MobileEmptyContentView(
                        systemImage: "tray",
                        title: "No notes here",
                        message: "New notes in this folder will appear here."
                    )
                    .padding(.horizontal, MobileTheme.pagePadding)
                } else if !hasLoadedOnce && notes.isEmpty {
                    // See RecentNotesView for the same rationale: large
                    // iCloud libraries can stretch the first-reload window,
                    // so signal in-progress instead of going blank.
                    InlineLoadingHint(text: "Loading notes…")
                } else {
                    let pinned = notes.filter(\.isPinned)
                    let others = notes.filter { !$0.isPinned }
                    if !pinned.isEmpty {
                        NoteSectionHeader(title: "Pinned")
                        ForEach(pinned) { note in
                            NoteCardLink(note: note)
                        }
                        if !others.isEmpty {
                            NoteSectionHeader(title: "Notes")
                        }
                    }
                    ForEach(others) { note in
                        NoteCardLink(note: note)
                    }
                }
            }
            .padding(.bottom, 22)
        }
        .refreshable { await reload() }
        .background(MobileTheme.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    showNewNote = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .foregroundStyle(MobileTheme.accent)
            }
        }
        .sheet(isPresented: $showNewNote, onDismiss: { triggerLoad() }) {
            NewNoteView(folder: folder)
        }
        .onAppear { triggerLoad() }
        .onDisappear { loadTask?.cancel() }
        .onChange(of: syncManager.revision) { triggerLoad() }
    }

    /// Coalesce revision-driven reloads so the skeleton doesn't get stuck
    /// during iCloud first-sync update bursts. See RecentNotesView for the
    /// full rationale.
    private func triggerLoad() {
        guard !isReloading else {
            pendingReload = true
            return
        }
        runLoad()
    }

    private func runLoad() {
        isReloading = true
        loadTask = Task {
            await reload()
            isReloading = false
            if pendingReload {
                pendingReload = false
                runLoad()
            }
        }
    }

    private func reload() async {
        let recursive = folder.isVirtualAll
        let loaded = await NoteFileStore.notes(in: folder.url, recursive: recursive)
        notes = loaded
        hasLoadedOnce = true
    }

}
