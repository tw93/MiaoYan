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

    /// Hovering `![](/files/clip.mov)` loaded the video as an image on the
    /// main thread, and again on every hover since a failure is not kept.
    /// Videos and linked files are not images to the hover preview; images,
    /// names with no extension, `data:` URIs and remote image endpoints are.
    func testTheHoverPreviewSkipsVideosAndFiles() {
        func found(_ text: String) -> Bool {
            ImageLinkParser.detectImageLink(in: text, at: 3) != nil
        }
        XCTAssertFalse(found("![](/files/clip.mov)"))
        XCTAssertFalse(found("![](/files/clip.MP4)"))
        XCTAssertFalse(found("<img src=\"/files/clip.m4v\">"))
        XCTAssertFalse(found("![](/files/Report-v2.pdf)"))
        XCTAssertFalse(found("![](/i/Layers.psd)"))
        XCTAssertFalse(found("![](https://example.com/talk.mp4)"))

        XCTAssertTrue(found("![](/i/shot.png)"))
        XCTAssertTrue(found("![](/i/IMG_1.HEIC \"title\")"))
        XCTAssertTrue(found("![](</i/a b.jpg>)"))
        XCTAssertTrue(found("<img src=\"/i/shot.webp\">"))
        XCTAssertTrue(found("![](/i/no-extension)"))
        XCTAssertTrue(found("![](https://example.com/avatar.php?u=1)"))
        XCTAssertTrue(found("![](https://example.com/a.png?raw=true)"))
        XCTAssertTrue(found("![](data:image/png;base64,iVBORw0KGgo=)"))
    }
}
