import JavaScriptCore
import WebKit
import XCTest

@testable import MiaoYan

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

    func testTemplatePlaceholdersInsideNoteTextStayAsWritten() {
        let template = "<style>DOWN_CSS</style><body class=\"CUSTOM_CSS\">DOWN_HTML</body>"
        let replacements = ["DOWN_CSS": "p{}", "CUSTOM_CSS": "lightmode", "DOWN_HTML": "<p>write CUSTOM_CSS and DOWN_CSS here</p>"]
        for _ in 0..<20 {
            XCTAssertEqual(
                HtmlManager.applyTemplateReplacements(template, replacements: replacements),
                "<style>p{}</style><body class=\"lightmode\"><p>write CUSTOM_CSS and DOWN_CSS here</p></body>")
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
