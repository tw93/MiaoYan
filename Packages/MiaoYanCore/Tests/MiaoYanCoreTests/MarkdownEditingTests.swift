import XCTest

@testable import MiaoYanCore

final class MarkdownEditingTests: XCTestCase {
    // MARK: Source lines

    func testLineRangesEndOnlyAtCmarkLineEndings() {
        let text = "a\u{2028}b\r\nsecond\rthird\nlast" as NSString
        XCTAssertEqual(SourceLines.range(ofLine: 0, in: text).map(text.substring(with:)), "a\u{2028}b")
        XCTAssertEqual(SourceLines.range(ofLine: 1, in: text).map(text.substring(with:)), "second")
        XCTAssertEqual(SourceLines.range(ofLine: 2, in: text).map(text.substring(with:)), "third")
        XCTAssertEqual(SourceLines.range(ofLine: 3, in: text).map(text.substring(with:)), "last")
        XCTAssertNil(SourceLines.range(ofLine: 4, in: text))
    }

    func testLineAtOffsetMatchesLineRanges() {
        let text = "one\r\ntwo\n\nfour" as NSString
        for index in 0..<4 {
            let range = SourceLines.range(ofLine: index, in: text)!
            XCTAssertEqual(SourceLines.line(atOffset: range.location, in: text), index)
            XCTAssertEqual(SourceLines.line(atOffset: NSMaxRange(range), in: text), index)
        }
        XCTAssertEqual(SourceLines.line(atOffset: 999, in: text), 3)
    }

    // MARK: Task marker

    func testToggleCountsBodyLinesAfterFrontmatter() {
        let text = "---\ntitle: a\n---\nintro\n- [ ] first\n- [x] second\n"
        XCTAssertEqual(TaskMarker.toggled(text, bodyLine: 2), "---\ntitle: a\n---\nintro\n- [x] first\n- [x] second\n")
        XCTAssertEqual(TaskMarker.toggled(text, bodyLine: 3), "---\ntitle: a\n---\nintro\n- [ ] first\n- [ ] second\n")
        XCTAssertNil(TaskMarker.toggled(text, bodyLine: 1))
        XCTAssertNil(TaskMarker.toggled(text, bodyLine: 9))
    }

    func testToggleReachesNestedAndQuotedItems() {
        XCTAssertEqual(TaskMarker.toggled("- a\n  1. [ ] b", bodyLine: 2), "- a\n  1. [x] b")
        XCTAssertEqual(TaskMarker.toggled("> - [X] q", bodyLine: 1), "> - [ ] q")
    }

    // MARK: List continuation

    private func pressReturn(_ text: String, at caret: Int? = nil) -> (String, Int)? {
        let ns = text as NSString
        guard let edit = ListContinuation.edit(in: ns, caret: caret ?? ns.length) else { return nil }
        return (ns.replacingCharacters(in: edit.range, with: edit.replacement), edit.caret)
    }

    func testReturnContinuesBulletsNumbersAndTasks() {
        XCTAssertEqual(pressReturn("- one")?.0, "- one\n- ")
        XCTAssertEqual(pressReturn("* one")?.0, "* one\n* ")
        XCTAssertEqual(pressReturn("9. nine")?.0, "9. nine\n10. ")
        XCTAssertEqual(pressReturn("1) one")?.0, "1) one\n2) ")
        XCTAssertEqual(pressReturn("- [x] done")?.0, "- [x] done\n- [ ] ")
        XCTAssertEqual(pressReturn("  - nested")?.0, "  - nested\n  - ")
        XCTAssertEqual(pressReturn("> - quoted")?.0, "> - quoted\n> - ")
        XCTAssertEqual(pressReturn("- 中文条目")?.1, ("- 中文条目\n- " as NSString).length)
    }

    func testReturnOnAnEmptyItemEndsTheList() {
        XCTAssertEqual(pressReturn("- one\n- ")?.0, "- one\n")
        XCTAssertEqual(pressReturn("- one\n- ")?.1, 6)
        XCTAssertEqual(pressReturn("- [ ] ")?.0, "")
        XCTAssertEqual(pressReturn("- [ ]")?.0, "")
        XCTAssertEqual(pressReturn("2. ")?.0, "")
    }

    func testReturnElsewhereIsAPlainNewline() {
        XCTAssertNil(pressReturn("plain text"))
        XCTAssertNil(pressReturn("- one", at: 3))
        XCTAssertNil(pressReturn("-not a list"))
        XCTAssertNil(pressReturn("**bold** line"))
        XCTAssertNil(pressReturn("---"))
        XCTAssertNil(pressReturn("- one\nplain"))
    }

    func testReturnOnAMiddleLineContinuesThatLine() {
        let text = "- one\n- two\nend"
        let caret = ("- one" as NSString).length
        XCTAssertEqual(pressReturn(text, at: caret)?.0, "- one\n- \n- two\nend")
    }

    func testReturnWorksOnCRLFNotes() {
        XCTAssertEqual(pressReturn("- one\r\n- two", at: 5)?.0, "- one\n- \r\n- two")
    }
}
