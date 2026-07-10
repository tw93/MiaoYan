import SwiftUI

/// First column of the iPad split layout: a sidebar over the library's
/// folders plus the Recent / All Notes / Trash entry points.
struct PadSidebarView: View {
    let root: URL
    @Binding var selection: SidebarItem?
    let openPicker: () -> Void
    let openSettings: () -> Void

    @ObservedObject private var syncManager = CloudSyncManager.shared
    @State private var folders: [FolderItem] = []
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var newFolderError: String?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Notes", systemImage: "note.text")
                    .tag(SidebarItem.recent)
                Label("All Notes", systemImage: "tray.full")
                    .tag(SidebarItem.allNotes)
            }

            if !subfolders.isEmpty {
                Section("Folders") {
                    ForEach(subfolders, id: \.id) { folder in
                        Label(folder.name, systemImage: "folder")
                            .tag(SidebarItem.folder(url: folder.url))
                    }
                }
            }

            if trashFolder != nil {
                Section {
                    Label("Trash", systemImage: "trash")
                        .tag(SidebarItem.trash)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(MobileTheme.paper)
        .navigationTitle("MiaoYan")
        .tint(MobileTheme.accent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    newFolderName = ""
                    showNewFolderAlert = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .accessibilityLabel(Text("New folder"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    openPicker()
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                }
                .accessibilityLabel(Text("Choose folder"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(Text("Settings"))
            }
        }
        .alert("New folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { createFolder() }
        }
        .alert(
            "Could not create folder",
            isPresented: Binding(
                get: { newFolderError != nil },
                set: { if !$0 { newFolderError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { newFolderError = nil }
        } message: {
            Text(newFolderError ?? "")
        }
        .onAppear { load() }
        .onChange(of: syncManager.revision) { load() }
        .onDisappear { loadTask?.cancel() }
    }

    private var subfolders: [FolderItem] {
        folders.filter { !$0.isVirtualAll && !$0.isTrash }
    }

    private var trashFolder: FolderItem? {
        folders.first { $0.isTrash }
    }

    private func load() {
        loadTask?.cancel()
        loadTask = Task {
            let loaded = await NoteFileStore.folders(in: root)
            guard !Task.isCancelled else { return }
            folders = loaded
        }
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task { @MainActor in
            do {
                try await NoteFileStore.createFolder(named: name, in: root)
                Haptics.success()
                CloudSyncManager.shared.notifyExternalChange()
                load()
            } catch {
                newFolderError = error.localizedDescription
                Haptics.error()
            }
        }
    }
}
