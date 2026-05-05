import CryptoKit
import Foundation

/// On-disk snapshot of the most recent notes shown on the Notes tab.
/// Persisted between launches so a returning user sees their cards
/// instantly on cold start instead of waiting for NSMetadataQuery to
/// re-gather the iCloud catalog and `recentNotes` to re-enumerate.
///
/// We intentionally store only fields needed to render the card chrome
/// (title + modified date). Preview text stays lazy via NotePreviewCache
/// — adding it here would multiply disk usage with limited UX gain.
struct RecentNotesSnapshot: Codable {
    let rootURLString: String
    let savedAt: Date
    let notes: [Entry]

    struct Entry: Codable {
        let urlString: String
        let title: String
        let modifiedDate: Date
    }
}

@MainActor
final class RecentNotesCache {
    static let shared = RecentNotesCache()

    /// Memoise the last decoded snapshot per root key so repeated
    /// `snapshot(for:)` calls during a single session don't re-read /
    /// re-decode JSON. Cleared implicitly when `save(_:for:)` overwrites.
    private var memoryCache: [String: RecentNotesSnapshot] = [:]

    private init() {}

    /// Synchronous lookup. Memory hit first, then a one-shot disk read.
    /// Safe to call on the main thread on a hot path — JSON decode of
    /// ~40 entries is sub-millisecond.
    func snapshot(for root: URL) -> RecentNotesSnapshot? {
        let key = cacheKey(for: root)
        if let mem = memoryCache[key] { return mem }
        guard let snapshot = readFromDisk(key: key) else { return nil }
        // Defence against MD5 collisions: the snapshot's stored
        // rootURLString must match the root we were asked about. Without
        // this, a stale snapshot from a previous folder could surface.
        guard snapshot.rootURLString == root.absoluteString else { return nil }
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
        let snapshot = RecentNotesSnapshot(
            rootURLString: root.absoluteString,
            savedAt: Date(),
            notes: notes.map {
                RecentNotesSnapshot.Entry(
                    urlString: $0.url.absoluteString,
                    title: $0.title,
                    modifiedDate: $0.modifiedDate
                )
            }
        )
        let key = cacheKey(for: root)
        memoryCache[key] = snapshot
        Task.detached(priority: .background) {
            Self.writeToDisk(snapshot, key: key)
        }
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
}
