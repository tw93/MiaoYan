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
    /// paste path: the file is copied to `i/` and its link goes in at the
    /// drop point. A text drag is still NSTextView's.
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
        let match = try XCTUnwrap(text.range(of: "^before !\\[\\]\\((/i/[^)]+\\.png)\\)after$", options: .regularExpression), text)
        let link = String(text[match].dropFirst("before ![](".count).dropLast(")after".count))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path + link), "copied to \(link)")
        XCTAssertEqual(note.content.string, text)
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
    func testPerformDragOperationRoutesFilesToDropFilesAtTheDragPoint() throws {
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
        let match = try XCTUnwrap(text.range(of: "^(.*)!\\[\\]\\((/i/[^)]+\\.png)\\)(.*)$", options: .regularExpression), text)
        let head = String(text[..<(text.range(of: "![](")!.lowerBound)])
        XCTAssertEqual(head.utf16.count, expected, "the link lands at the drag point")
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
    func testPastedTitleLineBreaksBecomeSpaces() {
        XCTAssertEqual(ShellModel.singleLineTitle("plain"), "plain")
        XCTAssertEqual(ShellModel.singleLineTitle("one\ntwo"), "one two")
        XCTAssertEqual(ShellModel.singleLineTitle("one\r\ntwo\rthree"), "one two three")
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
