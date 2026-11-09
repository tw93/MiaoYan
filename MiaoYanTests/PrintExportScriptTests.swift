import AppKit
import WebKit
import XCTest

@testable import MiaoYan

/// PDF export injects its print sheet and title into an offscreen copy of the
/// preview and swaps lazy images back to their files. From V4.3.0 the sheet
/// sat in a template literal whose comments held backticks, so the script
/// never parsed: the PDF had no print styles and every image the reader had
/// not scrolled to printed blank.
@available(macOS 12.0, *)
final class PrintExportScriptTests: XCTestCase {
    private static let placeholder = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiaoYan Print Script Tests \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    @MainActor
    private func loadPage(_ body: String) async throws -> WKWebView {
        let page = """
            <!doctype html><html><head><meta charset="utf-8"></head><body>
            <div id="write">\(body)</div>
            <script>window.__ready = true;</script>
            </body></html>
            """
        let url = directory.appendingPathComponent("page-\(UUID().uuidString).html")
        try page.write(to: url, atomically: true, encoding: .utf8)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        webView.loadFileURL(url, allowingReadAccessTo: directory)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, (try? await webView.evaluateJavaScript("window.__ready === true") as? Bool) != true {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        return webView
    }

    @MainActor
    func testPrintSetupRunsWithTheRealSheetAndUnlazesImages() async throws {
        let real = directory.appendingPathComponent("p2.png").absoluteString
        let webView = try await loadPage(
            "<p><img class=\"lazy-image\" loading=\"lazy\" src=\"\(Self.placeholder)\" data-src=\"\(real)\"></p>")

        let title = "Notes `with` 'quotes', \"doubles\" and ${braces} \\ slash"
        let sheet = HtmlManager.paginatedPrintCSS()
        XCTAssertTrue(sheet.contains("`"), "the real sheet's comments hold backticks, the case that broke")
        let ran = try await webView.evaluateJavaScript(PdfExportController.printSetupScript(css: sheet, title: title)) as? Bool
        XCTAssertEqual(ran, true)

        let state =
            try await webView.evaluateJavaScript(
                """
                (function() {
                    var img = document.querySelector('#write img');
                    var style = document.getElementById('miaoyan-pdf-print-style');
                    return {
                        src: img.getAttribute('src'),
                        lazy: img.classList.contains('lazy-image') || img.hasAttribute('data-src') || img.hasAttribute('loading'),
                        sheet: style ? style.textContent : '',
                        title: document.getElementById('export-generated-title').innerText
                    };
                })();
                """) as? [String: Any]
        XCTAssertEqual(state?["src"] as? String, real)
        XCTAssertEqual(state?["lazy"] as? Bool, false)
        XCTAssertEqual(state?["sheet"] as? String, sheet)
        XCTAssertEqual(state?["title"] as? String, title)
    }

    /// A note that opens with its own heading is not given a second title.
    @MainActor
    func testANoteThatOpensWithAHeadingKeepsItAsTheTitle() async throws {
        let webView = try await loadPage("<h1>Trip</h1><p>Day one.</p>")
        _ = try await webView.evaluateJavaScript(PdfExportController.printSetupScript(css: "", title: "Trip"))
        let titles = try await webView.evaluateJavaScript("document.querySelectorAll('#write h1').length") as? Int
        XCTAssertEqual(titles, 1)
    }

    /// PNG export snapshots the live preview, where a PlantUML diagram is an
    /// image marked loading="lazy" and a Mermaid diagram may still be
    /// drawing. Its check force-loaded only Swift's lazy images, so a
    /// diagram below the view was captured blank or missing.
    @MainActor
    func testImageExportWaitsForLazyDiagramsAsPDFDoes() async throws {
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = directory.appendingPathComponent("diagram.png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: png)
        let webView = try await loadPage(
            """
            <pre><code class="language-mermaid">flowchart LR</code></pre>
            <div style="height: 6000px"></div>
            <pre><img class="plantuml-image" loading="lazy" src="\(png.absoluteString)"></pre>
            """)

        let waiting = try await webView.evaluateJavaScript(HtmlManager.checkImagesScript) as? Bool
        XCTAssertEqual(waiting, false, "a Mermaid diagram still drawing holds the capture")
        _ = try await webView.evaluateJavaScript("document.querySelector('code.language-mermaid').setAttribute('data-processed', 'true'); true")

        var ready = false
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, !ready {
            ready = (try? await webView.evaluateJavaScript(HtmlManager.checkImagesScript) as? Bool) == true
            if !ready { try await Task.sleep(nanoseconds: 50_000_000) }
        }
        XCTAssertTrue(ready, "the PlantUML image below the view loads for the capture")
        let state = try await webView.evaluateJavaScript(
            "(function() { var img = document.querySelector('.plantuml-image'); return img.hasAttribute('loading') + ':' + img.naturalWidth; })()")
        XCTAssertEqual(state as? String, "false:8")
    }

    /// Text carried into a script goes in as `HtmlManager.jsStringLiteral`,
    /// never inside a template literal, where a backtick or `${` in it ends
    /// the string or runs as code, the preview's live update included.
    func testScriptsDoNotInterpolateSwiftTextIntoTemplateLiterals() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let interpolation = try NSRegularExpression(pattern: #"`\\\("#)
        // Markdown.swift names `\( \)` math in a comment; TextFormatter wraps inline code.
        let allowed = ["Business/Markdown.swift": 1, "Helpers/TextFormatter.swift": 1]
        var found: [String: Int] = [:]
        for folder in ["Business", "Controllers", "Extensions", "Helpers", "Shell", "Views"] {
            let files = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            while let url = files?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                let count = interpolation.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
                if count > 0 { found["\(folder)/\(url.lastPathComponent)"] = count }
            }
        }
        XCTAssertEqual(found, allowed)
    }

    /// Loads a body in the real preview page with the print sheet applied and
    /// print media on, so computed styles and layout are what the PDF gets.
    @MainActor
    private func loadPrintedPreview(_ body: String) async throws -> WKWebView {
        let page = try HtmlManager.htmlFromTemplate(body, css: HtmlManager.previewStyle(), currentName: "print")
        let index = try XCTUnwrap(HtmlManager.createTemporaryBundle(pageHTMLString: page))
        let url = index.deletingLastPathComponent().appendingPathComponent("print-\(UUID().uuidString).html")
        try page.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 505, height: 800))
        webView.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline,
            (try? await webView.evaluateJavaScript("document.readyState === 'complete' && !!document.getElementById('write')") as? Bool) != true
        {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        _ = try await webView.evaluateJavaScript(
            PdfExportController.printSetupScript(css: HtmlManager.paginatedPrintCSS(), title: "Print"))
        webView.mediaType = "print"
        return webView
    }

    /// A caption is its own paragraph, as Weekly writes one under its cover.
    /// The preview's -1.2em pull suits its wide paragraph gaps; against print's
    /// 0.6em it laid the caption over the image.
    @MainActor
    func testACaptionPrintsBelowItsImage() async throws {
        let markdown = "<img src=\"\(Self.placeholder)\" style=\"width:200px;height:100px\" />\n\n<small>Caption</small>\n"
        let body = try XCTUnwrap(renderMarkdownHTML(markdown: markdown, useGithubLineBreak: true))
        let webView = try await loadPrintedPreview(body)
        let gap =
            try await webView.evaluateJavaScript(
                """
                (function() {
                    var image = document.querySelector('#write img').getBoundingClientRect();
                    var small = document.querySelector('#write small').getBoundingClientRect();
                    return small.top - image.bottom;
                })();
                """) as? Double
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(gap), 4)
    }

    /// A picture sharing a paragraph with text keeps clear of the line above.
    @MainActor
    func testAPictureAfterTextPrintsClearOfIt() async throws {
        let webView = try await loadPrintedPreview(
            "<p><span id=\"line\">Line above</span><video poster=\"\(Self.placeholder)\" style=\"width:200px;height:100px\"></video></p>")
        let gap =
            try await webView.evaluateJavaScript(
                """
                (function() {
                    var line = document.getElementById('line').getBoundingClientRect();
                    var video = document.querySelector('#write video').getBoundingClientRect();
                    return video.top - line.bottom;
                })();
                """) as? Double
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(gap), 4)
    }

    /// A quote prints as the preview draws it: muted text beside the thin bar,
    /// no tint, light on paper even when the export starts from dark mode.
    @MainActor
    func testAQuotePrintsAsThePreviewDrawsIt() async throws {
        let webView = try await loadPrintedPreview(
            "<blockquote><p>Plain <strong>bold</strong> <code>code</code></p></blockquote><p id=\"body\">Body</p>")
        for dark in [false, true] {
            if dark {
                _ = try await webView.evaluateJavaScript("document.documentElement.classList.add('darkmode'); true")
            }
            let state =
                try await webView.evaluateJavaScript(
                    """
                    (function() {
                        var quote = document.querySelector('#write blockquote');
                        var p = quote.querySelector('p');
                        var bar = getComputedStyle(quote, '::before');
                        var box = quote.getBoundingClientRect();
                        var text = document.createRange();
                        text.selectNodeContents(p);
                        var rect = text.getBoundingClientRect();
                        return {
                            background: getComputedStyle(quote).backgroundColor,
                            radius: getComputedStyle(quote).borderTopLeftRadius,
                            paragraph: getComputedStyle(p).color,
                            strong: getComputedStyle(quote.querySelector('strong')).color,
                            code: getComputedStyle(quote.querySelector('code')).color,
                            body: getComputedStyle(document.getElementById('body')).color,
                            bar: bar.backgroundColor,
                            barTop: box.top + parseFloat(bar.top) - rect.top,
                            barBottom: box.top + parseFloat(bar.top) + parseFloat(bar.height) - rect.bottom
                        };
                    })();
                    """) as? [String: Any]
            let muted = "rgb(106, 98, 86)"
            XCTAssertEqual(state?["background"] as? String, "rgba(0, 0, 0, 0)", "dark: \(dark)")
            XCTAssertEqual(state?["radius"] as? String, "0px", "dark: \(dark)")
            XCTAssertEqual(state?["paragraph"] as? String, muted, "dark: \(dark)")
            XCTAssertEqual(state?["strong"] as? String, muted, "dark: \(dark)")
            XCTAssertEqual(state?["code"] as? String, muted, "dark: \(dark)")
            XCTAssertEqual(state?["body"] as? String, "rgb(38, 35, 29)", "dark: \(dark)")
            XCTAssertEqual(state?["bar"] as? String, "rgb(221, 217, 205)", "dark: \(dark)")
            // The bar starts and stops with the text, as it does on screen.
            XCTAssertEqual(try XCTUnwrap(state?["barTop"] as? Double), 0, accuracy: 3, "dark: \(dark)")
            XCTAssertEqual(try XCTUnwrap(state?["barBottom"] as? Double), 0, accuracy: 3, "dark: \(dark)")
        }
    }

    /// The player's controls printed a play button over the poster, hiding the
    /// picture's own words. A poster stays; a video with no poster loads its
    /// first frame, and one that cannot is hidden, not an empty box.
    @MainActor
    func testVideosPrintAsPicturesWithoutThePlayer() async throws {
        let webView = try await loadPrintedPreview(
            """
            <p><video id="poster" controls poster="\(Self.placeholder)"><source src="file:///no-such.mp4"></video></p>
            <p><video id="dead" controls style="width:400px;height:300px"><source src="file:///no-such.mp4"></video></p>
            """)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline,
            (try? await webView.evaluateJavaScript(PdfExportController.videosSettledExpression) as? Bool) != true
        {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        let settled = try await webView.evaluateJavaScript(PdfExportController.videosSettledExpression) as? Bool
        XCTAssertEqual(settled, true)
        _ = try await webView.evaluateJavaScript(PdfExportController.hideUndrawnVideosScript + " true")
        let state =
            try await webView.evaluateJavaScript(
                """
                (function() {
                    var poster = document.getElementById('poster');
                    var dead = document.getElementById('dead');
                    return {
                        controls: document.querySelectorAll('video[controls]').length,
                        posterShown: getComputedStyle(poster).display !== 'none',
                        deadShown: getComputedStyle(dead).display !== 'none',
                        deadHeight: dead.getBoundingClientRect().height
                    };
                })();
                """) as? [String: Any]
        XCTAssertEqual(state?["controls"] as? Int, 0)
        XCTAssertEqual(state?["posterShown"] as? Bool, true)
        XCTAssertEqual(state?["deadShown"] as? Bool, false)
        XCTAssertEqual(state?["deadHeight"] as? Double, 0)
    }
}
