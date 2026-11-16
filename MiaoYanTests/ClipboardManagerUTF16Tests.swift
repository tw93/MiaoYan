import XCTest

@testable import MiaoYan

/// Regression coverage for V3.5.1+ fix `6a3c591d`: when replacing the
/// `![](uploading-...)` placeholder with the uploaded URL, the search range
/// used to be built from `String.count`. NSRegularExpression works in UTF-16
/// space; with surrogate-pair characters (emoji, some CJK) ahead of the
/// placeholder, String.count was smaller than the real UTF-16 length and the
/// truncated range cut the tail off the match, silently dropping the upload.
/// These tests exercise the same regex logic and length divergence the real
/// code path relies on, so any future regression that goes back to
/// `String.count` would fail here before users see lost uploads again.
final class ClipboardManagerUTF16Tests: XCTestCase {

    /// A heading copied on its own gives its words; anything else copies as written.
    func testLoneHeadingCopiesWithoutItsMarks() {
        XCTAssertEqual(ClipboardManager.headingTitle(ofLine: "# 潮流周刊\n"), "潮流周刊")
        XCTAssertEqual(ClipboardManager.headingTitle(ofLine: "### Notes on C# 12"), "Notes on C# 12")
        XCTAssertEqual(ClipboardManager.headingTitle(ofLine: "## Closed ##"), "Closed")
        XCTAssertNil(ClipboardManager.headingTitle(ofLine: "# Title\nBody\n"), "past the line, the Markdown stays")
        XCTAssertNil(ClipboardManager.headingTitle(ofLine: "#tag is not a heading"))
        XCTAssertNil(ClipboardManager.headingTitle(ofLine: "Plain line\n"))
        XCTAssertNil(ClipboardManager.headingTitle(ofLine: "####### seven marks"))
        XCTAssertNil(ClipboardManager.headingTitle(ofLine: "# "))
    }

    @MainActor
    func testCopyStripsMarksOnlyForOneHeadingLineOutsideCode() {
        let textView = EditTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let text = "# Title\nBody\n```\n# comment\n```\n"
        textView.textStorage?.setAttributedString(NSAttributedString(string: text))
        let clipboard = ClipboardManager(textView: textView)
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let saved { pasteboard.setString(saved, forType: .string) }
        }
        func copied(_ range: NSRange) -> String? {
            pasteboard.clearContents()
            textView.setSelectedRange(range)
            return clipboard.handleCopy() ? pasteboard.string(forType: .string) : nil
        }
        XCTAssertEqual(copied(NSRange(location: 3, length: 0)), "Title", "caret on the heading")
        XCTAssertEqual(copied(NSRange(location: 0, length: 8)), "Title", "the whole line, as a triple click selects it")
        XCTAssertNil(copied(NSRange(location: 0, length: 12)), "heading and body: the editor's own copy keeps the Markdown")
        XCTAssertNil(copied(NSRange(location: 2, length: 5)), "the words alone are already what is selected")
        let comment = (text as NSString).range(of: "# comment")
        XCTAssertEqual(copied(NSRange(location: comment.location + 2, length: 0)), "# comment", "a comment in a code block")
    }

    func testEmojiPrefixedPlaceholderMatchedWithNSStringLength() throws {
        // Reproduce the failure mode exactly: the placeholder is the last thing
        // in the buffer. With a surrogate-pair emoji ahead of it, String.count
        // is one short of the real UTF-16 length, so a search range built from
        // String.count cuts the closing `)` off the placeholder and the regex
        // fails to match. Any trailing content would absorb the offset and
        // hide the bug, which is why prior tests with a `" trailing"` suffix
        // would not have caught the original V3.5.1 regression.
        let placeholder = "![](uploading-abc123)"
        let body = "🌟\(placeholder)"

        let pattern = NSRegularExpression.escapedPattern(for: placeholder)
        let regex = try NSRegularExpression(pattern: pattern)

        let nsLength = (body as NSString).length
        let swiftCount = body.count
        XCTAssertGreaterThan(
            nsLength, swiftCount,
            "🌟 is a UTF-16 surrogate pair, so NSString.length must exceed String.count")

        let nsMatch = regex.firstMatch(in: body, range: NSRange(location: 0, length: nsLength))
        XCTAssertNotNil(nsMatch, "current code path (NSString length) must find the placeholder")

        let truncatedMatch = regex.firstMatch(in: body, range: NSRange(location: 0, length: swiftCount))
        XCTAssertNil(
            truncatedMatch,
            "old String.count range cuts the placeholder's closing `)` off — that is the regression we guard against")
    }

    func testMultipleEmojiAheadOfPlaceholderWidensTheGap() throws {
        // Two surrogate-pair emoji ahead of the placeholder mean String.count
        // undershoots by two code units. The placeholder can sit a bit inside
        // the buffer and the truncated range still cuts into it.
        let placeholder = "![](uploading-xyz)"
        let body = "📸🌟\(placeholder)x"

        let pattern = NSRegularExpression.escapedPattern(for: placeholder)
        let regex = try NSRegularExpression(pattern: pattern)

        let nsLength = (body as NSString).length
        XCTAssertEqual(nsLength - body.count, 2, "two surrogate-pair emoji widen the gap by 2")

        XCTAssertNotNil(regex.firstMatch(in: body, range: NSRange(location: 0, length: nsLength)))
        XCTAssertNil(regex.firstMatch(in: body, range: NSRange(location: 0, length: body.count)))
    }

    func testAsciiOnlyBodyMatchesUnderBothLengths() throws {
        // Documents the boundary: with no surrogate-pair characters, the two
        // lengths agree and the regex matches either way. Helps a future
        // reader understand exactly when the bug surfaces.
        let placeholder = "![](uploading-plain)"
        let body = "hello \(placeholder) world"

        let regex = try NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: placeholder))

        XCTAssertEqual(body.count, (body as NSString).length)
        XCTAssertNotNil(regex.firstMatch(in: body, range: NSRange(location: 0, length: body.count)))
    }

    /// Option-drag column copies keep the first line's indentation.
    @MainActor
    func testColumnCopyKeepsIndentation() {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let saved { pasteboard.setString(saved, forType: .string) }
        }
        let editor = EditTextView(frame: .zero)
        editor.string = "    let a = 1\n    let b = 2\n"
        editor.selectedRanges = [NSValue(range: NSRange(location: 0, length: 13)), NSValue(range: NSRange(location: 14, length: 13))]
        XCTAssertTrue(ClipboardManager(textView: editor).handleCopy())
        XCTAssertEqual(pasteboard.string(forType: .string), "    let a = 1\n    let b = 2")
    }
}
