import XCTest

@testable import MiaoYan

/// Preview checkboxes send the source line of their task item; the app has to
/// find that line again in the full note, frontmatter included.
final class CheckboxToggleTests: XCTestCase {

    private func marker(_ text: String, line: Int) -> String? {
        HandlerCheckbox.taskMarkerRange(in: text, bodyLine: line).map { (text as NSString).substring(with: $0) }
    }

    func testFrontmatterLinesAreAddedBack() {
        let text = "---\ntitle: x\n---\n- [ ] first\n- [x] second\n"
        XCTAssertEqual(marker(text, line: 1), " ")
        XCTAssertEqual(marker(text, line: 2), "x")
        let range = HandlerCheckbox.taskMarkerRange(in: text, bodyLine: 2)
        XCTAssertEqual(range.map { (text as NSString).lineRange(for: $0) }.map { (text as NSString).substring(with: $0) }, "- [x] second\n")
    }

    func testEveryListMarkerAndCRLFIsFound() {
        XCTAssertEqual(marker("* [ ] star", line: 1), " ")
        XCTAssertEqual(marker("+ [X] plus", line: 1), "X")
        XCTAssertEqual(marker("1. [ ] numbered", line: 1), " ")
        XCTAssertEqual(marker("intro\r\n- [ ] crlf", line: 2), " ")
    }

    /// Text pasted from the web can carry U+2028; cmark does not end a line
    /// there, so the preview's line 2 is the task below it.
    func testUnicodeLineSeparatorsDoNotShiftTheLine() {
        XCTAssertEqual(marker("intro\u{2028}still intro\n- [x] task", line: 2), "x")
        XCTAssertEqual(marker("a\u{2029}b\u{0085}c\n- [ ] task", line: 2), " ")
    }

    func testALineThatIsNotATaskIsLeftAlone() {
        XCTAssertNil(marker("plain line\n- [ ] task", line: 1))
        XCTAssertNil(marker("- [ ] task", line: 5), "a line past the end finds nothing")
    }

    func testTaskItemsCarryTheirSourceLine() throws {
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: "```\n- [ ] code\n```\n\n* [ ] real", useGithubLineBreak: false))
        XCTAssertTrue(html.contains(#"<li data-sourcepos="5:"#), "the rendered task item names line 5")
    }

    /// An item that is only `[ ]` or `[x]` is drawn as a checkbox, as in
    /// Obsidian; `[]` without the space and items with text keep the usual rules.
    func testEmptyTaskItemsRenderAsCheckboxes() throws {
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: "- [ ]\n- [x]\n- []\n- [ ] milk", useGithubLineBreak: false))
        XCTAssertTrue(html.contains(#"<li data-sourcepos="1:1-1:5"><input type="checkbox" disabled="" /></li>"#), html)
        XCTAssertTrue(html.contains(#"<li data-sourcepos="2:1-2:5"><input type="checkbox" checked="" disabled="" /></li>"#), html)
        XCTAssertTrue(html.contains(#">[]</li>"#), "no space inside the brackets stays text")
        XCTAssertTrue(html.contains(#"<input type="checkbox" disabled="" /> milk</li>"#))
        XCTAssertEqual(HandlerCheckbox.taskMarkerRange(in: "- [ ]\n- [x]", bodyLine: 2).map { ("- [ ]\n- [x]" as NSString).substring(with: $0) }, "x")
    }

    func testEmptyTaskItemInALooseListRendersAsCheckbox() throws {
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: "- [ ]\n\n- [x]\n", useGithubLineBreak: false))
        XCTAssertFalse(html.contains("[ ]"), html)
        XCTAssertFalse(html.contains("[x]"), html)
    }
}
