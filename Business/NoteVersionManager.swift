import Foundation
import MiaoYanCore

final class NoteVersionManager: @unchecked Sendable {
    static let shared = NoteVersionManager()

    private let versionsRoot: URL
    private let minInterval: TimeInterval = 300
    private var lastSaved: [String: Date] = [:]
    /// The history's size as of the last walk plus what was written since,
    /// never under the real size: the ceiling walks every version folder,
    /// so it runs once per launch and again only when this passes it.
    private var historySize: Int64?
    private let queue = DispatchQueue(label: "com.tw93.miaoyan.versions")

    private init() {
        // Unit tests run inside the app and used to file their fixture notes
        // into the user's real history, hundreds of directories over time.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || Self.isScripted {
            versionsRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanTestVersions-\(ProcessInfo.processInfo.processIdentifier)")
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            versionsRoot = base.appendingPathComponent("com.tw93.miaoyan/Versions")
        }
        try? FileManager.default.createDirectory(at: versionsRoot, withIntermediateDirectories: true)
    }

    @MainActor
    func saveVersionIfNeeded(
        for note: Note, force: Bool = false, exact: Bool = false, completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        let key = versionKey(for: note.url)
        let text = note.content.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion?()
            return
        }
        saveVersion(key: key, text: text, force: force, exact: exact, completion: completion)
    }

    private func saveVersion(
        key: String, text: String, force: Bool, exact: Bool = false, completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        queue.async { [weak self] in
            defer { DispatchQueue.main.async { completion?() } }
            guard let self else { return }
            if !force, let last = self.lastSaved[key], Date().timeIntervalSince(last) < self.minInterval {
                return
            }

            let dir = self.versionsRoot.appendingPathComponent(key)
            let written: URL?
            do {
                written = try NoteVersionFiles.save(text, in: dir, exact: exact)
            } catch {
                // Not marked as saved, so the next save tries again instead of
                // skipping the whole interval without a snapshot.
                DispatchQueue.main.async { AppDelegate.trackError(error, context: "NoteVersionManager.saveVersion") }
                return
            }
            // The same text as the newest version writes nothing.
            guard written != nil else { return }

            self.lastSaved[key] = Date()
            let size = Int64(text.utf8.count)
            if let history = self.historySize, history + size <= NoteVersionFiles.budget {
                self.historySize = history + size
            } else {
                self.historySize = NoteVersionFiles.keepWithinBudget(root: self.versionsRoot, budget: NoteVersionFiles.budget)
            }
        }
    }

    /// A scripted run (UIScript) is a Debug or timing build typing into a
    /// scratch library, and those builds share the release app's folder.
    /// Shipped builds never take this path.
    private static var isScripted: Bool {
        #if DEBUG || MIAOYAN_SCRIPT
            return UserDefaults.standard.string(forKey: "MiaoYanScript") != nil
        #else
            return false
        #endif
    }

    @MainActor
    func versions(for note: Note) -> [(date: Date, url: URL)] {
        let dir = versionsRoot.appendingPathComponent(versionKey(for: note.url))
        return NoteVersionFiles.versions(in: dir)
    }

    @MainActor
    func hasVersions(for note: Note) -> Bool {
        let dir = versionsRoot.appendingPathComponent(versionKey(for: note.url))
        return !((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).isEmpty
    }

    @MainActor
    func removeVersions(for note: Note) {
        let dir = versionsRoot.appendingPathComponent(versionKey(for: note.url))
        queue.async {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    /// Versions are filed by path, so a rename, move or trip to the Trash
    /// has to carry them along: otherwise the history vanished from the UI,
    /// a new note at the old path inherited it, and deleting from the Trash
    /// looked under the Trash path and never removed the real directory.
    func moveVersions(from oldURL: URL, to newURL: URL) {
        let oldKey = versionKey(for: oldURL)
        let newKey = versionKey(for: newURL)
        guard oldKey != newKey else { return }
        let source = versionsRoot.appendingPathComponent(oldKey)
        let target = versionsRoot.appendingPathComponent(newKey)
        queue.async { [weak self] in
            let manager = FileManager.default
            guard manager.fileExists(atPath: source.path) else { return }
            if !manager.fileExists(atPath: target.path) {
                do {
                    try manager.moveItem(at: source, to: target)
                } catch {
                    DispatchQueue.main.async { AppDelegate.trackError(error, context: "NoteVersionManager.moveVersions") }
                }
            } else {
                // The source folder goes only once every version left it: a
                // move that failed used to be followed by deleting that
                // version. A file that is no version (`.DS_Store`) is not
                // carried and does not hold the folder back.
                var allMoved = true
                do {
                    for file in try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
                    where NoteVersionFiles.isVersionFileName(file.lastPathComponent) {
                        do {
                            try NoteVersionFiles.merge(version: file, into: target)
                        } catch {
                            allMoved = false
                            DispatchQueue.main.async { AppDelegate.trackError(error, context: "NoteVersionManager.moveVersions.merge") }
                        }
                    }
                } catch {
                    allMoved = false
                    DispatchQueue.main.async { AppDelegate.trackError(error, context: "NoteVersionManager.moveVersions.list") }
                }
                // Finder's `.DS_Store` goes with it; anything else someone
                // put there keeps the folder, which is removed only empty.
                if allMoved {
                    try? manager.removeItem(at: source.appendingPathComponent(".DS_Store"))
                    if (try? manager.contentsOfDirectory(atPath: source.path))?.isEmpty == true {
                        try? manager.removeItem(at: source)
                    }
                }
                NoteVersionFiles.prune(target)
            }
            if let last = self?.lastSaved.removeValue(forKey: oldKey) {
                self?.lastSaved[newKey] = last
            }
        }
    }

    /// Returns once queued version work has run; tests use it to read the result.
    func waitForPendingWork() {
        queue.sync {}
    }

    private func versionKey(for url: URL) -> String {
        NoteVersionFiles.folderName(for: url)
    }
}
