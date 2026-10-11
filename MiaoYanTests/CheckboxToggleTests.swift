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

    func testALineThatIsNotATaskIsLeftAlone() {
        XCTAssertNil(marker("plain line\n- [ ] task", line: 1))
        XCTAssertNil(marker("- [ ] task", line: 5), "a line past the end finds nothing")
    }

    func testTaskItemsCarryTheirSourceLine() throws {
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: "```\n- [ ] code\n```\n\n* [ ] real", useGithubLineBreak: false))
        XCTAssertTrue(html.contains(#"<li data-sourcepos="5:"#), "the rendered task item names line 5")
    }
}
