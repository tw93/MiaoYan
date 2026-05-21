import XCTest

@testable import MiaoYan

final class ImageLinkParserTests: XCTestCase {

    func testDetectMarkdownImageAtCaret() {
        let text = "before ![alt text](path/to/img.png) after"
        let caret = text.distance(from: text.startIndex, to: text.range(of: "img.png")!.lowerBound)

        let info = ImageLinkParser.detectImageLink(in: text, at: caret)

        XCTAssertNotNil(info)
        XCTAssertEqual(info?.type, .markdown)
        XCTAssertEqual(info?.src, "path/to/img.png")
        XCTAssertEqual(info?.alt, "alt text")
    }

    func testDetectMarkdownImageWithEmptyAlt() {
        let text = "![](image.jpg)"
        let info = ImageLinkParser.detectImageLink(in: text, at: 2)

        XCTAssertEqual(info?.type, .markdown)
        XCTAssertEqual(info?.src, "image.jpg")
        XCTAssertEqual(info?.alt, "")
    }

    func testDetectHtmlImage() {
        let text = "<p><img src=\"foo.png\" alt=\"hello\" /></p>"
        guard let imgRange = text.range(of: "<img") else { return XCTFail("range") }
        let caret = text.distance(from: text.startIndex, to: imgRange.lowerBound) + 2

        let info = ImageLinkParser.detectImageLink(in: text, at: caret)

        XCTAssertEqual(info?.type, .html)
        XCTAssertEqual(info?.src, "foo.png")
        XCTAssertEqual(info?.alt, "hello")
    }

    func testDetectHtmlImageSingleQuotedSrcCaseInsensitive() {
        let text = "<IMG SRC='bar.gif'>"
        let info = ImageLinkParser.detectImageLink(in: text, at: 5)

        XCTAssertEqual(info?.type, .html)
        XCTAssertEqual(info?.src, "bar.gif")
        XCTAssertEqual(info?.alt, "")
    }

    func testNoMatchOutsideImageBounds() {
        let text = "before ![alt](img.png) after"
        let outsideCaret = text.count - 2  // inside "after"

        XCTAssertNil(ImageLinkParser.detectImageLink(in: text, at: outsideCaret))
    }

    func testGetAllImageLinksCollectsBothFlavors() {
        let text = "![one](a.png) and <img src=\"b.png\" alt=\"two\" /> and ![](c.png)"

        let links = ImageLinkParser.getAllImageLinks(in: text)
        let sources = Set(links.map(\.src))

        XCTAssertEqual(sources, Set(["a.png", "b.png", "c.png"]))
    }

    func testGetAllImageLinksReturnsEmptyForPlainText() {
        XCTAssertTrue(ImageLinkParser.getAllImageLinks(in: "just a plain paragraph").isEmpty)
    }

    func testRegexLiteralsCompile() {
        // Tripwire for the precondition path in ImageLinkParser. If anyone
        // breaks the regex literal in a future edit, this test fails before
        // production code crashes.
        XCTAssertNotNil(ImageLinkParser.markdownImageRegex)
        XCTAssertNotNil(ImageLinkParser.htmlImageRegex)
    }
}
