import WebKit
import XCTest

@testable import MiaoYan

/// A live preview update replaces only the blocks that changed
/// (`MiaoYanCommon.patchContent`), so images, diagrams and formulas the
/// reader is looking at stay put while the note is written to.
@available(macOS 12.0, *)
final class PreviewPatchTests: XCTestCase {
    private var tempDirectory: URL!
    private var commonScript: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiaoYan Preview Patch Tests \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let bundle = try XCTUnwrap(Bundle.main.url(forResource: "DownView", withExtension: "bundle"))
        commonScript = bundle.appendingPathComponent("js/common.js")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    private static let image = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
    private static let before = "# Title\n\nFirst paragraph.\n\n![](\(image))\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\nLast paragraph."

    @MainActor
    private func loadPage(_ markdown: String) async throws -> WKWebView {
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: markdown, useGithubLineBreak: false))
        // common.js after #write, as the deferred script runs in the app, so
        // it records the renderer's blocks before anything changes them.
        let page = """
            <!doctype html><html><head><meta charset="utf-8"></head><body>
            <div class="markdown-body heti" id="write">\(html)</div>
            <script src="\(commonScript.absoluteString)"></script>
            <script>MiaoYanCommon.wrapWideTables(); window.__ready = true;</script>
            </body></html>
            """
        let url = tempDirectory.appendingPathComponent("page-\(UUID().uuidString).html")
        try page.write(to: url, atomically: true, encoding: .utf8)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        webView.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if (try? await webView.evaluateJavaScript("window.__ready === true") as? Bool) == true { return webView }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("page did not load")
        return webView
    }

    @MainActor
    private func patch(_ webView: WKWebView, to markdown: String) async throws -> [String: Any] {
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: markdown, useGithubLineBreak: false))
        let literal = String(data: try JSONEncoder().encode(html), encoding: .utf8) ?? "\"\""
        let script = """
            (function() {
                const container = document.getElementById('write');
                const inserted = MiaoYanCommon.patchContent(container, \(literal));
                MiaoYanCommon.wrapWideTables();
                const img = container.querySelector('img');
                const table = container.querySelector('table');
                const last = Array.from(container.querySelectorAll('p')).pop();
                return {
                    inserted: inserted.filter((n) => n.nodeType === 1).length,
                    imageKept: img && img.__mark === 'kept',
                    tableKept: table && table.__mark === 'kept',
                    imageLine: parseInt(img.closest('p').getAttribute('data-sourcepos'), 10),
                    lastLine: parseInt(last.getAttribute('data-sourcepos'), 10),
                    text: container.textContent.replace(/\\s+/g, ' ').trim()
                };
            })();
            """
        let raw = try await webView.evaluateJavaScript(script)
        return try XCTUnwrap(raw as? [String: Any])
    }

    @MainActor
    private func mark(_ webView: WKWebView) async throws {
        _ = try await webView.evaluateJavaScript(
            "document.querySelector('#write img').__mark = 'kept'; document.querySelector('#write table').__mark = 'kept'; true")
    }

    @MainActor
    func testEditKeepsTheBlocksThatDidNotChangeAndShiftsTheirLines() async throws {
        let webView = try await loadPage(Self.before)
        try await mark(webView)
        let after = "Added above.\n\n" + Self.before.replacingOccurrences(of: "First paragraph.", with: "First paragraph, edited.")

        let result = try await patch(webView, to: after)

        XCTAssertEqual(result["imageKept"] as? Bool, true, "\(result)")
        XCTAssertEqual(result["tableKept"] as? Bool, true, "the wrapped table is matched through its scroll box")
        XCTAssertEqual(result["inserted"] as? Int, 2, "the added paragraph and the edited one; the heading between them is reused")
        XCTAssertEqual(result["imageLine"] as? Int, 7, "a kept block takes its new source line")
        XCTAssertEqual(result["lastLine"] as? Int, 13)
        XCTAssertEqual(
            result["text"] as? String,
            "Added above. Title First paragraph, edited. A B 1 2 Last paragraph.")
    }

    /// A blank line added inside a quote renders the same HTML, but the lines
    /// inside it moved; the block is replaced so its positions are right.
    @MainActor
    func testABlockWhoseInnerLinesMovedIsReplaced() async throws {
        let webView = try await loadPage("> one\n>\n> two\n\nTail.")
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: "> one\n>\n>\n> two\n\nTail.", useGithubLineBreak: false))
        let script = """
            (function() {
                const container = document.getElementById('write');
                const inserted = MiaoYanCommon.patchContent(container, \(HtmlManager.jsStringLiteral(html)));
                const quoted = container.querySelectorAll('blockquote p');
                return {
                    inserted: inserted.filter((n) => n.nodeType === 1).length,
                    second: parseInt(quoted[1].getAttribute('data-sourcepos'), 10),
                    tail: parseInt(container.querySelector(':scope > p').getAttribute('data-sourcepos'), 10)
                };
            })();
            """
        let raw = try await webView.evaluateJavaScript(script)
        let result = try XCTUnwrap(raw as? [String: Any])
        XCTAssertEqual(result["inserted"] as? Int, 1, "only the quote; the tail is kept and moved a line down")
        XCTAssertEqual(result["second"] as? Int, 4)
        XCTAssertEqual(result["tail"] as? Int, 6)
    }

    @MainActor
    func testUnchangedNoteInsertsNothing() async throws {
        let webView = try await loadPage(Self.before)
        try await mark(webView)
        let result = try await patch(webView, to: Self.before)
        XCTAssertEqual(result["inserted"] as? Int, 0)
        XCTAssertEqual(result["imageKept"] as? Bool, true)
    }

    @MainActor
    func testAPageTheRecordNoLongerDescribesIsRebuilt() async throws {
        let webView = try await loadPage(Self.before)
        try await mark(webView)
        _ = try await webView.evaluateJavaScript("document.getElementById('write').appendChild(document.createElement('hr')); true")
        let result = try await patch(webView, to: Self.before)
        XCTAssertEqual(result["imageKept"] as? Bool, false, "everything is replaced")
        XCTAssertEqual(result["text"] as? String, "Title First paragraph. A B 1 2 Last paragraph.")
        let count = try await webView.evaluateJavaScript("document.querySelectorAll('#write hr').length") as? Int
        XCTAssertEqual(count, 0, "the stray node is gone")
    }

    /// A page with the bundle's renderers, as index.html loads them, showing
    /// `markdown` the way a load does (renderPage).
    @MainActor
    private func loadRenderedPage(_ markdown: String) async throws -> WKWebView {
        let html = try XCTUnwrap(MPreviewView.previewHTML(markdown: markdown, useGithubLineBreak: false, imagesStorage: tempDirectory))
        let bundle = commonScript.deletingLastPathComponent().deletingLastPathComponent()
        let scripts = ["highlight.min.js", "katex.min.js", "auto-render.min.js", "emoji.min.js", "lightense.min.js", "tocbot.min.js", "common.js"]
            .map { "<script src=\"\(bundle.appendingPathComponent("js/\($0)").absoluteString)\"></script>" }.joined()
        let sheets = ["typography.css", "theme-light.css", "base.css"]
            .map { "<link rel=\"stylesheet\" href=\"\(bundle.appendingPathComponent("css/\($0)").absoluteString)\">" }.joined()
        let page = """
            <!doctype html><html><head><meta charset="utf-8">\(sheets)</head><body>
            <div class="toc-hover-trigger"></div><nav class="toc-nav"><div class="toc-content"></div></nav>
            <div class="markdown-body heti" id="write">\(html)</div>
            \(scripts)
            <script>MiaoYanCommon.renderPage(); setTimeout(function() { window.__ready = true; }, 400);</script>
            </body></html>
            """
        let url = tempDirectory.appendingPathComponent("page-\(UUID().uuidString).html")
        try page.write(to: url, atomically: true, encoding: .utf8)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        webView.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if (try? await webView.evaluateJavaScript("window.__ready === true") as? Bool) == true { return webView }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("page did not load")
        return webView
    }

    /// A live update did only some of what a load does to the blocks it
    /// inserts: `$5 and $10` typed in split view became a formula, emoji
    /// shortcodes stayed text, a new heading had no id and the table of
    /// contents never saw it.
    @MainActor
    func testALiveUpdateRendersNewBlocksAsALoadDoes() async throws {
        let before = "# One\n\nFirst."
        let after = "# One\n\nFirst.\n\n## Two\n\nIt costs $5 and $10 :smile:\n\nInline $x^2$ math."
        let updated = try await loadRenderedPage(before)
        let html = try XCTUnwrap(MPreviewView.previewHTML(markdown: after, useGithubLineBreak: false, imagesStorage: tempDirectory))
        _ = try await updated.evaluateJavaScript(
            MPreviewView.buildUpdateScript(html: html, initializeMath: true, initializeDiagrams: false, preserveScroll: false))
        try await Task.sleep(nanoseconds: 500_000_000)
        let loaded = try await loadRenderedPage(after)

        let probe = """
            (function() {
                const blocks = Array.from(document.querySelectorAll('#write > *'));
                return {
                    html: blocks.map((b) => b.outerHTML.replace(/ data-sourcepos="[^"]*"/g, '')),
                    katex: document.querySelectorAll('#write .katex').length,
                    skipped: document.querySelectorAll('#write .skip-math-dollar').length,
                    id: (document.querySelector('#write h2') || {}).id,
                    toc: document.querySelectorAll('.toc-content a').length,
                    shortcode: document.getElementById('write').innerHTML.includes(':smile:')
                };
            })();
            """
        let gotRaw = try await updated.evaluateJavaScript(probe)
        let wantRaw = try await loaded.evaluateJavaScript(probe)
        let got = try XCTUnwrap(gotRaw as? [String: Any])
        let want = try XCTUnwrap(wantRaw as? [String: Any])
        XCTAssertEqual(got["skipped"] as? Int, 2, "both amounts stay text: \(got)")
        XCTAssertEqual(got["katex"] as? Int, 1, "only $x^2$ is math")
        XCTAssertEqual(want["shortcode"] as? Bool, false, "a load turns :smile: into an emoji")
        XCTAssertEqual(got["shortcode"] as? Bool, false, "and so does an update")
        XCTAssertEqual(got["id"] as? String, "Two")
        XCTAssertEqual(got["toc"] as? Int, 2, "the new heading joins the table of contents")
        XCTAssertEqual(got["html"] as? [String], want["html"] as? [String], "an updated block reads as a loaded one")
    }

    /// Each heading shows a small link beside it on hover, as on GitHub,
    /// without changing its id or its text, and an in-page link reaches a
    /// heading whose id is no CSS selector: `querySelector('#1. Intro')`
    /// threw, so the click did nothing.
    @MainActor
    func testHeadingsCarryAHoverLinkThatScrollsToThem() async throws {
        let filler = (1...60).map { "Paragraph \($0)." }.joined(separator: "\n\n")
        let webView = try await loadRenderedPage("# 1. Intro\n\nText.\n\n\(filler)\n\n## Two\n\n[back](#1.%20Intro)\n\n\(filler)")
        let probe = """
            (function() {
                MiaoYanCommon.setupHeaderAnchors();
                const h = document.querySelector('#write h1');
                const links = Array.from(document.querySelectorAll('#write .heading-anchor'));
                const style = getComputedStyle(links[0]);
                const range = document.createRange();
                range.selectNodeContents(h);
                getSelection().removeAllRanges();
                getSelection().addRange(range);
                const copied = MiaoYanCommon.selectionPayload();
                getSelection().removeAllRanges();
                return {
                    ids: Array.from(document.querySelectorAll('#write h1, #write h2'), (x) => x.id),
                    hrefs: links.map((a) => a.getAttribute('href')),
                    text: h.textContent,
                    opacity: style.opacity,
                    transition: style.transitionDuration + ' ' + style.transitionTimingFunction,
                    copied: copied.html
                };
            })();
            """
        let raw = try await webView.evaluateJavaScript(probe)
        let result = try XCTUnwrap(raw as? [String: Any])
        XCTAssertEqual(result["ids"] as? [String], ["1. Intro", "Two"], "ids stay the heading's text")
        XCTAssertEqual(result["hrefs"] as? [String], ["#1.%20Intro", "#Two"], "one link per heading, even when run again")
        XCTAssertEqual(result["text"] as? String, "1. Intro")
        XCTAssertEqual(result["opacity"] as? String, "0", "hidden until the pointer is over the heading")
        XCTAssertEqual(result["transition"] as? String, "0.12s ease-out")
        XCTAssertEqual(result["copied"] as? String, "1. Intro", "copying a heading leaves the link behind")

        _ = try await webView.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight); document.querySelector('#write a[href=\"#1.%20Intro\"]').click(); true")
        try await Task.sleep(nanoseconds: 900_000_000)
        let top = try await webView.evaluateJavaScript("Math.round(document.getElementById('1. Intro').getBoundingClientRect().top)") as? Int
        XCTAssertNotNil(top)
        XCTAssertLessThan(abs(top ?? 9_999), 40, "the link scrolled to the heading")

        let asExported = """
            (function() {
                document.querySelectorAll('.heading-anchor').forEach((a) => a.remove());
                const base = document.createElement('base');
                base.href = 'https://cdn.miaoyan.app/Resources/DownView.bundle/';
                document.head.appendChild(base);
                MiaoYanCommon.setupHeaderAnchors();
                return document.querySelectorAll('.heading-anchor').length;
            })();
            """
        let exported = try await webView.evaluateJavaScript(asExported) as? Int
        XCTAssertEqual(exported, 0, "exported HTML has no hover links")

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let base = try String(contentsOf: root.appendingPathComponent("Resources/DownView.bundle/css/base.css"), encoding: .utf8)
        XCTAssertTrue(base.contains("@media print {\n  #write .heading-anchor {\n    display: none !important;"), "print")
        XCTAssertTrue(base.contains("@media (prefers-reduced-motion: no-preference) {\n  #write .heading-anchor {\n    transition"), "Reduce Motion")
        XCTAssertTrue(HtmlManager.paginatedPrintCSS().contains(".heading-anchor"), "PDF")
        let export = try String(contentsOf: root.appendingPathComponent("Extensions/MPreviewView+Export.swift"), encoding: .utf8)
        XCTAssertTrue(export.contains(".heading-anchor { display: none !important; }"), "PNG")
    }

    /// A reload while an in-place switch is still rendering (the app comes
    /// back to the front, WebContent restarts) loaded the note being
    /// replaced, which cancelled the switch and left the preview on it while
    /// the list showed the next one.
    func testReloadsMidSwitchLoadTheNoteOnItsWayIn() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Views/MPreviewView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("if let note = inPlaceNote ?? self.note {\n            self.load(note: note, force: true)"), "WebContent restart")
        XCTAssertTrue(source.contains("guard let note = inPlaceNote ?? note else { return }\n        load(note: note, force: true)"), "app reactivation")
    }
}
