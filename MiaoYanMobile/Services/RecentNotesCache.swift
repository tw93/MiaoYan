import CryptoKit
import Foundation

/// On-disk snapshot of the most recent notes shown on the Notes tab.
/// Persisted between launches so a returning user sees their cards
/// instantly on cold start instead of waiting for NSMetadataQuery to
/// re-gather the iCloud catalog and `recentNotes` to re-enumerate.
///
/// Stores the card fields needed for the Notes tab's first frame. Preview
/// text is included because the list can otherwise render title/date instantly
/// but leave a visually empty detail band until each iCloud file is re-read.
struct RecentNotesSnapshot: Codable {
    let rootURLString: String
    let savedAt: Date
    let notes: [Entry]

    struct Entry: Codable {
        /// Stored as a plain file-system path (e.g. `/private/var/…/note.md`)
        /// rather than `url.absoluteString` because `URL(string:)` cannot
        /// round-trip paths that contain spaces or non-ASCII characters.
        /// Reconstruct the URL with `URL(fileURLWithPath: path)`.
        let path: String
        let title: String
        let modifiedDate: Date
        let preview: String
        /// Pin state captured at snapshot time so the cold-start
        /// `NoteFile(snapshotEntry:)` path can sort pinned notes without
        /// a disk read.
        let isPinned: Bool

        init(path: String, title: String, modifiedDate: Date, preview: String, isPinned: Bool) {
            self.path = path
            self.title = title
            self.modifiedDate = modifiedDate
            self.preview = preview
            self.isPinned = isPinned
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            path = try container.decode(String.self, forKey: .path)
            title = try container.decode(String.self, forKey: .title)
            modifiedDate = try container.decode(Date.self, forKey: .modifiedDate)
            // Older snapshots did not persist preview text. They decode as
            // empty and will be backfilled as cards lazily load previews.
            preview = try container.decodeIfPresent(String.self, forKey: .preview) ?? ""
            // Snapshots written before the pin field existed decode as
            // unpinned; the next background reload corrects them.
            isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        }
    }
}

@MainActor
final class RecentNotesCache {
    static let shared = RecentNotesCache()

    /// Memoise the last decoded snapshot per root key so repeated
    /// `snapshot(for:)` calls during a single session don't re-read /
    /// re-decode JSON. Cleared implicitly when `save(_:for:)` overwrites.
    private var memoryCache: [String: RecentNotesSnapshot] = [:]

    /// Keys whose disk read came back empty. Without this a user with no
    /// snapshot re-stats and re-fails the cache file on every `body`
    /// re-evaluation during cold start (the hot path this lookup guards),
    /// because a miss was never memoized. Cleared in `save(_:for:)`.
    private var knownMissing: Set<String> = []
    private var pendingWrites: [String: Task<Void, Never>] = [:]

    private init() {}

    /// Synchronous lookup. Memory hit first, then a one-shot disk read.
    /// Safe to call on the main thread on a hot path — JSON decode of
    /// ~40 entries is sub-millisecond, and misses are memoized.
    func snapshot(for root: URL) -> RecentNotesSnapshot? {
        let key = cacheKey(for: root)
        if let mem = memoryCache[key] { return mem }
        if knownMissing.contains(key) { return nil }
        // Defence against MD5 collisions: the snapshot's stored
        // rootURLString must match the root we were asked about. Without
        // this, a stale snapshot from a previous folder could surface.
        guard let snapshot = readFromDisk(key: key),
            snapshot.rootURLString == root.absoluteString
        else {
            knownMissing.insert(key)
            return nil
        }
        memoryCache[key] = snapshot
        return snapshot
    }

    func hasSnapshot(for root: URL) -> Bool {
        snapshot(for: root) != nil
    }

    /// Capture the current `notes` list as a snapshot. Memory copy is
    /// updated synchronously so subsequent `snapshot(for:)` calls within
    /// the same session see the fresh data; disk write is dispatched
    /// to a background task to keep the main thread free.
    func save(_ notes: [NoteFile], for root: URL) {
        let previousByPath =
            snapshot(for: root)?.notes.reduce(into: [String: RecentNotesSnapshot.Entry]()) { result, entry in
                result[entry.path] = entry
            } ?? [:]
        let snapshot = RecentNotesSnapshot(
            rootURLString: root.absoluteString,
            savedAt: Date(),
            notes: notes.map {
                let previous = previousByPath[$0.url.path]
                let cachedPreview =
                    NotePreviewCache.shared.preview(for: $0.url, modifiedDate: $0.modifiedDate)
                    ?? (previous?.modifiedDate == $0.modifiedDate ? previous?.preview : nil)
                    ?? ""
                return RecentNotesSnapshot.Entry(
                    path: $0.url.path,
                    title: $0.title,
                    modifiedDate: $0.modifiedDate,
                    preview: $0.preview.isEmpty ? cachedPreview : $0.preview,
                    isPinned: $0.isPinned
                )
            }
        )
        let key = cacheKey(for: root)
        memoryCache[key] = snapshot
        knownMissing.remove(key)
        scheduleWrite(snapshot, key: key, delay: .zero)
    }

    /// Apply cached preview strings to freshly-enumerated notes without
    /// trusting stale content. A preview is reused only when path and modified
    /// date both match the snapshot entry.
    func hydratePreviews(_ notes: [NoteFile], for root: URL) -> [NoteFile] {
        guard let snapshot = snapshot(for: root) else { return notes }
        let entriesByPath = snapshot.notes.reduce(into: [String: RecentNotesSnapshot.Entry]()) { result, entry in
            result[entry.path] = entry
        }

        return notes.map { note in
            guard note.preview.isEmpty,
                let entry = entriesByPath[note.url.path],
                entry.modifiedDate == note.modifiedDate,
                !entry.preview.isEmpty
            else { return note }
            var copy = note
            copy.preview = entry.preview
            NotePreviewCache.shared.store(entry.preview, for: note.url, modifiedDate: note.modifiedDate)
            return copy
        }
    }

    /// Backfill the snapshot as visible cards finish lazy preview reads. This
    /// makes the next cold start render title, date and preview together.
    func storePreview(_ preview: String, for note: NoteFile, root: URL) {
        guard !preview.isEmpty, var snapshot = snapshot(for: root) else { return }
        var didChange = false
        let entries = snapshot.notes.map { entry -> RecentNotesSnapshot.Entry in
            guard entry.path == note.url.path,
                entry.modifiedDate == note.modifiedDate,
                entry.preview != preview
            else { return entry }
            didChange = true
            return RecentNotesSnapshot.Entry(
                path: entry.path,
                title: entry.title,
                modifiedDate: entry.modifiedDate,
                preview: preview,
                isPinned: entry.isPinned
            )
        }
        guard didChange else { return }
        snapshot = RecentNotesSnapshot(
            rootURLString: snapshot.rootURLString,
            savedAt: Date(),
            notes: entries
        )
        let key = cacheKey(for: root)
        memoryCache[key] = snapshot
        knownMissing.remove(key)
        scheduleWrite(snapshot, key: key, delay: .milliseconds(300))
    }

    // MARK: - Disk

    /// Cache directory under `Library/Caches/MiaoYanMobile/`. Caches is
    /// the right home: contents persist across launches but the system
    /// is allowed to purge under storage pressure (in which case we
    /// just rebuild on next reload — no data loss because the
    /// authoritative copy is in iCloud).
    nonisolated private static func cacheDirectory() -> URL? {
        guard
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("MiaoYanMobile", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cacheKey(for root: URL) -> String {
        // MD5 truncated to 12 hex chars: enough to keep snapshots from
        // different roots (iCloud / external bookmarks) in separate
        // files. Collisions still possible in theory; the rootURLString
        // sanity check inside `snapshot(for:)` catches them.
        let hash = Insecure.MD5.hash(data: Data(root.absoluteString.utf8))
        return hash.map { String(format: "%02x", $0) }.joined().prefix(12).description
    }

    private func cachePath(for key: String) -> URL? {
        Self.cacheDirectory()?.appendingPathComponent("recent-\(key).json")
    }

    private func readFromDisk(key: String) -> RecentNotesSnapshot? {
        guard let path = cachePath(for: key),
            let data = try? Data(contentsOf: path)
        else { return nil }
        return try? JSONDecoder().decode(RecentNotesSnapshot.self, from: data)
    }

    nonisolated private static func writeToDisk(_ snapshot: RecentNotesSnapshot, key: String) {
        guard let dir = cacheDirectory() else { return }
        let path = dir.appendingPathComponent("recent-\(key).json")
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: path, options: .atomic)
    }

    private func scheduleWrite(_ snapshot: RecentNotesSnapshot, key: String, delay: Duration) {
        pendingWrites[key]?.cancel()
        pendingWrites[key] = Task { [weak self] in
            if delay != .zero {
                do { try await Task.sleep(for: delay) } catch { return }
            }
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .background) {
                Self.writeToDisk(snapshot, key: key)
            }.value
            await MainActor.run {
                self?.pendingWrites[key] = nil
            }
        }
    }
}
