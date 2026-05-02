import SwiftUI
import UniformTypeIdentifiers

struct FolderListView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var syncManager = CloudSyncManager.shared
    @State private var folders: [FolderItem] = []
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.rootURL == nil {
                    emptyState
                } else {
                    folderList
                }
            }
            .navigationTitle("妙言")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    syncStatusIcon
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showPicker = true
                    } label: {
                        Image(systemName: "folder.badge.gear")
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                FolderPickerView { url in
                    appState.selectRootFolder(url)
                    showPicker = false
                }
            }
            .onChange(of: appState.rootURL) { _ in
                loadFolders()
            }
            .onAppear {
                loadFolders()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: syncManager.iCloudAvailable ? "icloud.and.arrow.down" : "folder")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(syncManager.iCloudAvailable ? "iCloud Drive 已就绪" : "选择笔记文件夹")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(syncManager.iCloudAvailable ? "笔记将自动在 Mac 和 iPhone 间同步。" : "请选择一个文件夹存放笔记。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("选择文件夹") {
                showPicker = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var syncStatusIcon: some View {
        Group {
            switch syncManager.status {
            case .syncing:
                Image(systemName: "icloud.and.arrow.up.and.down")
                    .foregroundStyle(.blue)
            case .synced:
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundStyle(.green)
            case .offline:
                Image(systemName: "icloud.slash")
                    .foregroundStyle(.secondary)
            case .error:
                Image(systemName: "exclamationmark.icloud")
                    .foregroundStyle(.red)
            }
        }
        .font(.body)
    }

    private var folderList: some View {
        List(folders) { folder in
            NavigationLink {
                NotesListView(folder: folder)
                    .environmentObject(appState)
            } label: {
                FolderRow(folder: folder)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func loadFolders() {
        guard let root = appState.rootURL else {
            folders = []
            return
        }
        folders = FileReader.folders(in: root)
    }
}

private struct FolderRow: View {
    let folder: FolderItem

    var body: some View {
        HStack {
            Image(systemName: folder.isTrash ? "trash" : "folder")
                .foregroundStyle(folder.isTrash ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                .frame(width: 28)
            Text(folder.name)
            Spacer()
            Text("\(folder.noteCount)")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

struct FolderPickerView: UIViewControllerRepresentable {
    var onSelect: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: (URL) -> Void

        init(onSelect: @escaping (URL) -> Void) {
            self.onSelect = onSelect
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onSelect(url)
        }
    }
}
