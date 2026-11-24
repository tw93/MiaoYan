import Carbon.HIToolbox
import XCTest

@testable import MiaoYan

/// Paths that run on every keystroke or every preview update, kept cheap
/// without changing what they produce.
final class EditorHotPathTests: XCTestCase {
    private func emojiMatches(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: EmojiPattern, options: [.allowCommentsAndWhitespace]) else {
            XCTFail("EmojiPattern must compile")
            return []
        }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// Keycaps used to sit inside the character class, which put every ASCII
    /// digit in it: each number in a note was an emoji match, and each match
    /// rescanned the document for fenced code.
    func testEmojiPatternSkipsDigitsButKeepsKeycapsAndEmoji() {
        XCTAssertEqual(emojiMatches("2026-10-26 v4.6.0 #543 0123456789"), [])
        XCTAssertEqual(emojiMatches("第 1️⃣ 步"), ["1\u{FE0F}\u{20E3}"])
        XCTAssertEqual(emojiMatches("0️⃣9️⃣"), ["0\u{FE0F}\u{20E3}", "9\u{FE0F}\u{20E3}"])
        XCTAssertEqual(emojiMatches("ok 😀 🚀"), ["😀", "🚀"])
        // A heart with its presentation selector still matches both scalars.
        XCTAssertEqual(emojiMatches("❤\u{FE0F}").joined(), "❤\u{FE0F}")
    }

    @MainActor
    func testFencedCodeRangesMatchTheOneAtATimeLookup() {
        let text = "intro 😀\n```swift\nlet a = \"😀\"\n```\nafter 🚀\n```\nplain\n```\n"
        let storage = NSMutableAttributedString(string: text)
        let ranges = NotesTextProcessor.fencedCodeBlockRanges(in: storage)
        XCTAssertEqual(ranges.count, 2)

        let regex = try? NSRegularExpression(pattern: EmojiPattern, options: [.allowCommentsAndWhitespace])
        let emoji = regex?.matches(in: text, range: NSRange(location: 0, length: storage.length)).map(\.range) ?? []
        XCTAssertEqual(emoji.count, 3)
        for range in emoji {
            let single = NotesTextProcessor.getFencedCodeBlockRange(paragraphRange: range, string: storage)
            let batched = ranges.first { $0.intersection(range) != nil }
            XCTAssertEqual(single, batched)
        }
        XCTAssertEqual(emoji.filter { range in ranges.contains { $0.intersection(range) != nil } }.count, 1)
    }

    /// The preview turns `[[note]]` into a link everywhere but code. Each
    /// link used to rescan the note from the top for fenced blocks, on every
    /// preview update; the blocks are found once now, with the same result.
    @MainActor
    func testWikilinksSkipFencedCodeWithOneScan() throws {
        let text = "See [[Alpha]].\n\n```\n[[Inside]]\n```\n\nAnd `[[Span]]` and [[Beta Note]].\n"
        let converted = NotesTextProcessor.convertAppLinks(in: NSMutableAttributedString(string: text)).string
        XCTAssertEqual(
            converted,
            "See [Alpha](miaoyan://goto/Alpha).\n\n```\n[[Inside]]\n```\n\nAnd `[[Span]]` and [Beta Note](miaoyan://goto/Beta%20Note).\n")

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Helpers/NotesTextProcessor.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "public static func convertAppLinks"))
        let end = try XCTUnwrap(source.range(of: "public static func highlight(note:", range: start.upperBound..<source.endIndex))
        XCTAssertFalse(source[start.lowerBound..<end.lowerBound].contains("getFencedCodeBlockRange("), "no per-link rescan")
    }

    /// Typing hands plain text to `save(content:)`, which skips the unload
    /// copies; content with a checkbox attachment must still be unloaded.
    @MainActor
    func testSaveContentUnloadsOnlyWhenThereAreAttachments() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanHotPath-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let project = Project(url: dir, label: "test", isRoot: true)
        let note = Note(url: dir.appendingPathComponent("hot.md"), with: project)

        note.save(content: NSMutableAttributedString(string: "plain 中文 text"))
        XCTAssertEqual(note.content.string, "plain 中文 text")

        let withAttachment = NSMutableAttributedString(attributedString: NSAttributedString(attachment: NSTextAttachment()))
        XCTAssertTrue(withAttachment.hasAttachmentAttribute)
        XCTAssertFalse(NSAttributedString(string: "plain").hasAttachmentAttribute)
        _ = note.flushPendingSave(globalStorage: false)
    }

    /// A draw restyles the list cell only when something it is styled from
    /// changed; a redraw of an unchanged cell used to rebuild both labels'
    /// attributed strings every time.
    @MainActor
    func testNoteCellDrawRestylesOnlyWhenItsStateChanges() {
        let cell = NoteCellView(frame: NSRect(x: 0, y: 0, width: 240, height: 60))
        cell.name = NSTextField(labelWithString: "Title")
        cell.date = NSTextField(labelWithString: "Today")
        cell.pin = NSImageView()
        cell.addSubview(cell.name)
        cell.addSubview(cell.date)
        cell.addSubview(cell.pin)

        for _ in 0..<20 { cell.draw(cell.bounds) }
        XCTAssertEqual(cell.drawRestyleCount, 1)

        let styled = cell.name.attributedStringValue
        XCTAssertNotNil(styled.attribute(.kern, at: 0, effectiveRange: nil))
        XCTAssertNotNil(styled.attribute(.foregroundColor, at: 0, effectiveRange: nil))

        cell.name.stringValue = "Another title"
        for _ in 0..<5 { cell.draw(cell.bounds) }
        XCTAssertEqual(cell.drawRestyleCount, 2)
        XCTAssertNotNil(cell.name.attributedStringValue.attribute(.kern, at: 0, effectiveRange: nil))

        cell.appearance = NSAppearance(named: .darkAqua)
        for _ in 0..<5 { cell.draw(cell.bounds) }
        XCTAssertEqual(cell.drawRestyleCount, 3)

        cell.backgroundStyle = .emphasized
        for _ in 0..<5 { cell.draw(cell.bounds) }
        XCTAssertEqual(cell.drawRestyleCount, 4)

        // The date's binding sets the same text again, plain: the spacing
        // comes back on the next draw (2026-11-22).
        cell.date.stringValue = "Today"
        for _ in 0..<5 { cell.draw(cell.bounds) }
        XCTAssertEqual(cell.drawRestyleCount, 5)
        XCTAssertNotNil(cell.date.attributedStringValue.attribute(.kern, at: 0, effectiveRange: nil))
    }

    /// The note list resolves its two fonts once per face and size, not on
    /// every redraw; a size change rebuilds them.
    @MainActor
    func testNoteListFontsAreCachedUntilTheSizeChanges() {
        let first = NoteCellView.listFonts()
        XCTAssertEqual(NoteCellView.listFonts(), first)
        XCTAssertEqual(first.name, UserDefaultsManagement.nameFont)
        XCTAssertEqual(first.date, UserDefaultsManagement.dateFont)

        let saved = UserDefaultsManagement.nameFontSize
        defer { UserDefaultsManagement.nameFontSize = saved }
        UserDefaultsManagement.nameFontSize = saved + 3
        XCTAssertEqual(NoteCellView.listFonts().name.pointSize, CGFloat(saved + 3))
    }

    /// A skipped KaTeX or Mermaid pass schedules one more update for just past
    /// the throttle window, so the last edit never stays unrendered.
    func testThrottledRendererUpdateSchedulesACatchUp() {
        let interval = MPreviewView.rendererInterval
        let skipped = MPreviewView.specialRendererPlan(needsRenderers: true, preserveScroll: true, now: 100.3, lastInitialization: 100)
        XCTAssertFalse(skipped.initialize)
        let delay = try? XCTUnwrap(skipped.catchUpAfter)
        XCTAssertGreaterThan(100.3 + (delay ?? 0) - 100, interval)

        let due = MPreviewView.specialRendererPlan(needsRenderers: true, preserveScroll: true, now: 101, lastInitialization: 100)
        XCTAssertTrue(due.initialize)
        XCTAssertNil(due.catchUpAfter)

        let fresh = MPreviewView.specialRendererPlan(needsRenderers: true, preserveScroll: false, now: 100.1, lastInitialization: 100)
        XCTAssertTrue(fresh.initialize)
        XCTAssertNil(fresh.catchUpAfter)

        let none = MPreviewView.specialRendererPlan(needsRenderers: false, preserveScroll: true, now: 100.1, lastInitialization: 100)
        XCTAssertFalse(none.initialize)
        XCTAssertNil(none.catchUpAfter)
    }

    /// Return marked links over the whole note while every other key kept to
    /// its paragraph. It now marks the two lines around the caret: the URL in
    /// the line it ended is a link, one far above is not touched.
    @MainActor
    func testReturnMarksLinksInTheLinesAroundTheCaretOnly() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanHotPath-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let body = "https://far.example\n\nsee https://near.example"
        let url = dir.appendingPathComponent("return.md")
        try body.write(to: url, atomically: true, encoding: .utf8)
        let note = Note(url: url, with: Project(url: dir, label: "test", isRoot: true))
        note.content = NSMutableAttributedString(string: body)
        let previousNote = EditTextView.note
        defer { EditTextView.note = previousNote }
        EditTextView.note = note
        let editor = EditTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        editor.isShellHosted = true
        editor.publishStorage(NSAttributedString(string: body), owner: note)
        editor.setSelectedRange(NSRange(location: (body as NSString).length, length: 0))

        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: UInt16(kVK_Return)))
        editor.keyDown(with: event)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let storage = try XCTUnwrap(editor.textStorage)
        XCTAssertEqual(storage.string, body + "\n")
        let near = (body as NSString).range(of: "https://near").location
        XCTAssertNotNil(storage.attribute(.link, at: near, effectiveRange: nil), "the line Return ended")
        XCTAssertNil(storage.attribute(.link, at: 0, effectiveRange: nil), "a line far from the caret")
    }

    // MARK: - Large notes

    /// The chapters of `scripts/ui_scripts/gen_bench_library.py`: prose,
    /// lists, tasks, a table, a quote and a fenced block, each about 600
    /// characters, so 1,700 of them make a note the size of the bench's
    /// `Large`.
    private static func chapters(_ count: Int) -> String {
        let prose =
            "Writing in Markdown keeps the text plain and the structure visible, so a note opened years later still reads the same. "
            + "用 Markdown 写东西\u{FF0C}文字保持纯文本\u{FF0C}结构一眼就能看到\u{FF0C}过了很多年再打开也还是一样。"
        return (1...count).map { n in
            [
                "## Chapter \(n)", "", prose + " (part \(n))", "",
                "- point one of chapter \(n) with **bold** and *italic* words",
                "- point two with `inline code` and a [link](https://miaoyan.app)",
                "  - a nested point", "- [ ] task \(n)", "- [x] done \(n)", "",
                "| Item | Count | Note |", "| ---- | ----: | ---- |", "| apples | \(n) | fresh |", "",
                "> " + String(prose.prefix(120)), "",
                "```swift", "let chapter = \(n)", "```", "",
            ].joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private static func milliseconds(_ runs: Int, _ body: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<runs { body() }
        return (CFAbsoluteTimeGetCurrent() - start) * 1000 / Double(runs)
    }

    /// The hanging indent asked the fence scan on every keystroke, and since
    /// 4a2ef16c that scan reads every line from the top of the note whenever
    /// a fence sits above the edit: typing prose near the end of a note of a
    /// million characters with a fence on line 1 rescanned all of it. Only a
    /// list item needs the scan now, and a list line inside a fence still
    /// gets no indent.
    @MainActor
    func testTypingProseBelowAFenceDoesNotRescanTheNote() {
        let tail = "\n\n- an item after the last fence\n\n```\n- a dash inside a fence\n```\n\nThe last words of the note."
        let storage = NSTextStorage(string: "```\nfence on line 1\n```\n\n" + Self.chapters(1700) + tail)
        let text = storage.mutableString
        let prose = text.range(of: "The last words")
        XCTAssertGreaterThan(text.length, 1_000_000)

        let perKey = Self.milliseconds(20) { ListHangingIndent.apply(in: NSRange(location: prose.location + 4, length: 1), of: storage) }
        print("ListHangingIndent, prose at the end of a 1M-character note under a fence: \(String(format: "%.3f", perKey)) ms per keystroke")
        XCTAssertLessThan(perKey, 1, "a keystroke in prose does not scan the note for fences")

        let tailRange = text.range(of: tail)
        ListHangingIndent.apply(in: tailRange, of: storage)
        func indent(at needle: String) -> CGFloat {
            let at = text.range(of: needle, options: .backwards).location
            return (storage.attribute(.paragraphStyle, at: at, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0
        }
        XCTAssertGreaterThan(indent(at: "- an item after the last fence"), 0, "a list item below the fences hangs")
        XCTAssertEqual(indent(at: "- a dash inside a fence"), 0, "a list line inside a fence does not")
    }
}
