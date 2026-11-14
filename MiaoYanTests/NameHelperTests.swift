import XCTest

@testable import MiaoYan

/// A new or renamed note that clashes with an existing file gets a counted
/// suffix. The old pattern was unanchored and kept one digit, so `Meeting 3
/// notes` became `Meeting 4.md` (losing ` notes`) and `Note 12` became
/// `Note 3.md`.
final class NameHelperTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("NameHelperTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func touch(_ names: String...) throws {
        for name in names {
            try Data().write(to: tempDir.appendingPathComponent(name + ".md"))
        }
    }

    @MainActor
    private func unique(_ name: String) -> String {
        let project = Project(url: tempDir, label: "root")
        return NameHelper.getUniqueFileName(name: name, project: project, ext: "md").deletingPathExtension().lastPathComponent
    }

    @MainActor
    func testFreeNameIsKept() {
        XCTAssertEqual(unique("Plan"), "Plan")
    }

    @MainActor
    func testClashCountsFromOne() throws {
        try touch("Plan", "Plan 1")
        XCTAssertEqual(unique("Plan"), "Plan 2")
    }

    @MainActor
    func testNumberInsideTheNameIsKept() throws {
        try touch("Meeting 3 notes")
        XCTAssertEqual(unique("Meeting 3 notes"), "Meeting 3 notes 1")
    }

    @MainActor
    func testMultiDigitSuffixCountsUp() throws {
        try touch("Note 12")
        XCTAssertEqual(unique("Note 12"), "Note 13")
    }

    @MainActor
    func testNameWithEmojiBeforeTheNumber() throws {
        try touch("🎉 Party 2")
        XCTAssertEqual(unique("🎉 Party 2"), "🎉 Party 3")
    }

    func testOnlyANumberIsTheWholeName() {
        XCTAssertEqual(NameHelper.splitTrailingNumber("2026").base, "2026")
        XCTAssertNil(NameHelper.splitTrailingNumber("2026").number)
    }
}
