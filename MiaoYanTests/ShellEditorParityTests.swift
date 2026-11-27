import SwiftUI
import XCTest

@testable import MiaoYan

/// The SwiftUI shell's editor column against the storyboard window's rules.
final class ShellEditorParityTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanShellEditorTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Both windows' list dates: a locale made from the app's language alone
    /// had no region and no clock, so an English interface in China or
    /// Britain printed `10:06 PM` beside a 22:06 menu bar clock (I-60).
    @MainActor
    func testTheListDateKeepsTheSystemsRegionAndClock() {
        let shown = Locale.components(fromIdentifier: Note.listDateLocale.identifier)
        let system = Locale.components(fromIdentifier: Locale.current.identifier)
        let region = NSLocale.Key.countryCode.rawValue
        XCTAssertNotNil(system[region], "the test machine names a region")
        XCTAssertEqual(shown[region], system[region])
        let systemHour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        let shownHour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Note.listDateLocale) ?? ""
        XCTAssertEqual(shownHour.contains("H"), systemHour.contains("H"), "12 or 24-hour as the system shows it")
    }

    @MainActor
    private func makeLoadedNote(_ name: String, body: String) -> Note {
        let url = tempDir.appendingPathComponent(name)
        try? body.write(to: url, atomically: true, encoding: .utf8)
        let project = Project(url: tempDir, label: "test", isRoot: true)
        let note = Note(url: url, with: project)
        note.content = NSMutableAttributedString(string: body)
        note.markContentAsLoaded()
        note.loadModifiedLocalAt()
        return note
    }

    /// A task ticked in the preview is saved to the note while the editor is
    /// off screen. Coming back, the editor must show the tick, or the next
    /// keystroke saves the old buffer over it.
    @available(macOS 14, *)
    @MainActor
    func testTaskTickedInPreviewSurvivesTheNextKeystroke() {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let note = makeLoadedNote("tasks.md", body: "- [ ] buy milk")
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)
        XCTAssertEqual(controller.textView.string, "- [ ] buy milk")

        // HandlerCheckbox's path when no editor is in the window.
        note.save(content: NSMutableAttributedString(string: "- [x] buy milk"))
        controller.show(note)

        XCTAssertEqual(controller.textView.string, "- [x] buy milk")
        XCTAssertTrue(controller.textView.storageNote === note, "the refill keeps the buffer's owner (#543)")
        let end = (controller.textView.string as NSString).length
        controller.textView.insertText("!", replacementRange: NSRange(location: end, length: 0))
        XCTAssertEqual(note.content.string, "- [x] buy milk!")
    }

    /// Command-S while the preview shows: the hidden editor still holds the
    /// text from before a task was ticked there, and copying it back undid
    /// the tick.
    @available(macOS 14, *)
    @MainActor
    func testSaveNowInPreviewKeepsATickMadeThere() {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let note = makeLoadedNote("tick.md", body: "- [ ] buy milk")
        defer { note.discardPendingSave() }
        let model = ShellModel()
        model.editor.show(note)
        XCTAssertNil(model.editor.textView.window, "off screen, as in preview")

        note.save(content: NSMutableAttributedString(string: "- [x] buy milk"))
        model.saveNow()

        XCTAssertEqual(note.content.string, "- [x] buy milk")
    }

    @available(macOS 14, *)
    @MainActor
    func testShowLeavesAnUnchangedBufferAlone() {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let note = makeLoadedNote("same.md", body: "line one\nline two")
        let controller = ShellEditorController()
        controller.show(note)
        controller.textView.setSelectedRange(NSRange(location: 5, length: 3))
        controller.show(note)
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 5, length: 3))
    }

    /// Command-+, a light/dark switch or a font change reloads the buffer.
    /// The selection made before it stays, not the cursor saved on disk.
    @available(macOS 14, *)
    @MainActor
    func testReloadKeepsTheLiveSelectionNotTheSavedCursor() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let note = makeLoadedNote("zoom.md", body: "line one\nline two\nline three")
        var saved = 0
        try note.url.setExtendedAttribute(data: Data(bytes: &saved, count: MemoryLayout.size(ofValue: saved)), forName: AppIdentifier.cursorKey)
        let controller = ShellEditorController()
        controller.show(note)
        controller.textView.setSelectedRange(NSRange(location: 9, length: 8))

        controller.reload(note)

        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 9, length: 8))
        XCTAssertTrue(controller.textView.storageNote === note)
    }

    /// New text from disk keeps the caret where it was, clamped to the new
    /// length, as the storyboard window's refill after an outside edit.
    @available(macOS 14, *)
    @MainActor
    func testReloadWithNewTextKeepsOnlyTheCaret() {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let note = makeLoadedNote("outside.md", body: "line one\nline two\nline three")
        let controller = ShellEditorController()
        controller.show(note)
        controller.textView.setSelectedRange(NSRange(location: 9, length: 8))

        note.content = NSMutableAttributedString(string: "line one\nline 2\nline three")
        controller.reload(note)
        XCTAssertEqual(controller.textView.string, "line one\nline 2\nline three")
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 9, length: 0))

        controller.textView.setSelectedRange(NSRange(location: 20, length: 0))
        note.content = NSMutableAttributedString(string: "short")
        controller.reload(note)
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 5, length: 0))
    }

    /// The last note of a folder deleted: the editor lets it go, and the
    /// next keystroke saves nothing into it.
    @available(macOS 14, *)
    @MainActor
    func testClearLetsTheRemovedNoteGo() {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let note = makeLoadedNote("gone.md", body: "removed text")
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)
        XCTAssertTrue(EditTextView.note === note)

        controller.clear()

        XCTAssertNil(EditTextView.note)
        XCTAssertNil(controller.textView.storageNote)
        XCTAssertEqual(controller.textView.string, "")
        XCTAssertFalse(controller.textView.isEditable)
        controller.textView.insertText("x", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(note.content.string, "removed text")
    }

    /// Prettier runs off the main thread; text typed meanwhile was replaced
    /// by the formatted copy of the older text when the result came back.
    @available(macOS 14, *)
    @MainActor
    func testTypingWhileFormattingKeepsTheTypedText() {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let note = makeLoadedNote("format.md", body: "#   Title\n\n*   item")
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)
        let host = NSViewController()
        host.view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let finished = expectation(description: "format finished")
        controller.onFormattingChange = { running in
            if !running { finished.fulfill() }
        }

        controller.format(in: host)
        let end = (controller.textView.string as NSString).length
        controller.textView.insertText(" typed", replacementRange: NSRange(location: end, length: 0))
        wait(for: [finished], timeout: 20)

        XCTAssertEqual(controller.textView.string, "#   Title\n\n*   item typed")
        XCTAssertEqual(note.content.string, "#   Title\n\n*   item typed")
    }

    /// Format wrote straight into the storage, so it was not on the undo
    /// stack: Command-Z after it replayed the earlier typing at stale ranges
    /// in the reformatted text. One undo now gives back the text from before
    /// Format, and the next one the text from before the typing.
    @available(macOS 14, *)
    @MainActor
    func testUndoAfterFormatRestoresTheTextBeforeIt() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let note = makeLoadedNote("undo-format.md", body: "#   Title\n\n*   item")
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)
        let undo = try XCTUnwrap(controller.textView.undoManager)
        // The test host never ends the event group a key press would end, so
        // each step here is its own group, as each event is in the app.
        undo.groupsByEvent = false
        defer { undo.groupsByEvent = true }
        undo.removeAllActions()
        undo.beginUndoGrouping()
        let end = (controller.textView.string as NSString).length
        controller.textView.insertText(" typed", replacementRange: NSRange(location: end, length: 0))
        undo.endUndoGrouping()

        let host = NSViewController()
        host.view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let finished = expectation(description: "format finished")
        controller.onFormattingChange = { running in
            if !running { finished.fulfill() }
        }
        undo.beginUndoGrouping()
        controller.format(in: host)
        wait(for: [finished], timeout: 20)
        undo.endUndoGrouping()
        let formatted = controller.textView.string
        XCTAssertNotEqual(formatted, "#   Title\n\n*   item typed", "Prettier changed the text")

        undo.undo()
        XCTAssertEqual(controller.textView.string, "#   Title\n\n*   item typed")
        XCTAssertEqual(note.content.string, "#   Title\n\n*   item typed")
        undo.undo()
        XCTAssertEqual(controller.textView.string, "#   Title\n\n*   item")
        undo.redo()
        undo.redo()
        XCTAssertEqual(controller.textView.string, formatted)
    }

    /// A file dragged in from Finder became an inline attachment NSTextView
    /// never saved (the drop handling went in a73f4585). It now takes the
    /// paste path: the file is copied to `i/` and its link goes in on its
    /// own line after the drop point's line. A text drag is still NSTextView's.
    @available(macOS 14, *)
    @MainActor
    func testDroppedFileIsCopiedAndLinkedAtTheDropPoint() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let previousUpload = UserDefaultsManagement.defaultPicUpload
        defer { UserDefaultsManagement.defaultPicUpload = previousUpload }
        UserDefaultsManagement.defaultPicUpload = "None"
        let note = makeLoadedNote("drop.md", body: "before after")
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)

        let source = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanDrop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4))
        image.unlockFocus()
        let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?.representation(using: .png, properties: [:]))
        let file = source.appendingPathComponent("dropped.png")
        try png.write(to: file)

        // The editor's own ClipboardManager is private; this one is built the same way.
        let drop = ClipboardManager(textView: controller.textView)
        let board = NSPasteboard(name: NSPasteboard.Name("miaoyan-drop-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("plain text", forType: .string)
        XCTAssertNil(drop.dropFiles(from: board, at: 0), "a text drag is NSTextView's")

        // A note dragged from the shell's list arrives as its file URL; it is
        // not copied into the note as an attachment.
        let library = Storage(loadsLibrary: false)
        let listed = makeLoadedNote("listed.md", body: "listed")
        library.add(listed)
        board.clearContents()
        board.writeObjects([listed.url as NSURL])
        XCTAssertEqual(drop.dropFiles(from: board, at: 7, storage: library), false, "a library note is refused")
        XCTAssertEqual(controller.textView.string, "before after")

        board.clearContents()
        board.writeObjects([file as NSURL, listed.url as NSURL])
        XCTAssertEqual(drop.dropFiles(from: board, at: 7, storage: library), true)

        XCTAssertFalse(controller.textView.textStorage?.containsAttachments ?? true)
        let text = controller.textView.string
        let match = try XCTUnwrap(text.range(of: "^before after\n!\\[\\]\\((/i/[^)]+\\.png)\\)$", options: .regularExpression), text)
        let link = String(text[match].dropFirst("before after\n![](".count).dropLast(")".count))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path + link), "copied to \(link)")
        XCTAssertEqual(note.content.string, text)
    }

    /// A PDF dragged in went to `files/` linked as an image, `![](/files/x.pdf)`,
    /// which the preview drew as an image that never loads. It is a link
    /// named as it was dropped, the Markdown the iPhone writes too.
    @available(macOS 14, *)
    @MainActor
    func testADroppedPDFIsALinkNamedAsTheFile() async throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let previousUpload = UserDefaultsManagement.defaultPicUpload
        defer { UserDefaultsManagement.defaultPicUpload = previousUpload }
        UserDefaultsManagement.defaultPicUpload = "None"
        let note = makeLoadedNote("drop-pdf.md", body: "before after")
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)

        let source = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanDrop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let file = source.appendingPathComponent("Report v2.pdf")
        try Data("%PDF-1.4".utf8).write(to: file)

        let drop = ClipboardManager(textView: controller.textView)
        let board = NSPasteboard(name: NSPasteboard.Name("miaoyan-drop-pdf-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.writeObjects([file as NSURL])
        XCTAssertEqual(drop.dropFiles(from: board, at: 7), true)

        XCTAssertEqual(controller.textView.string, "before after\n[Report v2.pdf](/files/Report-v2.pdf)")
        for copy in drop.copies { await copy.value }
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("files/Report-v2.pdf").path))
    }

    /// A file dropped inside a line went in at the drop point and split the
    /// line around its link. It goes after the line it was dropped on, on a
    /// line of its own (maintainer 2026-11-26); one undo takes the whole drop
    /// back, and a drop that puts nothing in leaves no line break behind.
    @available(macOS 14, *)
    @MainActor
    func testADropGoesOnItsOwnLineAfterTheLineItWasDroppedOn() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let previousUpload = UserDefaultsManagement.defaultPicUpload
        defer { UserDefaultsManagement.defaultPicUpload = previousUpload }
        UserDefaultsManagement.defaultPicUpload = "None"
        let body = "first line\n\nthird line"
        let note = makeLoadedNote("drop-line.md", body: body)
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)
        let editor = controller.textView
        // A text view only has an undo manager inside a window.
        let scroll = try XCTUnwrap(editor.enclosingScrollView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = scroll
        defer { window.contentView = nil }
        let undo = try XCTUnwrap(editor.undoManager)
        undo.groupsByEvent = false
        defer { undo.groupsByEvent = true }
        undo.removeAllActions()

        let source = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanDropLine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let file = source.appendingPathComponent("Plan.pdf")
        try Data("%PDF-1.4".utf8).write(to: file)
        let drop = ClipboardManager(textView: editor)
        let board = NSPasteboard(name: NSPasteboard.Name("miaoyan-drop-line-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.writeObjects([file as NSURL])

        XCTAssertEqual(drop.dropFiles(from: board, at: 3), true)
        XCTAssertEqual(editor.string, "first line\n[Plan.pdf](/files/Plan.pdf)\n\nthird line", "after the line, which stays whole")
        undo.undo()
        XCTAssertEqual(editor.string, body, "one undo takes the drop back")

        XCTAssertEqual(drop.dropFiles(from: board, at: 11), true)
        XCTAssertTrue(editor.string.hasPrefix("first line\n[Plan.pdf](/files/"), "an empty line takes the link with no extra break: \(editor.string)")
        XCTAssertTrue(editor.string.hasSuffix(")\nthird line"), editor.string)
        undo.undo()
        XCTAssertEqual(editor.string, body)

        // A picture whose file cannot be written (a file named `i` where
        // the folder goes) inserts nothing, and the line break made for it
        // is taken back.
        let blocker = tempDir.appendingPathComponent("i")
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let picture = source.appendingPathComponent("shot.png")
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4))
        image.unlockFocus()
        try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?.representation(using: .png, properties: [:])).write(to: picture)
        board.clearContents()
        board.writeObjects([picture as NSURL])
        _ = drop.dropFiles(from: board, at: 3)
        XCTAssertEqual(editor.string, body, "no stray line break")
    }

    /// uPic and Picsee put an `uploading-…` placeholder in and trashed the
    /// local picture once they answered, whether or not the swap found the
    /// placeholder, so a link edited during the upload pointed at the Trash.
    /// They now share the PicGo and S3 path: the local link goes in first and
    /// the file goes only after the note points at the upload.
    @available(macOS 14, *)
    @MainActor
    func testAnUploaderAppKeepsThePictureWhenTheLinkChangedMeanwhile() async throws {
        let previousNote = EditTextView.note
        let previousHost = UserDefaultsManagement.defaultPicUpload
        let previousExecutable = ClipboardManager.appUploaderExecutable
        defer {
            EditTextView.note = previousNote
            UserDefaultsManagement.defaultPicUpload = previousHost
            ClipboardManager.appUploaderExecutable = previousExecutable
        }
        EditTextView.note = nil
        let note = makeLoadedNote("upload-app.md", body: "")
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)
        let editor = controller.textView

        let source = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanUploadApp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let uploader = source.appendingPathComponent("uPic")
        try "#!/bin/sh\nsleep 0.3\necho https://img.example.com/shot.png\n".write(to: uploader, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: uploader.path)
        ClipboardManager.appUploaderExecutable = { _ in uploader.path }
        UserDefaultsManagement.defaultPicUpload = "uPic"

        let picture = source.appendingPathComponent("shot.png")
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?.representation(using: .png, properties: [:]))
        try png.write(to: picture)
        let board = NSPasteboard(name: NSPasteboard.Name("miaoyan-upload-app-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.writeObjects([picture as NSURL])

        // Held as the editor holds its own; a freed manager drops the reply.
        let manager = ClipboardManager(textView: editor)
        XCTAssertEqual(manager.dropFiles(from: board, at: 0), true)
        let inserted = editor.string
        let link = try XCTUnwrap(inserted.range(of: #"!\[\]\(/i/[^)]+\)"#, options: .regularExpression).map { String(inserted[$0]) }, inserted)
        let local = note.project.url.path + String(link.dropFirst(4).dropLast())
        XCTAssertTrue(FileManager.default.fileExists(atPath: local), "the local link goes in first")

        // Alt text typed while the upload runs, so the swap misses the link.
        let altAt = (inserted as NSString).range(of: "![](").location + 2
        editor.insertText("a red dot", replacementRange: NSRange(location: altAt, length: 0))
        XCTAssertTrue(note.content.string.contains("![a red dot](/i/"), "typing reaches the note at once")
        try await Task.sleep(nanoseconds: 1_500_000_000)
        withExtendedLifetime(manager) {}

        XCTAssertTrue(editor.string.contains("![a red dot](/i/"), editor.string)
        XCTAssertFalse(editor.string.contains("img.example.com"), editor.string)
        XCTAssertTrue(FileManager.default.fileExists(atPath: local), "the picture the note still links stays")
        try? FileManager.default.removeItem(atPath: local)
    }

    /// A file dropped inside a table became a row of it, and one dropped in a
    /// code block a line of the code; it goes after the whole block.
    @available(macOS 14, *)
    @MainActor
    func testADropInsideATableOrCodeGoesAfterTheBlock() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let body = "| a | b |\n| - | - |\n| 1 | 2 |\n\n```\ncode\n```\nend"
        let note = makeLoadedNote("drop-block.md", body: body)
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)
        let editor = controller.textView

        let source = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanDropBlock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let file = source.appendingPathComponent("Plan.pdf")
        try Data("%PDF-1.4".utf8).write(to: file)
        let drop = ClipboardManager(textView: editor)
        let board = NSPasteboard(name: NSPasteboard.Name("miaoyan-drop-block-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.writeObjects([file as NSURL])

        XCTAssertEqual(drop.dropFiles(from: board, at: 2), true)
        XCTAssertTrue(editor.string.hasPrefix("| a | b |\n| - | - |\n| 1 | 2 |\n[Plan.pdf](/files/Plan"), editor.string)
        editor.string = body
        XCTAssertEqual(drop.dropFiles(from: board, at: (body as NSString).range(of: "code").location), true)
        XCTAssertTrue(editor.string.contains("```\ncode\n```\n[Plan.pdf](/files/"), editor.string)
    }

    /// A CRLF note keeps one kind of line ending, and the break a drop adds
    /// at the end of a line just typed on is not folded into that typing:
    /// one undo takes the drop back and leaves the typing.
    @available(macOS 14, *)
    @MainActor
    func testADropKeepsCRLFAndIsItsOwnUndoStepAfterTyping() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let note = makeLoadedNote("drop-crlf.md", body: "first line\r\nthird line")
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)
        let editor = controller.textView
        let scroll = try XCTUnwrap(editor.enclosingScrollView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = scroll
        defer { window.contentView = nil }
        let undo = try XCTUnwrap(editor.undoManager)
        undo.groupsByEvent = false
        defer { undo.groupsByEvent = true }
        undo.removeAllActions()

        undo.beginUndoGrouping()
        editor.setSelectedRange(NSRange(location: 10, length: 0))
        editor.insertText("!", replacementRange: editor.selectedRange())
        undo.endUndoGrouping()
        let typed = "first line!\r\nthird line"
        XCTAssertEqual(editor.string, typed)

        let source = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanDropCRLF-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let file = source.appendingPathComponent("Plan.pdf")
        try Data("%PDF-1.4".utf8).write(to: file)
        let drop = ClipboardManager(textView: editor)
        let board = NSPasteboard(name: NSPasteboard.Name("miaoyan-drop-crlf-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.writeObjects([file as NSURL])

        XCTAssertEqual(drop.dropFiles(from: board, at: 3), true)
        XCTAssertEqual(editor.string, "first line!\r\n[Plan.pdf](/files/Plan.pdf)\r\nthird line")
        undo.undo()
        XCTAssertEqual(editor.string, typed, "one undo takes the drop back, the typing stays")
    }

    /// A dropped file whose copy fails later has its link taken out; the
    /// line break the drop made for it goes with it.
    @available(macOS 14, *)
    @MainActor
    func testADropWhoseCopyFailsTakesItsLineBreakBack() async throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let body = "first line\nthird line"
        let note = makeLoadedNote("drop-copy-fails.md", body: body)
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)

        // `files/` that cannot be written: the name is taken, the copy fails.
        let files = tempDir.appendingPathComponent("files")
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: files.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: files.path) }
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanDropFail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let file = source.appendingPathComponent("Plan.pdf")
        try Data("%PDF-1.4".utf8).write(to: file)
        let drop = ClipboardManager(textView: controller.textView)
        let board = NSPasteboard(name: NSPasteboard.Name("miaoyan-drop-fail-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.writeObjects([file as NSURL])

        XCTAssertEqual(drop.dropFiles(from: board, at: 3), true)
        XCTAssertEqual(controller.textView.string, "first line\n[Plan.pdf](/files/Plan.pdf)\nthird line")
        for copy in drop.copies { await copy.value }
        XCTAssertEqual(controller.textView.string, body, "the link and its line break are gone")
    }

    /// With an image host set, every dropped file went up to it whatever its
    /// kind: a PDF came back as `![](https://….pdf)` and its local file was
    /// trashed, the toast saying an image was uploading. Only `i/` images go
    /// up; a PDF stays a local link and nothing is started. Picsee is not
    /// installed on the test Macs, so the old code's attempt reached no host.
    @available(macOS 14, *)
    @MainActor
    func testWithAnImageHostSetADroppedPDFStaysALocalLink() async throws {
        XCTAssertEqual(ClipboardManager.uploadHost(forAttachmentAt: "/i/shot.png", setting: "PicGo"), .http)
        XCTAssertEqual(ClipboardManager.uploadHost(forAttachmentAt: "/i/shot.png", setting: "PicList"), .http)
        XCTAssertEqual(ClipboardManager.uploadHost(forAttachmentAt: "/i/shot.png", setting: "uPic"), .app("uPic"))
        XCTAssertNil(ClipboardManager.uploadHost(forAttachmentAt: "/i/shot.png", setting: "None"))
        for host in ["PicGo", "PicList", "uPic", "Picsee"] {
            XCTAssertNil(ClipboardManager.uploadHost(forAttachmentAt: "/files/Report-v2.pdf", setting: host), host)
            XCTAssertNil(ClipboardManager.uploadHost(forAttachmentAt: "/files/clip.mov", setting: host), host)
        }

        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let previousUpload = UserDefaultsManagement.defaultPicUpload
        defer { UserDefaultsManagement.defaultPicUpload = previousUpload }
        UserDefaultsManagement.defaultPicUpload = "Picsee"
        let note = makeLoadedNote("drop-pdf-host.md", body: "before after")
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)

        let source = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanDrop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let file = source.appendingPathComponent("Report v2.pdf")
        try Data("%PDF-1.4".utf8).write(to: file)

        let drop = ClipboardManager(textView: controller.textView)
        let board = NSPasteboard(name: NSPasteboard.Name("miaoyan-drop-pdf-host-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.writeObjects([file as NSURL])
        XCTAssertEqual(drop.dropFiles(from: board, at: 7), true)

        XCTAssertEqual(controller.textView.string, "before after\n[Report v2.pdf](/files/Report-v2.pdf)")
        for copy in drop.copies { await copy.value }
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("files/Report-v2.pdf").path))
    }

    /// A large video or PDF was read whole into memory and written back on
    /// the main thread. Anything but an image is now linked at once, in drop
    /// order with the images beside it, and cloned into `files/` off the main
    /// thread; a copy that fails takes its link out again.
    @available(macOS 14, *)
    @MainActor
    func testDroppedFilesAreLinkedInOrderAndCopiedOffTheMainThread() async throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let previousUpload = UserDefaultsManagement.defaultPicUpload
        defer { UserDefaultsManagement.defaultPicUpload = previousUpload }
        UserDefaultsManagement.defaultPicUpload = "None"
        let note = makeLoadedNote("drop-many.md", body: "before after")
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)

        let source = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanDrop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let video = Data((0..<4096).map { UInt8($0 % 251) })
        try video.write(to: source.appendingPathComponent("clip.mov"))
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4))
        image.unlockFocus()
        let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?.representation(using: .png, properties: [:]))
        try png.write(to: source.appendingPathComponent("shot.png"))
        try Data("%PDF-1.4".utf8).write(to: source.appendingPathComponent("Plan.pdf"))

        // Where each copy ran, read from inside the copy itself.
        let threads = CopyThreads()
        ImagesProcessor.willCopyAttachment = { _ in threads.record(Thread.isMainThread) }
        defer { ImagesProcessor.willCopyAttachment = nil }

        let drop = ClipboardManager(textView: controller.textView)
        let board = NSPasteboard(name: NSPasteboard.Name("miaoyan-drop-many-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.writeObjects(["clip.mov", "shot.png", "Plan.pdf"].map { source.appendingPathComponent($0) as NSURL })
        XCTAssertEqual(drop.dropFiles(from: board, at: 7), true)

        XCTAssertEqual(
            controller.textView.string, "before after\n![](/files/clip.mov)\n\n![](/i/shot.png)\n\n[Plan.pdf](/files/Plan.pdf)",
            "every link is in, in drop order, before the copies finish")
        XCTAssertEqual(drop.copies.count, 2, "the video and the PDF are copied, the image is written as before")
        // The same file again, its name taken (on disk, or held while the
        // first copy runs): it gets a name of its own.
        XCTAssertTrue(drop.saveFile(url: source.appendingPathComponent("Plan.pdf"), in: note))
        let text = controller.textView.string
        let second = try XCTUnwrap(text.range(of: #"\[Plan\.pdf\]\(/files/Plan\.pdf\)\[Plan\.pdf\]\(/files/[^)]+\)$"#, options: .regularExpression), text)
        let secondName = String(text[second].dropFirst("[Plan.pdf](/files/Plan.pdf)[Plan.pdf](/files/".count).dropLast(")".count))
        XCTAssertNotEqual(secondName, "Plan.pdf")
        for copy in drop.copies { await copy.value }
        XCTAssertEqual(threads.onMainThread, [false, false, false], "the video and both PDFs were copied, none on the main thread")

        let files = tempDir.appendingPathComponent("files")
        XCTAssertEqual(try Data(contentsOf: files.appendingPathComponent("clip.mov")), video)
        XCTAssertEqual(try Data(contentsOf: files.appendingPathComponent("Plan.pdf")), Data("%PDF-1.4".utf8))
        XCTAssertEqual(try Data(contentsOf: files.appendingPathComponent(secondName)), Data("%PDF-1.4".utf8))
        XCTAssertEqual(try Data(contentsOf: tempDir.appendingPathComponent("i/shot.png")), png)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: files.path).filter { $0.hasPrefix(".") }, [],
            "no partial copy is left beside them")
        XCTAssertEqual(note.content.string, controller.textView.string)

        // A file gone before it could be copied: its link comes back out.
        let before = controller.textView.string
        XCTAssertTrue(drop.saveFile(url: source.appendingPathComponent("gone.pdf"), in: note))
        XCTAssertNotEqual(controller.textView.string, before)
        for copy in drop.copies { await copy.value }
        XCTAssertEqual(controller.textView.string, before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.appendingPathComponent("gone.pdf").path))
    }

    /// Moving a note while a file dropped into it was still copying found
    /// no file to carry: the copy then landed in the old folder and the moved
    /// note's link pointed nowhere. The move is refused with a toast while
    /// the copy runs, and once it has landed the move carries the file.
    @available(macOS 14, *)
    @MainActor
    func testANoteIsNotMovedWhileAFileIsBeingCopiedIntoIt() async throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let previousUpload = UserDefaultsManagement.defaultPicUpload
        defer { UserDefaultsManagement.defaultPicUpload = previousUpload }
        UserDefaultsManagement.defaultPicUpload = "None"
        let previousFailure = Note.showFailure
        defer { Note.showFailure = previousFailure }
        var failures: [String] = []
        Note.showFailure = { message in
            failures.append(message)
            return true
        }
        let note = makeLoadedNote("drop-move.md", body: "before after")
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)

        let manager = FileManager.default
        let source = manager.temporaryDirectory.appendingPathComponent("MiaoYanDrop-\(UUID().uuidString)")
        try manager.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: source) }
        try Data("%PDF-1.4".utf8).write(to: source.appendingPathComponent("Plan.pdf"))
        let other = Project(url: tempDir.appendingPathComponent("Other", isDirectory: true), label: "Other")
        try manager.createDirectory(at: other.url, withIntermediateDirectories: true)

        // The copy waits inside the copy until the move has been tried.
        let gate = DispatchSemaphore(value: 0)
        ImagesProcessor.willCopyAttachment = { _ in gate.wait() }
        defer { ImagesProcessor.willCopyAttachment = nil }

        let drop = ClipboardManager(textView: controller.textView)
        let board = NSPasteboard(name: NSPasteboard.Name("miaoyan-drop-move-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.writeObjects([source.appendingPathComponent("Plan.pdf") as NSURL])
        XCTAssertEqual(drop.dropFiles(from: board, at: 7), true)
        let before = note.url

        note.move(toProject: other)
        XCTAssertEqual(note.url, before, "the note stays while its file copies")
        XCTAssertEqual(failures, ["A file is still being copied into this note, so it was not moved"])
        gate.signal()
        for copy in drop.copies { await copy.value }
        XCTAssertFalse(ImagesProcessor.isCopying(into: note))

        note.move(toProject: other)
        XCTAssertEqual(note.url.deletingLastPathComponent().standardizedFileURL, other.url.standardizedFileURL, "moved once the copy landed")
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(try Data(contentsOf: other.url.appendingPathComponent("files/Plan.pdf")), Data("%PDF-1.4".utf8), "the file went with it")
        let text = try String(contentsOf: other.url.appendingPathComponent("drop-move.md"), encoding: .utf8)
        XCTAssertTrue(text.contains("[Plan.pdf](/files/Plan.pdf)"), text)
    }

    /// Picture data dragged with no file beside it, as from a browser, was
    /// left to NSTextView and became an inline attachment never written to
    /// the note's folder (#578). It is saved and linked like a paste; a text
    /// selection that carries a picture stays text.
    @available(macOS 14, *)
    @MainActor
    func testDroppedPictureDataIsSavedAndLinkedAtTheDropPoint() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        let previousUpload = UserDefaultsManagement.defaultPicUpload
        defer { UserDefaultsManagement.defaultPicUpload = previousUpload }
        UserDefaultsManagement.defaultPicUpload = "None"
        let note = makeLoadedNote("drop-data.md", body: "before after")
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)

        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4))
        image.unlockFocus()
        let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?.representation(using: .png, properties: [:]))
        let drop = ClipboardManager(textView: controller.textView)
        let board = NSPasteboard(name: NSPasteboard.Name("miaoyan-drop-data-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }

        board.clearContents()
        board.setData(png, forType: .png)
        board.setString("a picture in a sentence", forType: .string)
        XCTAssertNil(drop.dropFiles(from: board, at: 7), "a text selection with a picture stays NSTextView's")

        board.clearContents()
        board.setData(png, forType: .png)
        XCTAssertEqual(drop.dropFiles(from: board, at: 7), true)

        XCTAssertFalse(controller.textView.textStorage?.containsAttachments ?? true)
        let text = controller.textView.string
        let match = try XCTUnwrap(text.range(of: "^before after\n!\\[\\]\\((/i/[^)]+\\.png)\\)$", options: .regularExpression), text)
        let link = String(text[match].dropFirst("before after\n![](".count).dropLast(")".count))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: tempDir.path + link)), png, "written to \(link) as it was dragged")
        XCTAssertEqual(note.content.string, text)
    }

    /// A photo dragged from Photos or Mail is a promise of a file; the editor
    /// refused it, so nothing happened (#578).
    @MainActor
    func testTheEditorAcceptsPromisedFiles() {
        let editor = EditTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let accepted = Set(editor.acceptableDragTypes.map(\.rawValue))
        XCTAssertTrue(Set(NSFilePromiseReceiver.readableDraggedTypes).isSubset(of: accepted))
        let plain = NSTextView(frame: editor.frame)
        plain.isRichText = editor.isRichText
        plain.importsGraphics = editor.importsGraphics
        XCTAssertTrue(Set(plain.acceptableDragTypes.map(\.rawValue)).isSubset(of: accepted), "Finder files and text still")
    }

    /// AppKit hands each promised file over on the receiver's operation queue.
    /// The reader once belonged to the main actor and the app crashed there on
    /// the first photo dropped; the files still come back in drag order.
    @MainActor
    func testPromisedFilesArriveFromABackgroundQueueInDragOrder() async {
        let done = expectation(description: "all promises answered")
        var received: [URL] = []
        let arrivals = PromiseArrivals(count: 3) { files in
            XCTAssertTrue(Thread.isMainThread)
            received = files
            done.fulfill()
        }
        let first = URL(fileURLWithPath: "/tmp/first.png"), third = URL(fileURLWithPath: "/tmp/third.png")
        let queue = OperationQueue()
        queue.addOperation { PromiseArrivals.reader(for: arrivals, at: 2)(third, nil) }
        queue.addOperation { PromiseArrivals.reader(for: arrivals, at: 1)(URL(fileURLWithPath: "/tmp/failed.png"), CocoaError(.fileWriteUnknown)) }
        queue.addOperation { PromiseArrivals.reader(for: arrivals, at: 0)(first, nil) }

        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(received, [first, third], "the failed one is left out")
    }

    /// The storyboard window's Format ends in the same `replaceWholeBuffer`
    /// (`ViewController+Editor`), so its one-undo-step guarantee is checked on a
    /// bare storyboard-style editor (not shell hosted). Not covered: Prettier
    /// and the ViewController around it, which need the storyboard window.
    @available(macOS 14, *)
    @MainActor
    func testReplaceWholeBufferIsOneUndoStepOnTheStoryboardEditor() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        let note = makeLoadedNote("undo-whole.md", body: "#   Title\n\n*   item")
        defer { note.discardPendingSave() }
        EditTextView.note = note
        let editor = EditTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        editor.allowsUndo = true
        // A text view only has an undo manager inside a window.
        let window = NSWindow(contentRect: editor.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = editor
        defer { window.contentView = nil }
        editor.publishStorage(NSAttributedString(string: "#   Title\n\n*   item"), owner: note)
        let undo = try XCTUnwrap(editor.undoManager)
        undo.groupsByEvent = false
        defer { undo.groupsByEvent = true }
        undo.removeAllActions()

        undo.beginUndoGrouping()
        let end = (editor.string as NSString).length
        editor.insertText(" typed", replacementRange: NSRange(location: end, length: 0))
        undo.endUndoGrouping()
        let typed = "#   Title\n\n*   item typed"
        XCTAssertEqual(editor.string, typed)

        undo.beginUndoGrouping()
        XCTAssertTrue(editor.replaceWholeBuffer(with: "# Title\n\n- item typed", note: note))
        undo.endUndoGrouping()
        XCTAssertEqual(editor.string, "# Title\n\n- item typed")

        undo.undo()
        XCTAssertEqual(editor.string, typed, "one undo gives back the text from before Format")
        editor.saveTextStorageContent(to: note)
        XCTAssertEqual(note.content.string, typed)
        undo.undo()
        XCTAssertEqual(editor.string, "#   Title\n\n*   item", "the next undo reaches the typing, not stale ranges")
    }

    /// The drop reaches `ClipboardManager.dropFiles` through
    /// `EditTextView.performDragOperation`, with the caret taken from the drag
    /// location; a text drag stays NSTextView's.
    @available(macOS 14, *)
    @MainActor
    func testPerformDragOperationRoutesFilesToDropFilesOnTheDragLine() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let previousUpload = UserDefaultsManagement.defaultPicUpload
        defer { UserDefaultsManagement.defaultPicUpload = previousUpload }
        UserDefaultsManagement.defaultPicUpload = "None"
        let note = makeLoadedNote("drag.md", body: "before after")
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.show(note)
        let editor = controller.textView
        // In a window, so the drag's window coordinates convert as they do in the app.
        let scroll = try XCTUnwrap(editor.enclosingScrollView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        defer { window.contentView = nil }
        scroll.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
        scroll.layoutSubtreeIfNeeded()

        let source = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanDrag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4))
        image.unlockFocus()
        let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?.representation(using: .png, properties: [:]))
        let file = source.appendingPathComponent("dragged.png")
        try png.write(to: file)

        let board = NSPasteboard(name: NSPasteboard.Name("miaoyan-drag-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.writeObjects([file as NSURL])

        // The caret index performDragOperation will compute from this point.
        editor.layoutManager?.ensureLayout(for: editor.textContainer!)
        let glyphRect = try XCTUnwrap(editor.layoutManager?.boundingRect(forGlyphRange: NSRange(location: 0, length: 12), in: editor.textContainer!))
        let origin = editor.textContainerOrigin
        let inView = NSPoint(x: origin.x + glyphRect.minX + glyphRect.width * 7 / 12, y: origin.y + glyphRect.midY)
        let point = editor.convert(inView, to: nil)
        let expected = editor.characterIndexForInsertion(at: inView)
        XCTAssertTrue((1..<11).contains(expected), "the drop point is inside the text: \(expected)")

        let handled = editor.performDragOperation(StubDraggingInfo(pasteboard: board, location: point))
        XCTAssertTrue(handled)
        let text = editor.string
        let match = try XCTUnwrap(text.range(of: "^before after\n!\\[\\]\\((/i/[^)]+\\.png)\\)$", options: .regularExpression), text)
        XCTAssertFalse(editor.textStorage?.containsAttachments ?? true)
        let link = String(text[text.range(of: "(/i/")!.lowerBound...].dropFirst().prefix(while: { $0 != ")" }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path + link), "copied to \(link) (\(match))")
        XCTAssertEqual(note.content.string, text)

        // A text drag is left to NSTextView: no file is copied and no link is added.
        let before = editor.string
        board.clearContents()
        board.setString("plain text", forType: .string)
        _ = editor.performDragOperation(StubDraggingInfo(pasteboard: board, location: point))
        XCTAssertEqual(editor.string.components(separatedBy: "![](").count, before.components(separatedBy: "![](").count)
    }

    /// The shell's text view is made in code; it must carry what the
    /// storyboard's EditTextView sets in Main.storyboard and ViewController.
    @available(macOS 14, *)
    @MainActor
    func testShellTextViewMatchesTheStoryboardEditor() {
        let shell = ShellEditorController().textView
        func traits(_ view: NSTextView) -> [String: String] {
            [
                "textCompletion": "\(view.isAutomaticTextCompletionEnabled)",
                "usesRuler": "\(view.usesRuler)",
                "rulerVisible": "\(view.isRulerVisible)",
                "importsGraphics": "\(view.importsGraphics)",
                "richText": "\(view.isRichText)",
                "allowsImageEditing": "\(view.allowsImageEditing)",
                "documentBackgroundColorChange": "\(view.allowsDocumentBackgroundColorChange)",
                "characterPicker": "\(view.allowsCharacterPickerTouchBarItem)",
                "smartInsertDelete": "\(view.smartInsertDeleteEnabled)",
                "usesFontPanel": "\(view.usesFontPanel)",
                "allowsUndo": "\(view.allowsUndo)",
                "usesFindBar": "\(view.usesFindBar)",
                "incrementalSearching": "\(view.isIncrementalSearchingEnabled)",
                "linkDetection": "\(view.isAutomaticLinkDetectionEnabled)",
                "quoteSubstitution": "\(view.isAutomaticQuoteSubstitutionEnabled)",
                "dataDetection": "\(view.isAutomaticDataDetectionEnabled)",
                "textReplacement": "\(view.isAutomaticTextReplacementEnabled)",
                "dashSubstitution": "\(view.isAutomaticDashSubstitutionEnabled)",
                "spellChecking": "\(view.isContinuousSpellCheckingEnabled)",
                "spellingCorrection": "\(view.isAutomaticSpellingCorrectionEnabled)",
                "grammarChecking": "\(view.isGrammarCheckingEnabled)",
                "attachmentScaling": "\(String(describing: view.layoutManager?.defaultAttachmentScaling.rawValue))",
                "nonContiguousLayout": "\(view.layoutManager?.allowsNonContiguousLayout ?? false)",
                "fieldEditor": "\(view.isFieldEditor)",
                "selectable": "\(view.isSelectable)",
                "inspectorBar": "\(view.usesInspectorBar)",
                "linkToolTips": "\(view.displaysLinkToolTips)",
                "verticallyResizable": "\(view.isVerticallyResizable)",
                "horizontallyResizable": "\(view.isHorizontallyResizable)",
                "focusRing": "\(view.focusRingType.rawValue)",
                "inlinePrediction": "\(view.inlinePredictionType.rawValue)",
                "lineFragmentPadding": "\(view.textContainer?.lineFragmentPadding ?? -1)",
            ]
        }
        // The window the test host opened, when it has one.
        if let storyboard = ViewController.shared()?.editArea {
            let expected = traits(storyboard)
            let actual = traits(shell)
            for key in expected.keys.sorted() {
                XCTAssertEqual(actual[key], expected[key], key)
            }
        }
        XCTAssertFalse(shell.isAutomaticTextCompletionEnabled)
        XCTAssertTrue(shell.importsGraphics)
        XCTAssertTrue(shell.allowsDocumentBackgroundColorChange)
        XCTAssertFalse(shell.allowsCharacterPickerTouchBarItem)
        XCTAssertEqual(shell.layoutManager?.defaultAttachmentScaling, .scaleProportionallyDown)
        XCTAssertFalse(shell.isEditable, "nothing is editable until a note is filled in")
    }

    /// Hovering an image link shows the Command-key tip in the shell too,
    /// whose editor has no ViewController.
    @available(macOS 14, *)
    @MainActor
    func testImageTipAppearsWithoutAViewController() {
        let original = UserDefaultsManagement.imagePreviewTipShowCount
        defer { UserDefaultsManagement.imagePreviewTipShowCount = original }
        UserDefaultsManagement.imagePreviewTipShowCount = 0
        let host = NSViewController()
        host.view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let window = NSWindow(contentRect: host.view.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentViewController = host
        let textView = EditTextView(frame: host.view.bounds)
        textView.isShellHosted = true
        host.view.addSubview(textView)
        textView.string = "![](i/a.png)"
        XCTAssertNil(textView.viewDelegate)

        ImagePreviewManager(textView: textView).handleImageLinkHover(at: 5, mousePoint: .zero, allowPreview: false)

        XCTAssertEqual(UserDefaultsManagement.imagePreviewTipShowCount, 1)
        ToastManager.shared.dismissCurrentToast()
    }

    func testPreviewDelayMatchesTheStoryboardEditor() {
        XCTAssertEqual(ShellSplitMath.previewDelay(forReplacement: "a"), 0.15)
        XCTAssertEqual(ShellSplitMath.previewDelay(forReplacement: nil), 0.15)
        XCTAssertEqual(ShellSplitMath.previewDelay(forReplacement: ""), 0.15)
        XCTAssertEqual(ShellSplitMath.previewDelay(forReplacement: "\n"), 0)
        XCTAssertEqual(ShellSplitMath.previewDelay(forReplacement: "\r\n"), 0)
        XCTAssertEqual(ShellSplitMath.previewDelay(forReplacement: "pasted"), 0)
        // One composed CJK character is one key.
        XCTAssertEqual(ShellSplitMath.previewDelay(forReplacement: "\u{4E2D}"), 0.15)
    }

    func testScrollSyncLinesSkipTheFrontmatter() {
        let text = "---\ntitle: a\n---\n# Heading\n\nbody"
        let starts = ShellSplitMath.lineStarts(of: text)
        XCTAssertEqual(starts, [0, 4, 13, 17, 27, 28])
        let frontmatter = 3
        // The heading is the body's first line.
        XCTAssertEqual(ShellSplitMath.bodyLine(atCharacter: 17, lineStarts: starts, frontmatterLines: frontmatter), 1)
        XCTAssertEqual(ShellSplitMath.bodyLine(atCharacter: 30, lineStarts: starts, frontmatterLines: frontmatter), 3)
        // Inside the frontmatter clamps to the first body line.
        XCTAssertEqual(ShellSplitMath.bodyLine(atCharacter: 5, lineStarts: starts, frontmatterLines: frontmatter), 1)
        // And back: body line 1 is buffer line 3 (0-based).
        let back = ShellSplitMath.bufferLine(forPreviewLine: 1.5, frontmatterLines: frontmatter)
        XCTAssertEqual(back.line, 3)
        XCTAssertEqual(back.fraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(ShellSplitMath.bufferLine(forPreviewLine: 3, frontmatterLines: 0).line, 2)
    }

    /// The editor reported a whole line number, so a paragraph that wraps
    /// to many rows, or the one line an image takes, moved the preview in a
    /// single jump. The position inside the line now travels with it, and
    /// the way back lands on the same height.
    @available(macOS 14, *)
    @MainActor
    func testAPlaceInsideAWrappedLineSurvivesTheTripToThePreviewAndBack() throws {
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let long = String(repeating: "wrapped words ", count: 120)
        let note = makeLoadedNote("wrap.md", body: "first\n\(long)\nlast")
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.scrollView.frame = NSRect(x: 0, y: 0, width: 420, height: 300)
        controller.show(note)
        controller.scrollView.layoutSubtreeIfNeeded()
        let textView = controller.textView
        let starts = ShellSplitMath.lineStarts(of: textView.string)

        let top = try XCTUnwrap(textView.documentY(ofSourceLine: 1, fraction: 0, lineStarts: starts))
        let foot = try XCTUnwrap(textView.documentY(ofSourceLine: 1, fraction: 1, lineStarts: starts))
        XCTAssertGreaterThan(foot - top, 100, "the paragraph wraps to several rows")

        let middle = top + (foot - top) * 0.5
        let place = try XCTUnwrap(textView.sourceLine(atDocumentY: middle, lineStarts: starts))
        XCTAssertEqual(place.line, 1)
        XCTAssertEqual(place.fraction, 0.5, accuracy: 0.01)
        let back = try XCTUnwrap(textView.documentY(ofSourceLine: place.line, fraction: place.fraction, lineStarts: starts))
        XCTAssertEqual(back, middle, accuracy: 0.5)

        XCTAssertEqual(ShellSplitMath.previewLine(bufferLine: 1, fraction: 0.5, frontmatterLines: 0), 2.5)
        XCTAssertEqual(ShellSplitMath.previewLine(bufferLine: 1, fraction: 0.5, frontmatterLines: 3), 1, "frontmatter is the top of the body")
        XCTAssertEqual(ShellSplitMath.previewLine(bufferLine: 4, fraction: 0.25, frontmatterLines: 3), 2.25)
    }

    func testThePreviewIsPulledToItsEndOnlyOverTheEditorsLastScreen() {
        XCTAssertEqual(ShellSplitMath.endPull(offset: 0, maxOffset: 3000, viewport: 600), 0)
        XCTAssertEqual(ShellSplitMath.endPull(offset: 2400, maxOffset: 3000, viewport: 600), 0)
        XCTAssertEqual(ShellSplitMath.endPull(offset: 2700, maxOffset: 3000, viewport: 600), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ShellSplitMath.endPull(offset: 3000, maxOffset: 3000, viewport: 600), 1)
        XCTAssertEqual(ShellSplitMath.endPull(offset: 3050, maxOffset: 3000, viewport: 600), 1, "rubber-banding past the end")
        // A note shorter than two screens: the whole scroll is the last screen.
        XCTAssertEqual(ShellSplitMath.endPull(offset: 100, maxOffset: 200, viewport: 600), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ShellSplitMath.endPull(offset: 0, maxOffset: 0, viewport: 600), 0, "nothing to scroll")
    }

    /// A fast scroll to the end left the preview a third of the way up: the
    /// editor's scrolls were ignored for 50ms after each sync and nothing
    /// followed the last of them, so the preview stayed where the editor
    /// had been a moment before it stopped, until the next scroll.
    @available(macOS 14, *)
    @MainActor
    func testThePreviewFollowsTheLastScrollOfAFastGesture() async throws {
        final class Recorder: MPreviewView {
            var calls: [(line: CGFloat, end: (line: CGFloat, pull: CGFloat)?)] = []
            override func scrollToLine(_ line: CGFloat, fallbackRatio: CGFloat? = nil, end: (line: CGFloat, pull: CGFloat)? = nil) {
                calls.append((line, end))
            }
            override func runWhenPreviewReady(_ block: @escaping () -> Void) { block() }
        }
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = nil
        let body = (1...200).map { "line \($0)" }.joined(separator: "\n")
        let note = makeLoadedNote("fast.md", body: body)
        defer { note.discardPendingSave() }
        let controller = ShellEditorController()
        controller.scrollView.frame = NSRect(x: 0, y: 0, width: 420, height: 300)
        controller.show(note)
        controller.scrollView.layoutSubtreeIfNeeded()
        let preview = Recorder(frame: .zero, note: note, closure: nil)
        controller.attachSplitPreview(preview)
        defer { controller.attachSplitPreview(nil) }
        try await Task.sleep(nanoseconds: 120_000_000)

        let clip = controller.scrollView.contentView
        let document = try XCTUnwrap(controller.scrollView.documentView)
        let maxOffset = document.bounds.height - controller.scrollView.contentSize.height
        XCTAssertGreaterThan(maxOffset, 1000)
        preview.calls.removeAll()
        // Two scrolls inside one 50ms window, the second reaching the end.
        clip.setBoundsOrigin(NSPoint(x: 0, y: 200))
        clip.setBoundsOrigin(NSPoint(x: 0, y: maxOffset))
        XCTAssertEqual(preview.calls.count, 1, "the first scroll moves the preview at once")
        try await Task.sleep(nanoseconds: 200_000_000)

        let last = try XCTUnwrap(preview.calls.last)
        let end = try XCTUnwrap(last.end)
        XCTAssertEqual(preview.calls.count, 2, "and the last one follows when the window closes")
        XCTAssertEqual(end.pull, 1, "the editor is at its end")
        XCTAssertEqual(last.line, end.line, accuracy: 0.001)
        XCTAssertGreaterThan(last.line, 150)
    }

    func testSplitPaneWidthFollowsEditorContentSplitView() {
        // First use: half, at most 600pt.
        XCTAssertEqual(ShellSplitMath.editorWidth(total: 800, savedRatio: 0), 400)
        XCTAssertEqual(ShellSplitMath.editorWidth(total: 1600, savedRatio: 0), 600)
        // A saved ratio, kept 200pt from either edge and under 1200pt.
        XCTAssertEqual(ShellSplitMath.editorWidth(total: 1000, savedRatio: 0.3), 300)
        XCTAssertEqual(ShellSplitMath.editorWidth(total: 1000, savedRatio: 0.05), 200)
        XCTAssertEqual(ShellSplitMath.editorWidth(total: 1000, savedRatio: 0.95), 800)
        XCTAssertEqual(ShellSplitMath.editorWidth(total: 3000, savedRatio: 0.9), 1200)
        // Never wider than the split itself.
        XCTAssertLessThanOrEqual(ShellSplitMath.editorWidth(total: 150, savedRatio: 0.5), 150)
    }

    @available(macOS 14, *)
    func testAPastedNoteKeepsItsFirstLineAndWhatWasTypedAroundIt() {
        XCTAssertEqual(ShellModel.singleLineTitle("plain", was: "plai"), "plain")
        // A whole note pasted at the caret between the two spaces of "Week  draft".
        XCTAssertEqual(ShellModel.singleLineTitle("Week \n# Plan #\r\nbody\n\nmore draft", was: "Week  draft"), "Week Plan draft")
        XCTAssertEqual(ShellModel.singleLineTitle("one\ntwo", was: ""), "one")
        // Replacing a selection: "old" selected, a note pasted over it.
        XCTAssertEqual(ShellModel.singleLineTitle("a new\nbody b", was: "a old b"), "a new b")
        XCTAssertEqual(ShellModel.singleLineTitle("ab\n  \nc", was: "abc"), "abc", "a paste of blank lines changes nothing")
    }

    func testRelaunchFromTheShellReopensTheShell() {
        let path = "'/Applications/MiaoYan.app'"
        XCTAssertEqual(
            AppDelegate.relaunchCommand(quotedAppPath: path, intoShell: false),
            "sleep 0.7; /usr/bin/open -n -a '/Applications/MiaoYan.app'")
        XCTAssertEqual(
            AppDelegate.relaunchCommand(quotedAppPath: path, intoShell: true),
            "sleep 0.7; /usr/bin/open -n -a '/Applications/MiaoYan.app' --args -MiaoYanShell YES")
    }

    /// Split mode takes the editor's container as SwiftUI's host leaves it,
    /// Auto Layout on and no constraints; the layout engine sized it to
    /// nothing, the split editor drew blank or ran under the preview, and
    /// leaving split mode left the whole note column blank (2026-11-21).
    @available(macOS 14, *)
    @MainActor
    func testTheSplitPaneSizesTheEditorTheEditOnlyViewHandsOver() {
        let controller = ShellEditorController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = NSView(frame: window.contentLayoutRect)
        window.contentView = root
        let pane = NSView(frame: NSRect(x: 0, y: 0, width: 459, height: 708))
        root.addSubview(pane)
        // The window runs the layout engine, as SwiftUI's host does.
        let pinned = NSView()
        pinned.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(pinned)
        NSLayoutConstraint.activate([pinned.widthAnchor.constraint(equalToConstant: 10), pinned.heightAnchor.constraint(equalToConstant: 10)])
        controller.container.translatesAutoresizingMaskIntoConstraints = false

        controller.moveContainer(into: pane)
        root.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.container.frame, pane.bounds)
        pane.frame = NSRect(x: 0, y: 0, width: 384, height: 708)
        root.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.container.frame, pane.bounds)
        XCTAssertEqual(controller.scrollView.frame, controller.container.bounds)
    }

    /// The shell's preview loaded the page again for every note, the blank
    /// frame between notes the storyboard window removed with
    /// `showNoteInPlace`, and on Command-3 rendered the note twice: once in
    /// `MPreviewView.init` and again from `makeNSView`. The next note now
    /// opens in the page on screen, and the first render is the only one.
    @available(macOS 14, *)
    @MainActor
    func testTheShellPreviewRendersOnceAndOpensTheNextNoteInPlace() async throws {
        let first = makeLoadedNote("first.md", body: "# First\n\nOne.")
        let second = makeLoadedNote("second.md", body: "# Second\n\nTwo.")
        var made: MPreviewView?
        var loads: [Note?] = []
        func preview(_ note: Note) -> ShellPreview {
            ShellPreview(note: note, switchesNotesInPlace: true, onMake: { made = $0 }, onLoad: { loads.append($0.displayedNote) })
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: preview(first))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(made)

        let firstShown = expectation(description: "first note shown")
        view.runWhenShowing(first) { firstShown.fulfill() }
        await fulfillment(of: [firstShown], timeout: 20)
        XCTAssertEqual(view.loadEpoch, 1, "the note is rendered once, by MPreviewView.init")
        XCTAssertEqual(loads.count, 1)
        _ = try await view.evaluateJavaScript("window.__miaoyanSamePage = true")

        host.rootView = preview(second)
        host.layoutSubtreeIfNeeded()
        let secondShown = expectation(description: "second note shown")
        view.runWhenShowing(second) { secondShown.fulfill() }
        await fulfillment(of: [secondShown], timeout: 20)
        let samePage = try await view.evaluateJavaScript("window.__miaoyanSamePage === true") as? Bool
        XCTAssertEqual(samePage, true, "the second note opened in the page already on screen")
        let text = try await view.evaluateJavaScript("document.getElementById('write').innerText") as? String
        XCTAssertTrue(text?.contains("Two.") == true, text ?? "")
        for _ in 0..<100 where loads.count < 2 { await Task.yield() }
        XCTAssertEqual(loads.count, 2)
        XCTAssertTrue(loads.last.flatMap { $0 } === second, "onLoad runs once the page shows the note")
    }
}

/// A drag the test controls: a private pasteboard and a point in the view.
@MainActor
private final class StubDraggingInfo: NSObject, @preconcurrency NSDraggingInfo {
    private let board: NSPasteboard
    private let location: NSPoint
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    init(pasteboard: NSPasteboard, location: NSPoint) {
        board = pasteboard
        self.location = location
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { board }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
    func resetSpringLoading() {}
}

/// The threads `ImagesProcessor.willCopyAttachment` reports, from whichever
/// thread each copy ran on.
private final class CopyThreads: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    func record(_ onMainThread: Bool) {
        lock.lock()
        values.append(onMainThread)
        lock.unlock()
    }

    var onMainThread: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
