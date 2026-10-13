import AppKit
import XCTest

@testable import MiaoYan

final class TitleInputTests: XCTestCase {
    @MainActor
    func testReturnDuringCompositionKeepsFocusInTitle() throws {
        try withTitleEditor { controller, fieldEditor in
            fieldEditor.setMarkedText("english", selectedRange: NSRange(location: 7, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertTrue(fieldEditor.hasMarkedText())

            XCTAssertTrue(controller.handleTitleReturn())

            XCTAssertTrue(controller.titleLabel.hasFocus(), "Return must reach the input method before focus can leave the title")
            XCTAssertTrue(controller.titleLabel.window?.firstResponder === fieldEditor)
            XCTAssertEqual(fieldEditor.string, "english")
        }
    }

    @MainActor
    func testReturnAfterCompositionMovesFocusToBody() throws {
        try withTitleEditor { controller, fieldEditor in
            fieldEditor.setMarkedText("english", selectedRange: NSRange(location: 7, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            fieldEditor.unmarkText()
            XCTAssertFalse(fieldEditor.hasMarkedText())

            XCTAssertFalse(controller.handleTitleReturn())

            XCTAssertTrue(controller.editArea.window?.firstResponder === controller.editArea)
            XCTAssertFalse(controller.titleLabel.hasFocus())
        }
    }

    @MainActor
    func testCompositionInEnglishLocaleKeepsFocusInTitle() throws {
        try withTitleEditor { controller, fieldEditor in
            UserDefaultsManagement.defaultLanguage = 1
            fieldEditor.setMarkedText("english", selectedRange: NSRange(location: 7, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertTrue(fieldEditor.hasMarkedText())

            XCTAssertTrue(controller.handleTitleReturn())

            XCTAssertTrue(controller.titleLabel.window?.firstResponder === fieldEditor)
            XCTAssertEqual(fieldEditor.string, "english")
        }
    }

    @MainActor
    func testJapaneseLocalePreservesTitleFocusAfterReturn() throws {
        try withTitleEditor { controller, fieldEditor in
            UserDefaultsManagement.defaultLanguage = 2
            XCTAssertFalse(fieldEditor.hasMarkedText())

            XCTAssertFalse(controller.handleTitleReturn())

            XCTAssertTrue(controller.titleLabel.window?.firstResponder === fieldEditor)
        }
    }

    @MainActor
    private func withTitleEditor(_ body: (ViewController, NSTextView) throws -> Void) throws {
        let previousNote = EditTextView.note
        let previousLanguage = UserDefaults.standard.object(forKey: "defaultLanguage")
        UserDefaultsManagement.defaultLanguage = 0

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.orderOut(nil)
            EditTextView.note = previousNote
            if let previousLanguage {
                UserDefaults.standard.set(previousLanguage, forKey: "defaultLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "defaultLanguage")
            }
        }

        let controller = ViewController(nibName: nil, bundle: nil)
        controller.titleLabel = TitleTextField(frame: NSRect(x: 10, y: 250, width: 380, height: 30))
        controller.titleLabel.isEditable = true
        controller.editArea = EditTextView(frame: NSRect(x: 10, y: 10, width: 380, height: 230))
        controller.notesTableView = NotesTableView(frame: .zero)
        let contentView = try XCTUnwrap(window.contentView)
        contentView.addSubview(controller.titleLabel)
        contentView.addSubview(controller.editArea)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanTitleInput-\(UUID().uuidString)")
        EditTextView.note = Note(url: root.appendingPathComponent("note.md"), with: Project(url: root, label: "title-input", isRoot: true))
        XCTAssertTrue(window.makeFirstResponder(controller.titleLabel))
        let fieldEditor = try XCTUnwrap(controller.titleLabel.currentEditor() as? NSTextView)
        XCTAssertTrue(controller.titleLabel.hasFocus())

        try body(controller, fieldEditor)
    }
}
