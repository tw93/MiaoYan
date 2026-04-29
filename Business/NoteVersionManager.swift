import Foundation

final class NoteVersionManager: @unchecked Sendable {
    static let shared = NoteVersionManager()

    private let versionsRoot: URL
    private let maxVersions = 20
    private let minInterval: TimeInterval = 300
    private var lastSaved: [String: Date] = [:]
    private let queue = DispatchQueue(label: "com.tw93.miaoyan.versions")

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        versionsRoot = base.appendingPathComponent("com.tw93.miaoyan/Versions")
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
               self.normalizeForComparison(prev) == self.normalizeForComparison(text) {
                return
            }

            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
            fmt.timeZone = TimeZone(secondsFromGMT: 0)
            fmt.locale = Locale(identifier: "en_US_POSIX")
            let name = fmt.string(from: Date())
            let dest = dir.appendingPathComponent(name + ".md")
            try? text.write(to: dest, atomically: true, encoding: .utf8)

            self.lastSaved[key] = Date()
            self.prune(dir: dir)
        }
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
              all.count > maxVersions else { return }
        all.sorted { $0.lastPathComponent > $1.lastPathComponent }
            .dropFirst(maxVersions)
            .forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
