import XCTest

@testable import MiaoYan

/// The storyboard's Format menu targets a stand-in EditTextView that sits in
/// no window. Bold, Italic and the rest must reach the window's editor; acting
/// on the stand-in did nothing, because it never has focus.
final class EditorMenuRoutingTests: XCTestCase {
    @MainActor
    func testFormatMenuOnTheStandInFormatsTheWindowEditor() {
        let dir = URL(fileURLWithPath: "/tmp/miaoyan-menu-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("note.md")
        try? "word".write(to: url, atomically: true, encoding: .utf8)
        let note = Note(url: url, with: Project(url: dir, label: "menu", isRoot: true))
        note.content = NSMutableAttributedString(string: "word")

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let editor = EditTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = editor
        editor.publishStorage(NSAttributedString(string: "word"), owner: note)
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 0, length: 4))

        let standIn = EditTextView(frame: .zero)
        standIn.configureOnLoad()
        let previous = EditorMenuManager.windowEditor
        EditorMenuManager.windowEditor = { editor }
        defer { EditorMenuManager.windowEditor = previous }

        standIn.boldMenu(NSMenuItem())

        XCTAssertEqual(editor.string, "**word**")
        XCTAssertEqual(standIn.string, "")
    }

    /// The storyboard stores Control-Option-Command-Delete for Clean Unused
    /// Attachments and only the storyboard window rewrote it, so the shell
    /// showed and took the old keys. The app now rewrites it once.
    @MainActor
    func testCleanUnusedAttachmentsIsShiftOptionCommandDelete() {
        let main = NSMenu()
        let app = NSMenuItem(title: "MiaoYan", action: nil, keyEquivalent: "")
        app.submenu = NSMenu()
        let clean = NSMenuItem(title: "Clean Unused Attachments", action: nil, keyEquivalent: "\u{8}")
        clean.identifier = NSUserInterfaceItemIdentifier("cleanAttachmentsMenu")
        clean.keyEquivalentModifierMask = [.control, .option, .command]
        app.submenu?.addItem(clean)
        main.addItem(app)

        AppDelegate.applyMenuShortcuts(to: main)

        XCTAssertEqual(clean.keyEquivalentModifierMask, [.command, .option, .shift])
    }

    /// The note list's context menu lives in the Editor scene, and an action
    /// wired to an object of another scene reaches nothing: MiaoYan PPT pointed
    /// at the Application scene's stand-in ViewController and showed greyed
    /// out in 4.5.0 (#571). Every item must target an object of its own scene.
    func testNoteListContextMenuTargetsItsOwnScene() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let xml = try String(contentsOf: root.appendingPathComponent("Resources/Localization/Base.lproj/Main.storyboard"), encoding: .utf8)
        let menuStart = try XCTUnwrap(xml.range(of: "<menu id=\"AaK-Xd-i52\">"))
        let sceneStart = try XCTUnwrap(xml.range(of: "<scene ", options: .backwards, range: xml.startIndex..<menuStart.lowerBound))
        let sceneEnd = try XCTUnwrap(xml.range(of: "</scene>", range: menuStart.upperBound..<xml.endIndex))
        let scene = String(xml[sceneStart.lowerBound..<sceneEnd.upperBound])
        let menu = String(xml[menuStart.lowerBound..<sceneEnd.lowerBound])

        func captures(_ pattern: String, in text: String) throws -> [String] {
            let regex = try NSRegularExpression(pattern: pattern)
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range(at: 1), in: text).map { String(text[$0]) }
            }
        }
        let sceneIDs = Set(try captures(" id=\"([^\"]+)\"", in: scene))
        let actions = try captures("<action selector=\"([^\"]+:)\" target=\"[^\"]+\"", in: menu)
        XCTAssertTrue(actions.contains("toggleMagicPPT:"))
        for (action, target) in zip(actions, try captures("<action selector=\"[^\"]+\" target=\"([^\"]+)\"", in: menu)) {
            XCTAssertTrue(sceneIDs.contains(target), "\(action) targets \(target), outside the note list's scene")
        }
    }
}
