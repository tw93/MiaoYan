import Foundation

/// Where pins are shared between devices: iCloud's key-value store in the
/// apps, a dictionary in tests.
public protocol PinCloudStore: AnyObject {
    func array(forKey key: String) -> [Any]?
    func set(_ value: Any?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: PinCloudStore {}

/// Pins that follow a note to every device on one iCloud account
/// (maintainer, 2026-11-21). The App Store Mac app and the iPhone and iPad
/// app share one key-value store, since both are `com.tw93.miaoyan`; it
/// holds the pinned notes' paths inside the library, so the same note in the
/// iCloud Drive folder is named alike on every device. The pin extended
/// attribute both apps always wrote stays: it is what a device without the
/// store reads (the GitHub build has no iCloud entitlement), and what a note
/// outside the library keeps.
///
/// A device that never merged shows a pin when either side has it, and
/// merges its own attribute pins into the store once; from then on the
/// store decides for every note it can name, so an unpin on one device
/// reaches the others. Thread-safe, since the iPhone reads pins while it
/// lists a folder off the main thread.
public final class PinCloud: @unchecked Sendable {
    public static let storeKey = "MiaoYan.PinnedNotes"
    /// What `NSUbiquitousKeyValueStore` puts under
    /// `NSUbiquitousKeyValueStoreChangeReasonKey` for a change from the
    /// server and for iCloud's first answer after launch.
    public static let serverChange = 0
    public static let initialSyncChange = 1

    private let lock = NSLock()
    private let store: PinCloudStore?
    private let defaults: UserDefaults
    private let mergedKey: String
    private var roots: [String] = []
    /// The pins this device brought at its merge in this launch, written
    /// again on top of iCloud's first answer should that answer replace them.
    private var pendingMerge: Set<String>?

    /// `store` is nil where the app has no key-value entitlement; every pin
    /// then comes from the attribute alone. `mergedKey` names the local
    /// default that remembers this device has merged.
    public init(store: PinCloudStore?, defaults: UserDefaults = .standard, mergedKey: String) {
        self.store = store
        self.defaults = defaults
        self.mergedKey = mergedKey
    }

    public var isShared: Bool { store != nil }

    /// The library folder paths are taken inside, nil for none.
    public func setLibrary(_ root: URL?) {
        lock.withLock {
            guard let root else { return roots = [] }
            let standard = root.standardizedFileURL.path
            let resolved = root.resolvingSymlinksInPath().standardizedFileURL.path
            roots = Array(Set([standard, resolved]))
        }
    }

    /// `url`'s path inside the library, `/` between folders, in precomposed
    /// form so the two file systems' spellings of one name agree; nil when
    /// it is the library itself or outside it.
    public static func relativePath(of url: URL, inLibrary root: String) -> String? {
        let path = url.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix), path.count > prefix.count else { return nil }
        return String(path.dropFirst(prefix.count)).precomposedStringWithCanonicalMapping
    }

    /// Whether `url` shows pinned, given what its own attribute says.
    public func isPinned(_ url: URL, attribute: Bool) -> Bool {
        lock.withLock {
            guard let path = path(of: url), let shared = shared() else { return attribute }
            if shared.contains(path) { return true }
            return merged ? false : attribute
        }
    }

    /// Records a pin or an unpin the person made here.
    public func setPinned(_ pinned: Bool, _ url: URL) {
        lock.withLock {
            guard store != nil, let path = path(of: url) else { return }
            var next = shared() ?? []
            if pinned { next.insert(path) } else { next.remove(path) }
            write(next)
        }
    }

    /// A note or folder moved or was renamed from `old` to `new`; the pins
    /// at and under it move along, and leave when it left the library.
    public func moved(from old: URL, to new: URL) {
        lock.withLock {
            guard let oldPath = path(of: old), let current = shared() else { return }
            let next = Self.moving(current, from: oldPath, to: path(of: new))
            if next != current { write(next) }
        }
    }

    /// A note or folder was deleted for good; its pins leave the store, so
    /// a later note at the same path does not come back pinned.
    public func removed(_ url: URL) {
        lock.withLock {
            guard let path = path(of: url), let current = shared() else { return }
            let next = Self.moving(current, from: path, to: nil)
            if next != current { write(next) }
        }
    }

    static func moving(_ paths: Set<String>, from old: String, to new: String?) -> Set<String> {
        var next = Set<String>()
        for path in paths {
            guard path == old || path.hasPrefix(old + "/") else {
                next.insert(path)
                continue
            }
            if let new { next.insert(new + path.dropFirst(old.count)) }
        }
        return next
    }

    /// The note files under `root` that are on this device, the ones whose
    /// attribute a merge reads: a note iCloud has not downloaded is a hidden
    /// placeholder and carries no pin of this device's. Hidden folders and
    /// packages are skipped, symlinks are not followed. Call it off the main
    /// thread.
    public static func downloadedNotes(in root: URL, extensions: [String]) -> [URL] {
        let wanted = Set(extensions.map { $0.lowercased() })
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var notes: [URL] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            if wanted.contains(url.pathExtension.lowercased()) { notes.append(url) }
        }
        return notes
    }

    /// Once per device: the notes pinned here by attribute join the shared
    /// pins. `urls` are this device's pinned notes, from `downloadedNotes`
    /// and whatever else the app has loaded.
    public func mergeLocalPins(_ urls: [URL]) {
        lock.withLock {
            guard store != nil, !merged else { return }
            let local = Set(urls.compactMap(path(of:)))
            write((shared() ?? []).union(local))
            defaults.set(true, forKey: mergedKey)
            pendingMerge = local
        }
    }

    /// The store changed from outside. A merge made before iCloud's first
    /// answer is laid over that answer once, so neither side's pins are
    /// lost; the caller then reads every note's pin again.
    public func changedExternally(reason: Int?) {
        lock.withLock {
            guard let local = pendingMerge, reason == Self.serverChange || reason == Self.initialSyncChange else { return }
            pendingMerge = nil
            let current = shared() ?? []
            if !local.isSubset(of: current) { write(current.union(local)) }
        }
    }

    // MARK: - Under the lock

    private var merged: Bool { defaults.bool(forKey: mergedKey) }

    private func path(of url: URL) -> String? {
        for root in roots {
            if let path = Self.relativePath(of: url, inLibrary: root) { return path }
        }
        return nil
    }

    /// The shared pins, nil before any device wrote them.
    private func shared() -> Set<String>? {
        guard let values = store?.array(forKey: Self.storeKey) else { return nil }
        return Set(values.compactMap { $0 as? String })
    }

    private func write(_ paths: Set<String>) {
        store?.set(paths.sorted(), forKey: Self.storeKey)
        store?.synchronize()
    }
}
