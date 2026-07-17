import XCTest

@testable import MiaoYan

final class HtmlToMarkdownTests: XCTestCase {

    // MARK: - Structure gate

    func testSpanSoupWithoutStructureReturnsNil() {
        let html = "<div><span style=\"color: red\">let</span> <span>x = 1</span></div>"
        XCTAssertNil(HtmlToMarkdown.convertIfStructured(html))
    }

    func testHeadingTriggersConversion() {
        XCTAssertNotNil(HtmlToMarkdown.convertIfStructured("<h2>Title</h2><p>Body</p>"))
    }

    func testUlWordInTextDoesNotTriggerConversion() {
        XCTAssertNil(HtmlToMarkdown.convertIfStructured("<p>an ultimate ulterior plan</p>"))
    }

    // MARK: - Blocks

    func testHeadingsAndParagraphs() {
        let markdown = HtmlToMarkdown.convert("<h1>One</h1><p>First</p><h3>Three</h3><p>Second</p>")
        XCTAssertEqual(markdown, "# One\n\nFirst\n\n### Three\n\nSecond")
    }

    func testUnorderedList() {
        let markdown = HtmlToMarkdown.convert("<ul><li>alpha</li><li>beta</li></ul>")
        XCTAssertEqual(markdown, "- alpha\n- beta")
    }

    func testOrderedListWithNestedList() {
        let markdown = HtmlToMarkdown.convert("<ol><li>first<ul><li>sub</li></ul></li><li>second</li></ol>")
        XCTAssertEqual(markdown, "1. first\n   - sub\n2. second")
    }

    func testBlockquote() {
        let markdown = HtmlToMarkdown.convert("<blockquote><p>quoted words</p></blockquote>")
        XCTAssertEqual(markdown, "> quoted words")
    }

    func testPreCodeWithLanguageClass() {
        let html = "<pre><code class=\"language-swift\">let a = 1\nlet b = 2</code></pre>"
        let markdown = HtmlToMarkdown.convert(html)
        XCTAssertEqual(markdown, "```swift\nlet a = 1\nlet b = 2\n```")
    }

    func testTableWithHeader() {
        let html = "<table><thead><tr><th>Name</th><th>Age</th></tr></thead><tbody><tr><td>Ann</td><td>3</td></tr></tbody></table>"
        let markdown = HtmlToMarkdown.convert(html)
        XCTAssertEqual(markdown, "| Name | Age |\n| --- | --- |\n| Ann | 3 |")
    }

    func testPipeInTableCellEscaped() {
        let html = "<table><tr><th>Expr</th></tr><tr><td>a | b</td></tr></table>"
        let markdown = HtmlToMarkdown.convert(html)
        XCTAssertTrue(markdown.contains("a \\| b"))
    }

    func testHorizontalRule() {
        let markdown = HtmlToMarkdown.convert("<p>above</p><hr><p>below</p>")
        XCTAssertEqual(markdown, "above\n\n---\n\nbelow")
    }

    // MARK: - Inline

    func testInlineFormatting() {
        let markdown = HtmlToMarkdown.convert("<p>mix <strong>bold</strong> and <em>italic</em> and <code>code</code> and <del>gone</del></p>")
        XCTAssertEqual(markdown, "mix **bold** and *italic* and `code` and ~~gone~~")
    }

    func testLink() {
        let markdown = HtmlToMarkdown.convert("<p>see <a href=\"https://example.com\">docs</a> here</p>")
        XCTAssertEqual(markdown, "see [docs](https://example.com) here")
    }

    func testAnchorLinkKeepsTextOnly() {
        let markdown = HtmlToMarkdown.convert("<p>jump <a href=\"#section\">below</a></p>")
        XCTAssertEqual(markdown, "jump below")
    }

    func testImage() {
        let markdown = HtmlToMarkdown.convert("<p><img src=\"https://example.com/a.png\" alt=\"pic\"></p>")
        XCTAssertEqual(markdown, "![pic](https://example.com/a.png)")
    }

    func testDataURIImageDropped() {
        let markdown = HtmlToMarkdown.convert("<p>before <img src=\"data:image/png;base64,AAAA\"> after</p>")
        XCTAssertEqual(markdown, "before after")
    }

    func testScriptAndStyleDropped() {
        let html = "<style>p { color: red }</style><script>alert(1)</script><p>kept</p><h1>k</h1>"
        let markdown = HtmlToMarkdown.convert(html)
        XCTAssertFalse(markdown.contains("alert"))
        XCTAssertFalse(markdown.contains("color"))
        XCTAssertTrue(markdown.contains("kept"))
    }

    func testWhitespaceCollapsedInParagraphs() {
        let markdown = HtmlToMarkdown.convert("<p>a\n   lot    of\n whitespace</p>")
        XCTAssertEqual(markdown, "a lot of whitespace")
    }

    func testEntitiesDecoded() {
        let markdown = HtmlToMarkdown.convert("<p>a &amp; b &lt; c</p>")
        XCTAssertEqual(markdown, "a & b < c")
    }

    func testFullDocumentWithHeadIgnored() {
        let html = "<html><head><title>t</title></head><body><h2>Hello</h2><p>World</p></body></html>"
        XCTAssertEqual(HtmlToMarkdown.convert(html), "## Hello\n\nWorld")
    }

    // MARK: - CJK regressions (tidy defaults to Latin-1 without a charset hint)

    func testChineseWithChromeMetaCharsetShorthand() {
        // Chrome writes <meta charset='utf-8'> which tidy ignores; CJK became mojibake.
        let html = "<meta charset='utf-8'><ul><li>第一项</li><li>第二项 <b>加粗</b></li></ul>"
        XCTAssertEqual(HtmlToMarkdown.convert(html), "- 第一项\n- 第二项 **加粗**")
    }

    func testChineseBareFragmentWithoutCharset() {
        // Bare fragments (Safari-style) dropped CJK characters entirely.
        let html = "<h1>中文标题</h1><p>正文内容</p>"
        XCTAssertEqual(HtmlToMarkdown.convert(html), "# 中文标题\n\n正文内容")
    }

    // MARK: - Structure regressions

    func testBlankLinesInsideCodeBlockPreserved() {
        let html = "<pre><code>def a():\n    pass\n\n\ndef b():\n    pass</code></pre>"
        let markdown = HtmlToMarkdown.convert(html)
        XCTAssertTrue(markdown.contains("pass\n\n\ndef b()"), "blank lines inside a fence must survive: \(markdown)")
    }

    func testTextAfterCodeBlockInListItemKeepsOrder() {
        let html = "<ul><li>before<pre><code>code</code></pre>after</li></ul>"
        XCTAssertEqual(HtmlToMarkdown.convert(html), "- before\n  ```\n  code\n  ```\n  after")
    }

    func testTableCellWithNestedListSpaceSeparated() {
        let html = "<table><tr><th>Opts</th></tr><tr><td><ul><li>alpha</li><li>beta</li></ul></td></tr></table>"
        XCTAssertTrue(HtmlToMarkdown.convert(html).contains("| alpha beta |"))
    }

    func testInlineCodeWithEdgeBacktickPadded() {
        let markdown = HtmlToMarkdown.convert("<p>tick <code>`x</code> here</p>")
        XCTAssertEqual(markdown, "tick `` `x `` here")
    }

    func testHeadingWithBrStaysOneLine() {
        XCTAssertEqual(HtmlToMarkdown.convert("<h1>part1<br>part2</h1>"), "# part1 part2")
    }
}
