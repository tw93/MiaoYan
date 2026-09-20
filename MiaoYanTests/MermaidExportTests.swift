import WebKit
import XCTest

@testable import MiaoYan

@available(macOS 12.0, *)
final class MermaidExportTests: XCTestCase {
    private var tempDirectory: URL!
    private var downViewBundleURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiaoYan Mermaid Export Tests \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        downViewBundleURL = try XCTUnwrap(
            Bundle.main.url(forResource: "DownView", withExtension: "bundle"),
            "DownView.bundle must be present in the test host app")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    @MainActor
    func testRenderedMermaidSurvivesExportReloadWithoutOrphanError() async throws {
        let webView = makeWebView()
        let sourceURL = try writePage(
            named: "source",
            mermaid: """
                flowchart LR
                A["Normal diagram A"] --> B["Normal diagram B"]
                """)

        webView.loadFileURL(sourceURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        try await waitForMermaid(in: webView, expectedURL: sourceURL, expectedPage: "source")

        let initialState = try await readState(from: webView)
        XCTAssertEqual(initialState.rendered, "true")
        XCTAssertEqual(initialState.diagramSVGCount, 1)
        XCTAssertEqual(initialState.orphanErrorContainerCount, 0)

        let rawRenderedHTML = try await webView.evaluateJavaScript("document.documentElement.outerHTML")
        let renderedHTML = try XCTUnwrap(rawRenderedHTML as? String)
        let reloadHTML = renderedHTML.replacingOccurrences(
            of: "data-miaoyan-test-page=\"source\"",
            with: "data-miaoyan-test-page=\"export-reload\"")
        XCTAssertNotEqual(reloadHTML, renderedHTML)
        let reloadURL = tempDirectory.appendingPathComponent("export-reload.html")
        try reloadHTML.write(to: reloadURL, atomically: true, encoding: .utf8)

        webView.loadFileURL(reloadURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        try await waitForMermaid(
            in: webView,
            expectedURL: reloadURL,
            expectedPage: "export-reload")

        let reloadedState = try await readState(from: webView)
        XCTAssertEqual(reloadedState.rendered, "true")
        XCTAssertEqual(reloadedState.diagramSVGCount, 1)
        XCTAssertEqual(reloadedState.orphanErrorContainerCount, 0)
        XCTAssertEqual(reloadedState.errorNodeCount, 0)
    }

    @MainActor
    func testInvalidMermaidFallsBackWithoutOrphanError() async throws {
        let webView = makeWebView()
        let sourceURL = try writePage(
            named: "invalid-source",
            mermaid: "flowchart ??? definitely invalid")

        webView.loadFileURL(sourceURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        try await waitForMermaid(
            in: webView,
            expectedURL: sourceURL,
            expectedPage: "invalid-source")

        let state = try await readState(from: webView)
        XCTAssertEqual(state.rendered, "failed")
        XCTAssertTrue(state.hasSourceFallback)
        XCTAssertEqual(state.diagramSVGCount, 0)
        XCTAssertEqual(state.orphanErrorContainerCount, 0)
        XCTAssertEqual(state.errorNodeCount, 0)
    }

    @MainActor
    func testRepeatedImageExportPreparesWideTablesEveryTime() async throws {
        let previousPPT = UserDefaultsManagement.magicPPT
        let previousExportPPT = UserDefaultsManagement.isOnExportPPT
        UserDefaultsManagement.magicPPT = false
        UserDefaultsManagement.isOnExportPPT = false
        defer {
            UserDefaultsManagement.magicPPT = previousPPT
            UserDefaultsManagement.isOnExportPPT = previousExportPPT
        }
        let project = Project(url: tempDirectory, label: "export-test", isRoot: true)
        let noteURL = tempDirectory.appendingPathComponent("wide-table.md")
        let token = String(repeating: "W", count: 100)
        try "| First | Second |\n| --- | --- |\n| \(token) | \(token) |".write(to: noteURL, atomically: true, encoding: .utf8)
        let note = Note(url: noteURL, with: project)
        let preview = ExportTestPreviewView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), note: note, closure: nil)
        let page = """
            <!doctype html><html><head>
            <link rel="stylesheet" href="\(downViewBundleURL.appendingPathComponent("css/typography.css").absoluteString)">
            <link rel="stylesheet" href="\(downViewBundleURL.appendingPathComponent("css/base.css").absoluteString)">
            <script src="\(downViewBundleURL.appendingPathComponent("js/common.js").absoluteString)"></script>
            </head><body><div class="heti" id="write">
            <table><thead><tr><th>First</th><th>Second</th></tr></thead>
            <tbody><tr><td>\(token)</td><td>\(token)</td></tr></tbody></table>
            </div><script>MiaoYanCommon.wrapWideTables();</script></body></html>
            """
        let pageURL = tempDirectory.appendingPathComponent("wide-table.html")
        try page.write(to: pageURL, atomically: true, encoding: .utf8)
        preview.loadFileURL(pageURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        let controller = ExportTestViewController()
        controller.view = NSView(frame: preview.frame)
        defer { controller.toastDismiss() }

        let deadline = Date().addingTimeInterval(10)
        var hasTable = false
        while Date() < deadline {
            hasTable = (try? await preview.evaluateJavaScript("!!document.querySelector('.table-scroll > table')") as? Bool) == true
            if hasTable { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(hasTable)
        guard hasTable else { return }

        let geometry = """
            (function() {
                const wrapper = document.querySelector('.table-scroll');
                const table = wrapper.querySelector('table');
                return { overflow: getComputedStyle(wrapper).overflowX,
                         layout: getComputedStyle(table).tableLayout,
                         wrapperWidth: wrapper.getBoundingClientRect().width,
                         tableWidth: table.getBoundingClientRect().width };
            })()
            """
        let originalRaw = try await preview.evaluateJavaScript(geometry)
        let original = try XCTUnwrap(originalRaw as? [String: Any])
        XCTAssertGreaterThan(try XCTUnwrap(original["tableWidth"] as? Double), try XCTUnwrap(original["wrapperWidth"] as? Double))

        for attempt in 1...2 {
            var cleanupAction: (() -> Void)?
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                preview.performExport(viewController: controller) { cleanup in
                    cleanupAction = cleanup
                    continuation.resume()
                }
            }
            let cleanup = try XCTUnwrap(cleanupAction)
            let stateRaw = try await preview.evaluateJavaScript(geometry)
            let state = try XCTUnwrap(stateRaw as? [String: Any])
            cleanup()
            XCTAssertEqual(state["overflow"] as? String, "visible", "Export \(attempt)")
            XCTAssertEqual(state["layout"] as? String, "fixed", "Export \(attempt)")
            XCTAssertLessThanOrEqual(try XCTUnwrap(state["tableWidth"] as? Double), try XCTUnwrap(state["wrapperWidth"] as? Double) + 1, "Export \(attempt)")
            let restoredRaw = try await preview.evaluateJavaScript(geometry)
            let restored = try XCTUnwrap(restoredRaw as? [String: Any])
            XCTAssertEqual(restored["overflow"] as? String, "auto")
        }
    }

    @MainActor
    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        return WKWebView(
            frame: CGRect(x: 0, y: 0, width: 900, height: 700),
            configuration: configuration)
    }

    private func writePage(named name: String, mermaid source: String) throws -> URL {
        let escapedSource =
            source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let scriptDirectory = downViewBundleURL.appendingPathComponent("js", isDirectory: true)
        let page = """
            <!doctype html>
            <html data-miaoyan-test-page="\(name)">
            <head>
              <meta charset="utf-8">
              <script defer src="\(scriptDirectory.appendingPathComponent("mermaid.min.js").absoluteString)"></script>
              <script defer src="\(scriptDirectory.appendingPathComponent("theme-config.js").absoluteString)"></script>
              <script defer src="\(scriptDirectory.appendingPathComponent("theme-manager.js").absoluteString)"></script>
              <script defer src="\(scriptDirectory.appendingPathComponent("diagram-handler.js").absoluteString)"></script>
            </head>
            <body>
              <div id="write"><pre><code class="language-mermaid">\(escapedSource)</code></pre></div>
              <script>
                window.__miaoyanMermaidTestDone = false;
                document.addEventListener('DOMContentLoaded', async function () {
                  try {
                    await DiagramHandler.initializeMermaid();
                  } finally {
                    window.__miaoyanMermaidTestDone = true;
                  }
                });
              </script>
            </body>
            </html>
            """
        let url = tempDirectory.appendingPathComponent("\(name).html")
        try page.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @MainActor
    private func waitForMermaid(
        in webView: WKWebView,
        expectedURL: URL,
        expectedPage: String
    ) async throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if webView.url?.path == expectedURL.path,
                let done = try? await webView.evaluateJavaScript(
                    """
                    document.readyState === 'complete' &&
                      document.documentElement.dataset.miaoyanTestPage === '\(expectedPage)' &&
                      window.__miaoyanMermaidTestDone === true
                    """) as? Bool,
                done
            {
                return
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw NSError(
            domain: "MermaidExportTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for Mermaid rendering"])
    }

    @MainActor
    private func readState(from webView: WKWebView) async throws -> MermaidDOMState {
        let raw = try await webView.evaluateJavaScript(
            """
            ({
              rendered: document.querySelector('code.language-mermaid')?.getAttribute('data-mermaid-rendered') || null,
              diagramSVGCount: document.querySelectorAll('code.language-mermaid svg').length,
              orphanErrorContainerCount: document.querySelectorAll('body > div[id^="dmermaid-"]').length,
              errorNodeCount: document.querySelectorAll('svg .error-icon, svg .error-text').length,
              hasSourceFallback: document.querySelector('pre')?.classList.contains('mermaid-source-fallback') || false
            })
            """)
        let dictionary = try XCTUnwrap(raw as? [String: Any])
        return MermaidDOMState(
            rendered: dictionary["rendered"] as? String,
            diagramSVGCount: try XCTUnwrap(dictionary["diagramSVGCount"] as? Int),
            orphanErrorContainerCount: try XCTUnwrap(dictionary["orphanErrorContainerCount"] as? Int),
            errorNodeCount: try XCTUnwrap(dictionary["errorNodeCount"] as? Int),
            hasSourceFallback: try XCTUnwrap(dictionary["hasSourceFallback"] as? Bool)
        )
    }
}

@available(macOS 12.0, *)
private struct MermaidDOMState {
    let rendered: String?
    let diagramSVGCount: Int
    let orphanErrorContainerCount: Int
    let errorNodeCount: Int
    let hasSourceFallback: Bool
}

@MainActor
private final class ExportTestViewController: ViewController {
    override func viewDidLoad() {}
}

@MainActor
private final class ExportTestPreviewView: MPreviewView {
    override func load(note: Note, force: Bool = false, completion: (() -> Void)? = nil) {}
}
