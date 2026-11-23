import Foundation

final class NoteVersionManager: @unchecked Sendable {
    static let shared = NoteVersionManager()

    private let versionsRoot: URL
    private let maxVersions = 20
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
    func saveVersionIfNeeded(for note: Note, force: Bool = false, completion: (@MainActor @Sendable () -> Void)? = nil) {
        let key = versionKey(for: note.url)
        let text = note.content.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion?()
            return
        }
        saveVersion(key: key, text: text, force: force, completion: completion)
    }

    private func saveVersion(key: String, text: String, force: Bool, completion: (@MainActor @Sendable () -> Void)? = nil) {
        queue.async { [weak self] in
            defer { DispatchQueue.main.async { completion?() } }
            guard let self else { return }
            if !force, let last = self.lastSaved[key], Date().timeIntervalSince(last) < self.minInterval {
                return
            }

            let dir = self.versionsRoot.appendingPathComponent(key)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            if let latest = self.versionsInDir(dir).first,
                let prev = try? String(contentsOf: latest.url, encoding: .utf8),
                self.normalizeForComparison(prev) == self.normalizeForComparison(text)
            {
                return
            }

            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
            fmt.timeZone = TimeZone(secondsFromGMT: 0)
            fmt.locale = Locale(identifier: "en_US_POSIX")
            let name = fmt.string(from: Date())
            let dest = dir.appendingPathComponent(name + ".md")
            do {
                try text.write(to: dest, atomically: true, encoding: .utf8)
            } catch {
                // Not marked as saved, so the next save tries again instead of
                // skipping the whole interval without a snapshot.
                DispatchQueue.main.async { AppDelegate.trackError(error, context: "NoteVersionManager.saveVersion") }
                return
            }

            self.lastSaved[key] = Date()
            self.prune(dir: dir)
            let written = Int64(text.utf8.count)
            if let size = self.historySize, size + written <= Self.libraryBudget {
                self.historySize = size + written
            } else {
                self.historySize = Self.keepWithinBudget(root: self.versionsRoot, budget: Self.libraryBudget)
            }
        }
    }

    /// Every note's versions together stay under this: 20 versions of a
    /// few long notes, kept forever, otherwise grow without a ceiling
    /// (quiet-md keeps the same 200 MiB, 2026-11-21).
    static let libraryBudget: Int64 = 200 << 20

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

    /// Removes the oldest versions across all notes until the history fits
    /// in `budget`, never a note's newest one, so each note keeps the
    /// version it can always go back to. Version files are named by their
    /// UTC time, so names sort oldest first in every folder alike. Returns
    /// the size left.
    @discardableResult
    static func keepWithinBudget(root: URL, budget: Int64) -> Int64 {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let folders = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        var removable: [(url: URL, size: Int64)] = []
        // Only real folders and files named as a version are counted or
        // removed: a symlink, a .DS_Store or anything else left in the folder
        // is neither, and must not pass for a note's newest version.
        for folder in folders {
            let folderValues = try? folder.resourceValues(forKeys: Set(keys))
            guard folderValues?.isDirectory == true, folderValues?.isSymbolicLink != true else { continue }
            let files = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
            let versions = files.filter { file in
                let values = try? file.resourceValues(forKeys: Set(keys))
                return values?.isRegularFile == true && values?.isSymbolicLink != true && isVersionFileName(file.lastPathComponent)
            }
            let newestFirst = versions.sorted { $0.lastPathComponent > $1.lastPathComponent }
            for (index, file) in newestFirst.enumerated() {
                let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                total += size
                if index > 0 { removable.append((file, size)) }
            }
        }
        guard total > budget else { return total }
        for file in removable.sorted(by: { $0.url.lastPathComponent < $1.url.lastPathComponent }) {
            guard total > budget else { break }
            if (try? manager.removeItem(at: file.url)) != nil { total -= file.size }
        }
        return total
    }

    /// `2026-11-21T10-00-00Z.md`, the name `saveVersion` gives a version.
    static func isVersionFileName(_ name: String) -> Bool {
        name.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}Z\.md$"#, options: .regularExpression) != nil
    }

    @MainActor
    func versions(for note: Note) -> [(date: Date, url: URL)] {
        let dir = versionsRoot.appendingPathComponent(versionKey(for: note.url))
        return versionsInDir(dir)
    }

    private func versionsInDir(_ dir: URL) -> [(date: Date, url: URL)] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .compactMap { url -> (Date, URL)? in
                guard let d = fmt.date(from: url.deletingPathExtension().lastPathComponent) else { return nil }
                return (d, url)
            }
            .sorted { $0.0 > $1.0 } ?? []
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
                try? manager.moveItem(at: source, to: target)
            } else {
                for file in (try? manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? [] {
                    try? manager.moveItem(at: file, to: target.appendingPathComponent(file.lastPathComponent))
                }
                try? manager.removeItem(at: source)
                self?.prune(dir: target)
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
        var hash: UInt64 = 5381
        for byte in url.path.utf8 { hash = hash &* 31 &+ UInt64(byte) }
        return "\(url.deletingPathExtension().lastPathComponent)-\(String(hash, radix: 16))"
    }

    private func normalizeForComparison(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func prune(dir: URL) {
        guard let all = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
            all.count > maxVersions
        else { return }
        all.sorted { $0.lastPathComponent > $1.lastPathComponent }
            .dropFirst(maxVersions)
            .forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
