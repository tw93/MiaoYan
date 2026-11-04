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

    /// Text carried into a script goes in as `HtmlManager.jsStringLiteral`,
    /// never inside a template literal, where a backtick or `${` in it ends
    /// the string or runs as code. The preview's update keeps its template
    /// literal because it escapes the HTML first (`rawEscaped`).
    func testScriptsDoNotInterpolateSwiftTextIntoTemplateLiterals() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let interpolation = try NSRegularExpression(pattern: #"`\\\("#)
        // Markdown.swift names `\( \)` math in a comment; TextFormatter wraps inline code.
        let allowed = ["Business/Markdown.swift": 1, "Helpers/TextFormatter.swift": 1, "Views/MPreviewView.swift": 2]
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
}
