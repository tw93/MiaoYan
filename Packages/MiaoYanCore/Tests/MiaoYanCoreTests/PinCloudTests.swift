import XCTest

@testable import MiaoYanCore

/// Pins shared through iCloud's key-value store, one `PinCloud` per device
/// over one store.
final class PinCloudTests: XCTestCase {
    private final class MemoryStore: PinCloudStore {
        var values: [String: Any] = [:]
        func array(forKey key: String) -> [Any]? { values[key] as? [Any] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
        func synchronize() -> Bool { true }
    }

    private var suites: [String] = []

    override func tearDown() {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    private func device(_ store: PinCloudStore?, library: String = "/Users/me/Library/Mobile Documents/iCloud~com~tw93~miaoyan/Documents") -> PinCloud {
        let suite = "PinCloudTests-\(UUID().uuidString)"
        suites.append(suite)
        let cloud = PinCloud(store: store, defaults: UserDefaults(suiteName: suite)!, mergedKey: "merged")
        cloud.setLibrary(URL(fileURLWithPath: library, isDirectory: true))
        return cloud
    }

    private let mac = "/Users/me/Library/Mobile Documents/iCloud~com~tw93~miaoyan/Documents"
    private let phone = "/private/var/mobile/Library/Mobile Documents/iCloud~com~tw93~miaoyan/Documents"

    private func note(_ library: String, _ path: String) -> URL { URL(fileURLWithPath: library + "/" + path) }

    func testAPinOnTheMacShowsOnThePhoneAndAnUnpinThereReachesTheMac() {
        let store = MemoryStore()
        let macCloud = device(store, library: mac)
        let phoneCloud = device(store, library: phone)
        macCloud.mergeLocalPins([])
        phoneCloud.mergeLocalPins([])

        macCloud.setPinned(true, note(mac, "Work/Plan.md"))
        XCTAssertTrue(phoneCloud.isPinned(note(phone, "Work/Plan.md"), attribute: false))

        phoneCloud.setPinned(false, note(phone, "Work/Plan.md"))
        XCTAssertFalse(macCloud.isPinned(note(mac, "Work/Plan.md"), attribute: true), "the store outranks a stale attribute")
    }

    func testEachDevicesOwnPinsJoinTheStoreOnce() {
        let store = MemoryStore()
        let macCloud = device(store, library: mac)
        let phoneCloud = device(store, library: phone)
        XCTAssertTrue(macCloud.isPinned(note(mac, "A.md"), attribute: true), "before any merge the attribute shows")

        macCloud.mergeLocalPins([note(mac, "A.md")])
        XCTAssertTrue(phoneCloud.isPinned(note(phone, "B.md"), attribute: true), "the phone has not merged yet")
        phoneCloud.mergeLocalPins([note(phone, "B.md")])
        XCTAssertEqual(Set(store.array(forKey: PinCloud.storeKey) as? [String] ?? []), ["A.md", "B.md"])

        // A second merge on the same device changes nothing.
        macCloud.setPinned(false, note(mac, "A.md"))
        macCloud.mergeLocalPins([note(mac, "A.md")])
        XCTAssertEqual(store.array(forKey: PinCloud.storeKey) as? [String], ["B.md"])
    }

    func testPinsFollowARenameAndAFolderMoveAndLeaveWithTheLibrary() {
        let store = MemoryStore()
        let cloud = device(store, library: mac)
        cloud.mergeLocalPins([note(mac, "Inbox/One.md"), note(mac, "Inbox/Sub/Two.md"), note(mac, "Inboxes.md")])

        cloud.moved(from: note(mac, "Inbox/One.md"), to: note(mac, "Inbox/First.md"))
        cloud.moved(from: note(mac, "Inbox"), to: note(mac, "Archive/Inbox"))
        XCTAssertEqual(
            Set(store.array(forKey: PinCloud.storeKey) as? [String] ?? []),
            ["Archive/Inbox/First.md", "Archive/Inbox/Sub/Two.md", "Inboxes.md"], "a sibling sharing the prefix stays")

        cloud.moved(from: note(mac, "Inboxes.md"), to: URL(fileURLWithPath: "/Users/me/Desktop/Inboxes.md"))
        XCTAssertFalse((store.array(forKey: PinCloud.storeKey) as? [String] ?? []).contains("Inboxes.md"))

        cloud.removed(note(mac, "Archive"))
        XCTAssertEqual(store.array(forKey: PinCloud.storeKey) as? [String], [], "a deleted folder takes its pins along")
    }

    func testAMergeBeforeICloudsFirstAnswerIsLaidOverIt() {
        let store = MemoryStore()
        let cloud = device(store, library: mac)
        cloud.mergeLocalPins([note(mac, "Mine.md")])
        // iCloud's first answer replaces the store with another device's pins.
        store.values[PinCloud.storeKey] = ["Theirs.md"]
        cloud.changedExternally(reason: PinCloud.initialSyncChange)
        XCTAssertEqual(Set(store.array(forKey: PinCloud.storeKey) as? [String] ?? []), ["Mine.md", "Theirs.md"])

        // Only once: a later unpin elsewhere is not undone.
        store.values[PinCloud.storeKey] = ["Theirs.md"]
        cloud.changedExternally(reason: PinCloud.serverChange)
        XCTAssertEqual(store.array(forKey: PinCloud.storeKey) as? [String], ["Theirs.md"])
    }

    func testWithoutTheStoreOrOutsideTheLibraryTheAttributeDecides() {
        let alone = device(nil, library: mac)
        alone.mergeLocalPins([note(mac, "A.md")])
        alone.setPinned(true, note(mac, "A.md"))
        XCTAssertTrue(alone.isPinned(note(mac, "A.md"), attribute: true))
        XCTAssertFalse(alone.isPinned(note(mac, "A.md"), attribute: false))

        let store = MemoryStore()
        let cloud = device(store, library: mac)
        cloud.mergeLocalPins([])
        let outside = URL(fileURLWithPath: "/Users/me/Downloads/Opened.md")
        cloud.setPinned(true, outside)
        XCTAssertEqual(store.array(forKey: PinCloud.storeKey) as? [String], [])
        XCTAssertTrue(cloud.isPinned(outside, attribute: true))
    }

    func testTheMergeReadsTheNotesOnDiskNotPlaceholdersOrHiddenFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PinCloudTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["A.md", "Work/B.markdown", "Work/.C.md.icloud", ".git/D.md", "Work/i/photo.png"] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        let found = PinCloud.downloadedNotes(in: root, extensions: ["md", "markdown"])
            .compactMap { PinCloud.relativePath(of: $0, inLibrary: root.standardizedFileURL.path) }
        XCTAssertEqual(Set(found), ["A.md", "Work/B.markdown"])
    }

    func testOneNameInEitherUnicodeFormIsOneNote() {
        XCTAssertEqual(
            PinCloud.relativePath(of: URL(fileURLWithPath: "/L/Cafe\u{301}.md"), inLibrary: "/L"),
            PinCloud.relativePath(of: URL(fileURLWithPath: "/L/Caf\u{E9}.md"), inLibrary: "/L"))
        XCTAssertNil(PinCloud.relativePath(of: URL(fileURLWithPath: "/L"), inLibrary: "/L"))
        XCTAssertNil(PinCloud.relativePath(of: URL(fileURLWithPath: "/Lib/A.md"), inLibrary: "/L"))
    }
}
