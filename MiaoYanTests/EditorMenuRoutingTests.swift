import MiaoYanCore
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

    /// File > Single Mode targets the Application scene's stand-in
    /// ViewController, whose outlets are nil. Its panel callback reloaded on
    /// that stand-in and trapped on `storageOutlineView` as soon as a folder
    /// was picked (#572). The stand-in has nothing to reload and must return.
    @MainActor
    func testSingleModeReloadOnTheStandInDoesNotTrap() {
        let standIn = ViewController()
        XCTAssertNil(standIn.storageOutlineView)
        standIn.reloadForSingleMode()
        XCTAssertNil(standIn.storageOutlineView)
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

    // MARK: - TextFormatter

    @MainActor
    private func makeEditor(_ text: String) -> (EditTextView, Note) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("miaoyan-formatter-\(UUID().uuidString)")
        let note = Note(url: dir.appendingPathComponent("note.md"), with: Project(url: dir, label: "formatter", isRoot: true))
        note.content = NSMutableAttributedString(string: text)
        let editor = EditTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        editor.publishStorage(NSAttributedString(string: text), owner: note)
        return (editor, note)
    }

    /// Return after "- [x] done" started "- [x] ", a task already ticked.
    @MainActor
    func testReturnAfterACheckedTaskStartsAnUncheckedOne() {
        for (text, expected) in [
            ("- [x] done", "- [x] done\n- [ ] "),
            ("  - [X] done", "  - [X] done\n  - [ ] "),
            ("- [ ] open", "- [ ] open\n- [ ] "),
        ] {
            let (editor, note) = makeEditor(text)
            editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            TextFormatter(textView: editor, note: note, shouldScanMarkdown: false).newLine()
            XCTAssertEqual(editor.string, expected, text)
        }
    }

    /// Command-T replaced the line's first six characters with a task
    /// marker: "  - [x] a" became "- [ ] ] a". Only the box flips now.
    @MainActor
    func testToggleTodoFlipsOnlyTheTaskBox() {
        for (text, expected) in [
            ("  - [x] a", "  - [ ] a"),
            ("  - [ ] a", "  - [x] a"),
            ("- [X] a", "- [ ] a"),
            ("1. [ ] b", "1. [x] b"),
            ("plain", "- [ ] plain"),
            ("text - [ ] not a task", "- [ ] text - [ ] not a task"),
        ] {
            let (editor, note) = makeEditor(text)
            editor.setSelectedRange(NSRange(location: 2, length: 1))
            TextFormatter(textView: editor, note: note).toggleTodo()
            XCTAssertEqual(editor.string, expected, text)
            if text.contains("[") && !text.hasPrefix("text") {
                XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 1), "the selection stays: \(text)")
            }
        }
    }

    /// Command-K and the image command tested the selection against 4 and 5,
    /// the length of "[]()" and "![]()": an empty selection put the caret in
    /// the parentheses and a four-letter one in the brackets.
    @MainActor
    func testLinkAndImageCaretFollowsWhetherTextWasSelected() {
        var (editor, note) = makeEditor("")
        TextFormatter(textView: editor, note: note).link()
        XCTAssertEqual(editor.string, "[]()")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 1, length: 0))

        (editor, note) = makeEditor("abcd")
        editor.setSelectedRange(NSRange(location: 0, length: 4))
        TextFormatter(textView: editor, note: note).link()
        XCTAssertEqual(editor.string, "[abcd]()")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 7, length: 0))

        (editor, note) = makeEditor("")
        TextFormatter(textView: editor, note: note).image()
        XCTAssertEqual(editor.string, "![]()")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 0))

        (editor, note) = makeEditor("abcde")
        editor.setSelectedRange(NSRange(location: 0, length: 5))
        TextFormatter(textView: editor, note: note).image()
        XCTAssertEqual(editor.string, "![abcde]()")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 9, length: 0))
    }

    /// "\r\n" ends a CRLF line: the caret at the end of its text sat two
    /// before the paragraph's end, which the list continuation took for the
    /// middle of the line, and an empty item measured one short. The new
    /// line was a bare "\n" until 2026-11-11; it keeps the note's CRLF now,
    /// as the iPhone editor always did, so one note has one line ending.
    @MainActor
    func testListContinuesOnCRLFLines() {
        for (text, caret, expected) in [
            ("- a\r\n- b", 3, "- a\r\n- \r\n- b"),
            ("1. a\r\nx", 4, "1. a\r\n2. \r\nx"),
            ("- [x] a\r\nx", 7, "- [x] a\r\n- [ ] \r\nx"),
            ("- a\r\n- \r\nend", 7, "- a\r\n\r\nend"),
            ("> a\r\nx", 3, "> a\r\n> \r\nx"),
            ("\u{2022} a\r\nx", 3, "\u{2022} a\r\n\u{2022} \r\nx"),
        ] {
            let (editor, note) = makeEditor(text)
            editor.setSelectedRange(NSRange(location: caret, length: 0))
            TextFormatter(textView: editor, note: note, shouldScanMarkdown: false).newLine()
            XCTAssertEqual(editor.string, expected, text.debugDescription)
        }
    }

    /// Return at the end of `text`, or at `caret`, through the editor.
    @MainActor
    private func pressReturn(_ text: String, at caret: Int? = nil) -> (String, NSRange) {
        let (editor, note) = makeEditor(text)
        editor.setSelectedRange(NSRange(location: caret ?? (text as NSString).length, length: 0))
        TextFormatter(textView: editor, note: note, shouldScanMarkdown: false).newLine()
        return (editor.string, editor.selectedRange())
    }

    /// `- name:` in a YAML block got a `- ` on the next line; inside a
    /// fenced block Return is a plain newline, keeping the line's indent.
    @MainActor
    func testReturnInAFencedCodeBlockContinuesNoList() {
        let yaml = "```yaml\n- name: a\n  - b\n> c\n```\n"
        let ns = yaml as NSString
        for (line, insertion) in [("- name: a", "\n"), ("  - b", "\n  "), ("> c", "\n")] {
            let caret = NSMaxRange(ns.range(of: line))
            let (text, selection) = pressReturn(yaml, at: caret)
            XCTAssertEqual(text, ns.replacingCharacters(in: NSRange(location: caret, length: 0), with: insertion), line)
            XCTAssertEqual(selection, NSRange(location: caret + (insertion as NSString).length, length: 0), line)
        }
        XCTAssertEqual(pressReturn(yaml + "- after").0, yaml + "- after\n- ")
    }

    /// The Mac continued `> ` but not `1) `, the iPhone the other way round;
    /// both continue both now, a quote at its depth, and an empty quote line
    /// ends the quote as an empty item ends its list.
    @MainActor
    func testReturnContinuesQuotesAndParenthesisNumbers() {
        for (text, expected) in [
            ("1) one", "1) one\n2) "),
            ("  9) nine", "  9) nine\n  10) "),
            ("> quoted", "> quoted\n> "),
            ("> > deeper", "> > deeper\n> > "),
            ("> - quoted item", "> - quoted item\n> - "),
            ("> - [x] quoted task", "> - [x] quoted task\n> - [ ] "),
        ] {
            let (result, selection) = pressReturn(text)
            XCTAssertEqual(result, expected, text)
            XCTAssertEqual(selection, NSRange(location: (expected as NSString).length, length: 0), text)
        }
        XCTAssertEqual(pressReturn("> a\n> > ").0, "> a\n")
        XCTAssertEqual(pressReturn("> a\n> \nend", at: 6).0, "> a\n\nend")
        XCTAssertEqual(pressReturn("> a\n> \nend", at: 6).1, NSRange(location: 4, length: 0))
    }

    /// The same Return through MiaoYanCore, which the iPhone editor runs,
    /// and through the Mac editor gives the same text and caret.
    @MainActor
    func testReturnMatchesTheCoreRuleTheIPhoneRuns() {
        let cases: [(String, Int?)] = [
            ("- one", nil), ("* one", nil), ("+ one", nil), ("9. nine", nil), ("1) one", nil),
            ("- [x] done", nil), ("1. [ ] box", nil), ("\t- tab", nil), ("  - nested", nil),
            ("> quoted", nil), ("> > deeper", nil), ("> - item", nil),
            ("- one\n- ", nil), ("> a\n> ", nil), ("2. ", nil), ("- [ ] ", nil),
            ("- one\n- two\nend", 5), ("- a\r\n- b", 3), ("- a\r\n- \r\nend", 7),
            ("```\n- a\n```", 7), ("```\n- a", nil), ("plain", nil), ("- one", 3),
        ]
        for (text, caret) in cases {
            let ns = text as NSString
            let at = caret ?? ns.length
            let core: (String, NSRange)
            if let edit = ListContinuation.edit(in: ns, caret: at) {
                core = (ns.replacingCharacters(in: edit.range, with: edit.replacement), NSRange(location: edit.caret, length: 0))
            } else {
                // No marker: the iPhone's text view types a plain "\n".
                core = (ns.replacingCharacters(in: NSRange(location: at, length: 0), with: "\n"), NSRange(location: at + 1, length: 0))
            }
            let mac = pressReturn(text, at: caret)
            XCTAssertEqual(mac.0, core.0, text.debugDescription)
            XCTAssertEqual(mac.1, core.1, text.debugDescription)
        }
    }

    /// The en dash, em dash, bullet and `| ` lines the Mac continued before
    /// MiaoYanCore took Return over still continue, and still end when empty.
    @MainActor
    func testReturnKeepsTheMacOnlyMarkers() {
        for marker in ["\u{2013}", "\u{2014}", "\u{2022}", "|"] {
            XCTAssertEqual(pressReturn("\(marker) a").0, "\(marker) a\n\(marker) ", marker)
            XCTAssertEqual(pressReturn("x\n\(marker) ").0, "x\n", marker)
            XCTAssertEqual(
                pressReturn("```\n\(marker) a\n```", at: 4 + ("\(marker) a" as NSString).length).0,
                "```\n\(marker) a\n\n```", marker)
        }
    }

    /// Tab and Shift-Tab over a selection reselect what they rewrote; the
    /// length was counted in Characters, so an emoji left the end unselected.
    @MainActor
    func testTabSelectionCoversTheWholeTextInUTF16() {
        let text = "- \u{1F600} a\n- b"
        let (editor, note) = makeEditor(text)
        editor.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        TextFormatter(textView: editor, note: note).tab()
        XCTAssertEqual(editor.string, "  - \u{1F600} a\n  - b")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: (editor.string as NSString).length))

        TextFormatter(textView: editor, note: note).unTab()
        XCTAssertEqual(editor.string, text)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: (text as NSString).length))
    }

    /// Tab renumbers an item to "1.", which is shorter from 10 up, but the
    /// caret moved by the whole indent, so at the end of "10. item" it landed
    /// at the start of the next line.
    @MainActor
    func testTabOnATwoDigitItemKeepsTheCaretOnItsLine() {
        for (text, caret, expected, expectedCaret) in [
            ("10. item\nnext", 8, "  1. item\nnext", 9),
            ("10. item", 8, "  1. item", 9),
            ("10. item", 0, "  1. item", 2),
            ("5. a", 4, "  1. a", 6),
        ] {
            let (editor, note) = makeEditor(text)
            editor.setSelectedRange(NSRange(location: caret, length: 0))
            TextFormatter(textView: editor, note: note).tab()
            XCTAssertEqual(editor.string, expected, text)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: expectedCaret, length: 0), "\(text) at \(caret)")
        }
    }

    // MARK: - Find and replace

    /// A shell-hosted editor in a scroll view, so the find bar has a container.
    @MainActor
    private func makeSearchEditor(_ text: String) -> (EditTextView, NSView) {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        let scrollView = NSScrollView(frame: container.bounds)
        let editor = EditTextView(frame: scrollView.bounds)
        editor.isShellHosted = true
        scrollView.documentView = editor
        container.addSubview(scrollView)
        editor.publishStorage(NSAttributedString(string: text), owner: nil)
        return (editor, container)
    }

    /// Replace when the replacement still matches the search: the new text was
    /// found again at the same place, so every Replace rewrote the same word
    /// (cat to cats grew "catss") and the later matches were never reached.
    @MainActor
    func testReplaceMovesPastAReplacementThatStillMatches() {
        let (editor, container) = makeSearchEditor("cat cat cat")
        editor.showSearchBar(prefilledText: "cat", mode: .replace)
        XCTAssertTrue(editor.isSearchBarVisible)
        editor.replaceNext(with: "cats")
        XCTAssertEqual(editor.string, "cats cat cat")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 5, length: 3))
        editor.replaceNext(with: "cats")
        editor.replaceNext(with: "cats")
        XCTAssertEqual(editor.string, "cats cats cats")

        let (caseEditor, caseContainer) = makeSearchEditor("iphone and iphone")
        caseEditor.showSearchBar(prefilledText: "iphone", mode: .replace)
        caseEditor.replaceNext(with: "iPhone")
        caseEditor.replaceNext(with: "iPhone")
        XCTAssertEqual(caseEditor.string, "iPhone and iPhone")
        withExtendedLifetime((container, caseContainer)) {}
    }

    @MainActor
    private func isHighlighted(_ editor: EditTextView, at index: Int) -> Bool {
        editor.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: index, effectiveRange: nil) != nil
    }

    /// The matches are searched again on the edit itself. A delayed refresh
    /// (tried 2026-11-11) left Find Next and Replace working on positions from
    /// before the edit, past the end of the text after a deletion.
    @MainActor
    func testAnEditRefreshesTheMatchesAtOnce() {
        let (editor, container) = makeSearchEditor("iphone x")
        editor.showSearchBar(prefilledText: "iphone")
        XCTAssertTrue(isHighlighted(editor, at: 0))
        editor.insertText(" iphone", replacementRange: NSRange(location: 8, length: 0))
        XCTAssertTrue(isHighlighted(editor, at: 9), "the edit refreshes the search")
        editor.insertText("", replacementRange: NSRange(location: 8, length: 7))
        editor.findNext()
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 6), "the only match left")
        withExtendedLifetime(container) {}
    }

    /// The highlights follow the text through an edit while the stored match
    /// ranges do not, so clearing only those ranges left part of a broken
    /// match highlighted.
    @MainActor
    func testAnEditInsideAMatchLeavesNoHighlightBehind() {
        let (editor, container) = makeSearchEditor("aa iphone bb")
        editor.showSearchBar(prefilledText: "iphone")
        editor.insertText("x", replacementRange: NSRange(location: 6, length: 0))
        XCTAssertEqual(editor.string, "aa iphxone bb")
        for index in 0..<(editor.string as NSString).length {
            XCTAssertFalse(isHighlighted(editor, at: index), "highlight left at \(index)")
        }
        withExtendedLifetime(container) {}
    }
}
