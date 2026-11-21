import XCTest

@testable import MiaoYan

/// A build with its own bundle id must not inherit the shipped app's settings
/// through the legacy `com.tw93.MiaoYan` domain, which on a case-insensitive
/// volume is the shipped app's own preferences file.
final class LegacyPreferencesMigrationTests: XCTestCase {
    private let suiteName = "miaoyan-legacy-migration-tests"

    private func freshDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    @MainActor
    func testBuildWithItsOwnBundleIdCopiesNothing() {
        let standard = freshDefaults()
        let legacy: [String: Any] = ["fontName": "TsangerJinKai02-W04", "storageUrl": "/Users/someone/Notes"]

        AppDelegate.migrateLegacyPreferences(into: standard, legacy: legacy, bundleIdentifier: "com.tw93.miaoyan.qa")

        XCTAssertNil(standard.object(forKey: "fontName"))
        XCTAssertNil(standard.object(forKey: "storageUrl"))
    }

    @MainActor
    func testShippedBundleIdCopiesOnlyMissingKeysOnce() {
        let standard = freshDefaults()
        standard.set(15, forKey: "fontsize")
        let legacy: [String: Any] = ["fontName": "LXGW WenKai", "fontsize": 17]

        AppDelegate.migrateLegacyPreferences(into: standard, legacy: legacy, bundleIdentifier: AppDelegate.shippedBundleIdentifier)
        XCTAssertEqual(standard.string(forKey: "fontName"), "LXGW WenKai")
        XCTAssertEqual(standard.integer(forKey: "fontsize"), 15)
        XCTAssertTrue(standard.bool(forKey: AppDelegate.legacyMigrationKey))

        standard.removeObject(forKey: "fontName")
        AppDelegate.migrateLegacyPreferences(into: standard, legacy: legacy, bundleIdentifier: AppDelegate.shippedBundleIdentifier)
        XCTAssertNil(standard.object(forKey: "fontName"))
    }

    /// A new install reads one Return inside a paragraph as a space, as
    /// CommonMark and GitHub do; an install that ran before keeps the break
    /// on every Return it always had, and a choice made in Settings stays.
    @MainActor
    func testLineBreaksFollowCommonMarkOnlyForANewInstall() {
        let key = "editorLineBreak"
        let fresh = freshDefaults()
        UserDefaultsManagement.settleLineBreakDefault(in: fresh, stored: nil)
        XCTAssertEqual(fresh.string(forKey: key), "Github")

        let migratedOnly = freshDefaults()
        UserDefaultsManagement.settleLineBreakDefault(in: migratedOnly, stored: [AppDelegate.legacyMigrationKey: true])
        XCTAssertEqual(migratedOnly.string(forKey: key), "Github", "the migration's own mark is not a sign of an earlier run")

        let earlier = freshDefaults()
        UserDefaultsManagement.settleLineBreakDefault(in: earlier, stored: [AppDelegate.legacyMigrationKey: true, "fontsize": 15])
        XCTAssertEqual(earlier.string(forKey: key), "MiaoYan")

        let chosen = freshDefaults()
        chosen.set("MiaoYan", forKey: key)
        UserDefaultsManagement.settleLineBreakDefault(in: chosen, stored: nil)
        XCTAssertEqual(chosen.string(forKey: key), "MiaoYan", "a stored choice is never replaced")
        chosen.set("Github", forKey: key)
        UserDefaultsManagement.settleLineBreakDefault(in: chosen, stored: ["fontsize": 15])
        XCTAssertEqual(chosen.string(forKey: key), "Github")
    }
}
