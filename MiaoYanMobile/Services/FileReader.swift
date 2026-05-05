import Foundation

struct NoteFile: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let title: String
    let modifiedDate: Date
    let createdDate: Date
    var preview: String
    let isPinned: Bool
    let byteSize: Int64

    /// Hydrate from a persisted snapshot entry without touching disk.
    /// Used on cold start to render Notes-tab cards instantly while the
    /// real `recentNotes` reload runs in the background. Skipping
    /// `resourceValues(forKeys:)` matters because that call can block
    /// for seconds on iCloud placeholder files that haven't synced
    /// down yet.
    init(snapshotEntry entry: RecentNotesSnapshot.Entry) {
        self.id = entry.urlString
        self.url = URL(string: entry.urlString) ?? URL(fileURLWithPath: "/")
        self.title = entry.title
        self.modifiedDate = entry.modifiedDate
        self.createdDate = entry.modifiedDate
        self.byteSize = 0
        self.isPinned = self.url.lastPathComponent.hasPrefix("📌")
        self.preview = ""
    }

    /// Lightweight initializer that does not touch file contents.
    /// Preview is filled in lazily by `NoteFileStore.fillPreviews(for:)`.
    init(url: URL, preview: String = "") {
        let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .creationDateKey,
            .fileSizeKey,
        ])
        let fallbackAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)

        self.id = url.absoluteString
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
        self.modifiedDate =
            values?.contentModificationDate
            ?? fallbackAttributes?[.modificationDate] as? Date
            ?? Date.distantPast
        self.createdDate =
            values?.creationDate
            ?? fallbackAttributes?[.creationDate] as? Date
            ?? modifiedDate
        self.byteSize = Int64(values?.fileSize ?? 0)
        self.isPinned = url.lastPathComponent.hasPrefix("📌")
        self.preview = preview
    }

    static func == (lhs: NoteFile, rhs: NoteFile) -> Bool {
        lhs.url == rhs.url
            && lhs.modifiedDate == rhs.modifiedDate
            && lhs.preview == rhs.preview
    }
}

struct FolderItem: Identifiable, Sendable {
    let id: String
    let url: URL
    let name: String
    let noteCount: Int
    let isTrash: Bool
    let isVirtualAll: Bool

    init(url: URL, name: String, noteCount: Int, isTrash: Bool = false, isVirtualAll: Bool = false) {
        self.id = url.absoluteString + (isVirtualAll ? "#all" : "")
        self.url = url
        self.name = name
        self.noteCount = noteCount
        self.isTrash = isTrash
        self.isVirtualAll = isVirtualAll
    }
}

enum NoteFileStore {
    private static let allowedExtensions: Set<String> = ["md", "markdown", "txt"]
    private static let ignoredFolderNames: Set<String> = ["i", "files", ".Trash", "Trash"]
    private static let previewByteLimit = 900
    private static let recentNoteLimit = 40
    /// Bytes read off disk for search snippet matching. Most matches in
    /// Markdown notes occur near the head (titles, intros, keywords).
    /// Reading 16KB instead of the whole file (and bypassing
    /// NSFileCoordinator) drops a 1500-note search from several seconds
    /// to <1s.
    private static let searchReadByteLimit = 16 * 1024

    // MARK: - Preview noise stripping

    /// Pre-compiled regexes for `stripPreviewNoise`. Compiling per-call
    /// would dominate CPU for a 1500-note search.
    nonisolated(unsafe) private static let htmlTagRegex = try? NSRegularExpression(
        pattern: "<[^>]+>", options: [])
    nonisolated(unsafe) private static let mdImageRegex = try? NSRegularExpression(
        pattern: "!\\[[^\\]]*\\]\\([^)]*\\)", options: [])
    nonisolated(unsafe) private static let mdLinkRegex = try? NSRegularExpression(
        pattern: "\\[([^\\]]*)\\]\\([^)]*\\)", options: [])
    nonisolated(unsafe) private static let bareUrlRegex = try? NSRegularExpression(
        pattern: "https?://\\S+", options: [])
    nonisolated(unsafe) private static let inlineCodeRegex = try? NSRegularExpression(
        pattern: "`([^`]+)`", options: [])
    nonisolated(unsafe) private static let whitespaceRunRegex = try? NSRegularExpression(
        pattern: "\\s+", options: [])

    /// Remove HTML tags and Markdown noise (raw image syntax, link URLs,
    /// bare URLs, inline-code backticks) so card previews and search
    /// snippets read like prose instead of source. Markdown link text is
    /// preserved (`[label](url)` → `label`); inline-code text is
    /// preserved minus the backticks. Whitespace runs collapse to a
    /// single space at the end.
    ///
    /// Used by `previewTextSync` (note cards) and `extractSnippet`
    /// (search results) so both surfaces share the same cleanup rules.
    nonisolated static func stripPreviewNoise(_ input: String) -> String {
        var s = input
        let full = { (str: String) in NSRange(location: 0, length: (str as NSString).length) }
        if let re = htmlTagRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: "")
        }
        if let re = mdImageRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: "")
        }
        if let re = mdLinkRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: "$1")
        }
        if let re = bareUrlRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: "")
        }
        if let re = inlineCodeRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: "$1")
        }
        if let re = whitespaceRunRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: " ")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Read up to `maxBytes` from a file via plain FileHandle, no
    /// NSFileCoordinator. Used only by search snippet scanning where:
    ///  - the read is read-only and short-lived
    ///  - per-file coordinator overhead (~10-50ms) dominates over
    ///    the actual IO cost for 16KB reads
    ///  - the caller has already verified the file is local (not an
    ///    iCloud placeholder)
    /// Do NOT use this for content the user opens — those still go
    /// through `coordinatedReadString` for write-conflict safety.
    nonisolated static func readFirstBytes(at url: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Folders

    /// Off-main folder enumeration with light note counts.
    /// Does not instantiate `NoteFile` for every URL.
    static func folders(in root: URL) async -> [FolderItem] {
        await Task.detached(priority: .userInitiated) {
            foldersSync(in: root)
        }.value
    }

    nonisolated static func foldersSync(in root: URL) -> [FolderItem] {
        let fm = FileManager.default
        guard
            let items = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        let allNoteURLs = recursiveNoteURLsSync(in: root)
        func noteCount(containedIn folder: URL) -> Int {
            let folderPath = folder.standardizedFileURL.path
            return allNoteURLs.reduce(0) { count, noteURL in
                noteURL.standardizedFileURL.path.hasPrefix(folderPath + "/") ? count + 1 : count
            }
        }

        var result: [FolderItem] = []
        result.append(
            FolderItem(
                url: root,
                name: "All Notes",
                noteCount: allNoteURLs.count,
                isVirtualAll: true
            )
        )

        let dirs =
            items
            .filter { isDirectory($0) }
            .filter { !ignoredFolderNames.contains($0.lastPathComponent) }
            .filter { !$0.lastPathComponent.localizedCaseInsensitiveContains("Trash") }
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        for dir in dirs {
            result.append(
                FolderItem(
                    url: dir,
                    name: dir.lastPathComponent,
                    noteCount: noteCount(containedIn: dir)
                )
            )
        }

        let trashURL = root.appendingPathComponent("Trash")
        if fm.fileExists(atPath: trashURL.path) {
            let count = noteCountSync(in: trashURL, recursive: true)
            result.append(FolderItem(url: trashURL, name: "Trash", noteCount: count, isTrash: true))
        }

        return result
    }

    // MARK: - Notes

    /// Off-main note enumeration. Returns notes without preview text;
    /// call `fillPreviews(for:)` to load previews lazily.
    ///
    /// iCloud-aware path: on cold start NSMetadataQuery already has the
    /// catalog in memory while `FileManager.enumerator` over the
    /// just-attached ubiquity container can return zero results — or
    /// block for seconds — until iCloud finishes placing local
    /// placeholder files. So when the cloud catalog has anything for
    /// this folder we return it directly and skip the disk enumeration
    /// entirely; subsequent revision-driven reloads (after files
    /// download) keep the list fresh. Only when the cloud catalog is
    /// empty (non-iCloud root, or query not yet started) do we fall back
    /// to disk enumeration.
    static func notes(in folder: URL, recursive: Bool = false) async -> [NoteFile] {
        let cloudURLs = await CloudSyncManager.shared.cloudNoteURLs(under: folder)
        let scopedCloud =
            recursive
            ? cloudURLs
            : cloudURLs.filter {
                $0.deletingLastPathComponent().resolvingSymlinksInPath().path
                    == folder.resolvingSymlinksInPath().path
            }
        if !scopedCloud.isEmpty {
            return await Task.detached(priority: .userInitiated) {
                scopedCloud.map { NoteFile(url: $0) }.sorted(by: sortNotes)
            }.value
        }
        return await Task.detached(priority: .userInitiated) {
            notesSync(in: folder, recursive: recursive)
        }.value
    }

    /// Off-main; returns notes WITHOUT preview text. The previous
    /// implementation eagerly read 900 bytes from each file via FileHandle to
    /// build preview strings — that pattern blocked indefinitely under iCloud
    /// because opening a non-resident file triggers a synchronous on-demand
    /// download. With ~50 notes that meant the list was empty for minutes.
    /// Preview is now lazy-loaded per visible card (see NoteCard / NotePreviewCache).
    nonisolated static func notesSync(in folder: URL, recursive: Bool = false) -> [NoteFile] {
        let urls = recursive ? recursiveNoteURLsSync(in: folder) : directNoteURLsSync(in: folder)
        return
            urls
            .map { NoteFile(url: $0) }
            .sorted(by: sortNotes)
    }

    /// Lazy preview helper for the card layer. Returns nil for iCloud files
    /// that haven't been downloaded yet, so visible cards never trigger a
    /// blocking download just to render a two-line snippet. Once the file is
    /// downloaded by NSMetadataQuery, the next revision bump re-renders the
    /// card and this returns the preview.
    nonisolated static func previewIfDownloaded(for url: URL) -> String? {
        let status =
            (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                .ubiquitousItemDownloadingStatus)
        // Non-iCloud files have no status (nil) — proceed.
        // iCloud files only proceed when fully current locally.
        if let status, status != .current { return nil }
        return previewTextSync(for: url)
    }

    static func recentNotes(in root: URL, limit: Int = recentNoteLimit) async -> [NoteFile] {
        // Cloud-first: see `notes(in:recursive:)` doc for the rationale.
        // The home screen used to get stuck on "Loading…" because
        // FileManager.enumerator on the iCloud container blocked while
        // placeholders synced; now we read directly from the in-memory
        // NSMetadataQuery catalog and only touch disk when there is no
        // cloud catalog at all.
        let cloudURLs = await CloudSyncManager.shared.cloudNoteURLs(under: root)
        if !cloudURLs.isEmpty {
            return await Task.detached(priority: .userInitiated) {
                Array(
                    cloudURLs.map { NoteFile(url: $0) }.sorted(by: sortNotes).prefix(limit)
                )
            }.value
        }
        return await Task.detached(priority: .userInitiated) {
            Array(notesSync(in: root, recursive: true).prefix(limit))
        }.value
    }

    // MARK: - Lightweight counts

    nonisolated static func noteCountSync(in folder: URL, recursive: Bool) -> Int {
        if recursive {
            return recursiveNoteURLsSync(in: folder).count
        }
        return directNoteURLsSync(in: folder).count
    }

    // MARK: - Read / write

    static func readContent(of note: NoteFile) async -> String {
        await Task.detached(priority: .userInitiated) {
            (try? coordinatedReadString(at: note.url)) ?? ""
        }.value
    }

    static func write(content: String, to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try coordinatedWriteString(content, to: url)
        }.value
    }

    @MainActor
    static func createNote(title: String, content: String, in folder: FolderItem) async throws -> URL {
        let baseName = sanitizedFileName(title)
        let dest = await Task.detached(priority: .userInitiated) { () -> URL in
            var dest = folder.url.appendingPathComponent(baseName).appendingPathExtension("md")
            var index = 1
            while FileManager.default.fileExists(atPath: dest.path) {
                dest = folder.url.appendingPathComponent("\(baseName) \(index)").appendingPathExtension("md")
                index += 1
            }
            return dest
        }.value
        try await write(content: content, to: dest)
        return dest
    }

    @MainActor
    static func trash(_ note: NoteFile) async throws {
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.trashItem(at: note.url, resultingItemURL: nil)
        }.value
    }

    nonisolated static func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
            ?? Date.distantPast
    }

    static func modificationDateOffMain(for url: URL) async -> Date {
        await Task.detached(priority: .userInitiated) {
            modificationDate(for: url)
        }.value
    }

    // MARK: - Search

    /// Result of a single-file search probe. `skipped` separates iCloud files
    /// that haven't downloaded yet (which we deliberately don't trigger to
    /// download) from genuine non-matches.
    private enum SearchHitResult {
        case hit(NoteFile, snippet: String)
        case skippedNotDownloaded
        case noMatch
    }

    struct SearchOutcome: Sendable {
        let hits: [(NoteFile, String)]
        /// Number of iCloud files skipped because they haven't downloaded yet.
        /// Surface this in UI so users know why a recently-added note might
        /// not show up — they can wait for iCloud or pull-to-refresh.
        let skippedDownloadingCount: Int
    }

    private static let searchMaxConcurrent = 8

    /// Cancellation-aware search across the library.
    ///
    /// Performance / correctness properties:
    ///  1. URL source is cloud-aware: NSMetadataQuery's in-memory catalog
    ///     is the primary source on iCloud, with FileManager enumeration
    ///     as a fallback for non-iCloud roots. Same rationale as
    ///     `recentNotes` — `FileManager.enumerator` over a freshly
    ///     attached ubiquity container can hang for seconds.
    ///  2. Skip iCloud files whose data isn't local. Reading them would
    ///     block while iCloud downloads each file, freezing the UI for
    ///     seconds per file. Users learn about skipped files via
    ///     `skippedDownloadingCount` so they can wait or refresh.
    ///  3. Each file body read is capped at `searchReadByteLimit` (16KB)
    ///     and bypasses NSFileCoordinator (`readFirstBytes`). For 1500
    ///     notes this drops total IO from "full read x coordinator"
    ///     (multi-second) to "16KB head x raw FileHandle" (sub-second).
    ///  4. Probes run in parallel capped at `searchMaxConcurrent`.
    static func search(query: String, in root: URL) async -> SearchOutcome {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return SearchOutcome(hits: [], skippedDownloadingCount: 0)
        }

        // Primary URL source: NSMetadataQuery catalog (cloud + downloaded).
        // Fallback: disk enumeration (non-iCloud roots, or pre-init).
        let cloudURLs = await CloudSyncManager.shared.cloudNoteURLs(under: root)

        return await Task.detached(priority: .userInitiated) { () -> SearchOutcome in
            let urls = cloudURLs.isEmpty ? recursiveNoteURLsSync(in: root) : cloudURLs
            let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

            return await withTaskGroup(of: SearchHitResult.self) { group in
                var iterator = urls.makeIterator()
                var inFlight = 0

                // Prime the window with up to `searchMaxConcurrent` probes.
                while inFlight < searchMaxConcurrent, let url = iterator.next() {
                    group.addTask {
                        searchSingleFile(url: url, query: normalizedQuery, options: opts)
                    }
                    inFlight += 1
                }

                var hits: [(NoteFile, String)] = []
                hits.reserveCapacity(min(urls.count, 64))
                var skipped = 0

                while inFlight > 0, let result = await group.next() {
                    inFlight -= 1
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    switch result {
                    case .hit(let note, let snippet):
                        hits.append((note, snippet))
                    case .skippedNotDownloaded:
                        skipped += 1
                    case .noMatch:
                        break
                    }
                    // Refill the window so we keep `searchMaxConcurrent`
                    // probes running until the URL list is exhausted.
                    if let url = iterator.next() {
                        group.addTask {
                            searchSingleFile(url: url, query: normalizedQuery, options: opts)
                        }
                        inFlight += 1
                    }
                }

                hits.sort { $0.0.modifiedDate > $1.0.modifiedDate }
                return SearchOutcome(hits: hits, skippedDownloadingCount: skipped)
            }
        }.value
    }

    nonisolated private static func searchSingleFile(
        url: URL, query: String, options: String.CompareOptions
    ) -> SearchHitResult {
        // Skip files that aren't downloaded yet. nil status = non-iCloud
        // (always proceed). Anything other than `.current` means the file
        // body isn't local — opening it would trigger a blocking download.
        let downloadStatus =
            (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                .ubiquitousItemDownloadingStatus)
        if let downloadStatus, downloadStatus != .current {
            return .skippedNotDownloaded
        }

        let title = url.deletingPathExtension().lastPathComponent
        let titleHit = title.range(of: query, options: options) != nil

        // Read only the head of the file (16KB by default) and bypass
        // NSFileCoordinator. The body scan only needs enough text for
        // matching + snippet — full reads via coordinator dominate the
        // search latency for large libraries. See `readFirstBytes` doc.
        guard let head = readFirstBytes(at: url, maxBytes: searchReadByteLimit) else {
            return .noMatch
        }

        let bodyHit = head.range(of: query, options: options) != nil
        // Title-only match still counts as a hit even if the body doesn't
        // contain the query; snippet falls back to the body's opening line.
        guard titleHit || bodyHit else { return .noMatch }

        // `extractSnippet` re-finds the match in the cleaned text, so
        // passing `knownRange` (which referred to the raw `head`) would
        // be misleading — drop it.
        let snippet = extractSnippet(from: head, query: query)
        return .hit(NoteFile(url: url, preview: ""), snippet: snippet)
    }

    // MARK: - Internal: URL enumeration

    nonisolated private static func directNoteURLsSync(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ))?
        .filter { !isDirectory($0) && isNoteURL($0) } ?? []
    }

    nonisolated private static func recursiveNoteURLsSync(in root: URL) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            if isDirectory(url) {
                let name = url.lastPathComponent
                if ignoredFolderNames.contains(name) || name.hasPrefix(".") {
                    enumerator.skipDescendants()
                }
                continue
            }
            if isNoteURL(url) {
                urls.append(url)
            }
        }
        return urls
    }

    nonisolated private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    nonisolated private static func isNoteURL(_ url: URL) -> Bool {
        allowedExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Internal: file IO

    nonisolated static func previewTextSync(for url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: previewByteLimit),
            let head = String(data: data, encoding: .utf8)
        else { return "" }

        let lines = head.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("#")
                    && !line.hasPrefix("---")
                    && !line.hasPrefix("```")
                    && !line.hasPrefix("!")
            }

        // Line filter handles whole-line markdown noise; the post-pass
        // handles inline noise (HTML tags, ![](...), [text](url), bare
        // URLs, inline-code backticks) that survives the line filter.
        return stripPreviewNoise(lines.prefix(2).joined(separator: " "))
    }

    nonisolated static func coordinatedReadString(at url: URL) throws -> String {
        var coordinationError: NSError?
        var readError: Error?
        var content = ""
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            do {
                content = try String(contentsOf: readURL, encoding: .utf8)
            } catch {
                readError = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        return content
    }

    nonisolated static func coordinatedWriteString(_ content: String, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { writeURL in
            do {
                try content.write(to: writeURL, atomically: true, encoding: .utf8)
            } catch {
                writeError = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    // MARK: - Helpers

    nonisolated private static func sortNotes(_ a: NoteFile, _ b: NoteFile) -> Bool {
        if a.isPinned != b.isPinned { return a.isPinned }
        if a.modifiedDate != b.modifiedDate { return a.modifiedDate > b.modifiedDate }
        return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }

    nonisolated private static func sanitizedFileName(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let parts = trimmed.components(separatedBy: invalid)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = parts.joined(separator: "-")
        return joined.isEmpty ? "Untitled" : joined
    }

    /// Extract a 140-ish-character window around a match. If `knownRange` is
    /// supplied (caller already located the match), skip the redundant
    /// `range(of:)` rescan — that doubles search cost for every hit.
    /// `knownRange` is intentionally ignored now: it referred to the raw
    /// body text, but we always operate on `stripPreviewNoise(content)`
    /// which has different offsets. Re-finding the query in the cleaned
    /// text is cheap (cleaned text is shorter and we already filtered
    /// out non-matches upstream).
    nonisolated private static func extractSnippet(
        from content: String, query: String, knownRange: Range<String.Index>? = nil
    ) -> String {
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let cleaned = stripPreviewNoise(content)
        guard let range = cleaned.range(of: query, options: opts) else {
            // Title-only match (no body hit) — fall back to a clean
            // opening snippet rather than echoing raw markdown.
            return String(cleaned.prefix(140))
        }
        let startDistance = cleaned.distance(from: cleaned.startIndex, to: range.lowerBound)
        let prefixStart = max(0, startDistance - 48)
        let startIndex = cleaned.index(cleaned.startIndex, offsetBy: prefixStart)
        let endDistance = min(cleaned.count, startDistance + query.count + 96)
        let endIndex = cleaned.index(cleaned.startIndex, offsetBy: endDistance)
        let prefix = prefixStart > 0 ? "…" : ""
        let suffix = endDistance < cleaned.count ? "…" : ""
        return prefix + String(cleaned[startIndex..<endIndex]) + suffix
    }
}
