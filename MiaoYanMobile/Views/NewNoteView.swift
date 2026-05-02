import SwiftUI

struct NewNoteView: View {
    let folder: FolderItem
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                TextField("标题", text: $title)
                    .font(.title2.bold())
                    .focused($titleFocused)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .submitLabel(.next)
                    .onSubmit { titleFocused = false }

                Divider()

                TextEditor(text: $content)
                    .font(.system(size: 16))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .navigationTitle("新建笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { titleFocused = true }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let fileName = trimmedTitle
            .replacingOccurrences(of: "/", with: ":")
            .replacingOccurrences(of: ":", with: "-")
        var dest = folder.url.appendingPathComponent(fileName).appendingPathExtension("md")

        var index = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = folder.url.appendingPathComponent("\(fileName) \(index)").appendingPathExtension("md")
            index += 1
        }

        let body = content.isEmpty ? "" : content
        try? CloudSyncManager.shared.writeFile(content: body, to: dest)
        dismiss()
    }
}
