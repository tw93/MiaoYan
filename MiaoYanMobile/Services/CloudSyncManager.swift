import Foundation

enum CloudSyncStatus: Equatable {
    case syncing
    case synced
    case offline
    case error(String)
}

private final class QueryBox: @unchecked Sendable {
    var query: NSMetadataQuery?

    func stop() {
        query?.stop()
        query = nil
    }
}

@MainActor
final class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()
    private static let containerIdentifier = "iCloud.com.tw93.miaoyan"
    /// Coalesce iCloud metadata bursts within this window before nudging UI.
    private static let revisionDebounceInterval: TimeInterval = 0.6
    /// Max number of seconds to wait for the iCloud ubiquity container to
    /// become available on cold launch. Provisioning often fails the first
    /// call after install / fresh sign-in but resolves within a few seconds.
    private static let containerProvisionMaxRetries = 7
    private static let containerProvisionRetryDelay: TimeInterval = 1.0
    /// If NSMetadataQuery is still gathering after this many seconds but has
    /// already discovered at least one note, we consider the catalog
    /// "good enough" and let the UI move on. Large libraries (thousands of
    /// notes) and slow simulator iCloud can otherwise leave the syncing
    /// view up indefinitely even though usable data is already available.
    private static let gatheringSoftTimeout: TimeInterval = 5.0

    @Published var status: CloudSyncStatus = .offline
    @Published var iCloudAvailable = false
    @Published private(set) var didFinishInitialSetup = false
    /// True after `NSMetadataQueryDidFinishGathering` fires for the first time
    /// in this process, i.e. the iCloud catalog has been enumerated. Stays
    /// true for the rest of the app lifetime. Views can use this to tell
    /// "iCloud library still gathering" apart from "library is genuinely
    /// empty" — the former should show a friendly syncing placeholder so
    /// users know first-time setup is in progress.
    @Published private(set) var hasFinishedInitialGathering = false
    /// Bumped after a debounced settle period when iCloud reports new structure.
    /// Views observe this and reload their lists; do not bump it for purely
    /// transient status changes.
    @Published var revision = UUID()

    /// Number of note items NSMetadataQuery has discovered so far. Updated
    /// during gathering and on every catalog delta. Drives the first-launch
    /// "Found N notes" counter so users can see something is happening.
    /// We intentionally don't expose download progress: NSMetadataQuery only
    /// indexes the catalog, iCloud doesn't auto-download file content, so
    /// any "X of Y downloaded" number would honestly stay at 0% forever
    /// until the user opens individual notes.
    @Published private(set) var discoveredItemCount = 0

    private let queryBox = QueryBox()
    private var iCloudContainerURL: URL?
    private var pendingRevisionTask: Task<Void, Never>?
    private var gatheringTimeoutTask: Task<Void, Never>?
    /// Set the first time we call `startDownloadingUbiquitousItem` on the
    /// catalog so we don't re-enqueue on every metadata delta.
    private var didKickoffProactiveDownloads = false

    nonisolated init() {
        Task { @MainActor in
            setupiCloud()
        }
    }

    private func setupiCloud() {
        // Fast path: container already provisioned.
        if tryAttachIcloudContainer() { return }

        // Cold launch frequently sees `forUbiquityContainerIdentifier:` return
        // nil even when the user is signed in — the system needs a few
        // seconds to provision the container. Retry on a 1s cadence so we
        // don't immediately fall back to "Choose folder" and force users
        // into the manual Files picker. `didFinishInitialSetup` stays false
        // during retries so the resolving placeholder keeps showing.
        Task { @MainActor [weak self] in
            for _ in 0..<Self.containerProvisionMaxRetries {
                do {
                    try await Task.sleep(for: .seconds(Self.containerProvisionRetryDelay))
                } catch { return }
                guard let self else { return }
                if self.tryAttachIcloudContainer() { return }
            }
            // Gave up: iCloud genuinely unavailable for this device / account.
            guard let self else { return }
            self.iCloudAvailable = false
            self.status = .offline
            self.didFinishInitialSetup = true
            self.hasFinishedInitialGathering = true
        }
    }

    /// Attempt to wire up the iCloud container. Returns true on success so
    /// the caller can stop polling.
    @discardableResult
    private func tryAttachIcloudContainer() -> Bool {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerIdentifier) else {
            return false
        }

        iCloudContainerURL = containerURL.appendingPathComponent("Documents")
        iCloudAvailable = true

        let fm = FileManager.default
        if let dir = iCloudContainerURL, !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        startMonitoring()
        didFinishInitialSetup = true
        return true
    }

    func getNotesDirectory() -> URL? {
        guard iCloudAvailable, let base = iCloudContainerURL else {
            return nil
        }
        return base
    }

    /// Snapshot of NSMetadataQuery URLs that live under `root`. Used as
    /// the primary source of truth on iCloud cold start: the simulator's
    /// (and sometimes a real device's) `FileManager.enumerator` over a
    /// freshly-attached ubiquity container can return zero results, or
    /// even block for seconds, while iCloud is still materialising
    /// placeholder files. NSMetadataQuery already has the cloud catalog
    /// in memory, so we hand it directly to the list views and keep
    /// disk enumeration as the fallback for non-iCloud roots.
    ///
    /// Returns absolute file URLs, deduped (via path) and filtered to
    /// descendants of `root`. Safe to call any time — wraps with
    /// `disableUpdates`/`enableUpdates` to freeze the result set.
    ///
    /// Path comparison resolves symlinks because on iOS the bookmark URL
    /// is often `/var/mobile/...` while NSMetadataItemURLKey returns the
    /// real path `/private/var/mobile/...`. A naive `hasPrefix` against
    /// `standardizedFileURL.path` would filter out every result.
    func cloudNoteURLs(under root: URL) -> [URL] {
        guard let query = queryBox.query else { return [] }
        query.disableUpdates()
        defer { query.enableUpdates() }

        let rootPath = root.resolvingSymlinksInPath().path
        var urls: [URL] = []
        urls.reserveCapacity(query.resultCount)
        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem,
                let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL
            else { continue }
            if url.resolvingSymlinksInPath().path.hasPrefix(rootPath) {
                urls.append(url)
            }
        }
        return urls
    }

    /// Whether the URL points at the app's own iCloud container.
    /// The container is read/write without security-scoped access.
    func isInsideContainer(_ url: URL) -> Bool {
        guard let container = iCloudContainerURL?.standardizedFileURL.path else { return false }
        return url.standardizedFileURL.path.hasPrefix(container)
    }

    private func startMonitoring() {
        guard iCloudAvailable else { return }

        let query = NSMetadataQuery()
        // ENDSWITH[c] is cheaper than three OR'd LIKE clauses and keeps Spotlight
        // indexing focused on note files only.
        query.predicate = NSPredicate(
            format: "%K ENDSWITH[c] '.md' OR %K ENDSWITH[c] '.markdown' OR %K ENDSWITH[c] '.txt'",
            NSMetadataItemFSNameKey,
            NSMetadataItemFSNameKey,
            NSMetadataItemFSNameKey
        )
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]

        // Gathering progress fires every batch while NSMetadataQuery is
        // building the initial catalog — exactly what we need to drive the
        // first-launch "Found N notes" counter before gathering finishes.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryGatheringProgress),
            name: .NSMetadataQueryGatheringProgress,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidFinishGathering),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )

        query.start()
        queryBox.query = query
        status = .syncing

        // Soft timeout: if gathering doesn't naturally finish within
        // `gatheringSoftTimeout` but we already have items, mark as
        // "finished gathering" so the UI moves on. NSMetadataQuery still
        // keeps running in the background and `queryDidUpdate` keeps
        // surfacing further deltas via `revision`. Also kick off proactive
        // downloads here — large libraries can sit in gathering for a
        // while on the simulator, no reason to wait that long to start
        // pulling content.
        gatheringTimeoutTask?.cancel()
        gatheringTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.gatheringSoftTimeout))
            guard let self else { return }
            if !self.hasFinishedInitialGathering, self.discoveredItemCount > 0 {
                self.hasFinishedInitialGathering = true
                self.kickoffProactiveDownloads()
                self.scheduleRevisionBump(immediate: true)
            }
        }
    }

    @objc private func queryGatheringProgress(_ notification: Notification) {
        // During gathering NSMetadataQuery still owns mutation; disable
        // updates around the snapshot read to avoid races. Note that
        // `percentDownloaded` is rarely populated this early — most items
        // start at 0 and become meaningful after `didFinishGathering`. We
        // surface the discovered count here so the syncing UI can show
        // forward motion ("Found 12 notes...") even before downloads start.
        Task { @MainActor in
            captureProgressSnapshot()
        }
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        Task { @MainActor in
            // After initial gathering completes, NSMetadataQuery updates are
            // catalog deltas (file metadata changes, downloads landing,
            // renames, etc.) — they should NOT toggle status to `.syncing`.
            // Toggling on every burst made the SyncRefreshButton flicker
            // (.syncing yellow ⇄ .synced green) and SF Symbol effect start /
            // stop, which in turn caused the empty list ScrollView to
            // micro-jitter on iOS 18. Status stays on whatever it was; we
            // only bump revision so observers can refresh the file list.
            captureProgressSnapshot()
            scheduleRevisionBump()
        }
    }

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        Task { @MainActor in
            status = .synced
            captureProgressSnapshot()
            hasFinishedInitialGathering = true
            gatheringTimeoutTask?.cancel()
            kickoffProactiveDownloads()
            scheduleRevisionBump(immediate: true)
        }
    }

    /// Eagerly request iCloud to materialise every catalogued note so the
    /// first read of any note is instant rather than triggering an on-demand
    /// download. Called once after gathering finishes (or after the soft
    /// timeout fires). Safe to no-op for items already current — iCloud
    /// dedupes the request internally.
    ///
    /// We snapshot URLs on the main actor (NSMetadataQuery requires it),
    /// then issue the downloads on a background task so 1k+ items don't
    /// stall the UI thread.
    private func kickoffProactiveDownloads() {
        guard !didKickoffProactiveDownloads else { return }
        guard let query = queryBox.query else { return }
        didKickoffProactiveDownloads = true

        query.disableUpdates()
        var urls: [URL] = []
        urls.reserveCapacity(query.resultCount)
        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem,
                let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL
            else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status == NSMetadataUbiquitousItemDownloadingStatusCurrent { continue }
            urls.append(url)
        }
        query.enableUpdates()

        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            for url in urls {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }
    }

    /// Read NSMetadataQuery results to update `discoveredItemCount`. Safe to
    /// call from any callback: we wrap with `disableUpdates`/`enableUpdates`
    /// to freeze the result set during the count read. We deliberately do
    /// not iterate per-item attributes — this fires on every catalog delta
    /// and a 1500+ note library would chew CPU for no UI gain.
    private func captureProgressSnapshot() {
        guard let query = queryBox.query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        discoveredItemCount = query.resultCount
    }

    /// Coalesce a burst of metadata callbacks into one revision change, so
    /// observers don't rescan the library for every individual file.
    /// When `settleToSynced` is true the debounced settle also flips status
    /// from `.syncing` back to `.synced`, unless a new burst arrives meanwhile.
    private func scheduleRevisionBump(immediate: Bool = false, settleToSynced: Bool = false) {
        pendingRevisionTask?.cancel()
        if immediate {
            revision = UUID()
            if settleToSynced, status == .syncing {
                status = .synced
            }
            return
        }
        pendingRevisionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(Self.revisionDebounceInterval))
            } catch { return }
            guard !Task.isCancelled else { return }
            revision = UUID()
            if settleToSynced, status == .syncing {
                status = .synced
            }
        }
    }

    /// Force an immediate refresh signal (e.g. after pull-to-refresh or
    /// the header refresh button). Flips status to `.syncing` first so
    /// the SyncRefreshButton actually rotates — without this the user
    /// taps the icon and nothing visibly moves. The icon settles back
    /// to `.synced` at the end of the debounce window (~600ms), giving
    /// a brief "I heard you" rotation that overlaps with the actual
    /// background reload kicked off by the revision bump.
    func notifyExternalChange() {
        status = .syncing
        // Bump revision immediately so list views can start their
        // reload, then schedule a debounced settle that flips the
        // spinner back to `.synced`.
        revision = UUID()
        pendingRevisionTask?.cancel()
        pendingRevisionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.revisionDebounceInterval))
            guard !Task.isCancelled else { return }
            if status == .syncing { status = .synced }
        }
    }

    // MARK: - File IO (off-main wrappers)

    func readFile(at url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try NoteFileStore.coordinatedReadString(at: url)
        }.value
    }

    func writeFile(content: String, to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try NoteFileStore.coordinatedWriteString(content, to: url)
        }.value
        status = .synced
        scheduleRevisionBump(settleToSynced: true)
    }

    deinit {
        queryBox.stop()
    }
}
