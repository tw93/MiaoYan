import Foundation

enum CloudSyncStatus {
    case syncing
    case synced
    case offline
    case error(String)
}

// Wrapper to let CloudSyncManager hold NSMetadataQuery across isolation boundaries
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

    @Published var status: CloudSyncStatus = .offline
    @Published var iCloudAvailable = false

    private let queryBox = QueryBox()
    private var iCloudContainerURL: URL?

    nonisolated init() {
        Task { @MainActor in
            setupiCloud()
        }
    }

    private func setupiCloud() {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            iCloudAvailable = false
            status = .offline
            return
        }

        iCloudContainerURL = containerURL.appendingPathComponent("Documents")
        iCloudAvailable = true

        let fm = FileManager.default
        if let dir = iCloudContainerURL, !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        startMonitoring()
    }

    func getNotesDirectory() -> URL? {
        guard iCloudAvailable, let base = iCloudContainerURL else {
            return nil
        }
        return base
    }

    private func startMonitoring() {
        guard iCloudAvailable else { return }

        let query = NSMetadataQuery()
        query.predicate = NSPredicate(
            format: "%K LIKE '*.md' OR %K LIKE '*.markdown' OR %K LIKE '*.txt'",
            NSMetadataItemFSNameKey,
            NSMetadataItemFSNameKey,
            NSMetadataItemFSNameKey
        )
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]

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
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        Task { @MainActor in
            status = .syncing
        }
    }

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        Task { @MainActor in
            status = .synced
        }
    }

    func readFile(at url: URL) throws -> String {
        var nsError: NSError?
        let coordinator = NSFileCoordinator()
        var content = ""

        coordinator.coordinate(readingItemAt: url, options: [], error: &nsError) { readURL in
            content = (try? String(contentsOf: readURL, encoding: .utf8)) ?? ""
        }

        if let nsError {
            throw nsError
        }
        return content
    }

    func writeFile(content: String, to url: URL) throws {
        var nsError: NSError?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(writingItemAt: url, options: [], error: &nsError) { writeURL in
            try? content.write(to: writeURL, atomically: true, encoding: .utf8)
        }

        if let nsError {
            throw nsError
        }
    }

    deinit {
        queryBox.stop()
    }
}
