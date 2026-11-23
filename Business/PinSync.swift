import Foundation
import MiaoYanCore
import Security

extension Notification.Name {
    /// Another device pinned or unpinned a note; the note list re-sorts.
    static let pinsChangedElsewhere = Notification.Name("PinsChangedElsewhere")
}

/// The Mac's side of `PinCloud`: pins follow a note in the iCloud Drive
/// library to the iPhone and iPad. Only the App Store build carries the
/// key-value entitlement (MiaoYan-Pro's `MiaoYan-AppStore.entitlements`);
/// this repository's build has none and keeps reading the pin attribute
/// alone, as it always did.
@MainActor
enum PinSync {
    static let cloud = PinCloud(
        store: hasKeyValueStore ? NSUbiquitousKeyValueStore.default : nil,
        mergedKey: "PinsMergedIntoICloud")

    private static var observer: NSObjectProtocol?
    /// The files of the notes shown pinned, by file identity, so a pinned
    /// note renamed outside MiaoYan (Finder, another Mac) keeps its pin at
    /// its new path: the store names the old one (2026-11-22).
    private static var pinnedFiles: [NSObject: URL] = [:]

    nonisolated static var hasKeyValueStore: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.ubiquity-kvstore-identifier" as CFString, nil) != nil
    }

    /// The pin attribute on the file, `AppIdentifier.pinKey` or the key of
    /// the bundle id before it was lowercased. A one-byte Bool.
    nonisolated static func attribute(of url: URL) -> Bool {
        let data =
            (try? url.extendedAttribute(forName: AppIdentifier.pinKey))
            ?? (try? url.extendedAttribute(forName: AppIdentifier.legacyPinKey))
        guard let first = data?.first else { return false }
        return first != 0
    }

    /// Whether the note shows pinned on this Mac.
    static func isPinned(_ url: URL, cloud: PinCloud = PinSync.cloud) -> Bool {
        let pinned = cloud.isPinned(url, attribute: attribute(of: url))
        if pinned, cloud.isShared, let file = identity(of: url) { pinnedFiles[file] = url }
        return pinned
    }

    /// A note file appeared at `url` outside MiaoYan. When it is a pinned
    /// note's file under a new name, and that name is gone, the pin moves
    /// with it before the note reads its pin.
    static func followRename(to url: URL, cloud: PinCloud = PinSync.cloud) {
        guard cloud.isShared, let file = identity(of: url), let old = pinnedFiles[file], old != url,
            !FileManager.default.fileExists(atPath: old.path)
        else { return }
        cloud.moved(from: old, to: url)
        pinnedFiles[file] = url
    }

    nonisolated private static func identity(of url: URL) -> NSObject? {
        (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier as? NSObject
    }

    /// Once at launch, before the notes load, which read their pins through
    /// `isPinned`: names notes inside the iCloud Drive folder, listens for
    /// other devices, and merges this Mac's own pins the first time, from
    /// the attributes on disk rather than the notes loaded so far.
    static func start(storage: Storage) {
        guard cloud.isShared, observer == nil, let library = UserDefaultsManagement.iCloudDocumentsContainer else { return }
        cloud.setLibrary(library)
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default, queue: .main
        ) { notification in
            let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            MainActor.assumeIsolated { changedElsewhere(reason: reason, storage: storage) }
        }
        NSUbiquitousKeyValueStore.default.synchronize()

        merge(library: library, storage: storage)
    }

    private static func merge(library: URL, storage: Storage) {
        let extensions = storage.allowedExtensions
        Task.detached(priority: .utility) {
            let pinned = PinCloud.downloadedNotes(in: library, extensions: extensions).filter(attribute(of:))
            await MainActor.run { cloud.mergeLocalPins(pinned) }
        }
    }

    private static func changedElsewhere(reason: Int?, storage: Storage) {
        let change = cloud.changedExternally(reason: reason)
        if change.needsMerge, let library = UserDefaultsManagement.iCloudDocumentsContainer {
            merge(library: library, storage: storage)
        }
        // Only the notes another device changed read their pin again; each
        // read touches the file, and the list can hold thousands.
        var count = 0
        for note in storage.noteList {
            if let changed = change.changedPaths {
                if let path = cloud.sharedPath(of: note.url), changed.contains(path) { note.isPinned = isPinned(note.url) }
            } else {
                note.isPinned = isPinned(note.url)
            }
            if note.isPinned { count += 1 }
        }
        storage.pinned = count
        NotificationCenter.default.post(name: .pinsChangedElsewhere, object: nil)
    }
}
