import SwiftUI
import WebKit

enum NoteViewMode {
    case edit
    case preview
}

struct NoteDetailView: View {
    let note: NoteFile
    @State private var content: String = ""
    @State private var mode: NoteViewMode = .edit
    @State private var hasUnsavedChanges = false
    @State private var showDeleteAlert = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            if mode == .edit {
                NoteEditorView(note: note, content: $content)
                    .onChange(of: content) { _ in hasUnsavedChanges = true }
            } else {
                PreviewView(content: content)
            }
        }
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        mode = mode == .edit ? .preview : .edit
                    } label: {
                        Image(systemName: mode == .edit ? "eye" : "pencil")
                    }

                    Menu {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear { loadContent() }
        .onDisappear { saveIfNeeded() }
        .alert("删除笔记", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteNote() }
        } message: {
            Text("确定要删除「\(note.title)」吗？")
        }
    }

    private func loadContent() {
        if let syncedContent = try? CloudSyncManager.shared.readFile(at: note.url) {
            content = syncedContent
        } else {
            content = FileReader.readContent(of: note)
        }
    }

    private func saveIfNeeded() {
        guard hasUnsavedChanges else { return }
        try? CloudSyncManager.shared.writeFile(content: content, to: note.url)
        hasUnsavedChanges = false
    }

    private func deleteNote() {
        try? FileManager.default.removeItem(at: note.url)
        dismiss()
    }
}

private struct PreviewView: View {
    let content: String
    @AppStorage("MiaoYanMobile.FontSize") private var fontSizeRaw = ReaderFontSize.medium.rawValue

    private var fontSize: ReaderFontSize {
        ReaderFontSize(rawValue: fontSizeRaw) ?? .medium
    }

    private var html: String {
        MobileHtmlRenderer.render(markdown: content, fontSize: fontSize.points)
    }

    var body: some View {
        WebReaderView(
            html: html,
            onScrollProgress: { _ in },
            onTap: {}
        )
        .ignoresSafeArea(edges: .bottom)
    }
}
