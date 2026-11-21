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
}
