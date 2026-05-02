import SwiftUI

struct NotesListView: View {
    let folder: FolderItem
    @EnvironmentObject private var appState: AppState
    @State private var notes: [NoteFile] = []
    @State private var showSearch = false
    @State private var showNewNote = false

    var body: some View {
        Group {
            if notes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "note.text")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("暂无笔记")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                notesList
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showNewNote = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
        .sheet(isPresented: $showNewNote) {
            NewNoteView(folder: folder)
                .environmentObject(appState)
        }
        .navigationDestination(isPresented: $showSearch) {
            if let root = appState.rootURL {
                SearchView(root: root)
            }
        }
        .onAppear { loadNotes() }
        .onChange(of: showNewNote) { _ in
            if !showNewNote { loadNotes() }
        }
    }

    private var notesList: some View {
        List(notes) { note in
            NavigationLink {
                NoteDetailView(note: note)
            } label: {
                NoteRow(note: note)
            }
        }
        .listStyle(.plain)
        .refreshable { loadNotes() }
    }

    private func loadNotes() {
        notes = FileReader.notes(in: folder.url)
    }
}

private struct NoteRow: View {
    let note: NoteFile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
            }
            if !note.preview.isEmpty {
                Text(note.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(relativeDate(note.modifiedDate))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 60)
    }

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func relativeDate(_ date: Date) -> String {
        Self.dateFormatter.localizedString(for: date, relativeTo: Date())
    }
}
