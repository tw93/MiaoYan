import SwiftUI

struct SearchView: View {
    let root: URL
    @State private var query = ""
    @State private var results: [(NoteFile, String)] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        Group {
            if query.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("搜索笔记")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty && !isSearching {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("未找到「\(query)」相关笔记")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                resultsList
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索笔记内容")
        .onChange(of: query) { newValue in
            isSearching = !newValue.isEmpty
            searchTask?.cancel()
            guard !newValue.isEmpty else { results = []; return }
            searchTask = Task {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                let found = FileReader.search(query: newValue, in: root)
                await MainActor.run { results = found; isSearching = false }
            }
        }
    }

    private var resultsList: some View {
        List(results, id: \.0.id) { note, snippet in
            NavigationLink {
                NoteReaderView(note: note)
            } label: {
                SearchResultRow(note: note, snippet: snippet, query: query)
            }
        }
        .listStyle(.plain)
    }
}

private struct SearchResultRow: View {
    let note: NoteFile
    let snippet: String
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title)
                .font(.headline)
                .lineLimit(1)
            Text(snippet)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }
}
