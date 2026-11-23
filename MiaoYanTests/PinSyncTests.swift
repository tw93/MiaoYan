import MiaoYanCore
import XCTest

@testable import MiaoYan

/// The Mac's pins. The test build has no key-value entitlement, as this
/// repository's build has none, so every pin comes from the attribute,
/// which is also what a device without iCloud reads; the shared store's
/// rules are tested in MiaoYanCore's `PinCloudTests`.
@MainActor
final class PinSyncTests: XCTestCase {
    private func makeNote() throws -> (Note, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PinSyncTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("note.md")
        try "text".write(to: url, atomically: true, encoding: .utf8)
        return (Note(url: url, with: Project(url: dir, label: "pins", isRoot: true)), dir)
    }

    func testThisBuildReadsPinsFromTheAttributeAlone() {
        XCTAssertFalse(PinSync.hasKeyValueStore)
        XCTAssertFalse(PinSync.cloud.isShared)
    }

    func testAPinAndAnUnpinOutliveAReload() throws {
        let (note, _) = try makeNote()
        note.addPin()
        let reloaded = Note(url: note.url, with: note.project)
        reloaded.loadMetadataFromDisk()
        XCTAssertTrue(reloaded.isPinned)

        // Unpinning writes a false byte rather than removing the attribute.
        note.removePin()
        reloaded.loadMetadataFromDisk()
        XCTAssertFalse(reloaded.isPinned)
    }

    func testAPinWrittenUnderTheOldBundleIdStillCounts() throws {
        let (note, _) = try makeNote()
        try note.url.setExtendedAttribute(data: Data([1]), forName: AppIdentifier.legacyPinKey)
        XCTAssertTrue(PinSync.attribute(of: note.url))
        try note.url.setExtendedAttribute(data: Data([0]), forName: AppIdentifier.pinKey)
        XCTAssertFalse(PinSync.attribute(of: note.url), "the current key, unpinned, outranks the old one")
    }

    func testAMovedNoteStaysPinned() throws {
        let (note, dir) = try makeNote()
        note.addPin()
        let destination = dir.appendingPathComponent("moved.md")
        XCTAssertTrue(note.move(to: destination, project: note.project))
        XCTAssertTrue(note.isPinned)
        XCTAssertTrue(PinSync.attribute(of: destination))
    }

    // MARK: - The shared store on delete paths

    /// iCloud's key-value store as the App Store build has it.
    private final class StandInStore: PinCloudStore {
        var values: [String: Any] = [:]
        func array(forKey key: String) -> [Any]? { values[key] as? [Any] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
        func synchronize() -> Bool { true }
    }

    /// A `PinCloud` over a stand-in store with `library` as the iCloud
    /// Drive folder, merged, so the store alone decides.
    private func sharedCloud(library: URL) -> PinCloud {
        let suite = "PinSyncTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let cloud = PinCloud(store: StandInStore(), defaults: UserDefaults(suiteName: suite)!, mergedKey: "merged")
        cloud.setLibrary(library)
        cloud.mergeLocalPins([])
        return cloud
    }

    private func makeLibrary() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PinSyncTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Trash"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.resolvingSymlinksInPath()
    }

    /// Renamed in Finder: the store named the old path and the attribute no
    /// longer counts once merged, so the note came back unpinned.
    func testANoteRenamedOutsideMiaoYanKeepsItsPin() throws {
        let library = try makeLibrary()
        let cloud = sharedCloud(library: library)
        let old = library.appendingPathComponent("Plan.md")
        let renamed = library.appendingPathComponent("Plan 2026.md")
        try "text".write(to: old, atomically: true, encoding: .utf8)
        cloud.setPinned(true, old)
        XCTAssertTrue(PinSync.isPinned(old, cloud: cloud))

        try FileManager.default.moveItem(at: old, to: renamed)
        PinSync.followRename(to: renamed, cloud: cloud)

        XCTAssertTrue(cloud.isPinned(renamed, attribute: false))
        XCTAssertFalse(cloud.isPinned(old, attribute: false), "a later note at the old name is not pinned")

        // A new file that is not the pinned one does not take its pin.
        let other = library.appendingPathComponent("Other.md")
        try "text".write(to: other, atomically: true, encoding: .utf8)
        PinSync.followRename(to: other, cloud: cloud)
        XCTAssertFalse(cloud.isPinned(other, attribute: false))
    }

    /// The delete moved the pin to the Trash path; Undo moved the file back
    /// without it, so the note came back unpinned and `Trash/x.md` stayed.
    func testUndoingADeleteBringsThePinBack() throws {
        let library = try makeLibrary()
        let cloud = sharedCloud(library: library)
        let original = library.appendingPathComponent("x.md")
        let trashed = library.appendingPathComponent("Trash/x.md")
        try "text".write(to: trashed, atomically: true, encoding: .utf8)
        cloud.setPinned(true, trashed)

        XCTAssertEqual(TrashReturn([trashed: original]).perform(pins: cloud) { _, _ in }, 0)

        XCTAssertTrue(cloud.isPinned(original, attribute: false), "the restored note is pinned again")
        XCTAssertFalse(cloud.isPinned(trashed, attribute: false), "the Trash path holds no pin")
    }

    /// Deleting from the Trash left the pin in the store, so the next note
    /// of that name deleted into the Trash showed pinned.
    func testDeletingFromTheTrashDropsThePin() throws {
        let library = try makeLibrary()
        let cloud = sharedCloud(library: library)
        let name = "PinSyncTests-\(UUID().uuidString).md"
        let trashed = library.appendingPathComponent("Trash/\(name)")
        try "text".write(to: trashed, atomically: true, encoding: .utf8)
        cloud.setPinned(true, trashed)
        let note = Note(url: trashed, with: Project(url: trashed.deletingLastPathComponent(), isTrash: true))
        addTeardownBlock { Self.removeFromSystemTrash(name, near: library) }

        guard case .hiddenFromMiaoYanTrash = note.removeFile(pins: cloud) else {
            return XCTFail("the note left the Trash")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: trashed.path))
        XCTAssertFalse(cloud.isPinned(trashed, attribute: false), "a later note of this name is not pinned")
    }

    /// Deleting a folder moves it out of the library; its notes' pins
    /// stayed in the store and came back on a new folder of that name.
    func testDeletingAFolderDropsItsPins() throws {
        let library = try makeLibrary()
        let cloud = sharedCloud(library: library)
        let folderName = "PinSyncTests-\(UUID().uuidString)"
        let folder = library.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let inside = folder.appendingPathComponent("note.md")
        let elsewhere = library.appendingPathComponent("kept.md")
        try "text".write(to: inside, atomically: true, encoding: .utf8)
        cloud.setPinned(true, inside)
        cloud.setPinned(true, elsewhere)
        let storage = Storage(loadsLibrary: false)
        let root = Project(url: library, label: "library", isRoot: true, isDefault: true)
        _ = storage.add(project: root)
        let project = try XCTUnwrap(storage.subfolders(of: root).first { $0.url.lastPathComponent == folderName })

        let destination = try XCTUnwrap(storage.trashFolder(project, pins: cloud))
        addTeardownBlock { try? FileManager.default.removeItem(at: destination) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertFalse(cloud.isPinned(inside, attribute: false), "the folder's pins left with it")
        XCTAssertTrue(cloud.isPinned(elsewhere, attribute: false), "other pins stay")
    }

    /// `Note.removeFile` hands a Trash note to the system Trash without
    /// saying where it went; the test file is taken out of there again.
    private static func removeFromSystemTrash(_ name: String, near url: URL) {
        guard let trash = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: url, create: false)
        else { return }
        try? FileManager.default.removeItem(at: trash.appendingPathComponent(name))
    }
}
