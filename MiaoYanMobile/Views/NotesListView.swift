import SwiftUI

struct NotesListView: View {
    let folder: FolderItem
    @State private var notes: [NoteFile] = []
    @State private var hasLoadedOnce = false
    @State private var showNewNote = false
    @State private var showEmptyTrashAlert = false
    @State private var actionError: String?
    @State private var loadTask: Task<Void, Never>?
    @State private var isReloading = false
    @State private var pendingReload = false
    @ObservedObject private var syncManager = CloudSyncManager.shared

    /// Library root, derived from the Trash folder's location. Only
    /// meaningful when `folder.isTrash`.
    private var libraryRoot: URL {
        folder.url.deletingLastPathComponent()
    }

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
                            noteLink(note)
                        }
                        if !others.isEmpty {
                            NoteSectionHeader(title: "Notes")
                        }
                    }
                    ForEach(others) { note in
                        noteLink(note)
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
                if folder.isTrash {
                    Button {
                        Haptics.warning()
                        showEmptyTrashAlert = true
                    } label: {
                        Text("Empty Trash")
                    }
                    .foregroundStyle(MobileTheme.accent)
                    .disabled(notes.isEmpty)
                } else {
                    Button {
                        Haptics.tap()
                        showNewNote = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .foregroundStyle(MobileTheme.accent)
                }
            }
        }
        .sheet(isPresented: $showNewNote, onDismiss: { triggerLoad() }) {
            NewNoteView(folder: folder)
        }
        .alert("Empty Trash?", isPresented: $showEmptyTrashAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty Trash", role: .destructive) { emptyTrash() }
        } message: {
            Text("This permanently deletes all notes in Trash.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .onAppear { triggerLoad() }
        .onDisappear { loadTask?.cancel() }
        .onChange(of: syncManager.revision) { triggerLoad() }
    }

    /// Trash rows carry a Restore context menu; regular folders keep the
    /// plain card (note management lives in the detail view).
    @ViewBuilder
    private func noteLink(_ note: NoteFile) -> some View {
        if folder.isTrash {
            NoteCardLink(note: note)
                .contextMenu {
                    Button {
                        restore(note)
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                }
        } else {
            NoteCardLink(note: note)
        }
    }

    private func restore(_ note: NoteFile) {
        let root = libraryRoot
        Task { @MainActor in
            do {
                _ = try await NoteFileStore.restore(note, libraryRoot: root)
                Haptics.success()
                CloudSyncManager.shared.notifyExternalChange()
                triggerLoad()
            } catch {
                actionError = error.localizedDescription
                Haptics.error()
            }
        }
    }

    private func emptyTrash() {
        let root = libraryRoot
        Task { @MainActor in
            do {
                try await NoteFileStore.emptyTrash(root: root)
                Haptics.success()
                CloudSyncManager.shared.notifyExternalChange()
                triggerLoad()
            } catch {
                actionError = error.localizedDescription
                Haptics.error()
            }
        }
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
