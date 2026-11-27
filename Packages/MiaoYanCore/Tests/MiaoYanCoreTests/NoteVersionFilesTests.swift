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

    /// The text a restore replaces is kept even when it differs from the
    /// newest version only in indentation: a list nested by hand and then
    /// restored over was in neither the note nor the history.
    func testAnExactSaveKeepsAnIndentOnlyChange() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNotNil(try NoteVersionFiles.save("- a\n- b\n", in: folder, at: start))
        XCTAssertNil(try NoteVersionFiles.save("- a\n    - b\n", in: folder, at: start.addingTimeInterval(60)))
        let kept = try XCTUnwrap(try NoteVersionFiles.save("- a\n    - b\n", in: folder, at: start.addingTimeInterval(120), exact: true))
        XCTAssertEqual(try String(contentsOf: kept, encoding: .utf8), "- a\n    - b\n")
        XCTAssertNil(try NoteVersionFiles.save("- a\n    - b\n", in: folder, at: start.addingTimeInterval(180), exact: true), "the same bytes again")
    }

    /// Past the budget the history goes down to nine tenths of it, so the
    /// next save does not pass the budget again and walk every note.
    func testTheBudgetTrimLeavesRoomForTheNextSave() throws {
        let kilobyte = Data(repeating: 0x61, count: 1024)
        let note = folder.appendingPathComponent("n-1")
        try FileManager.default.createDirectory(at: note, withIntermediateDirectories: true)
        for day in 1...10 {
            try kilobyte.write(to: note.appendingPathComponent(String(format: "2026-11-%02dT10-00-00Z.md", day)))
        }
        // 10 KiB over a 10000-byte budget: trimmed to 9000 or less, not just under 10000.
        XCTAssertEqual(NoteVersionFiles.keepWithinBudget(root: folder, budget: 10000), 8192)
        XCTAssertEqual(NoteVersionFiles.versions(in: note).count, 8)
    }

    /// With each note's newest version alone above nine tenths of the
    /// budget, a trim to nine tenths took every older version of every note.
    func testATrimStopsAtTheBudgetWhenTheNewestVersionsNearlyFillIt() throws {
        let kilobyte = Data(repeating: 0x61, count: 1024)
        for index in 0..<9 {
            let note = folder.appendingPathComponent("Note\(index)-abc")
            try FileManager.default.createDirectory(at: note, withIntermediateDirectories: true)
            try kilobyte.write(to: note.appendingPathComponent("2026-11-02T10-00-00Z.md"))
        }
        let edited = folder.appendingPathComponent("Note0-abc")
        for day in 3...5 {
            try kilobyte.prefix(512).write(to: edited.appendingPathComponent(String(format: "2026-10-%02dT10-00-00Z.md", day)))
        }
        // The nine newest (9216) are over nine tenths of 10200; 10752 in all.
        XCTAssertEqual(NoteVersionFiles.keepWithinBudget(root: folder, budget: 10200), 9728)
        XCTAssertEqual(NoteVersionFiles.versions(in: edited).count, 2, "the oldest two went, not all three")
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
