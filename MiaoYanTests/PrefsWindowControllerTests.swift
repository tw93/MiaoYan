import AppKit
import SwiftUI
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
        XCTAssertEqual(UserDefaultsManagement.noteFont.fontName, NSFont.systemFont(ofSize: CGFloat(UserDefaultsManagement.fontSize)).fontName)

        // A fresh install starts on the default face by name.
        defaults.removeObject(forKey: "fontName")
        XCTAssertEqual(UserDefaultsManagement.fontName, FontConfiguration.defaultEditorFont)
    }

    /// A chosen face that was missing appears: the shell re-renders, as the
    /// storyboard window does from its own observer. Unrelated font changes
    /// rebuild nothing.
    @available(macOS 14, *)
    @MainActor
    func testShellRerendersWhenAMissingChosenFaceAppears() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "fontName")
        defer {
            if let original { defaults.set(original, forKey: "fontName") } else { defaults.removeObject(forKey: "fontName") }
            NotesTextProcessor.hl = nil
            NotesTextProcessor.refreshFonts()
        }
        defaults.set("NoSuchFace-Regular", forKey: "fontName")
        let model = ShellModel()
        let revision = model.interfaceRevision
        let style = model.previewStyleRevision

        model.installedFontsDidChange()
        XCTAssertEqual(model.interfaceRevision, revision, "nothing chosen appeared")

        // The face is no longer missing, as when it gets installed.
        defaults.set("Helvetica", forKey: "fontName")
        model.installedFontsDidChange()
        XCTAssertEqual(model.interfaceRevision, revision + 1)
        XCTAssertEqual(model.previewStyleRevision, style + 1)
    }

    /// Both windows read fonts migrated before either opens.
    func testFontMigrationRunsAtLaunchForEitherWindow() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let delegate = try String(contentsOf: root.appendingPathComponent("Controllers/AppDelegate.swift"), encoding: .utf8)
        let start = try XCTUnwrap(delegate.range(of: "func applicationWillFinishLaunching("))
        let end = try XCTUnwrap(delegate.range(of: "\n    }\n", range: start.upperBound..<delegate.endIndex))
        XCTAssertTrue(delegate[start.upperBound..<end.lowerBound].contains("UserDefaultsManagement.migrateFontDefaultsIfNeeded()"))
        let controller = try String(contentsOf: root.appendingPathComponent("Controllers/ViewController.swift"), encoding: .utf8)
        XCTAssertFalse(controller.contains("migrateFontDefaultsIfNeeded()"), "runs once, at launch")
    }

    @MainActor
    func testTheDefaultFaceWaitingToBeInstalledSelectsItsRow() throws {
        guard !FontCatalog.isInstalled(family: FontCatalog.retiredBundledFamily) else {
            throw XCTSkip("TsangerJinKai02 is installed here, so there is no waiting row")
        }
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "previewFontName")
        defaults.set(FontCatalog.retiredBundledFace, forKey: "previewFontName")
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
        XCTAssertEqual(preview.itemArray.filter { $0.representedObject as? String == FontCatalog.retiredBundledFace }.count, 1)
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

    /// ⌘W then reopening the storyboard window used to leave Always on Top
    /// and live appearance changes without an observer: windowWillClose
    /// removed both and makeNew() never added them back.
    func testClosingTheStoryboardWindowKeepsItsObservers() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Controllers/MainWindowController.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "func windowWillClose("))
        let end = try XCTUnwrap(source.range(of: "\n    func ", range: start.upperBound..<source.endIndex))
        let close = String(source[start.upperBound..<end.lowerBound])
        XCTAssertFalse(close.contains("removeObserver"))
    }

    @MainActor
    func testFirstShellLaunchTakesTheStoryboardColumns() throws {
        guard #available(macOS 14, *) else { throw XCTSkip("The shell needs macOS 14") }
        let folders = ["0.000000, 0.000000, 200.000000, 680.000000, NO, NO", "201.000000, 0.000000, 1079.000000, 680.000000, NO, NO"]
        let notes = ["0.000000, 0.000000, 300.000000, 680.000000, NO, NO", "301.000000, 0.000000, 778.000000, 680.000000, NO, NO"]
        let shown = try XCTUnwrap(ShellWindowController.storyboardColumns(sidebar: folders, list: notes))
        XCTAssertEqual(shown.layout, .all)
        XCTAssertEqual(shown.frames.map { $0.components(separatedBy: ", ")[2] }, ["200.000000", "300.000000", "778.000000"])
        XCTAssertEqual(shown.frames.map { $0.components(separatedBy: ", ")[0] }, ["0.000000", "201.000000", "502.000000"])

        // Hidden folders keep the shell's default width for when they open.
        let noFolders = ["0.000000, 0.000000, 0.000000, 680.000000, NO, NO", "1.000000, 0.000000, 1279.000000, 680.000000, NO, NO"]
        let listAndNote = try XCTUnwrap(ShellWindowController.storyboardColumns(sidebar: noFolders, list: notes))
        XCTAssertEqual(listAndNote.layout, .listAndNote)
        XCTAssertEqual(listAndNote.frames.first?.components(separatedBy: ", ")[2], "180.000000")

        let noNotes = ["0.000000, 0.000000, 0.000000, 680.000000, YES, NO", "1.000000, 0.000000, 1279.000000, 680.000000, NO, NO"]
        XCTAssertEqual(ShellWindowController.storyboardColumns(sidebar: noFolders, list: noNotes)?.layout, .noteOnly)
        XCTAssertNil(ShellWindowController.storyboardColumns(sidebar: nil, list: notes))
    }

    @MainActor
    func testStoryboardColumnsAreAdoptedOnlyOnce() throws {
        guard #available(macOS 14, *) else { throw XCTSkip("The shell needs macOS 14") }
        let suite = "miaoyan-shell-columns-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["0.000000, 0.000000, 0.000000, 680.000000, NO, NO", "1.000000, 0.000000, 1279.000000, 680.000000, NO, NO"], forKey: "NSSplitView Subview Frames SidebarSplitView")
        defaults.set(["0.000000, 0.000000, 300.000000, 680.000000, NO, NO", "301.000000, 0.000000, 978.000000, 680.000000, NO, NO"], forKey: "NSSplitView Subview Frames EditorSplitView")

        ShellWindowController.adoptStoryboardColumns(defaults)
        XCTAssertEqual(defaults.stringArray(forKey: "NSSplitView Subview Frames MiaoYanShellSplit")?.count, 3)
        XCTAssertEqual(defaults.string(forKey: "ShellLayout"), "listAndNote")

        // The shell's own layout wins from then on.
        defaults.set(["0, 0, 150, 680, NO, NO"], forKey: "NSSplitView Subview Frames MiaoYanShellSplit")
        defaults.set("all", forKey: "ShellLayout")
        ShellWindowController.adoptStoryboardColumns(defaults)
        XCTAssertEqual(defaults.stringArray(forKey: "NSSplitView Subview Frames MiaoYanShellSplit"), ["0, 0, 150, 680, NO, NO"])
        XCTAssertEqual(defaults.string(forKey: "ShellLayout"), "all")
    }

    @MainActor
    func testTitleBarDoubleClickFollowsTheSystemSetting() throws {
        guard #available(macOS 14, *) else { throw XCTSkip("The shell needs macOS 14") }
        XCTAssertEqual(ShellTitleBarArea.doubleClick(action: nil, legacyMinimize: false), .zoom)
        XCTAssertEqual(ShellTitleBarArea.doubleClick(action: "Maximize", legacyMinimize: true), .zoom)
        XCTAssertEqual(ShellTitleBarArea.doubleClick(action: "Fill", legacyMinimize: false), .zoom)
        XCTAssertEqual(ShellTitleBarArea.doubleClick(action: "Minimize", legacyMinimize: false), .minimize)
        XCTAssertEqual(ShellTitleBarArea.doubleClick(action: "None", legacyMinimize: false), .none)
        XCTAssertEqual(ShellTitleBarArea.doubleClick(action: nil, legacyMinimize: true), .minimize)
    }

    /// The SwiftUI pane takes every click in the title band unless something
    /// AppKit sits under the header: empty space must reach the title bar
    /// area, while a header button and a field keep their clicks.
    @MainActor
    func testHeaderEmptySpaceReachesTheTitleBarArea() throws {
        guard #available(macOS 14, *) else { throw XCTSkip("The shell needs macOS 14") }
        let view = NSHostingView(
            rootView: VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Spacer()
                    Button("Format") {}.buttonStyle(.plain)
                    TextField("Search", text: .constant("")).frame(width: 60)
                }
                .frame(height: 52)
                .background(ShellTitleBarArea())
                .background(SwiftUI.Color.white)
                SwiftUI.Color.white
            }
            .frame(width: 400, height: 200)
            .ignoresSafeArea(.container, edges: .top))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.contentView = view
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.hitTest(NSPoint(x: 100, y: 174)) is ShellTitleBarArea.AreaView)
        XCTAssertFalse(view.hitTest(NSPoint(x: 100, y: 100)) is ShellTitleBarArea.AreaView)
        XCTAssertFalse(view.hitTest(NSPoint(x: 370, y: 174)) is ShellTitleBarArea.AreaView)
        let button = try XCTUnwrap((0..<340).map { CGFloat($0) }.first { view.hitTest(NSPoint(x: $0, y: 174)) === view })
        XCTAssertGreaterThan(button, 250)
    }
}
