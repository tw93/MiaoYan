import AppKit
import XCTest

@testable import MiaoYan

final class PrefsWindowControllerTests: XCTestCase {
    @MainActor
    func testFontMenusRefreshInstalledFamiliesWithoutChangingSelection() throws {
        let controller = TypographyPrefsViewController()
        func popups(in view: NSView) -> [NSPopUpButton] {
            view.subviews.flatMap { child in
                if let popup = child as? NSPopUpButton { return [popup] }
                return popups(in: child)
            }
        }
        let fontPopups = popups(in: controller.view).filter { popup in
            popup.itemArray.contains { $0.representedObject is String }
        }
        XCTAssertEqual(fontPopups.count, 4)
        for popup in fontPopups {
            let menu = try XCTUnwrap(popup.menu)
            let selected = try XCTUnwrap(popup.selectedItem?.representedObject as? String)
            let existing = Set(menu.items.compactMap { $0.representedObject as? String })
            let missing = try XCTUnwrap(
                menu.items.first { item in
                    guard let family = item.representedObject as? String else { return false }
                    return family != selected
                })
            // Model a menu built before an installed face became available.
            // Opening that same menu must refresh it, without rebuilding the
            // preferences controller or changing the user's chosen family.
            menu.removeItem(missing)
            menu.delegate?.menuNeedsUpdate?(menu)
            XCTAssertEqual(Set(menu.items.compactMap { $0.representedObject as? String }), existing)
            XCTAssertEqual(popup.selectedItem?.representedObject as? String, selected)
        }
    }

    @MainActor
    func testFontMigrationPreservesCustomFaces() throws {
        let defaults = UserDefaults.standard
        let keys = ["fontName", "windowFontName", "previewFontName", "codeFont", "hasMigratedSystemFonts_v1", "hasMigratedCodeFontDefault_v1", "hasMigratedCodeFontToText_v1", "hasMigratedFontDefaults_v2"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(false, forKey: "hasMigratedSystemFonts_v1")
        defaults.set(true, forKey: "hasMigratedCodeFontDefault_v1")
        defaults.set(true, forKey: "hasMigratedCodeFontToText_v1")
        defaults.set(true, forKey: "hasMigratedFontDefaults_v2")
        defaults.set("TsangerJinKai02-W04", forKey: "fontName")
        defaults.set("TsangerJinKai02-W04", forKey: "windowFontName")
        defaults.set("Helvetica", forKey: "previewFontName")
        defaults.set("Menlo", forKey: "codeFont")

        UserDefaultsManagement.migrateFontDefaultsIfNeeded()

        // Stored text faces are left alone whichever version wrote them.
        XCTAssertEqual(UserDefaults.standard.string(forKey: "fontName"), "TsangerJinKai02-W04")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "windowFontName"), "TsangerJinKai02-W04")
        XCTAssertEqual(UserDefaultsManagement.previewFontName, "Helvetica")
        XCTAssertEqual(UserDefaultsManagement.codeFontName, "Menlo")
    }

    @MainActor
    func testAMissingChosenFaceIsKeptAndRendersTheFallback() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "fontName")
        defer {
            if let original { defaults.set(original, forKey: "fontName") } else { defaults.removeObject(forKey: "fontName") }
        }

        // Absent right now, as a face is before it is installed or while a font
        // manager has yet to activate it. The choice must survive being read.
        defaults.set("NoSuchFace-Regular", forKey: "fontName")
        XCTAssertEqual(UserDefaultsManagement.fontName, "NoSuchFace-Regular")
        XCTAssertEqual(defaults.string(forKey: "fontName"), "NoSuchFace-Regular")
        XCTAssertEqual(UserDefaultsManagement.noteFont.fontName, FontConfiguration.fallbackFont)

        // A fresh install starts on the default face by name.
        defaults.removeObject(forKey: "fontName")
        XCTAssertEqual(UserDefaultsManagement.fontName, FontConfiguration.defaultEditorFont)
    }

    @MainActor
    func testTheDefaultFaceWaitingToBeInstalledSelectsItsRow() throws {
        guard !FontCatalog.isInstalled(family: FontCatalog.retiredBundledFamily) else {
            throw XCTSkip("TsangerJinKai02 is installed here, so there is no waiting row")
        }
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "previewFontName")
        defaults.set(FontConfiguration.defaultPreviewFont, forKey: "previewFontName")
        defer {
            if let original { defaults.set(original, forKey: "previewFontName") } else { defaults.removeObject(forKey: "previewFontName") }
        }

        let controller = TypographyPrefsViewController()
        func popups(in view: NSView) -> [NSPopUpButton] {
            view.subviews.flatMap { child in
                if let popup = child as? NSPopUpButton { return [popup] }
                return popups(in: child)
            }
        }
        let preview = try XCTUnwrap(popups(in: controller.view).first { $0.action == NSSelectorFromString("previewFontChanged:") })
        XCTAssertEqual(preview.selectedItem?.tag, 9001, "The not-installed row, not an orphan copy of the name")
        XCTAssertEqual(preview.itemArray.filter { $0.representedObject as? String == FontConfiguration.defaultPreviewFont }.count, 1)
    }

    @MainActor
    func testShippedMenloCodeFontMovesToFollowText() {
        let defaults = UserDefaults.standard
        let keys = ["codeFont", "hasMigratedSystemFonts_v1", "hasMigratedCodeFontDefault_v1", "hasMigratedCodeFontToText_v1", "hasMigratedFontDefaults_v2"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        for key in ["hasMigratedSystemFonts_v1", "hasMigratedCodeFontDefault_v1", "hasMigratedFontDefaults_v2"] {
            defaults.set(true, forKey: key)
        }

        // Menlo was written by an earlier migration, so it is not a choice.
        defaults.set(false, forKey: "hasMigratedCodeFontToText_v1")
        defaults.set("Menlo", forKey: "codeFont")
        UserDefaultsManagement.migrateFontDefaultsIfNeeded()
        XCTAssertEqual(UserDefaultsManagement.codeFontName, FontConfiguration.followTextFont)
        XCTAssertTrue(UserDefaultsManagement.codeFollowsText)

        // Any other face was picked by someone and stays.
        defaults.set(false, forKey: "hasMigratedCodeFontToText_v1")
        defaults.set("Monaco", forKey: "codeFont")
        UserDefaultsManagement.migrateFontDefaultsIfNeeded()
        XCTAssertEqual(UserDefaultsManagement.codeFontName, "Monaco")
    }

    func testWindowAppearanceDoesNotOverwriteTheSavedPreviewMode() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Controllers/ViewController.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "override func viewDidAppear()"))
        let end = try XCTUnwrap(source.range(of: "private func installLiveResizeObserverIfNeeded", range: start.upperBound..<source.endIndex))
        let appearance = String(source[start.upperBound..<end.lowerBound])
        XCTAssertNil(appearance.range(of: #"sessionPreviewMode\s*=\s*false"#, options: .regularExpression))
        XCTAssertTrue(appearance.contains("enablePreview()"))
    }

    @MainActor
    func testPreferencesWindowTracksAlwaysOnTopSetting() {
        let originalValue = UserDefaultsManagement.alwaysOnTop
        UserDefaultsManagement.alwaysOnTop = true

        let controller = PrefsWindowController()
        controller.show()

        defer {
            controller.window?.orderOut(nil)
            UserDefaultsManagement.alwaysOnTop = originalValue
            NotificationCenter.default.post(name: .alwaysOnTopChanged, object: nil)
        }

        XCTAssertEqual(controller.window?.level, .floating)

        UserDefaultsManagement.alwaysOnTop = false
        NotificationCenter.default.post(name: .alwaysOnTopChanged, object: nil)

        XCTAssertEqual(controller.window?.level, .normal)
    }
}
