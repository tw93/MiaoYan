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

        XCTAssertEqual(processed, "![](\(HtmlManager.localMediaURL(forPath: imageURL.path)))")
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
        // `\(` and `\[` are math only in a note without `$` math, so each
        // pair of styles is its own note.
        let dollars = #"""
            Inline $a_b*c_d$.

            $$
            \begin{matrix}
            a_b & c_d \\
            e_f & g_h
            \end{matrix}
            $$
            """#
        let brackets = #"""
            Inline \(e_f*g_h\).

            \[
            i_j < k_l & m_n
            \]
            """#
        let dollarHTML = try XCTUnwrap(renderMarkdownHTML(markdown: dollars, useGithubLineBreak: false))
        let bracketHTML = try XCTUnwrap(renderMarkdownHTML(markdown: brackets, useGithubLineBreak: false))

        XCTAssertTrue(dollarHTML.contains("$a_b*c_d$"))
        XCTAssertTrue(dollarHTML.contains(#"a_b &amp; c_d"#))
        XCTAssertTrue(bracketHTML.contains(#"\(e_f*g_h\)"#))
        XCTAssertTrue(bracketHTML.contains(#"i_j &lt; k_l &amp; m_n"#))
        for html in [dollarHTML, bracketHTML] {
            XCTAssertFalse(html.contains("<em>"))
            XCTAssertFalse(html.contains("<strong>"))
        }
    }

    /// Beside `$` math, `\[1\]` is the Markdown escape for a literal `[1]`
    /// and `\(` for `(`; on their own they are still math, as ChatGPT and
    /// Claude write it (maintainer, 2026-11-21).
    func testBracketsAreMathOnlyInANoteWithoutDollarMath() throws {
        let mixed = #"""
            The energy $E = mc^2$ is cited as \[1\], see \(note\).

            ```
            \[kept in code\]
            ```
            """#
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: mixed, useGithubLineBreak: false))
        XCTAssertTrue(html.contains("$E = mc^2$"), html)
        XCTAssertTrue(html.contains("cited as [1], see (note)."), html)
        XCTAssertFalse(html.contains(#"\[1\]"#), html)
        XCTAssertTrue(html.contains(#"\[kept in code\]"#), "code stays as written")

        // A currency sign or an escaped dollar is not `$` math.
        for prose in [#"It costs $5 and \(a_b*c\) holds."#, #"Pay \$x and \$y, then \(a_b*c\)."#] {
            let bracketHTML = try XCTUnwrap(renderMarkdownHTML(markdown: prose, useGithubLineBreak: false))
            XCTAssertTrue(bracketHTML.contains(#"\(a_b*c\)"#), bracketHTML)
        }
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
            \[
            x^2
            \]

            After
            """#
        for useGithubLineBreak in [false, true] {
            let html = try XCTUnwrap(renderMarkdownHTML(markdown: markdown, useGithubLineBreak: useGithubLineBreak))
            let mode = useGithubLineBreak ? "Github" : "MiaoYan"
            for (open, close) in [(#"\["#, #"\]"#), (#"\("#, #"\)"#)] {
                let start = try XCTUnwrap(html.range(of: open), "\(mode) \(open)")
                let end = try XCTUnwrap(html.range(of: close, range: start.upperBound..<html.endIndex), "\(mode) \(close)")
                XCTAssertFalse(html[start.lowerBound..<end.upperBound].contains("<br"), "\(mode) \(open)")
            }
            XCTAssertFalse(html.unicodeScalars.contains("\u{E000}"), mode)
            XCTAssertTrue(html.contains(#"<p data-sourcepos="14:1-14:5">After</p>"#), "\(mode): \(html)")
            XCTAssertEqual(html.contains("Prose one<br />"), !useGithubLineBreak, mode)
        }
        let dollars = #"""
            Lead $a
            b$ tail
            $$
            x^2
            $$
            """#
        for useGithubLineBreak in [false, true] {
            let html = try XCTUnwrap(renderMarkdownHTML(markdown: dollars, useGithubLineBreak: useGithubLineBreak))
            let mode = useGithubLineBreak ? "Github" : "MiaoYan"
            for (open, close) in [("$a", "b$"), ("$$", "$$")] {
                let start = try XCTUnwrap(html.range(of: open), "\(mode) \(open)")
                let end = try XCTUnwrap(html.range(of: close, range: start.upperBound..<html.endIndex), "\(mode) \(close)")
                XCTAssertFalse(html[start.lowerBound..<end.upperBound].contains("<br"), "\(mode) \(open)")
            }
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

    /// Inline `$` pairs as on GitHub. The pairing ran to the next `$`
    /// anywhere in the note, so two shell variables paragraphs apart became
    /// one formula and the heading and list between them were shown as raw
    /// text, and `$ 5 ... $ 6` hid the bold between two prices.
    func testInlineDollarPairsWithinAParagraphLikeGitHub() throws {
        let variables = "Set $PATH first.\n\n## Next\n\n- item\n\nThen $HOME."
        let variablesHTML = try XCTUnwrap(renderMarkdownHTML(markdown: variables, useGithubLineBreak: false))
        XCTAssertTrue(variablesHTML.contains("<h2"), variablesHTML)
        XCTAssertTrue(variablesHTML.contains("<ul"), variablesHTML)

        let prices = "US$ 5 for **a** and $ 6 for **b**"
        let pricesHTML = try XCTUnwrap(renderMarkdownHTML(markdown: prices, useGithubLineBreak: false))
        XCTAssertEqual(pricesHTML.components(separatedBy: "<strong>").count - 1, 2, pricesHTML)

        let spaced = "from $a **b** $ to x"
        XCTAssertEqual(protectMarkdownMath(spaced), spaced)
        let digitAfter = "cost $a_b$5 and *c*"
        XCTAssertEqual(protectMarkdownMath(digitAfter), digitAfter)

        let math = "Inline $a_b*c_d$ over\ntwo $x_1\ny_2$ lines."
        let mathHTML = try XCTUnwrap(renderMarkdownHTML(markdown: math, useGithubLineBreak: false))
        XCTAssertTrue(mathHTML.contains("$a_b*c_d$"), mathHTML)
        XCTAssertFalse(mathHTML.contains("<em>"), mathHTML)
    }

    /// Bare URLs become links, as in GitHub Flavored Markdown.
    func testBareURLsAreLinked() throws {
        let html = try XCTUnwrap(
            renderMarkdownHTML(markdown: "See https://miaoyan.app and www.example.com.", useGithubLineBreak: false))
        XCTAssertTrue(html.contains(#"<a href="https://miaoyan.app">"#), html)
        XCTAssertTrue(html.contains(#"<a href="http://www.example.com">"#), html)
    }

    /// The page takes the language set in MiaoYan, so WebKit draws kanji in
    /// Japanese forms for a Japanese reader instead of the system's Chinese
    /// ones; English sets none, since `hyphens: auto` would start breaking
    /// words. Emphasis in Han alone follows the page.
    @MainActor
    func testPreviewPageTakesTheLanguageSetInMiaoYan() throws {
        let previous = UserDefaults.standard.object(forKey: "defaultLanguage")
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: "defaultLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "defaultLanguage")
            }
        }
        let expected: [(LanguageType, String?)] = [(.Japanese, "ja"), (.ChineseTC, "zh-Hant"), (.Chinese, "zh-Hans"), (.English, nil)]
        for (language, lang) in expected {
            UserDefaultsManagement.defaultLanguage = language.rawValue
            let page = try HtmlManager.htmlFromTemplate("<p>x</p>", css: "", currentName: "t")
            if let lang {
                XCTAssertTrue(page.contains("<html lang=\"\(lang)\">"), "\(language)")
            } else {
                XCTAssertTrue(page.contains("<html>"), "\(language)")
                XCTAssertFalse(page.contains("<html lang"), "\(language)")
            }
        }

        let html = try XCTUnwrap(renderMarkdownHTML(markdown: "これは*漢字*です", useGithubLineBreak: false, documentLanguage: "ja"))
        XCTAssertTrue(html.contains("<em lang=\"ja\">漢字</em>"), html)
        let plain = try XCTUnwrap(renderMarkdownHTML(markdown: "这是*汉字*", useGithubLineBreak: false))
        XCTAssertTrue(plain.contains("<em lang=\"zh\">汉字</em>"), plain)
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

        XCTAssertEqual(
            lines[0], "<video preload=\"none\" data-preload=\"metadata\" src=\"\(HtmlManager.localMediaURL(forPath: clip.path))\" controls></video>")
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

    /// A full store emptied itself, so every image the library had shown
    /// jumped into place again on its next open; it now lets the oldest
    /// quarter go and keeps reading sizes saved before they carried an order.
    func testAFullRemoteImageSizeStoreDropsItsOldestQuarter() throws {
        let file = tempDirectory.appendingPathComponent("old-sizes.json")
        try JSONEncoder().encode(["https://example.com/old.png": [300, 200]]).write(to: file)
        let store = RemoteImageSizes(fileURL: file)
        XCTAssertEqual(store.size(for: "https://example.com/old.png")?.height, 200, "a size saved as width and height alone")
        for index in 1..<store.limit {
            store.record(url: "https://example.com/\(index).png", width: 10, height: index)
        }
        store.record(url: "https://example.com/new.png", width: 640, height: 480)
        XCTAssertNil(store.size(for: "https://example.com/old.png"), "the oldest goes first")
        XCTAssertNil(store.size(for: "https://example.com/\(store.limit / 4 - 1).png"))
        XCTAssertEqual(store.size(for: "https://example.com/\(store.limit / 4).png")?.height, store.limit / 4)
        XCTAssertEqual(store.size(for: "https://example.com/\(store.limit - 1).png")?.height, store.limit - 1)
        XCTAssertEqual(store.size(for: "https://example.com/new.png")?.width, 640)
    }

    /// The first learnt went first, so a weekly cover shown every week was
    /// dropped before images seen once since; a size read or recorded again
    /// is now the most recently used (2026-11-22).
    func testAFullRemoteImageSizeStoreKeepsWhatWasUsedLately() throws {
        let store = RemoteImageSizes(fileURL: nil)
        store.record(url: "https://example.com/cover.jpg", width: 800, height: 450)
        store.record(url: "https://example.com/logo.png", width: 64, height: 64)
        for index in 2..<store.limit {
            store.record(url: "https://example.com/\(index).png", width: 10, height: index)
            if index == store.limit / 2 {
                XCTAssertNotNil(store.size(for: "https://example.com/cover.jpg"))
                store.record(url: "https://example.com/logo.png", width: 64, height: 64)
            }
        }
        store.record(url: "https://example.com/new.png", width: 640, height: 480)
        XCTAssertEqual(store.size(for: "https://example.com/cover.jpg")?.width, 800, "read halfway, so not among the oldest")
        XCTAssertEqual(store.size(for: "https://example.com/logo.png")?.width, 64, "recorded again halfway")
        XCTAssertNil(store.size(for: "https://example.com/2.png"), "the least recently used still go")
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

    /// cmark drops the backslash of `\$`, and KaTeX's auto-render has no
    /// escape option, so `\$x and \$y` reached it as the formula `$x and $y`.
    func testEscapedDollarsRenderAsLiteralDollarsTheMathPassSkips() throws {
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: #"Costs \$5 and \$10, `\$code` stays"#, useGithubLineBreak: false))
        XCTAssertEqual(html.components(separatedBy: "<span class=\"skip-math-dollar\">$</span>").count - 1, 2, html)
        XCTAssertTrue(html.contains("<code>\\$code</code>"), html)

        XCTAssertEqual(protectMarkdownMath(#"\\$x$"#, literalEscapedDollars: true), #"\\&#36;&#120;&#36;"#, "an escaped backslash leaves the dollar a delimiter")
        XCTAssertEqual(protectMarkdownMath(#"$a \$ b$"#, literalEscapedDollars: true).contains("skip-math-dollar"), false, "inside math the escape is KaTeX's")
    }

    /// cmark renders with sourcepos, so a note opening with `# Title` starts
    /// with `<h1 data-sourcepos=…>`; HTML export printed the title twice.
    func testExportTitleIsSkippedWhenTheBodyOpensWithAHeading() throws {
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: "# Plan\n\nBody", useGithubLineBreak: false))
        XCTAssertTrue(HtmlManager.opensWithTitleHeading(html), html)
        XCTAssertFalse(HtmlManager.opensWithTitleHeading("<h2>Plan</h2>"))
        XCTAssertFalse(HtmlManager.opensWithTitleHeading("<header>x</header>"))
        XCTAssertEqual(HtmlManager.escapeHTMLText("R&D <draft>"), "R&amp;D &lt;draft&gt;")
    }

    /// CommonMark takes a space or a tab after the `#`s, and the preview
    /// renders `#\tTitle` as a heading; the editor coloured only the space.
    @MainActor
    func testEditorHeadingAcceptsATabAfterTheMarker() {
        for line in ["# Title", "#\tTitle", "###\tTitle"] {
            var found = false
            NotesTextProcessor.headersAtxRegex.matches(line, range: NSRange(location: 0, length: (line as NSString).length)) { result in
                if result != nil { found = true }
            }
            XCTAssertTrue(found, line)
        }
        var glued = false
        NotesTextProcessor.headersAtxRegex.matches("#Title", range: NSRange(location: 0, length: 6)) { if $0 != nil { glued = true } }
        XCTAssertFalse(glued)
    }

    /// KaTeX's mhchem extension ships in `DownView.bundle` and loads between
    /// `katex.min.js` and `auto-render.min.js` in `index.html`. Runtime PPT
    /// load order is asserted against `document.scripts` in
    /// `MathRenderingRuntimeTests.testPPTRendersMhchemChemistry`.
    func testMhchemShipsInThePreviewBundleInLoadOrder() throws {
        let bundle = try XCTUnwrap(Bundle.main.url(forResource: "DownView", withExtension: "bundle"))
        let mhchemURL = bundle.appendingPathComponent("js/mhchem.min.js")
        XCTAssertTrue(FileManager.default.fileExists(atPath: mhchemURL.path))

        let indexHTML = try String(contentsOf: bundle.appendingPathComponent("index.html"), encoding: .utf8)
        let katex = try XCTUnwrap(indexHTML.range(of: "js/katex.min.js"))
        let mhchem = try XCTUnwrap(indexHTML.range(of: "js/mhchem.min.js"))
        let autoRender = try XCTUnwrap(indexHTML.range(of: "js/auto-render.min.js"))
        XCTAssertLessThan(katex.lowerBound, mhchem.lowerBound)
        XCTAssertLessThan(mhchem.lowerBound, autoRender.lowerBound)
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
            \[
            x^2
            \]
            """#
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: markdown, useGithubLineBreak: false))
        let count = try await renderedKaTeXCount(page: try writePreviewPage(markdownHTML: html))
        XCTAssertEqual(count, 3, html)

        // `$` math is its own note: beside it the brackets are escapes.
        let dollars = #"""
            Lead $a
            b$ tail
            $$
            x^2
            $$
            """#
        let dollarHTML = try XCTUnwrap(renderMarkdownHTML(markdown: dollars, useGithubLineBreak: false))
        let dollarCount = try await renderedKaTeXCount(page: try writePreviewPage(markdownHTML: dollarHTML))
        XCTAssertEqual(dollarCount, 2, dollarHTML)
    }

    /// The real preview (`index.html`) loads KaTeX's bundled `mhchem` extension
    /// offline and renders `\ce` and `\pu` chemistry formulas with zero KaTeX
    /// errors, without affecting regular math, currency amounts, escaped dollars,
    /// or inline code.
    @MainActor
    func testPreviewRendersMhchemChemistry() async throws {
        let markdown = #"""
            Water is $\ce{H2O}$, rate $\ce{A ->[$k_1$] B}$, heated $\ce{A ->[$80 ^\circ C$] B}$, units $\pu{123 kJ/mol}$, and $E = mc^2$.

            $$
            \ce{2H2 + O2 -> 2H2O}
            $$

            $$
            \ce{Hg^2+ ->[I-] HgI2 ->[I-] [Hg^{II}I4]^2-}
            $$

            Prices $20 and $30, escaped \$100, code `$\ce{H2O}$`.

            The variable $PATH costs $20 and the radius is $r$.

            Cost $$20 and $x$.
            """#
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: markdown, useGithubLineBreak: false))
        let previewURL = try writeIndexPage(bodyHTML: html, named: "mhchem-preview")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: WKWebViewConfiguration())
        webView.loadFileURL(previewURL, allowingReadAccessTo: tempDirectory)

        let probe = """
            (() => {
                const paragraphs = Array.from(document.querySelectorAll('#write p'));
                const envParagraph = paragraphs[paragraphs.length - 2];
                const doubleDollarParagraph = paragraphs[paragraphs.length - 1];
                return {
                    katex: document.querySelectorAll('#write .katex').length,
                    display: document.querySelectorAll('#write .katex-display').length,
                    errors: document.querySelectorAll('#write .katex-error').length,
                    skippedDollars: Array.from(document.querySelectorAll('#write .skip-math-dollar'), (s) => s.textContent),
                    codeText: Array.from(document.querySelectorAll('#write code'), (c) => c.textContent),
                    rawCe: document.getElementById('write').innerText.includes('\\\\ce{2H2') || document.getElementById('write').innerText.includes('\\\\ce{A'),
                    rawPu: document.getElementById('write').innerText.includes('\\\\pu{'),
                    envParagraph: envParagraph ? envParagraph.innerText : '',
                    envParagraphKatex: envParagraph ? envParagraph.querySelectorAll('.katex').length : 0,
                    doubleDollarParagraph: doubleDollarParagraph ? doubleDollarParagraph.innerText : '',
                    doubleDollarKatex: doubleDollarParagraph ? doubleDollarParagraph.querySelectorAll('.katex').length : 0,
                    text: document.getElementById('write').innerText
                };
            })()
            """
        let deadline = Date().addingTimeInterval(10)
        var state: [String: Any] = [:]
        while Date() < deadline {
            state = (try? await webView.evaluateJavaScript(probe) as? [String: Any]) ?? [:]
            if (state["katex"] as? Int) == 9 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(state["katex"] as? Int, 9, "\(state)")
        XCTAssertEqual(state["display"] as? Int, 2, "\(state)")
        XCTAssertEqual(state["errors"] as? Int, 0, "\(state)")
        XCTAssertEqual(state["skippedDollars"] as? [String], ["$20", "$30", "$", "$20", "$20"], "\(state)")
        XCTAssertEqual(state["codeText"] as? [String], [#"\ce{H2O}"#].map { "$\($0)$" }, "\(state)")
        XCTAssertEqual(state["rawCe"] as? Bool, false, "\(state)")
        XCTAssertEqual(state["rawPu"] as? Bool, false, "\(state)")
        XCTAssertEqual(state["envParagraphKatex"] as? Int, 1, "\(state)")
        let envParagraph = try XCTUnwrap(state["envParagraph"] as? String)
        XCTAssertTrue(envParagraph.contains("The variable $PATH costs $20 and the radius is "), envParagraph)
        XCTAssertEqual(state["doubleDollarKatex"] as? Int, 1, "\(state)")
        let doubleDollarParagraph = try XCTUnwrap(state["doubleDollarParagraph"] as? String)
        XCTAssertTrue(doubleDollarParagraph.contains("Cost $$20 and "), doubleDollarParagraph)
        let text = try XCTUnwrap(state["text"] as? String)
        XCTAssertTrue(text.contains("$20"), text)
        XCTAssertTrue(text.contains("$30"), text)
        XCTAssertTrue(text.contains("$100"), text)
    }

    /// `\( \)` and `\[ \]` are math only in a note without `$` math (the
    /// maintainer's rule, 2026-11-21), so chemistry in them is checked on a
    /// note of its own; beside `$` math they are Markdown escapes.
    @MainActor
    func testBracketDelimitersRenderMhchemInANoteWithoutDollarMath() async throws {
        let markdown = #"""
            Water is \(\ce{H2O}\) and the reaction is:

            \[
            \ce{2H2 + O2 -> 2H2O}
            \]
            """#
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: markdown, useGithubLineBreak: false))
        let previewURL = try writeIndexPage(bodyHTML: html, named: "mhchem-brackets")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: WKWebViewConfiguration())
        webView.loadFileURL(previewURL, allowingReadAccessTo: tempDirectory)
        let probe = """
            JSON.stringify({
              katex: document.querySelectorAll('#write .katex').length,
              display: document.querySelectorAll('#write .katex-display').length,
              errors: document.querySelectorAll('#write .katex-error').length,
              raw: document.getElementById('write').innerText.includes('\\\\ce{')
            })
            """
        let deadline = Date().addingTimeInterval(10)
        var state: [String: Any] = [:]
        while Date() < deadline {
            if let json = try? await webView.evaluateJavaScript(probe) as? String,
                let data = json.data(using: .utf8),
                let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                state = parsed
                if (state["katex"] as? Int) == 2 { break }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(state["katex"] as? Int, 2, "\(state)")
        XCTAssertEqual(state["display"] as? Int, 1, "\(state)")
        XCTAssertEqual(state["errors"] as? Int, 0, "\(state)")
        XCTAssertEqual(state["raw"] as? Bool, false, "\(state)")
    }

    /// PDF export reloads already-rendered preview HTML into `index.html`;
    /// rendered `mhchem` formulas must survive the reload without
    /// double-rendering or errors once `renderPage()` finishes its math pass.
    @MainActor
    func testRenderedMhchemSurvivesReloadForPDFExport() async throws {
        let markdown = #"""
            Inline $\ce{H2O}$ and $\pu{123 kJ/mol}$.

            $$
            \ce{2H2 + O2 -> 2H2O}
            $$
            """#
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: markdown, useGithubLineBreak: false))
        let firstURL = try writeIndexPage(bodyHTML: html, named: "mhchem-pdf-first")
        let firstWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: WKWebViewConfiguration())
        firstWebView.loadFileURL(firstURL, allowingReadAccessTo: tempDirectory)

        let firstDeadline = Date().addingTimeInterval(10)
        var savedWriteHTML: String?
        while Date() < firstDeadline {
            let count = (try? await firstWebView.evaluateJavaScript("document.querySelectorAll('#write .katex').length") as? Int) ?? 0
            if count == 3 {
                savedWriteHTML = try? await firstWebView.evaluateJavaScript("document.getElementById('write').innerHTML") as? String
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let bodyHTML = try XCTUnwrap(savedWriteHTML, "initial preview did not finish rendering mhchem")

        // Queues a completion flag behind `renderPage()`'s own deferred math pass
        // so slow CI runners wait deterministically without a fixed sleep.
        let reloadDoneScript = """
            <script>
            window.__miaoyanReloadDone = false;
            document.addEventListener('DOMContentLoaded', function () {
              const markDone = () => { window.__miaoyanReloadDone = true; };
              if ('requestIdleCallback' in window) {
                requestIdleCallback(markDone, { timeout: 250 });
              } else {
                setTimeout(markDone, 0);
              }
            });
            </script>
            """
        let reloadURL = try writeIndexPage(bodyHTML: bodyHTML, named: "mhchem-pdf-reload", extraBodyScript: reloadDoneScript)
        let reloadWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: WKWebViewConfiguration())
        reloadWebView.loadFileURL(reloadURL, allowingReadAccessTo: tempDirectory)

        let reloadDeadline = Date().addingTimeInterval(10)
        var reloadDone = false
        while Date() < reloadDeadline {
            if (try? await reloadWebView.evaluateJavaScript("window.__miaoyanReloadDone === true") as? Bool) == true {
                reloadDone = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(reloadDone, "reloaded preview did not complete renderPage() math pass")
        let reloaded = try await reloadWebView.evaluateJavaScript(
            "({katex: document.querySelectorAll('#write .katex').length, errors: document.querySelectorAll('#write .katex-error').length})"
        )
        let reloadedState = try XCTUnwrap(reloaded as? [String: Any])
        XCTAssertEqual(reloadedState["katex"] as? Int, 3, "\(reloadedState)")
        XCTAssertEqual(reloadedState["errors"] as? Int, 0, "\(reloadedState)")
    }

    /// Real Reveal.js slides (`ppt.html`) load KaTeX's bundled `mhchem`
    /// extension in order (`katex` -> `mhchem` -> `auto-render`), render `\ce`
    /// and `\pu` formulas offline, and leave raw HTML `<code>` examples untouched.
    @MainActor
    func testPPTRendersMhchemChemistry() async throws {
        let pptMarkdown = #"""
            Example: <code>$\ce{H2O}$</code>. Rendered: $\ce{H2O}$ and $\pu{123 kJ/mol}$.

            $$
            \ce{2H2 + O2 -> 2H2O}
            $$

            $$
            \ce{Hg^2+ ->[I-] HgI2 ->[I-] [Hg^{II}I4]^2-}
            $$
            """#
        let pptURL = try writePPTPage(markdown: pptMarkdown, named: "mhchem-ppt")
        let pptWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: WKWebViewConfiguration())
        pptWebView.loadFileURL(pptURL, allowingReadAccessTo: tempDirectory)
        let pptProbe = """
            (() => ({
                katex: document.querySelectorAll('.katex').length,
                codeKatex: document.querySelectorAll('code .katex').length,
                codeText: Array.from(document.querySelectorAll('code'), (c) => c.textContent),
                errors: document.querySelectorAll('.katex-error').length,
                rawPu: document.body.innerText.includes('\\\\pu{'),
                scripts: Array.from(document.scripts, (s) => s.getAttribute('src') || '')
            }))()
            """
        let pptDeadline = Date().addingTimeInterval(10)
        var pptState: [String: Any] = [:]
        while Date() < pptDeadline {
            if (try? await pptWebView.evaluateJavaScript("window.__miaoyanMathDone === true") as? Bool) == true {
                pptState = (try? await pptWebView.evaluateJavaScript(pptProbe) as? [String: Any]) ?? [:]
                if (pptState["katex"] as? Int) == 4 { break }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(pptState["katex"] as? Int, 4, "\(pptState)")
        XCTAssertEqual(pptState["codeKatex"] as? Int, 0, "\(pptState)")
        XCTAssertEqual(pptState["codeText"] as? [String], [#"\ce{H2O}"#].map { "$\($0)$" }, "\(pptState)")
        XCTAssertEqual(pptState["errors"] as? Int, 0, "\(pptState)")
        XCTAssertEqual(pptState["rawPu"] as? Bool, false, "\(pptState)")
        let scripts = try XCTUnwrap(pptState["scripts"] as? [String])
        let katexIdx = try XCTUnwrap(scripts.firstIndex(of: "js/katex.min.js"), "\(scripts)")
        let mhchemIdx = try XCTUnwrap(scripts.firstIndex(of: "js/mhchem.min.js"), "\(scripts)")
        let autoRenderIdx = try XCTUnwrap(scripts.firstIndex(of: "js/auto-render.min.js"), "\(scripts)")
        XCTAssertLessThan(katexIdx, mhchemIdx)
        XCTAssertLessThan(mhchemIdx, autoRenderIdx)
    }

    /// Slides and the PPT export render the raw markdown in the page, so
    /// `PreviewMedia.relayedYouTubeFrames` never saw their frames and a
    /// YouTube embed showed Error 153. Every real frame, also one reveal
    /// loads from `data-src` later, now points at the relay; a frame written
    /// in a code fence stays text.
    @MainActor
    func testPPTSendsYouTubeFramesThroughTheRelay() async throws {
        let markdown = #"""
            <iframe src="https://www.youtube.com/watch?v=FCKJL-mTncY&t=90s" width="800" height="450"></iframe>

            ---

            <iframe data-src="https://youtu.be/FCKJL-mTncY" width="800" height="450"></iframe>

            <iframe src="https://player.bilibili.com/player.html?bvid=BV1"></iframe>

            ```html
            <iframe src="https://youtu.be/FCKJL-mTncY"></iframe>
            ```
            """#
        let url = try writePPTPage(markdown: markdown, named: "youtube-ppt")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: WKWebViewConfiguration())
        webView.loadFileURL(url, allowingReadAccessTo: tempDirectory)
        let probe = """
            (() => ({
                frames: Array.from(document.querySelectorAll('.slides iframe'), (f) => f.getAttribute('src') || f.getAttribute('data-src') || ''),
                code: Array.from(document.querySelectorAll('.slides pre code'), (c) => c.textContent).join('\\n')
            }))()
            """
        var state: [String: Any] = [:]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if (try? await webView.evaluateJavaScript("window.__miaoyanMathDone === true") as? Bool) == true {
                state = (try? await webView.evaluateJavaScript(probe) as? [String: Any]) ?? [:]
                if (state["frames"] as? [String])?.count == 3 { break }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let relay = PreviewMedia.youTubeRelay
        XCTAssertEqual(
            state["frames"] as? [String], ["\(relay)?v=FCKJL-mTncY&start=90", "\(relay)?v=FCKJL-mTncY", "https://player.bilibili.com/player.html?bvid=BV1"],
            "\(state)")
        XCTAssertTrue((state["code"] as? String)?.contains(#"<iframe src="https://youtu.be/FCKJL-mTncY"></iframe>"#) == true, "\(state)")

        // Reveal sets `src` again as a slide comes back into view.
        _ = try await webView.evaluateJavaScript("document.querySelector('.slides iframe').setAttribute('src', 'https://youtu.be/FCKJL-mTncY?t=5'); true")
        let reloaded = try await webView.evaluateJavaScript("document.querySelector('.slides iframe').getAttribute('src')")
        XCTAssertEqual(reloaded as? String, "\(relay)?v=FCKJL-mTncY&start=5")
    }

    /// `ppt.html` loaded `js/index.js`, which a4599830 removed (2025-10-10,
    /// before V2.1.2) when its code moved to `js/common.js`. With no
    /// `MiaoYanCommon` the page's three setup scripts threw, and the
    /// DOMContentLoaded one stopped at `optimizeImages`, before the diagram
    /// setup after it. Slides now load `common.js`, and the markmap that
    /// another path already drew is still drawn once.
    @MainActor
    func testPPTLoadsItsCommonScript() async throws {
        let markdown = """
            # Tasks

            - [x] done
            - [ ] open

            ![](data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7)

            ---

            ```markmap
            # Root
            - one
            - two
            ```
            """
        let url = try writePPTPage(markdown: markdown, named: "common-ppt")
        try capturePageErrors(in: url)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: WKWebViewConfiguration())
        webView.loadFileURL(url, allowingReadAccessTo: tempDirectory)
        let probe = """
            (() => ({
                common: typeof MiaoYanCommon,
                eagerImages: document.querySelectorAll('.slides img[loading=eager]').length,
                markmaps: document.querySelectorAll('.slides svg.markmap').length,
                errors: window.__miaoyanErrors
            }))()
            """
        var state: [String: Any] = [:]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if (try? await webView.evaluateJavaScript("window.__miaoyanMathDone === true") as? Bool) == true {
                state = (try? await webView.evaluateJavaScript(probe) as? [String: Any]) ?? [:]
                if state["common"] as? String == "object", (state["markmaps"] as? Int ?? 0) > 0 { break }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(state["common"] as? String, "object", "\(state)")
        XCTAssertEqual(state["eagerImages"] as? Int, 1, "optimizeImages ran: \(state)")
        XCTAssertEqual(state["markmaps"] as? Int, 1, "\(state)")
        XCTAssertEqual(state["errors"] as? [String], [], "\(state)")
    }

    /// A ```mermaid slide showed Mermaid's "Syntax error in text": reveal
    /// writes the block as `code.mermaid`, which DiagramHandler's
    /// `.language-mermaid` never matched, so Mermaid's own start-on-load drew
    /// it from the markup highlight.js had split into spans, in its default
    /// palette. The slide now draws from the source in the preview's palette,
    /// light and dark and in the print layout the PDF export reloads into,
    /// and a PlantUML block gets its image address (the image itself comes
    /// from the PlantUML server, so it is not loaded here).
    @MainActor
    func testPPTDrawsMermaidFromItsSource() async throws {
        let markdown = """
            ```mermaid
            graph TD
              A[Start] --> B[End]
            ```

            ---

            ```plantuml
            @startuml
            Alice -> Bob: hello
            @enduml
            ```

            ---

            ```markmap
            # Root
            - one
            ```
            """
        var fills: [String] = []
        for (theme, exporting) in [("lightmode", false), ("darkmode", false), ("lightmode", true)] {
            let url = try writePPTPage(markdown: markdown, named: "mermaid-ppt-\(theme)-\(exporting)")
            var page = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "CUSTOM_CSS", with: theme)
            if exporting { page = page.replacingOccurrences(of: "var exportType = '';", with: "var exportType = 'ppt';") }
            try page.write(to: url, atomically: true, encoding: .utf8)
            try capturePageErrors(in: url)
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: WKWebViewConfiguration())
            webView.loadFileURL(url, allowingReadAccessTo: tempDirectory)
            let probe = """
                (() => {
                    const code = document.querySelector('.slides pre code.mermaid');
                    const svg = code && code.querySelector('svg');
                    const node = svg && svg.querySelector('.node rect');
                    const plantuml = document.querySelector('.slides img.plantuml-image');
                    return {
                        svg: !!svg,
                        role: svg ? (svg.getAttribute('aria-roledescription') || '') : '',
                        syntaxError: document.querySelector('.slides').textContent.includes('Syntax error'),
                        highlighted: Array.from(document.querySelectorAll('.slides pre code.hljs'), (c) => c.className),
                        nodeFill: node ? getComputedStyle(node).fill : '',
                        dark: document.documentElement.classList.contains('darkmode'),
                        plantuml: plantuml ? plantuml.getAttribute('src') : '',
                        markmaps: document.querySelectorAll('.slides svg.markmap').length,
                        printing: location.search.includes('print-pdf'),
                        errors: window.__miaoyanErrors
                    };
                })()
                """
            var state: [String: Any] = [:]
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                if (try? await webView.evaluateJavaScript("window.__miaoyanMathDone === true") as? Bool) == true {
                    state = (try? await webView.evaluateJavaScript(probe) as? [String: Any]) ?? [:]
                    if state["svg"] as? Bool == true, !(state["nodeFill"] as? String ?? "").isEmpty { break }
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertEqual(state["svg"] as? Bool, true, "\(theme): \(state)")
            XCTAssertNotEqual(state["role"] as? String, "error", "\(theme): \(state)")
            XCTAssertEqual(state["syntaxError"] as? Bool, false, "\(theme): \(state)")
            XCTAssertEqual(state["highlighted"] as? [String], [], "diagram sources are not highlighted: \(state)")
            XCTAssertEqual(state["dark"] as? Bool, theme == "darkmode", "\(state)")
            XCTAssertEqual(state["printing"] as? Bool, exporting, "\(state)")
            XCTAssertTrue((state["plantuml"] as? String)?.hasPrefix("https://www.plantuml.com/plantuml/svg/~1") == true, "\(theme): \(state)")
            XCTAssertEqual(state["markmaps"] as? Int, 1, "\(theme): \(state)")
            let scriptErrors = (state["errors"] as? [String])?.filter { !$0.hasPrefix("load https://www.plantuml.com/") }
            XCTAssertEqual(scriptErrors, [], "\(theme): \(state)")
            fills.append(state["nodeFill"] as? String ?? "")
        }
        // Mermaid's own default node fill is #ECECFF; the slides take the
        // preview's warm palette, a different one in dark, the same in print.
        XCTAssertFalse(fills.contains("rgb(236, 236, 255)"), "\(fills)")
        XCTAssertNotEqual(fills[0], fills[1], "\(fills)")
        XCTAssertEqual(fills[0], fills[2], "\(fills)")
    }

    /// Records every error the page meets, a script or stylesheet that failed
    /// to load included, before any of its own scripts run.
    private func capturePageErrors(in url: URL) throws {
        let capture = """
            <script>
            window.__miaoyanErrors = [];
            window.addEventListener('error', function (event) {
              var target = event.target;
              if (target && target !== window && (target.src || target.href)) {
                window.__miaoyanErrors.push('load ' + (target.src || target.href));
              } else {
                window.__miaoyanErrors.push((event.filename || '') + ': ' + event.message);
              }
            }, true);
            var miaoyanConsoleError = console.error;
            console.error = function () {
              window.__miaoyanErrors.push('console ' + Array.prototype.join.call(arguments, ' '));
              return miaoyanConsoleError.apply(console, arguments);
            };
            </script>
            """
        let page = try String(contentsOf: url, encoding: .utf8)
        try page.replacingOccurrences(of: "<head>", with: "<head>" + capture).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Malformed mhchem inputs such as `\ce{A \bond{} B}` (`MhchemBugT`) or
    /// `\ce{A ->[\}] B}` (`ExtraCloseMissingOpen`) throw raw arrays instead of
    /// `katex.ParseError`. Both preview and slides must keep those formulas as
    /// raw text and continue rendering every subsequent formula on the page.
    @MainActor
    func testMalformedMhchemBondDoesNotBlockSubsequentMath() async throws {
        let markdown = #"""
            First $a^2$.

            Typing $\ce{A \bond{} B}$.

            Brace error $\ce{A ->[\}] B}$.

            Later $E=mc^2$.
            """#
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: markdown, useGithubLineBreak: false))
        let previewURL = try writeIndexPage(bodyHTML: html, named: "mhchem-malformed-preview")
        let previewWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: WKWebViewConfiguration())
        previewWebView.loadFileURL(previewURL, allowingReadAccessTo: tempDirectory)

        let previewProbe = """
            (() => ({
                katex: document.querySelectorAll('#write .katex').length,
                errors: document.querySelectorAll('#write .katex-error').length,
                hasRawBond: document.getElementById('write').innerText.includes('\\\\bond{}'),
                hasRawBrace: document.getElementById('write').innerText.includes('\\\\}]'),
                hasRawLater: document.getElementById('write').innerText.includes('$E=mc^2$')
            }))()
            """
        let previewDeadline = Date().addingTimeInterval(10)
        var previewState: [String: Any] = [:]
        while Date() < previewDeadline {
            previewState = (try? await previewWebView.evaluateJavaScript(previewProbe) as? [String: Any]) ?? [:]
            if (previewState["katex"] as? Int) == 2 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(previewState["katex"] as? Int, 2, "\(previewState)")
        XCTAssertEqual(previewState["errors"] as? Int, 0, "\(previewState)")
        XCTAssertEqual(previewState["hasRawBond"] as? Bool, true, "\(previewState)")
        XCTAssertEqual(previewState["hasRawBrace"] as? Bool, true, "\(previewState)")
        XCTAssertEqual(previewState["hasRawLater"] as? Bool, false, "\(previewState)")

        let pptURL = try writePPTPage(markdown: markdown, named: "mhchem-malformed-ppt")
        let pptWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: WKWebViewConfiguration())
        pptWebView.loadFileURL(pptURL, allowingReadAccessTo: tempDirectory)
        let pptProbe = """
            (() => ({
                katex: document.querySelectorAll('.katex').length,
                errors: document.querySelectorAll('.katex-error').length,
                hasRawBond: document.body.innerText.includes('\\\\bond{}'),
                hasRawBrace: document.body.innerText.includes('\\\\}]'),
                hasRawLater: document.body.innerText.includes('$E=mc^2$')
            }))()
            """
        let pptDeadline = Date().addingTimeInterval(10)
        var pptState: [String: Any] = [:]
        while Date() < pptDeadline {
            if (try? await pptWebView.evaluateJavaScript("window.__miaoyanMathDone === true") as? Bool) == true {
                pptState = (try? await pptWebView.evaluateJavaScript(pptProbe) as? [String: Any]) ?? [:]
                if (pptState["katex"] as? Int) == 2 { break }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(pptState["katex"] as? Int, 2, "\(pptState)")
        XCTAssertEqual(pptState["errors"] as? Int, 0, "\(pptState)")
        XCTAssertEqual(pptState["hasRawBond"] as? Bool, true, "\(pptState)")
        XCTAssertEqual(pptState["hasRawBrace"] as? Bool, true, "\(pptState)")
        XCTAssertEqual(pptState["hasRawLater"] as? Bool, false, "\(pptState)")
    }

    /// If `js/mhchem.min.js` is absent (e.g. stale cache or older CDN copy),
    /// PPT math must still degrade gracefully and render standard LaTeX.
    @MainActor
    func testPPTStandardMathDegradesGracefullyWithoutMhchem() async throws {
        let degradedDir = tempDirectory.appendingPathComponent("degraded-ppt", isDirectory: true)
        let degradedJS = degradedDir.appendingPathComponent("js", isDirectory: true)
        try FileManager.default.createDirectory(at: degradedJS, withIntermediateDirectories: true)
        for directory in ["css", "ppt", "themes"] {
            try FileManager.default.createSymbolicLink(
                at: degradedDir.appendingPathComponent(directory),
                withDestinationURL: downViewBundleURL.appendingPathComponent(directory))
        }
        for jsFile in try FileManager.default.contentsOfDirectory(atPath: downViewBundleURL.appendingPathComponent("js").path) where jsFile != "mhchem.min.js" {
            try FileManager.default.createSymbolicLink(
                at: degradedJS.appendingPathComponent(jsFile),
                withDestinationURL: downViewBundleURL.appendingPathComponent("js/\(jsFile)"))
        }
        let degradedTemplate = try String(contentsOf: downViewBundleURL.appendingPathComponent("ppt.html"), encoding: .utf8)
        let degradedPage = HtmlManager.applyTemplateReplacements(
            degradedTemplate,
            replacements: [
                "DOWN_RAW": HtmlManager.prepareMarkdownForPPT("Energy $E = mc^2$."),
                "DOWN_THEME": "",
                "DOWN_CSS": "",
                "DOWN_FONT_PATH": ".",
                "DOWN_EXPORT_TYPE": "",
            ]
        )
        let degradedURL = degradedDir.appendingPathComponent("degraded.html")
        try degradedPage.write(to: degradedURL, atomically: true, encoding: .utf8)
        let degradedWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: WKWebViewConfiguration())
        degradedWebView.loadFileURL(degradedURL, allowingReadAccessTo: tempDirectory)
        let degradedDeadline = Date().addingTimeInterval(10)
        var degradedCount = 0
        while Date() < degradedDeadline {
            degradedCount = (try? await degradedWebView.evaluateJavaScript("document.querySelectorAll('.katex').length") as? Int) ?? 0
            if degradedCount == 1 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(degradedCount, 1, "standard PPT math must still render when mhchem.min.js is unavailable")
    }

    private func writeIndexPage(bodyHTML: String, named: String, extraBodyScript: String = "") throws -> URL {
        let template = try String(contentsOf: downViewBundleURL.appendingPathComponent("index.html"), encoding: .utf8)
        var page = HtmlManager.applyTemplateReplacements(
            template,
            replacements: [
                "DOWN_META": "",
                "DOWN_CSS": "",
                "CUSTOM_CSS": "lightmode",
                "DOWN_HTML": bodyHTML,
            ]
        )
        if !extraBodyScript.isEmpty {
            page = page.replacingOccurrences(of: "</body>", with: extraBodyScript + "</body>")
        }
        return try write(page: page, named: named)
    }

    /// Markmap's branches take the family palette from theme-config.js, and a
    /// change of appearance draws the map again in the other palette; the
    /// patched render() used to draw twelve stock colours of its own.
    @MainActor
    func testMarkmapBranchesUseTheFamilyPaletteAndFollowTheAppearance() async throws {
        let webView = try loadMarkmapPage()
        let light = try await settledMarkmapLinkColours(webView, differentFrom: nil)
        XCTAssertEqual(light["1"], "#5E3DB3", "\(light)")
        XCTAssertEqual(light["2"], "#24837B", "\(light)")
        XCTAssertEqual(light["3"], "#9A7400", "\(light)")

        _ = try await webView.evaluateJavaScript("window.__dark = true; DiagramHandler.retheme(); true")
        let dark = try await settledMarkmapLinkColours(webView, differentFrom: light)
        XCTAssertEqual(dark["1"], "#8E6AD9", "\(dark)")
        XCTAssertEqual(dark["2"], "#58D8AD", "\(dark)")
        let maps = try await webView.evaluateJavaScript(
            "[document.querySelectorAll('.language-markmap svg').length, document.querySelector('.language-markmap').textContent.includes('Root')]")
        let state = try XCTUnwrap(maps as? [Any])
        XCTAssertEqual(state.first as? Int, 1, "one map after the redraw")
        XCTAssertEqual(state.last as? Bool, true, "the redraw starts from the note's source")
    }

    /// A page off screen (the PDF export's window, a preview behind other
    /// windows) gets no animation frames. The handler waited on two of them
    /// before drawing and d3 steps Markmap's transitions on them, so mind maps
    /// stayed blank in PDF and PNG exports; frame-fallback.js runs them from a
    /// timer there. The export's readiness check must not pass before the map
    /// has finished drawing, read here at the first moment it passes.
    @MainActor
    func testMarkmapDrawsAndShowsWithoutAnimationFrames() async throws {
        let webView = try loadMarkmapPage(standInFrames: false)
        let ready = try await waitForMarkmap(webView, every: 30_000_000) { $0["pending"] as? Int == 0 }
        XCTAssertEqual(ready["pending"] as? Int, 0, "\(ready)")
        XCTAssertEqual(ready["visible"] as? String, "visible", "\(ready)")
        XCTAssertEqual(ready["nodes"] as? Int, 4, "\(ready)")
        XCTAssertEqual(ready["settledLinks"] as? Int, 3, "links at their full width when the export may start: \(ready)")
        XCTAssertEqual(ready["opaqueLabels"] as? Int, 4, "labels faded in when the export may start: \(ready)")
    }

    /// The PDF export prints the preview's own HTML, maps already drawn.
    /// Markmap's loader, left automatic, redrew every `.markmap` element from
    /// the text of its SVG, so the PDF showed an empty box where the preview
    /// had a map. A map saved before it settled is drawn again from its source
    /// rather than holding the export until its wait runs out.
    @MainActor
    func testADrawnMarkmapSurvivesThePageBeingLoadedAgain() async throws {
        let first = try loadMarkmapPage(standInFrames: false)
        let drawn = try await waitForMarkmap(first) { $0["pending"] as? Int == 0 }
        XCTAssertEqual(drawn["settledLinks"] as? Int, 3, "\(drawn)")
        let savedHTML = try await first.evaluateJavaScript("document.querySelector('pre').outerHTML")
        let saved = try XCTUnwrap(savedHTML as? String)
        XCTAssertTrue(saved.contains("data-markmap-shown=\"true\""), saved)

        let second = try loadMarkmapPage(standInFrames: false, body: saved)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let reloaded = try await waitForMarkmap(second) { _ in true }
        XCTAssertEqual(reloaded["pending"] as? Int, 0, "\(reloaded)")
        XCTAssertEqual(reloaded["visible"] as? String, "visible", "\(reloaded)")
        XCTAssertEqual(reloaded["svgs"] as? Int, 1, "\(reloaded)")
        XCTAssertEqual(reloaded["nodes"] as? Int, 4, "the saved map, not one drawn from its SVG's text: \(reloaded)")
        XCTAssertEqual(reloaded["settledLinks"] as? Int, 3, "\(reloaded)")

        let unsettled = saved.replacingOccurrences(of: " data-markmap-shown=\"true\"", with: "")
        let third = try loadMarkmapPage(standInFrames: false, body: unsettled)
        let redrawn = try await waitForMarkmap(third) { $0["pending"] as? Int == 0 }
        XCTAssertEqual(redrawn["pending"] as? Int, 0, "a half-drawn map holds the export up: \(redrawn)")
        XCTAssertEqual(redrawn["svgs"] as? Int, 1, "\(redrawn)")
        XCTAssertEqual(redrawn["nodes"] as? Int, 4, "\(redrawn)")
        XCTAssertEqual(redrawn["settledLinks"] as? Int, 3, "\(redrawn)")
    }

    /// Reads the page's map until `done` holds or ten seconds pass. A link is
    /// settled at markmap's final width for its depth, a label once its fade
    /// has reached full opacity.
    @MainActor
    private func waitForMarkmap(
        _ webView: WKWebView, every interval: UInt64 = 200_000_000, until done: ([String: Any]) -> Bool
    ) async throws -> [String: Any] {
        let probe = """
            (() => {
              const code = document.querySelector('code.language-markmap');
              if (!code) return {};
              return {
                pending: \(HtmlManager.pendingDiagramsExpression),
                visible: getComputedStyle(code).visibility,
                svgs: code.querySelectorAll('svg').length,
                nodes: code.querySelectorAll('g.markmap-node').length,
                settledLinks: Array.from(code.querySelectorAll('path.markmap-link')).filter((p) =>
                  Number(p.getAttribute('stroke-width')) === Math.max(4 - 2 * Number(p.getAttribute('data-depth')), 1.5)).length,
                opaqueLabels: Array.from(code.getElementsByTagName('foreignObject'))
                  .filter((f) => Number(f.style.opacity || 0) === 1).length
              };
            })()
            """
        var last: [String: Any] = [:]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            last = (try? await webView.evaluateJavaScript(probe) as? [String: Any]) ?? [:]
            if !last.isEmpty, done(last) { break }
            try await Task.sleep(nanoseconds: interval)
        }
        return last
    }

    /// A page shaped like index.html: frame-fallback.js ahead of d3, and the
    /// markmap loader settings index.html sets, read from the file itself.
    @MainActor
    private func loadMarkmapPage(standInFrames: Bool = true, body: String? = nil) throws -> WKWebView {
        let js = downViewBundleURL.appendingPathComponent("js", isDirectory: true)
        let scripts = ["frame-fallback.js", "d3.min.js", "markmap.min.js", "markmap-view.min.js", "theme-config.js", "diagram-handler.js"]
            .map { "<script src=\"\(js.appendingPathComponent($0).absoluteString)\"></script>" }
            .joined()
        let index = try String(contentsOf: downViewBundleURL.appendingPathComponent("index.html"), encoding: .utf8)
        let loaderSettings = index.components(separatedBy: "\n")
            .filter { $0.contains("<script>window.markmap") }
            .joined(separator: "\n")
        // The palette test steps frames on timers of its own; the others run
        // on what an offscreen page gets, which is no animation frames.
        let frames = standInFrames ? "window.requestAnimationFrame = (cb) => setTimeout(() => cb(performance.now()), 16);" : ""
        let note = """
            <pre><code class="language-markmap">- Root
              - One
                - Two
                  - Three</code></pre>
            """
        let content = body ?? note
        let page = """
            <!doctype html><html><head><meta charset="utf-8"><script>
            \(frames)
            window.ThemeConfig = { isDarkMode: () => window.__dark === true };
            </script>
            \(loaderSettings)
            \(scripts)
            </head><body>\(content)
            <script>window.addEventListener('load', () => DiagramHandler.initializeMarkmap());</script>
            </body></html>
            """
        let url = try write(page: page, named: body == nil ? "markmap" : "markmap-saved")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: WKWebViewConfiguration())
        webView.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        return webView
    }

    /// Link colours by depth once two reads agree, so the transitions have ended.
    @MainActor
    private func settledMarkmapLinkColours(_ webView: WKWebView, differentFrom earlier: [String: String]?) async throws -> [String: String] {
        let probe = """
            (() => {
              const hex = (rgb) => '#' + (rgb.match(/\\d+/g) || []).slice(0, 3)
                .map((n) => Number(n).toString(16).padStart(2, '0')).join('').toUpperCase();
              const out = {};
              document.querySelectorAll('path.markmap-link').forEach((p) => {
                if (p.getAttribute('stroke')) out[p.getAttribute('data-depth')] = hex(getComputedStyle(p).stroke);
              });
              return Object.keys(out).length >= 3 ? out : null;
            })()
            """
        var previous: [String: String]?
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let colours = try? await webView.evaluateJavaScript(probe) as? [String: String]
            if let colours, colours == previous, colours != earlier { return colours }
            previous = colours
            try await Task.sleep(nanoseconds: 400_000_000)
        }
        XCTFail("Timed out waiting for Markmap links, last read \(String(describing: previous))")
        return [:]
    }

    /// Ids stay the headings' own text, and a link written for GitHub
    /// (`#getting-started`) finds its heading by GitHub's slug as well
    /// (maintainer, 2026-11-21).
    @MainActor
    func testAGitHubSlugLinkFindsItsHeading() async throws {
        let markdown = """
            [a](#getting-started) [b](#api-v2--more) [c](#notes-1) [d](#Getting%20Started) [e](#missing) [f](#notes-1-1)

            # Getting Started

            ## API (v2) & More!

            ## Notes

            ## Notes

            ## Notes-1
            """
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: markdown, useGithubLineBreak: true))
        let common = downViewBundleURL.appendingPathComponent("js/common.js").absoluteString
        let page = try write(
            page: """
                <!doctype html><html><head><meta charset="utf-8"></head><body><div id="write">\(html)</div>
                <script src="\(common)"></script><script>
                window.__scrolled = [];
                Element.prototype.scrollIntoView = function () { window.__scrolled.push(this.id); };
                MiaoYanCommon.setupHeaderAnchors();
                window.__ready = true;
                </script></body></html>
                """, named: "anchors")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: WKWebViewConfiguration())
        webView.loadFileURL(page, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        let deadline = Date().addingTimeInterval(10)
        while (try? await webView.evaluateJavaScript("window.__ready === true") as? Bool) != true, Date() < deadline {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        let result = try await webView.evaluateJavaScript(
            """
            document.querySelectorAll('#write p a').forEach((a) => a.click());
            JSON.stringify({ scrolled: window.__scrolled,
              ids: Array.from(document.querySelectorAll('h1, h2')).map((h) => h.id) })
            """)
        let json = try XCTUnwrap((result as? String)?.data(using: .utf8))
        let state = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: [String]])
        XCTAssertEqual(state["ids"], ["Getting Started", "API (v2) & More!", "Notes", "Notes-1", "Notes-1-1"], "ids are the headings' text")
        XCTAssertEqual(
            state["scrolled"], ["Getting Started", "API (v2) & More!", "Notes-1", "Getting Started", "Notes-1-1"],
            "a heading that already reads Notes-1 takes notes-1-1, as github-slugger does")
    }

    /// A display formula starts 1.5em in from the text, where a bulleted
    /// list's text starts, not in the middle of the column (maintainer's
    /// pick, 2026-11-21); the iPhone reader holds the same rule.
    @MainActor
    func testADisplayFormulaStartsAtTheListIndent() async throws {
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: "Text\n\n$$\nx = 1\n$$\n\n- item", useGithubLineBreak: true))
        let css = downViewBundleURL.appendingPathComponent("css", isDirectory: true)
        let js = downViewBundleURL.appendingPathComponent("js", isDirectory: true)
        let page = try write(
            page: """
                <!doctype html><html><head><meta charset="utf-8">
                <link rel="stylesheet" href="\(css.appendingPathComponent("katex.min.css").absoluteString)">
                <link rel="stylesheet" href="\(css.appendingPathComponent("typography.css").absoluteString)">
                <link rel="stylesheet" href="\(css.appendingPathComponent("base.css").absoluteString)">
                <script src="\(js.appendingPathComponent("katex.min.js").absoluteString)"></script>
                <script src="\(js.appendingPathComponent("auto-render.min.js").absoluteString)"></script>
                </head><body><div id="write" class="heti">\(html)</div><script>
                renderMathInElement(document.getElementById('write'), { delimiters: [{left: '$$', right: '$$', display: true}] });
                window.__ready = true;
                </script></body></html>
                """, named: "display-indent")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: WKWebViewConfiguration())
        webView.loadFileURL(page, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        let deadline = Date().addingTimeInterval(10)
        while (try? await webView.evaluateJavaScript("window.__ready === true && !!document.querySelector('.katex-display')") as? Bool) != true,
            Date() < deadline
        {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        let result = try await webView.evaluateJavaScript(
            """
            (() => {
              const math = document.querySelector('.katex-display .base').getBoundingClientRect().left;
              const text = document.querySelector('#write p').getBoundingClientRect().left;
              const item = document.querySelector('#write li');
              const range = document.createRange(); range.selectNodeContents(item);
              return JSON.stringify({ math: math - text, item: range.getBoundingClientRect().left - text });
            })()
            """)
        let json = try XCTUnwrap((result as? String)?.data(using: .utf8))
        let offsets = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Double])
        let math = try XCTUnwrap(offsets["math"])
        let item = try XCTUnwrap(offsets["item"])
        XCTAssertGreaterThan(math, 0, "\(offsets)")
        XCTAssertEqual(math, item, accuracy: 1, "the formula starts where the list's text starts: \(offsets)")
    }

    /// #write is overflow-x: hidden and KaTeX sets a formula nowrap, so a
    /// formula wider than the page was cut off with nothing to scroll. It
    /// scrolls inside its own line now, and the padding that lets it scroll
    /// does not clip an ordinary tall formula.
    @MainActor
    func testAWideDisplayFormulaScrollsAndATallOneIsNotClipped() async throws {
        let wide = (0..<60).map { "a_{\($0)}" }.joined(separator: " + ")
        let markdown = "$$\n\(wide)\n$$\n\n$$\n\\sum_{i=1}^{n} \\int_0^1 \\frac{x^i}{\\sqrt{1+x}} dx \\tag{1}\n$$"
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: markdown, useGithubLineBreak: true))
        let css = downViewBundleURL.appendingPathComponent("css", isDirectory: true)
        let js = downViewBundleURL.appendingPathComponent("js", isDirectory: true)
        let page = try write(
            page: """
                <!doctype html><html><head><meta charset="utf-8">
                <link rel="stylesheet" href="\(css.appendingPathComponent("katex.min.css").absoluteString)">
                <link rel="stylesheet" href="\(css.appendingPathComponent("typography.css").absoluteString)">
                <link rel="stylesheet" href="\(css.appendingPathComponent("base.css").absoluteString)">
                <script src="\(js.appendingPathComponent("katex.min.js").absoluteString)"></script>
                <script src="\(js.appendingPathComponent("auto-render.min.js").absoluteString)"></script>
                </head><body><div id="write" class="heti">\(html)</div><script>
                renderMathInElement(document.getElementById('write'), { delimiters: [{left: '$$', right: '$$', display: true}] });
                window.__ready = true;
                </script></body></html>
                """, named: "display-scroll")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: WKWebViewConfiguration())
        webView.loadFileURL(page, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        let deadline = Date().addingTimeInterval(10)
        while (try? await webView.evaluateJavaScript("window.__ready === true && document.querySelectorAll('.katex-display').length === 2") as? Bool) != true,
            Date() < deadline
        {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        let result = try await webView.evaluateJavaScript(
            """
            (() => JSON.stringify(Array.from(document.querySelectorAll('.katex-display')).map(d => ({
              overflowX: getComputedStyle(d).overflowX,
              scrollWidth: d.scrollWidth, clientWidth: d.clientWidth,
              scrollHeight: d.scrollHeight, clientHeight: d.clientHeight
            }))))()
            """)
        let json = try XCTUnwrap((result as? String)?.data(using: .utf8))
        let rows = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [[String: Any]])
        XCTAssertEqual(rows.count, 2)
        let wideRow = try XCTUnwrap(rows.first)
        XCTAssertEqual(wideRow["overflowX"] as? String, "auto", "\(wideRow)")
        XCTAssertGreaterThan(try XCTUnwrap(wideRow["scrollWidth"] as? Int), try XCTUnwrap(wideRow["clientWidth"] as? Int), "\(wideRow)")
        for row in rows {
            XCTAssertLessThanOrEqual(try XCTUnwrap(row["scrollHeight"] as? Int), try XCTUnwrap(row["clientHeight"] as? Int) + 1, "clipped: \(row)")
        }
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

    private func writePPTPage(markdown: String = nestedUnderbraceFormula, named: String = "ppt") throws -> URL {
        let prepared = HtmlManager.prepareMarkdownForPPT(markdown)
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
        return try write(page: page, named: named)
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

    /// CommonMark allows up to three spaces before `#` and `1)` as an
    /// ordered-list marker; the preview renders both, the editor coloured
    /// neither.
    @MainActor
    func testEditorHighlightsIndentedHeadingsAndParenthesisLists() {
        func matches(_ regex: MarklightRegex, _ line: String) -> Bool {
            var found = false
            regex.matches(line, range: NSRange(location: 0, length: (line as NSString).length)) { if $0 != nil { found = true } }
            return found
        }
        for line in [" # Title", "   ### Title"] {
            XCTAssertTrue(matches(NotesTextProcessor.headersAtxRegex, line), line)
            XCTAssertTrue(matches(NotesTextProcessor.headersAtxOpeningRegex, line), line)
        }
        XCTAssertFalse(matches(NotesTextProcessor.headersAtxRegex, "    # code"))
        XCTAssertTrue(matches(NotesTextProcessor.listRegex, "1) first"))
        XCTAssertTrue(matches(NotesTextProcessor.listRegex, "  12) twelfth"))
        XCTAssertTrue(matches(NotesTextProcessor.listOpeningRegex, "1) first"))
        XCTAssertFalse(matches(NotesTextProcessor.listRegex, "1)glued"))
    }
}
