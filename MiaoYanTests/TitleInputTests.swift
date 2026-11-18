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

    /// A whole note pasted into the title used to become one line of the
    /// entire text, whose failed rename raised an alert taller than the screen.
    @MainActor
    func testPastingANoteIntoTheTitleKeepsOnlyItsFirstLineAndLeavesTheClipboard() throws {
        try withTitleEditor { controller, fieldEditor in
            XCTAssertTrue(fieldEditor is TitleFieldEditor, "every way of pasting must reach the title's own field editor")
            controller.titleLabel.delegate = controller
            defer { UserDataService.instance.pendingTitleChange = nil }

            let note = "\n  \n# Weekly plan  \r\nFirst paragraph of the body.\n\nSecond paragraph."
            let pb = try pasteboard(holding: note)
            defer { pb.releaseGlobally() }

            // readSelection(from:) is what Cmd+V, Edit > Paste and the context menu all run.
            XCTAssertTrue(fieldEditor.readSelection(from: pb))

            XCTAssertEqual(fieldEditor.string, "Weekly plan", "the heading's # marks must not name the file")
            XCTAssertEqual(pb.string(forType: .string), note, "the clipboard still pastes intact into the body")
            XCTAssertEqual(UserDataService.instance.pendingTitleChange?.title, "Weekly plan")
        }
    }

    @MainActor
    func testSingleLinePasteKeepsItsSpacesAndABlankPasteChangesNothing() throws {
        try withTitleEditor { _, fieldEditor in
            fieldEditor.insertText("Plan", replacementRange: NSRange(location: NSNotFound, length: 0))
            let spaced = try pasteboard(holding: " draft ")
            defer { spaced.releaseGlobally() }
            XCTAssertTrue(fieldEditor.readSelection(from: spaced))
            XCTAssertEqual(fieldEditor.string, "Plan draft ")

            fieldEditor.selectAll(nil)
            let blank = try pasteboard(holding: "\n  \n")
            defer { blank.releaseGlobally() }
            fieldEditor.readSelection(from: blank)
            XCTAssertEqual(fieldEditor.string, "Plan draft ", "a paste of blank lines must not delete the selection")
        }
    }

    @MainActor
    func testATooLongTitleIsDroppedAndTheFieldShowsTheNoteTitleAgain() throws {
        try withTitleEditor { controller, _ in
            controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
            let note = try XCTUnwrap(EditTextView.note)
            let long = String(repeating: "这是一段正文。", count: 2000)
            controller.titleLabel.stringValue = long
            UserDataService.instance.pendingTitleChange = (title: long, note: note)
            defer { UserDataService.instance.pendingTitleChange = nil }

            controller.saveTitleSafely()

            XCTAssertNil(UserDataService.instance.pendingTitleChange, "a mode switch or note click must not try it again")
            XCTAssertEqual(controller.titleLabel.stringValue, note.getTitleWithoutLabel())
            XCTAssertNil(controller.titleLabel.window?.attachedSheet)
        }
    }

    @MainActor
    private func pasteboard(holding text: String) throws -> NSPasteboard {
        let pb = NSPasteboard(name: NSPasteboard.Name("MiaoYanTitlePaste-\(UUID().uuidString)"))
        pb.clearContents()
        XCTAssertTrue(pb.setString(text, forType: .string))
        return pb
    }

    func testATitleLongerThanAFileNameCanHoldIsRefused() {
        XCTAssertTrue(Note.fileNameFits(String(repeating: "a", count: 252), ext: "md"))
        XCTAssertFalse(Note.fileNameFits(String(repeating: "a", count: 253), ext: "md"))
        // Each CJK character is three UTF-8 bytes: 84 of them plus ".md" is 255.
        XCTAssertTrue(Note.fileNameFits(String(repeating: "妙", count: 84), ext: "md"))
        XCTAssertFalse(Note.fileNameFits(String(repeating: "妙", count: 85), ext: "md"))
        XCTAssertFalse(Note.fileNameFits(String(repeating: "这是一段正文。", count: 2000), ext: "md"))
    }

    func testAnAlertQuotesALongTitleCutShort() {
        XCTAssertEqual(MiaoYanAlert.shortTitle("Weekly"), "Weekly")
        let long = String(repeating: "这是一段正文。", count: 2000)
        XCTAssertEqual(MiaoYanAlert.shortTitle(long).count, 81)
        XCTAssertTrue(MiaoYanAlert.shortTitle(long).hasSuffix("\u{2026}"))
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
