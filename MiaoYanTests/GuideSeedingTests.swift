import MiaoYanCore
import XCTest

@testable import MiaoYan

/// A new library gets one guide folder, opened on its introduction, and a
/// library whose guide the iPhone already wrote gets nothing more.
@MainActor
final class GuideSeedingTests: XCTestCase {
    func testAnEmptyLibraryGetsOneGuideFolderOpenedOnItsIntroduction() throws {
        try withEmptyLibrary { storage, root in
            XCTAssertTrue(storage.checkFirstRun())

            let plan = GuideSeed.plan(forLanguage: Locale.preferredLanguages.first ?? "")
            let folder = root.appendingPathComponent(plan.folder)
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
            XCTAssertEqual(names, plan.notes.sorted(), "every guide note is bundled and copied")
            let top = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { !$0.hasPrefix(".") }
            XCTAssertEqual(top, [plan.folder], "the guide is one folder, not four")
            XCTAssertEqual(UserDefaultsManagement.lastSelectedURL?.lastPathComponent, plan.notes.first)
            XCTAssertEqual(storage.guideProject()?.url.lastPathComponent, plan.folder)
            XCTAssertTrue(UserDefaultsManagement.hasCreatedInitContent)
        }
    }

    func testAGuideTheOtherDeviceWroteIsNotWrittenAgain() throws {
        try withEmptyLibrary { storage, root in
            let other = root.appendingPathComponent("MiaoYan Guide")
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

            XCTAssertFalse(storage.checkFirstRun())

            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: other.path), [])
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("妙言指南").path))
            XCTAssertTrue(UserDefaultsManagement.hasCreatedInitContent, "and this device will not try later either")
        }
    }

    /// Launch reads notes two folders down, so a library whose notes all sit
    /// deeper looked empty and got the guide written into it.
    func testALibraryWithNotesOnlyDeepInFoldersGetsNoGuide() throws {
        try withEmptyLibrary { storage, root in
            let deep = root.appendingPathComponent("Work/2024/Q1")
            try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
            try "# Plan".write(to: deep.appendingPathComponent("Plan.md"), atomically: true, encoding: .utf8)
            XCTAssertTrue(storage.noteList.isEmpty)

            XCTAssertFalse(storage.checkFirstRun())

            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { !$0.hasPrefix(".") }, ["Work"])
            XCTAssertTrue(UserDefaultsManagement.hasCreatedInitContent)
        }
    }

    func testOnlyTheGuideLinkIsKeptInsideTheApp() {
        XCTAssertFalse(AppDelegate.openGuideLinkInProcess(URL(string: "miaoyan://goto/Plan")!))
        XCTAssertFalse(AppDelegate.openGuideLinkInProcess(URL(string: "https://miaoyan.app")!))
    }

    func testTheIntroductionEndsWithTheLinkThatPutsTheGuideAway() throws {
        let initial = try XCTUnwrap(Bundle.main.resourceURL).appendingPathComponent("Initial")
        for language in ["zh-Hans", "en"] {
            let intro = try XCTUnwrap(GuideSeed.plan(forLanguage: language).notes.first)
            let text = try String(contentsOf: initial.appendingPathComponent(intro), encoding: .utf8)
            XCTAssertTrue(text.contains("](\(GuideSeed.hideLink))"), intro)
            XCTAssertTrue(text.contains(GuideSeed.plan(forLanguage: language).folder), "\(intro) names the folder it moves")
        }
    }

    private func withEmptyLibrary(_ body: (Storage, URL) throws -> Void) throws {
        let defaults = UserDefaults.standard
        let keys = ["hasCreatedInitContent", "lastSelectedPath"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        UserDefaultsManagement.hasCreatedInitContent = false

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanGuide-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storage = Storage(loadsLibrary: false)
        _ = storage.add(project: Project(url: root, label: "guide", isRoot: true))
        try body(storage, root)
    }
}
