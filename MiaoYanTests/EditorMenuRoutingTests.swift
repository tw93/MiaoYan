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
}
