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
    /// ...and for a switch to another iCloud account.
    public static let accountChange = 3

    /// What a change from outside asks of the caller.
    public struct ExternalChange: Sendable {
        /// The iCloud account changed: this device's pins have not joined
        /// its store yet, so the caller runs the merge again.
        public let needsMerge: Bool
        /// Paths whose pin may differ from before, nil when every note has
        /// to read its pin again.
        public let changedPaths: Set<String>?
    }

    private let lock = NSLock()
    private let store: PinCloudStore?
    private let defaults: UserDefaults
    private let mergedKey: String
    private var roots: [String] = []
    /// The pins this device brought at its merge, written again on top of
    /// iCloud's next answer should that answer replace them. Kept in the
    /// defaults until then: iCloud drops writes made before its first
    /// answer, which may come in a later launch (2026-11-22).
    private var pendingMerge: Set<String>?
    /// Pins and unpins made here since the last change from outside. One
    /// device's whole list replaces the other's, so a change made here
    /// while another device wrote is put back once on top of its list.
    private var unconfirmed: [String: Bool] = [:]
    /// The shared pins as last seen, to tell which changed from outside.
    private var lastSeen: Set<String>?
    /// Pins of a note or folder that left the library in this launch, by
    /// where it went, so moving it back (an undo of a delete that fell back
    /// to the system Trash) brings them back.
    private var parked: [String: Set<String>] = [:]

    /// `store` is nil where the app has no key-value entitlement; every pin
    /// then comes from the attribute alone. `mergedKey` names the local
    /// default that remembers this device has merged.
    public init(store: PinCloudStore?, defaults: UserDefaults = .standard, mergedKey: String) {
        self.store = store
        self.defaults = defaults
        self.mergedKey = mergedKey
        if let pending = defaults.stringArray(forKey: pendingKey) { pendingMerge = Set(pending) }
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
            if shared.contains(path) || pendingMerge?.contains(path) == true { return true }
            return merged ? false : attribute
        }
    }

    /// Records a pin or an unpin the person made here.
    public func setPinned(_ pinned: Bool, _ url: URL) {
        lock.withLock {
            guard store != nil, let path = path(of: url) else { return }
            var next = shared() ?? []
            if pinned { next.insert(path) } else { next.remove(path) }
            unconfirmed[path] = pinned
            if !pinned, pendingMerge?.remove(path) != nil { savePending() }
            write(next)
        }
    }

    /// A note or folder moved or was renamed from `old` to `new`; the pins
    /// at and under it move along, and leave when it left the library. Ones
    /// that left come back if it moves back in this launch (2026-11-22: undo
    /// of a delete to the system Trash restored the note unpinned).
    public func moved(from old: URL, to new: URL) {
        lock.withLock {
            guard let current = shared() else { return }
            let newPath = path(of: new)
            let next: Set<String>
            if let oldPath = path(of: old) {
                if newPath == nil {
                    // Always written, so an unpinned note later moved to the
                    // same outside path does not take an older note's pins.
                    let leaving = current.filter { $0 == oldPath || $0.hasPrefix(oldPath + "/") }
                    parked[new.standardizedFileURL.path] = leaving.isEmpty ? nil : Set(leaving.map { String($0.dropFirst(oldPath.count)) })
                }
                next = Self.moving(current, from: oldPath, to: newPath)
            } else if let newPath, let suffixes = parked.removeValue(forKey: old.standardizedFileURL.path) {
                next = current.union(suffixes.map { newPath + $0 })
            } else {
                return
            }
            follow(from: path(of: old), to: newPath)
            if next != current { write(next) }
        }
    }

    /// A note or folder was deleted for good; its pins leave the store, so
    /// a later note at the same path does not come back pinned.
    public func removed(_ url: URL) {
        lock.withLock {
            guard let path = path(of: url), let current = shared() else { return }
            let next = Self.moving(current, from: path, to: nil)
            follow(from: path, to: nil)
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
            savePending()
        }
    }

    /// The store changed from outside. A merge, and the pins and unpins
    /// made here since the last such change, are laid over it once, so
    /// neither side's are lost; a change made after this device's reached
    /// the other one then stands. The caller reads the pins it names again.
    @discardableResult public func changedExternally(reason: Int?) -> ExternalChange {
        lock.withLock {
            if reason == Self.accountChange {
                defaults.removeObject(forKey: mergedKey)
                pendingMerge = nil
                savePending()
                unconfirmed = [:]
                lastSeen = shared()
                return ExternalChange(needsMerge: true, changedPaths: nil)
            }
            let before = lastSeen
            let current = shared() ?? []
            guard reason == Self.serverChange || reason == Self.initialSyncChange else {
                lastSeen = current
                return ExternalChange(needsMerge: false, changedPaths: nil)
            }
            var next = current.union(pendingMerge ?? [])
            for (path, pinned) in unconfirmed where current.contains(path) != pinned {
                if pinned { next.insert(path) } else { next.remove(path) }
            }
            pendingMerge = nil
            savePending()
            unconfirmed = [:]
            if next != current { write(next) } else { lastSeen = current }
            return ExternalChange(needsMerge: false, changedPaths: before.map { $0.symmetricDifference(next) })
        }
    }

    /// `url`'s path as the shared pins name it, nil outside the library.
    public func sharedPath(of url: URL) -> String? {
        lock.withLock { path(of: url) }
    }

    // MARK: - Under the lock

    private var merged: Bool { defaults.bool(forKey: mergedKey) }
    private var pendingKey: String { mergedKey + ".Pending" }

    private func savePending() {
        if let pendingMerge { defaults.set(pendingMerge.sorted(), forKey: pendingKey) } else { defaults.removeObject(forKey: pendingKey) }
    }

    /// The merge still waiting and the changes not yet confirmed follow a
    /// move, and leave with what left the library.
    private func follow(from old: String?, to new: String?) {
        guard let old else { return }
        if let pending = pendingMerge {
            let moved = Self.moving(pending, from: old, to: new)
            if moved != pending {
                pendingMerge = moved
                savePending()
            }
        }
        var next: [String: Bool] = [:]
        for (path, pinned) in unconfirmed {
            guard path == old || path.hasPrefix(old + "/") else {
                next[path] = pinned
                continue
            }
            if let new { next[new + path.dropFirst(old.count)] = pinned }
        }
        unconfirmed = next
    }

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
        lastSeen = paths
    }
}
