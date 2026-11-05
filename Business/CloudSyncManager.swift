import Foundation

enum CloudSyncStatus {
    case syncing
    case synced
    case offline
    case error(String)
}

@MainActor
final class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()

    @Published var status: CloudSyncStatus = .offline
    @Published var iCloudAvailable = false

    private var metadataQuery: NSMetadataQuery?
    private var iCloudContainerURL: URL?

    private init() {
        setupiCloud()
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

    private func startMonitoring() {
        guard iCloudAvailable else { return }

        let query = NSMetadataQuery()
        query.predicate = NSPredicate(
            format: "%K LIKE '*.md' OR %K LIKE '*.markdown' OR %K LIKE '*.txt'",
            NSMetadataItemFSNameKey,
            NSMetadataItemFSNameKey,
            NSMetadataItemFSNameKey)
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
        metadataQuery = query
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

    func writeFile(content: String, to url: URL) throws {
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

    deinit {
        metadataQuery?.stop()
    }
}
