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

        let checkbox = NSMutableAttributedString(attributedString: NSAttributedString(attachment: NSTextAttachment()))
        checkbox.addAttribute(.todo, value: 1, range: NSRange(location: 0, length: 1))
        checkbox.append(NSAttributedString(string: " buy milk"))
        XCTAssertTrue(checkbox.hasAttachmentAttribute)
        XCTAssertFalse(NSAttributedString(string: "plain").hasAttachmentAttribute)
        note.save(content: checkbox)
        XCTAssertEqual(note.content.string, "- [x] buy milk")
        _ = note.flushPendingSave(globalStorage: false)
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
}
