import XCTest

@testable import MiaoYanCore

final class NoteVersionFilesTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("NoteVersionFiles-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testASaveWritesOnlyWhenTheTextChanged() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNotNil(try NoteVersionFiles.save("# Plan\n\nOne\n", in: folder, at: start))
        // Blank lines and spaces at the ends of lines alone are no new version.
        XCTAssertNil(try NoteVersionFiles.save("# Plan\n\n\nOne  \n", in: folder, at: start.addingTimeInterval(60)))
        XCTAssertNotNil(try NoteVersionFiles.save("# Plan\n\nTwo\n", in: folder, at: start.addingTimeInterval(120)))
        let versions = NoteVersionFiles.versions(in: folder)
        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(try String(contentsOf: versions[0].url, encoding: .utf8), "# Plan\n\nTwo\n")
        XCTAssertTrue(versions.allSatisfy { NoteVersionFiles.isVersionFileName($0.url.lastPathComponent) })
    }

    func testTwoSavesInOneSecondKeepBoth() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try XCTUnwrap(try NoteVersionFiles.save("a", in: folder, at: start))
        let second = try XCTUnwrap(try NoteVersionFiles.save("b", in: folder, at: start))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(NoteVersionFiles.versions(in: folder).map(\.url.lastPathComponent), [second, first].map(\.lastPathComponent))
    }

    func testANoteKeepsItsNewestVersionsOnly() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<(NoteVersionFiles.keptPerNote + 3) {
            try NoteVersionFiles.save("v\(index)", in: folder, at: start.addingTimeInterval(Double(index) * 60))
        }
        let versions = NoteVersionFiles.versions(in: folder)
        XCTAssertEqual(versions.count, NoteVersionFiles.keptPerNote)
        XCTAssertEqual(try String(contentsOf: versions[0].url, encoding: .utf8), "v\(NoteVersionFiles.keptPerNote + 2)")
    }

    /// The iPhone's history must find its notes after an app update moves
    /// the container, across `/private`, and through an iCloud placeholder.
    func testADeviceNoteKeepsItsFolderAcrossTheWaysItsPathDrifts() {
        let before = "/var/mobile/Containers/Data/Application/AAAA"
        let after = "/private/var/mobile/Containers/Data/Application/BBBB"
        let key = NoteVersionFiles.folderName(for: URL(fileURLWithPath: before + "/Documents/Library/Work/Plan.md"), home: before)
        XCTAssertEqual(
            key, NoteVersionFiles.folderName(for: URL(fileURLWithPath: after + "/Documents/Library/Work/Plan.md"), home: after),
            "an update gave the app a new container")
        XCTAssertEqual(
            key, NoteVersionFiles.folderName(for: URL(fileURLWithPath: before + "/Documents/Library/Work/.Plan.md.icloud"), home: before),
            "a note iCloud has not downloaded")
        XCTAssertNotEqual(
            key, NoteVersionFiles.folderName(for: URL(fileURLWithPath: before + "/Documents/Library/Home/Plan.md"), home: before))

        let cloud = "/var/mobile/Library/Mobile Documents/iCloud~com~tw93~miaoyan/Documents/Plan.md"
        XCTAssertEqual(
            NoteVersionFiles.folderName(for: URL(fileURLWithPath: cloud), home: before),
            NoteVersionFiles.folderName(for: URL(fileURLWithPath: "/private" + cloud), home: after),
            "an iCloud note, outside the app's home, read with and without /private")
    }

    func testTheFolderNameKeepsTwoNotesOfOneNameApart() {
        let first = NoteVersionFiles.folderName(for: URL(fileURLWithPath: "/lib/Work/Plan.md"))
        let second = NoteVersionFiles.folderName(for: URL(fileURLWithPath: "/lib/Home/Plan.md"))
        XCTAssertTrue(first.hasPrefix("Plan-"))
        XCTAssertNotEqual(first, second)
    }
}
