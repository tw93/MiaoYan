import Foundation
import XCTest

@testable import MiaoYanCore

final class GuideSeedTests: XCTestCase {
    /// The Mac and the iPhone share an iCloud library: whichever opens it
    /// first writes the guide, and the other one must then write nothing.
    func testOnlyAnEmptyLibraryWithNoGuideGetsOneOnADeviceThatNeverSeeded() {
        XCTAssertTrue(GuideSeed.shouldSeed(libraryHasNotes: false, guideFolderExists: false, seededOnThisDevice: false))
        XCTAssertFalse(GuideSeed.shouldSeed(libraryHasNotes: true, guideFolderExists: false, seededOnThisDevice: false))
        XCTAssertFalse(
            GuideSeed.shouldSeed(libraryHasNotes: false, guideFolderExists: true, seededOnThisDevice: false),
            "the other device's guide arrived before its notes were read")
        XCTAssertFalse(
            GuideSeed.shouldSeed(libraryHasNotes: false, guideFolderExists: false, seededOnThisDevice: true),
            "a guide the user put away must not grow back")
    }

    func testChineseTagsGetTheChineseGuideAndEveryOtherLanguageTheEnglishOne() {
        for tag in ["zh-Hans-CN", "zh-Hant-TW", "zh-HK"] {
            XCTAssertEqual(GuideSeed.plan(forLanguage: tag).folder, "妙言指南", tag)
        }
        for tag in ["en-US", "ja-JP", "es-ES", ""] {
            XCTAssertEqual(GuideSeed.plan(forLanguage: tag).folder, "MiaoYan Guide", tag)
        }
        for tag in ["zh-Hans", "en"] {
            let plan = GuideSeed.plan(forLanguage: tag)
            XCTAssertTrue(GuideSeed.folderNames.contains(plan.folder))
            XCTAssertEqual(plan.notes.count, 3)
        }
    }

    func testAGuideFolderSitsDirectlyInTheLibrary() throws {
        let root = URL(fileURLWithPath: "/lib")
        XCTAssertTrue(GuideSeed.isGuideFolder(root.appendingPathComponent("妙言指南"), root: root))
        XCTAssertTrue(GuideSeed.isGuideFolder(root.appendingPathComponent("MiaoYan Guide"), root: root))
        XCTAssertFalse(GuideSeed.isGuideFolder(root.appendingPathComponent("Work/妙言指南"), root: root))
        XCTAssertFalse(GuideSeed.isGuideFolder(root.appendingPathComponent("指南"), root: root))

        // The same library reached through /var and /private/var.
        let real = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("GuideSeed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: real.appendingPathComponent("妙言指南"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: real) }
        let aliased = URL(fileURLWithPath: real.path.hasPrefix("/private") ? String(real.path.dropFirst(8)) : "/private" + real.path)
        XCTAssertTrue(GuideSeed.isGuideFolder(aliased.appendingPathComponent("妙言指南"), root: real))
        XCTAssertTrue(GuideSeed.isGuideFolder(real.appendingPathComponent("妙言指南"), root: aliased))
    }

    /// Two devices that seeded before either synced leave iCloud's numbered
    /// copy, which must count as a guide too.
    func testANumberedCopyIsAGuideAndOtherNamesAreNot() {
        XCTAssertTrue(GuideSeed.isGuideFolderName("MiaoYan Guide 2"))
        XCTAssertTrue(GuideSeed.isGuideFolderName("妙言指南 3"))
        XCTAssertFalse(GuideSeed.isGuideFolderName("MiaoYan Guide 2b"))
        XCTAssertFalse(GuideSeed.isGuideFolderName("MiaoYan Guides"))
        XCTAssertFalse(GuideSeed.isGuideFolderName("MiaoYan Guide "))
    }

    /// The launch-time note list reads two levels and skips hidden files, so
    /// a library of deep folders or of notes still in iCloud looked empty.
    func testNotesDeepInFoldersOrStillInICloudMakeALibraryNotEmpty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GuideNotes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let deep = root.appendingPathComponent("Work/2024/Q1")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("Work/cover.png"))
        XCTAssertFalse(GuideSeed.libraryHasNotes(at: root, extensions: ["md", "txt"]))

        try Data().write(to: deep.appendingPathComponent(".Plan.md.icloud"))
        XCTAssertTrue(GuideSeed.libraryHasNotes(at: root, extensions: ["md", "txt"]), "a note not downloaded yet")

        try FileManager.default.removeItem(at: deep.appendingPathComponent(".Plan.md.icloud"))
        try Data().write(to: deep.appendingPathComponent("Plan.MD"))
        XCTAssertTrue(GuideSeed.libraryHasNotes(at: root, extensions: ["md", "txt"]), "a note four levels down")
    }

    func testTheHideLinkIsRecognisedAndNothingElseIs() {
        XCTAssertTrue(GuideSeed.isHideLink(URL(string: GuideSeed.hideLink)!))
        XCTAssertFalse(GuideSeed.isHideLink(URL(string: "miaoyan://goto/Guide")!))
        XCTAssertFalse(GuideSeed.isHideLink(URL(string: "https://guide/hide")!))
    }
}
