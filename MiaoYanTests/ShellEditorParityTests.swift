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
