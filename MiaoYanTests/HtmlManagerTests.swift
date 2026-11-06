import ImageIO
import JavaScriptCore
import WebKit
import XCTest

@testable import MiaoYan

/// Serves `RemoteImageProbe`'s requests from memory and records the range
/// each one asked for.
final class ImageProbeStub: URLProtocol {
    private struct Response {
        let status: Int
        let body: Data
        var failuresLeft = 0
        var hangs = false
        var delay: TimeInterval = 0
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: Response] = [:]
    nonisolated(unsafe) private static var ranges: [String: String] = [:]
    nonisolated(unsafe) private static var counts: [String: Int] = [:]
    nonisolated(unsafe) private static var order: [String] = []

    /// Where `url` came in the order of all requests served so far.
    static func position(of url: String) -> Int? {
        lock.withLock { order.firstIndex(of: url) }
    }

    /// `failing` first requests time out before the response is served.
    static func serve(_ url: String, status: Int, body: Data, failing: Int = 0, hangs: Bool = false, delay: TimeInterval = 0) {
        lock.withLock { responses[url] = Response(status: status, body: body, failuresLeft: failing, hangs: hangs, delay: delay) }
    }

    static func range(for url: String) -> String? {
        lock.withLock { ranges[url] }
    }

    static func requests(for url: String) -> Int {
        lock.withLock { counts[url] ?? 0 }
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let key = url.absoluteString
        let (response, fails) = Self.lock.withLock { () -> (Response?, Bool) in
            Self.ranges[key] = request.value(forHTTPHeaderField: "Range")
            Self.counts[key, default: 0] += 1
            Self.order.append(key)
            guard var response = Self.responses[key] else { return (nil, false) }
            if response.failuresLeft > 0 {
                response.failuresLeft -= 1
                Self.responses[key] = response
                return (response, true)
            }
            return (response, false)
        }
        if fails {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        if response?.hangs == true { return }
        let finish = { [self] in
            let status = response?.status ?? 404
            let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
            if let http { client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed) }
            if let body = response?.body, !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
            client?.urlProtocolDidFinishLoading(self)
        }
        if let delay = response?.delay, delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: finish)
        } else {
            finish()
        }
    }

    override func stopLoading() {}
}

private let nestedUnderbraceFormula =
    #"$$"# + "\n"
    + #"r_{\text{emb}} = \underbrace{\left( \frac{|\mathcal{S}^+ \cap \text{top}_G(\mathcal{S}^+ \cup \mathcal{S}^-)|}{G} \right)}_{\text{Ranking}} \times "#
    + #"\underbrace{\left( \text{avg}(\mathcal{S}^+) - \text{avg}(\mathcal{S}^-) \right)}_{\text{Similarity Gap}}"#
    + "\n" + #"$$"#

final class HtmlManagerTests: XCTestCase {
    func testPreviewCurrencyGuardPreservesNumericMath() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Resources/DownView.bundle/js/common.js"), encoding: .utf8)
        let declaration = try XCTUnwrap(
            source.components(separatedBy: .newlines).first {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("const currencyRegex = ")
            })
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(declaration)
        for formula in ["$0$", "$1$", "$0.25$", "$100$", "$2(k-2)$"] {
            context.setObject(formula, forKeyedSubscript: "sample" as NSString)
            XCTAssertFalse(try XCTUnwrap(context.evaluateScript("currencyRegex.test(sample)")).toBool(), formula)
        }
        for price in ["$100", "$0.25 per item", "$100, today"] {
            context.setObject(price, forKeyedSubscript: "sample" as NSString)
            XCTAssertTrue(try XCTUnwrap(context.evaluateScript("currencyRegex.test(sample)")).toBool(), price)
        }
        XCTAssertNil(context.exception)
    }

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiaoYan PPT Tests \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    func testPPTLocalImageUsesEncodedFileURL() throws {
        let imageURL =
            tempDirectory
            .appendingPathComponent("i", isDirectory: true)
            .appendingPathComponent("CleanShot image.png")
        try FileManager.default.createDirectory(
            at: imageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0]).write(to: imageURL)

        let markdown = "![](/i/CleanShot image.png)"
        let processed = HtmlManager.processImagesInMarkdown(markdown, imagesStorage: tempDirectory)

        XCTAssertEqual(processed, "![](\(imageURL.absoluteString))")
    }

    func testNestedUnderbraceMathSurvivesPreviewMarkdownParsing() throws {
        for useGithubLineBreak in [false, true] {
            let html = try XCTUnwrap(
                renderMarkdownHTML(
                    markdown: nestedUnderbraceFormula,
                    useGithubLineBreak: useGithubLineBreak
                )
            )

            XCTAssertTrue(html.contains(#"\text{top}_G"#))
            XCTAssertTrue(html.contains(#"}_{\text{Ranking}}"#))
            XCTAssertFalse(
                html.contains("<em>"),
                "Markdown emphasis must not split a math delimiter range into separate DOM nodes")
        }
    }

    func testMathProtectionCoversAllPreviewDelimiters() throws {
        let markdown = #"""
            Inline $a_b*c_d$ and \(e_f*g_h\).

            \[
            i_j < k_l & m_n
            \]

            $$
            \begin{matrix}
            a_b & c_d \\
            e_f & g_h
            \end{matrix}
            $$
            """#
        let html = try XCTUnwrap(
            renderMarkdownHTML(markdown: markdown, useGithubLineBreak: false)
        )

        XCTAssertTrue(html.contains("$a_b*c_d$"))
        XCTAssertTrue(html.contains(#"\(e_f*g_h\)"#))
        XCTAssertTrue(html.contains(#"i_j &lt; k_l &amp; m_n"#))
        XCTAssertTrue(html.contains(#"a_b &amp; c_d"#))
        XCTAssertFalse(html.contains("<em>"))
        XCTAssertFalse(html.contains("<strong>"))
    }

    func testMathLineBreaksDoNotDependOnTheLineBreakMode() throws {
        let markdown = #"""
            Prose one
            prose two

            \[
            \boxed{z_{ih}^s\le y_h^s,\quad \forall i,h}\tag{6}
            \]

            Lead \(a
            b\) tail
            $$
            x^2
            $$

            After
            """#
        for useGithubLineBreak in [false, true] {
            let html = try XCTUnwrap(renderMarkdownHTML(markdown: markdown, useGithubLineBreak: useGithubLineBreak))
            let mode = useGithubLineBreak ? "Github" : "MiaoYan"
            for (open, close) in [(#"\["#, #"\]"#), (#"\("#, #"\)"#), ("$$", "$$")] {
                let start = try XCTUnwrap(html.range(of: open), "\(mode) \(open)")
                let end = try XCTUnwrap(html.range(of: close, range: start.upperBound..<html.endIndex), "\(mode) \(close)")
                XCTAssertFalse(html[start.lowerBound..<end.upperBound].contains("<br"), "\(mode) \(open)")
            }
            XCTAssertFalse(html.unicodeScalars.contains("\u{E000}"), mode)
            XCTAssertTrue(html.contains(#"<p data-sourcepos="14:1-14:5">After</p>"#), "\(mode): \(html)")
            XCTAssertEqual(html.contains("Prose one<br />"), !useGithubLineBreak, mode)
        }
    }

    func testMathLineBreakMarkerNeverStripsANotesOwnText() throws {
        let markdown = "keep \u{E000} here\n\n$$\nx^2\n$$"
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: markdown, useGithubLineBreak: false))
        XCTAssertTrue(html.contains("keep \u{E000} here"))
    }

    func testMathProtectionLeavesCodeEscapesAndUnclosedRangesUntouched() throws {
        let inlineCode = "`$inline_code$`"
        let fencedCode = """
            ```text
            $$
            fenced_code
            $$
            ```
            """
        let quotedFencedCode = """
            > ```text
            > $quoted_code$
            > ```
            """
        let indentedCode = "    $indented_code$"
        let crOnlyCode = "~~~text\r$cr_fenced_code$\r~~~\r\r    $cr_indented_code$"
        let escapedBackticks = #"\`literal $escaped_tick_math$ \`"#
        let escapedDollar = #"Price \$100"#
        let unclosedMath = "$value_with_underscore"

        XCTAssertEqual(protectMarkdownMath(inlineCode), inlineCode)
        XCTAssertEqual(protectMarkdownMath(fencedCode), fencedCode)
        XCTAssertEqual(protectMarkdownMath(quotedFencedCode), quotedFencedCode)
        XCTAssertEqual(protectMarkdownMath(indentedCode), indentedCode)
        XCTAssertEqual(protectMarkdownMath(crOnlyCode), crOnlyCode)
        XCTAssertEqual(protectMarkdownMath(escapedDollar), escapedDollar)
        XCTAssertEqual(protectMarkdownMath(unclosedMath), unclosedMath)

        let escapedBacktickHTML = try XCTUnwrap(
            renderMarkdownHTML(markdown: escapedBackticks, useGithubLineBreak: false)
        )
        XCTAssertTrue(escapedBacktickHTML.contains("$escaped_tick_math$"))
        XCTAssertFalse(escapedBacktickHTML.contains("<em>"))

        let currencyMarkdown = """
            Price $100

            ## Markdown between prices

            Price $200
            """
        XCTAssertEqual(protectMarkdownMath(currencyMarkdown), currencyMarkdown)
        let currencyHTML = try XCTUnwrap(
            renderMarkdownHTML(markdown: currencyMarkdown, useGithubLineBreak: false)
        )
        XCTAssertTrue(currencyHTML.contains("<h2"))
        XCTAssertTrue(currencyHTML.contains("Price $100"))
        XCTAssertTrue(currencyHTML.contains("Price $200"))
    }

    func testMathProtectionLeavesKaTeXIgnoredHTMLUntouched() {
        let ignoredHTML = #"""
            <script>const formula = "$script_value$";</script>
            <style>.sample::after { content: "$style_value$"; }</style>
            <textarea>$textarea_value$</textarea>
            <pre>$pre_value$</pre>
            <code>$code_value$</code>
            <option>$option_value$</option>
            """#

        XCTAssertEqual(protectMarkdownMath(ignoredHTML), ignoredHTML)
        XCTAssertNotEqual(
            protectMarkdownMath("<span>$visible_math$</span>"),
            "<span>$visible_math$</span>")
        XCTAssertEqual(
            protectMarkdownMath("`<script>$code_math$</script>`"),
            "`<script>$code_math$</script>`")
    }

    func testNumericOnlyMathDoesNotConsumeFollowingMarkdownBlocks() throws {
        let markdown = #"""
            - Write $0$ if they agree.
            - Write $1$ if they disagree.

            The disagreement distance is $0.25$.

            ## Counts

            | Symbol | Example |
            | ------ | ------- |
            | $n$    | $100$ variables |
            """#
        let html = try XCTUnwrap(
            renderMarkdownHTML(markdown: markdown, useGithubLineBreak: false)
        )

        XCTAssertEqual(html.components(separatedBy: "<li").count - 1, 2)
        XCTAssertTrue(html.contains("<h2"))
        XCTAssertTrue(html.contains("<table"))
        XCTAssertTrue(html.contains("$0.25$"))
        XCTAssertTrue(html.contains("$100$"))
    }

    func testCoefficientParenthesisMathDoesNotConsumeFollowingTable() throws {
        let markdown = #"""
            $2(k-2)$

            | Symbol | Meaning |
            | ------ | ------- |
            | $n$    | Number of variables |
            """#
        let html = try XCTUnwrap(
            renderMarkdownHTML(markdown: markdown, useGithubLineBreak: false)
        )

        XCTAssertTrue(html.contains("<table"))
        XCTAssertTrue(html.contains("$2(k-2)$"))
        XCTAssertTrue(html.contains("$n$"))
    }

    func testPPTPreparationUsesTheSharedMathProtection() {
        let prepared = HtmlManager.prepareMarkdownForPPT(nestedUnderbraceFormula)

        XCTAssertTrue(prepared.contains("&#95;"), "math underscores must be hidden from RevealMarkdown")
        XCTAssertFalse(prepared.contains(#"\text{top}_G"#))
        XCTAssertTrue(prepared.contains("&#36;&#36;"))
    }

    func testExportedHtmlCarriesLocalImagesInside() throws {
        let images = tempDirectory.appendingPathComponent("i", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: images.appendingPathComponent("Tom's & Jerry.png"))
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: "![](/i/Tom's%20&%20Jerry.png)\n\n![](https://example.com/a.png)", useGithubLineBreak: false))

        let embedded = HtmlManager.embedLocalImages(in: html, imagesStorage: tempDirectory)

        XCTAssertTrue(embedded.contains("src=\"data:image/png;base64,iVBORw==\""), "a local image travels inside the file")
        XCTAssertTrue(embedded.contains("src=\"https://example.com/a.png\""), "remote images keep their URL")
    }

    func testPreviewFindsImagesWhoseNamesCmarkEscaped() throws {
        let images = tempDirectory.appendingPathComponent("i", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Data([1]).write(to: images.appendingPathComponent("Tom's & Jerry.png"))
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: "![](/i/Tom's%20&%20Jerry.png)", useGithubLineBreak: false))
        XCTAssertTrue(html.contains("&amp;") || html.contains("&#x27;"), "cmark escapes the name, which is what this guards")

        let processed = HtmlManager.processImages(in: html, imagesStorage: tempDirectory)

        XCTAssertFalse(processed.contains("Image Not Found"), "the escaped name still resolves to the file")
    }

    /// A local image reserves its box before it loads, and no image holds
    /// the page back: a remote first image used to load eagerly, so the
    /// note stayed hidden until that server answered.
    func testPreviewImagesReserveTheirBoxAndLoadAfterThePage() throws {
        let images = tempDirectory.appendingPathComponent("i", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 30, pixelsHigh: 20, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: images.appendingPathComponent("a.png"))
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: images.appendingPathComponent("b.png"))

        let local = try XCTUnwrap(renderMarkdownHTML(markdown: "![](/i/a.png)\n\n![](/i/b.png)", useGithubLineBreak: false))
        let processed = HtmlManager.processImages(in: local, imagesStorage: tempDirectory)
        XCTAssertEqual(processed.components(separatedBy: "width=\"30\" height=\"20\" style=\"aspect-ratio: 30 / 20\"").count, 3, processed)
        XCTAssertEqual(processed.components(separatedBy: "decoding=\"async\"").count, 3, processed)
        XCTAssertEqual(processed.components(separatedBy: "lazy-image").count, 2, "only the second local image is lazy")

        let remote = try XCTUnwrap(renderMarkdownHTML(markdown: "![](https://example.com/a.png)", useGithubLineBreak: false))
        let remoteProcessed = HtmlManager.processImages(in: remote, imagesStorage: tempDirectory)
        XCTAssertTrue(remoteProcessed.contains("data-src=\"https://example.com/a.png\""), remoteProcessed)
        XCTAssertTrue(remoteProcessed.contains("lazy-image"), remoteProcessed)
    }

    /// A remote image is measured by the page the first time it loads, and
    /// renders after that reserve its box from the stored size.
    func testRemoteImagesReserveTheirBoxOnceThePageHasMeasuredThem() throws {
        let url = "https://example.com/\(UUID().uuidString).png"
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: "![](\(url))", useGithubLineBreak: false))

        let first = HtmlManager.processImages(in: html, imagesStorage: tempDirectory)
        XCTAssertTrue(first.contains("data-measure=\"1\""), first)
        XCTAssertFalse(first.contains("width="), first)

        RemoteImageSizes.shared.record(url: url, width: 1200, height: 800)
        let again = HtmlManager.processImages(in: html, imagesStorage: tempDirectory)
        XCTAssertTrue(again.contains("width=\"1200\" height=\"800\" style=\"aspect-ratio: 1200 / 800\""), again)
        XCTAssertFalse(again.contains("data-measure"), again)
        XCTAssertTrue(again.contains("data-src=\"\(url)\""), again)

        RemoteImageSizes.shared.record(url: "file:///etc/passwd", width: 10, height: 10)
        XCTAssertNil(RemoteImageSizes.shared.size(for: "file:///etc/passwd"), "only web images are kept")
    }

    /// Every video waits for the page: none may load before the load event,
    /// which hides the note until it fires, and each one MiaoYan held back is
    /// marked so the page loads its first frame afterwards. A video the note
    /// set to preload="none" itself stays that way.
    func testVideosWaitForThePageAndAreMarkedForTheirFirstFrame() throws {
        let clip = tempDirectory.appendingPathComponent("clip.mp4")
        try Data([0]).write(to: clip)
        let html = [
            "<video src=\"clip.mp4\" controls></video>",
            "<video controls preload=\"auto\" src=\"https://example.com/a.mp4\"></video>",
            "<video controls preload><source src=\"https://example.com/b.mp4\"></video>",
            "<VIDEO preload='metadata' src=\"https://example.com/c.mp4\"></VIDEO>",
            "<video preload=\"none\" src=\"https://example.com/d.mp4\"></video>",
        ].joined(separator: "\n")
        let lines = HtmlManager.processImages(in: html, imagesStorage: tempDirectory).components(separatedBy: "\n")

        XCTAssertEqual(lines[0], "<video preload=\"none\" data-preload=\"metadata\" src=\"file://\(clip.path)\" controls></video>")
        XCTAssertEqual(lines[1], "<video preload=\"none\" data-preload=\"metadata\" controls src=\"https://example.com/a.mp4\"></video>")
        XCTAssertEqual(lines[2], "<video preload=\"none\" data-preload=\"metadata\" controls><source src=\"https://example.com/b.mp4\"></video>")
        XCTAssertEqual(lines[3], "<VIDEO preload=\"none\" data-preload=\"metadata\" src=\"https://example.com/c.mp4\"></VIDEO>")
        XCTAssertEqual(lines[4], "<video preload=\"none\" src=\"https://example.com/d.mp4\"></video>")
        XCTAssertEqual(PreviewMedia.deferredVideoTags(lines[0]), lines[0], "a second pass changes nothing")
    }

    /// A video far from the view never loads its first frame in an export, so
    /// the tint it waits on printed as a grey 16:9 box. Print and the PNG
    /// capture drop the tint, leaving the bare player V4.6.1 showed.
    func testExportsDoNotPrintAVideoAsAGreyBox() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let css = try String(contentsOf: root.appendingPathComponent("Resources/DownView.bundle/css/base.css"), encoding: .utf8)
        let print = try XCTUnwrap(css.range(of: "@media print {\n  #write img.lazy-image,\n  #write img.media-pending,\n  #write video {\n    background-color: transparent;"))
        XCTAssertFalse(print.isEmpty)
        XCTAssertTrue(HtmlManager.checkImagesScript.contains("if (video.readyState < 2) video.style.backgroundColor = 'transparent';"))
    }

    /// An image that gives only its width, as every weekly note does, takes
    /// its height from the image's own ratio. The placeholder's square ratio
    /// drew an 800 by 800 box for a landscape photo.
    func testAnImageWithOnlyAWidthTakesItsOwnRatio() throws {
        let images = tempDirectory.appendingPathComponent("i", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: images.appendingPathComponent("w.png"))

        let local = HtmlManager.processImages(in: "<p>a</p><p><img src=\"/i/w.png\" width=\"800\" /></p><p><img src=\"/i/w.png\" width=\"800\" /></p>", imagesStorage: tempDirectory)
        XCTAssertEqual(local.components(separatedBy: "style=\"aspect-ratio: 40 / 30\"").count, 3, local)
        XCTAssertEqual(local.components(separatedBy: "width=\"800\"").count, 3, local)
        XCTAssertFalse(local.contains("height="), local)

        let url = "https://example.com/\(UUID().uuidString).jpg"
        let remote = "<p><img src=\"\(url)\" width=\"800\" /></p>"
        XCTAssertTrue(HtmlManager.processImages(in: remote, imagesStorage: tempDirectory).contains("data-measure=\"1\""))
        RemoteImageSizes.shared.record(url: url, width: 1600, height: 1200)
        let measured = HtmlManager.processImages(in: remote, imagesStorage: tempDirectory)
        XCTAssertTrue(measured.contains("style=\"aspect-ratio: 1600 / 1200\""), measured)
        XCTAssertFalse(measured.contains("data-measure"), measured)
        XCTAssertFalse(measured.contains("height="), measured)

        let both = HtmlManager.processImages(in: "<p><img src=\"\(url)\" width=\"800\" height=\"100\" /></p>", imagesStorage: tempDirectory)
        XCTAssertFalse(both.contains("aspect-ratio"), "a note that sets both keeps its own box")
    }

    /// Sizes outlive the app: a fresh store reads what an earlier one saved.
    func testRemoteImageSizesPersistAcrossLaunches() throws {
        let file = tempDirectory.appendingPathComponent("sizes.json")
        let store = RemoteImageSizes(fileURL: file)
        store.record(url: "https://example.com/p.png", width: 640, height: 480)
        let deadline = Date().addingTimeInterval(6)
        while !FileManager.default.fileExists(atPath: file.path), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        let reopened = RemoteImageSizes(fileURL: file)
        XCTAssertEqual(reopened.size(for: "https://example.com/p.png")?.width, 640)
        XCTAssertEqual(reopened.size(for: "https://example.com/p.png")?.height, 480)
    }

    /// A remote image's size comes from its first bytes: a PNG's within its
    /// first kilobyte, a JPEG's once the headers after its EXIF arrive,
    /// turned for an EXIF orientation that shows it a quarter round.
    func testSizedTagLetsALoadedPictureKeepItsOwnRatio() {
        let bare = "<img src=\"a.png\">"
        let reader = PreviewMedia.sized(bare, (400, 300), original: bare, placeholder: false)
        XCTAssertTrue(reader.contains("width=\"400\" height=\"300\""), reader)
        XCTAssertTrue(reader.contains("aspect-ratio: auto 400 / 300"), "the picture's own ratio wins once it loads")
        let preview = PreviewMedia.sized(bare, (400, 300), original: bare)
        XCTAssertTrue(preview.contains("aspect-ratio: 400 / 300"), "the 1px placeholder's square must not win")
        let widthOnly = "<img width=\"200\" src=\"a.png\">"
        let kept = PreviewMedia.sized(widthOnly, (400, 300), original: widthOnly, placeholder: false)
        XCTAssertFalse(kept.contains("height="), "a width the note wrote stays alone")
        XCTAssertTrue(kept.contains("aspect-ratio: auto 400 / 300"), kept)
    }

    /// Typora writes `<img src="a.png" style="zoom:50%;">`. Such a tag got the
    /// width and height but no ratio, so behind the 1px placeholder its box
    /// was square until the file loaded.
    func testSizedTagKeepsTheNotesOwnStyleAndAddsTheRatio() {
        let typora = "<img src=\"a.png\" style=\"zoom:50%;\">"
        let preview = PreviewMedia.sized(typora, (400, 300), original: typora)
        XCTAssertTrue(preview.contains("style=\"aspect-ratio: 400 / 300; zoom:50%;\""), preview)
        XCTAssertEqual(preview.components(separatedBy: "style=").count, 2, "one style attribute, not two")
        let single = "<img src='a.png' style='width:50%'>"
        XCTAssertTrue(PreviewMedia.sized(single, (400, 300), original: single).contains("style='aspect-ratio: 400 / 300; width:50%'"))
        let own = "<img src=\"a.png\" style=\"aspect-ratio: 1\">"
        XCTAssertFalse(PreviewMedia.sized(own, (400, 300), original: own).contains("400 / 300"), "a note's own ratio stays")
        let alt = "<img src=\"a.png\" alt=\"see style='x'\">"
        let altSized = PreviewMedia.sized(alt, (400, 300), original: alt)
        XCTAssertTrue(altSized.contains("alt=\"see style='x'\""), "style= inside the alt text is left alone")
        XCTAssertTrue(altSized.contains("style=\"aspect-ratio: 400 / 300\""), altSized)
        let bare = "<img src=\"a.png\" style=zoom:50%>"
        let bareSized = PreviewMedia.sized(bare, (400, 300), original: bare)
        XCTAssertTrue(bareSized.contains("style=\"aspect-ratio: 400 / 300; zoom:50%\""), bareSized)
        XCTAssertEqual(bareSized.components(separatedBy: "style=").count, 2, "an unquoted style is not doubled")
    }

    func testPixelSizeComesFromTheFirstBytesOfAFile() throws {
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        XCTAssertEqual(PreviewMedia.pixelSize(fromHeader: png.prefix(1024))?.width, 40)
        XCTAssertEqual(PreviewMedia.pixelSize(fromHeader: png.prefix(1024))?.height, 30)
        XCTAssertNil(PreviewMedia.pixelSize(fromHeader: png.prefix(12)), "a cut before the header has no size")

        let image = try XCTUnwrap(rep.cgImage)
        let jpeg = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(jpeg, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let bytes = [UInt8](jpeg as Data)
        // ImageIO gives a JPEG's size once the scan header after the frame
        // header has arrived (an iPhone photo's at byte 7640).
        let marker = { (code: UInt8) in (0..<bytes.count - 1).first { bytes[$0] == 0xFF && bytes[$0 + 1] == code } }
        let frame = try XCTUnwrap(marker(0xC0))
        let scan = try XCTUnwrap(marker(0xDA))
        XCTAssertNil(PreviewMedia.pixelSize(fromHeader: (jpeg as Data).prefix(frame)), "the EXIF alone has no size")
        let header = (jpeg as Data).prefix(scan + 16)
        XCTAssertLessThan(header.count, bytes.count)
        XCTAssertEqual(PreviewMedia.pixelSize(fromHeader: header)?.width, 30, "orientation 6 shows it turned")
        XCTAssertEqual(PreviewMedia.pixelSize(fromHeader: header)?.height, 40)

        // An animated WebP, which ImageIO gives no size for: the canvas in
        // its VP8X chunk (a 720 by 414 preview, sides stored less one).
        var webp = Data("RIFF".utf8) + Data([0x94, 0x90, 0x92, 0x00]) + Data("WEBPVP8X".utf8)
        webp += Data([0x0A, 0, 0, 0, 0x12, 0, 0, 0, 0xCF, 0x02, 0x00, 0x9D, 0x01, 0x00]) + Data("ANIM".utf8)
        XCTAssertEqual(PreviewMedia.pixelSize(fromHeader: webp)?.width, 720)
        XCTAssertEqual(PreviewMedia.pixelSize(fromHeader: webp)?.height, 414)
        XCTAssertEqual(PreviewMedia.extendedWebPSize(Data("RIFF".utf8) + Data(count: 4) + Data("WEBPVP8X".utf8) + Data(repeating: 0xFF, count: 14))?.width, 1 << 24)
    }

    /// The probe asks for the start of the file only and reads the size from
    /// it, keeping it for the next render, also from a server that ignores
    /// the range. An error status is remembered and not asked again; a
    /// timeout is not, so the next render tries once more.
    func testRemoteImageProbeAsksForTheHeaderOnly() async throws {
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 48, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        var body = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        body.append(Data(count: 600_000))
        let id = UUID().uuidString
        let url = "https://probe.invalid/\(id).png"
        let whole = "https://probe.invalid/\(id)-whole.png"
        let missing = "https://probe.invalid/\(id)-missing.png"
        let flaky = "https://probe.invalid/\(id)-flaky.png"
        ImageProbeStub.serve(url, status: 206, body: body)
        ImageProbeStub.serve(whole, status: 200, body: body)
        ImageProbeStub.serve(missing, status: 404, body: Data())
        ImageProbeStub.serve(flaky, status: 206, body: body, failing: 1)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageProbeStub.self]
        let sizes = RemoteImageSizes(fileURL: nil)
        let probe = RemoteImageProbe(configuration: configuration, sizes: sizes)

        let size = await probe.size(of: url)
        XCTAssertEqual(size?.width, 36)
        XCTAssertEqual(size?.height, 48)
        XCTAssertEqual(ImageProbeStub.range(for: url), "bytes=0-\(RemoteImageProbe.maxBytes - 1)")
        XCTAssertEqual(sizes.size(for: url)?.height, 48, "the next render reserves the box")
        let wholeSize = await probe.size(of: whole)
        XCTAssertEqual(wholeSize?.width, 36, "a server that sends the whole file still gives the size")

        var missingSize = await probe.size(of: missing)
        missingSize = await probe.size(of: missing)
        XCTAssertNil(missingSize)
        XCTAssertEqual(ImageProbeStub.requests(for: missing), 1, "an error status is not asked again")

        let firstTry = await probe.size(of: flaky)
        XCTAssertNil(firstTry)
        let secondTry = await probe.size(of: flaky)
        XCTAssertEqual(secondTry?.height, 48, "a timeout does not stop the next render from asking")

        sizes.record(url: "https://probe.invalid/\(id)-measured.png", width: 10, height: 20)
        ImageProbeStub.serve("https://probe.invalid/\(id)-measured.png", status: 206, body: body)
        let measured = await probe.size(of: "https://probe.invalid/\(id)-measured.png")
        XCTAssertEqual(measured?.width, 10, "the page's own measurement is kept")
        XCTAssertEqual(ImageProbeStub.requests(for: "https://probe.invalid/\(id)-measured.png"), 0)
    }

    /// Moving to another note puts the probes still queued for the last one
    /// behind the next note's: with four reads stuck on a dead host, a probe
    /// queued before the switch waited ahead of the new note's for up to 15s
    /// each. It is not dropped, since a cancelled switch keeps the old page.
    func testQueuedProbesGoBehindTheNextNotesWhenThePreviewMovesOn() async throws {
        let id = UUID().uuidString
        // Three reads hang and one answers after 0.4s, so slots free one at a time.
        let stuck = (0..<4).map { "https://probe.invalid/\(id)-stuck-\($0).png" }
        stuck.dropLast().forEach { ImageProbeStub.serve($0, status: 206, body: Data(), hangs: true) }
        ImageProbeStub.serve(stuck[3], status: 404, body: Data(), delay: 0.4)
        let old = "https://probe.invalid/\(id)-old.png"
        let next = "https://probe.invalid/\(id)-next.png"
        ImageProbeStub.serve(old, status: 404, body: Data())
        ImageProbeStub.serve(next, status: 404, body: Data())
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageProbeStub.self]
        configuration.timeoutIntervalForRequest = 4
        let probe = RemoteImageProbe(configuration: configuration, sizes: RemoteImageSizes(fileURL: nil))
        let reads = stuck.map { url in Task { await probe.size(of: url) } }
        var tries = 0
        while stuck.contains(where: { ImageProbeStub.requests(for: $0) == 0 }), tries < 300 {
            tries += 1
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let oldRead = Task { await probe.size(of: old) }
        while await probe.queuedCount < 1, tries < 600 {
            tries += 1
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        await probe.deferQueued()
        let nextRead = Task { await probe.size(of: next) }
        while await probe.queuedCount < 2, tries < 900 {
            tries += 1
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        _ = await nextRead.value
        _ = await oldRead.value
        reads.forEach { $0.cancel() }
        let nextAt = try XCTUnwrap(ImageProbeStub.position(of: next))
        let oldAt = try XCTUnwrap(ImageProbeStub.position(of: old), "a deferred probe still runs")
        XCTAssertLessThan(nextAt, oldAt, "the next note's probe goes first")
    }

    func testTemplatePlaceholdersInsideNoteTextStayAsWritten() {
        let template = "<style>DOWN_CSS</style><body class=\"CUSTOM_CSS\">DOWN_HTML</body>"
        let replacements = ["DOWN_CSS": "p{}", "CUSTOM_CSS": "lightmode", "DOWN_HTML": "<p>write CUSTOM_CSS and DOWN_CSS here</p>"]
        for _ in 0..<20 {
            XCTAssertEqual(
                HtmlManager.applyTemplateReplacements(template, replacements: replacements),
                "<style>p{}</style><body class=\"lightmode\"><p>write CUSTOM_CSS and DOWN_CSS here</p></body>")
        }
    }

    /// Every full preview load walked all of DownView.bundle on the main
    /// thread to refresh the cached copy. It is walked once per launch now,
    /// and again only when the cache lost a required file.
    @MainActor
    func testPreviewBundleIsWalkedOncePerLaunchAndAgainWhenLost() throws {
        HtmlManager.ensurePreviewResourcesAvailable()
        let walked = HtmlManager.bundleSyncCount
        XCTAssertGreaterThan(walked, 0)
        XCTAssertFalse(HtmlManager.ensurePreviewResourcesAvailable(), "nothing to repair")
        _ = HtmlManager.createTemporaryBundle(pageHTMLString: "<p>a</p>")
        XCTAssertEqual(HtmlManager.bundleSyncCount, walked, "a load does not walk the bundle again")

        let common = HtmlManager.previewBundleURL().appendingPathComponent("js/common.js")
        try FileManager.default.removeItem(at: common)
        XCTAssertTrue(HtmlManager.ensurePreviewResourcesAvailable(), "a lost file is put back")
        XCTAssertEqual(HtmlManager.bundleSyncCount, walked + 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: common.path))
    }

    /// KaTeX's stylesheet fetched every font from gw.alipayobjects.com, so
    /// offline formulas fell back to Times while the blog said math needs no
    /// network. The fonts ship in the built bundle, next to the stylesheet.
    func testKatexFontsShipInsideThePreviewBundle() throws {
        let bundle = try XCTUnwrap(Bundle.main.url(forResource: "DownView", withExtension: "bundle"))
        let cssURL = bundle.appendingPathComponent("css/katex.min.css")
        let css = try String(contentsOf: cssURL, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: "url\\(([^)]+)\\)")
        let urls = regex.matches(in: css, range: NSRange(css.startIndex..., in: css)).compactMap {
            Range($0.range(at: 1), in: css).map { String(css[$0]) }
        }
        XCTAssertFalse(urls.isEmpty)
        XCTAssertFalse(urls.contains { $0.contains("://") }, "no font is fetched from the network")
        let woff2 = Set(urls.filter { $0.hasSuffix(".woff2") })
        XCTAssertEqual(woff2.count, 20)
        for path in woff2 {
            let file = cssURL.deletingLastPathComponent().appendingPathComponent(path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "\(path) is bundled")
        }
    }
}

@available(macOS 12.0, *)
final class MathRenderingRuntimeTests: XCTestCase {
    private var tempDirectory: URL!
    private var downViewBundleURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiaoYan Math Runtime Tests \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        downViewBundleURL = try XCTUnwrap(
            Bundle.main.url(forResource: "DownView", withExtension: "bundle"))
        for directory in ["css", "js", "ppt", "themes"] {
            try FileManager.default.createSymbolicLink(
                at: tempDirectory.appendingPathComponent(directory),
                withDestinationURL: downViewBundleURL.appendingPathComponent(directory))
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    @MainActor
    func testPreviewAndPPTRenderNestedUnderbraceWithKaTeX() async throws {
        let previewHTML = try XCTUnwrap(
            renderMarkdownHTML(markdown: nestedUnderbraceFormula, useGithubLineBreak: true))
        try await assertKaTeXRendered(page: try writePreviewPage(markdownHTML: previewHTML))
        try await assertKaTeXRendered(page: try writePPTPage())
    }

    @MainActor
    func testMultiLineMathRendersInTheMiaoYanLineBreakMode() async throws {
        let markdown = #"""
            客户只能分配给启用站点

            \[
            \boxed{z_{ih}^s\le y_h^s,\quad \forall i,h}\tag{6}
            \]

            Lead \(a
            b\) tail
            $$
            x^2
            $$
            """#
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: markdown, useGithubLineBreak: false))
        let page = try writePreviewPage(markdownHTML: html)
        let count = try await renderedKaTeXCount(page: page)
        XCTAssertEqual(count, 3, html)
    }

    private func writePreviewPage(markdownHTML: String) throws -> URL {
        let jsDirectory = downViewBundleURL.appendingPathComponent("js", isDirectory: true)
        let page = """
            <!doctype html><html><head><meta charset="utf-8">
            <script src="\(jsDirectory.appendingPathComponent("katex.min.js").absoluteString)"></script>
            <script src="\(jsDirectory.appendingPathComponent("auto-render.min.js").absoluteString)"></script>
            </head><body><div id="write">\(markdownHTML)</div><script>
            window.__miaoyanMathDone = false;
            window.addEventListener('load', function () {
              renderMathInElement(document.getElementById('write'), {
                delimiters: [
                  {left: '$$', right: '$$', display: true},
                  {left: '$', right: '$', display: false},
                  {left: '\\\\(', right: '\\\\)', display: false},
                  {left: '\\\\[', right: '\\\\]', display: true}
                ], throwOnError: false
              });
              window.__miaoyanMathDone = true;
            });
            </script></body></html>
            """
        return try write(page: page, named: "preview")
    }

    private func writePPTPage() throws -> URL {
        let prepared = HtmlManager.prepareMarkdownForPPT(nestedUnderbraceFormula)
        let templateURL = downViewBundleURL.appendingPathComponent("ppt.html")
        var page = try String(contentsOf: templateURL, encoding: .utf8)
        let replacements = [
            "DOWN_RAW": prepared,
            "DOWN_THEME": "",
            "DOWN_CSS": "",
            "DOWN_FONT_PATH": ".",
            "DOWN_EXPORT_TYPE": "",
        ]
        for (placeholder, value) in replacements {
            page = page.replacingOccurrences(of: placeholder, with: value)
        }
        let readinessProbe = """
            <script>
            window.__miaoyanMathDone = false;
            const miaoyanMathReadyTimer = setInterval(function () {
              if (typeof Reveal !== 'undefined' && Reveal.isReady()) {
                window.__miaoyanMathDone = true;
                clearInterval(miaoyanMathReadyTimer);
              }
            }, 10);
            </script>
            """
        page = page.replacingOccurrences(of: "</body>", with: readinessProbe + "</body>")
        return try write(page: page, named: "ppt")
    }

    private func write(page: String, named: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent("\(named).html")
        try page.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @MainActor
    private func renderedKaTeXCount(page: URL) async throws -> Int {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: WKWebViewConfiguration())
        webView.loadFileURL(page, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let done = try? await webView.evaluateJavaScript(
                "document.readyState === 'complete' && window.__miaoyanMathDone === true") as? Bool,
                done
            {
                let count = try await webView.evaluateJavaScript("document.querySelectorAll('.katex').length")
                return try XCTUnwrap(count as? Int)
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Timed out waiting for KaTeX in \(page.lastPathComponent)")
        return 0
    }

    @MainActor
    private func assertKaTeXRendered(page: URL) async throws {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 900, height: 700),
            configuration: configuration)
        webView.loadFileURL(page, allowingReadAccessTo: URL(fileURLWithPath: "/"))

        let deadline = Date().addingTimeInterval(10)
        var lastState: [String: Any]?
        while Date() < deadline {
            if let done = try? await webView.evaluateJavaScript(
                "document.readyState === 'complete' && window.__miaoyanMathDone === true") as? Bool,
                done
            {
                let raw = try await webView.evaluateJavaScript(
                    "({katex: document.querySelectorAll('.katex').length, em: document.querySelectorAll('em').length, raw: document.body.innerText.includes('\\\\underbrace')})")
                let state = try XCTUnwrap(raw as? [String: Any])
                lastState = state
                if try XCTUnwrap(state["katex"] as? Int) > 0 {
                    XCTAssertEqual(try XCTUnwrap(state["em"] as? Int), 0, page.lastPathComponent)
                    XCTAssertEqual(try XCTUnwrap(state["raw"] as? Bool), false, page.lastPathComponent)
                    return
                }
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Timed out waiting for KaTeX in \(page.lastPathComponent): \(String(describing: lastState))")
    }
}
