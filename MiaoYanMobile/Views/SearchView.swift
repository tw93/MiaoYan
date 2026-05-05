import SwiftUI

struct SearchView: View {
    let root: URL
    @State private var query = ""
    @State private var results: [(NoteFile, String)] = []
    @State private var skippedNotDownloadedCount = 0
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(.vertical, 18)
        }
        .background(MobileTheme.paper)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        // Let the toolbar background show ONLY when content scrolls under
        // the search bar. The previous `.visible` lock made iPadOS draw a
        // permanent scroll-edge divider line right below the search drawer
        // even when nothing was scrolled, which read as an abrupt seam
        // against the paper background.
        .toolbarBackground(MobileTheme.paper, for: .navigationBar)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search notes")
        .onChange(of: query) { _, newValue in
            updateSearch(newValue)
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            MobileEmptyContentView(
                systemImage: "magnifyingglass",
                title: "Search your library",
                message: "Titles and note bodies are searched locally."
            )
            .padding(.horizontal, MobileTheme.pagePadding)
            .padding(.top, 8)
        } else if isSearching && results.isEmpty {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small).tint(MobileTheme.accent)
                Text("Searching…")
                    .font(MobileTheme.font(.subheadline))
                    .foregroundStyle(MobileTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
        } else if results.isEmpty {
            MobileEmptyContentView(
                systemImage: "doc.text.magnifyingglass",
                title: "No matches",
                message: "Nothing matched \u{201C}\(query)\u{201D} in this folder."
            )
            .padding(.horizontal, MobileTheme.pagePadding)
            .padding(.top, 8)
            if skippedNotDownloadedCount > 0 {
                pendingDownloadHint
            }
        } else {
            if skippedNotDownloadedCount > 0 {
                pendingDownloadHint
            }
            ForEach(results, id: \.0.id) { note, snippet in
                NavigationLink {
                    NoteDetailView(note: note)
                } label: {
                    SearchResultCard(note: note, snippet: snippet)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, MobileTheme.pagePadding)
            }
        }
    }

    /// Shown when iCloud files were skipped because their bodies aren't yet
    /// local. Search would otherwise have to block on each download — we
    /// surface the count so users know to wait or pull-to-refresh rather than
    /// assuming the note doesn't exist.
    private var pendingDownloadHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MobileTheme.warmAccent)
            Text(
                "\(skippedNotDownloadedCount) iCloud notes still downloading; results will improve as they sync."
            )
            .font(MobileTheme.font(.caption))
            .foregroundStyle(MobileTheme.secondaryInk)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MobileTheme.warmAccent.opacity(0.10))
        )
        .padding(.horizontal, MobileTheme.pagePadding)
    }

    private func updateSearch(_ newValue: String) {
        searchTask?.cancel()
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isSearching = false
            results = []
            skippedNotDownloadedCount = 0
            return
        }
        isSearching = true
        searchTask = Task {
            do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
            guard !Task.isCancelled else { return }
            let outcome = await NoteFileStore.search(query: trimmed, in: root)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                results = outcome.hits
                skippedNotDownloadedCount = outcome.skippedDownloadingCount
                isSearching = false
            }
        }
    }
}

private struct SearchResultCard: View {
    let note: NoteFile
    let snippet: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(note.title)
                .font(MobileTheme.editorialFont(.headline, weight: .semibold))
                .foregroundStyle(MobileTheme.ink)
                .lineLimit(2)
            Text(snippet)
                .font(MobileTheme.font(.subheadline))
                .foregroundStyle(MobileTheme.secondaryInk)
                .lineSpacing(2)
                .lineLimit(3)
        }
        .mobileCard()
    }
}
