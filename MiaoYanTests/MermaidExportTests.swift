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

    /// A system light/dark switch changed only the body class of a preview
    /// it did not reload (the shell window's), so `html` and `#write` kept
    /// the old theme, diagrams kept their old palette, and the native
    /// layers around the page kept the old paper.
    @MainActor
    func testAppearanceSwitchRethemesThePageInPlace() async throws {
        let previousType = UserDefaultsManagement.appearanceType
        let previousDark = UserDataService.instance.isDark
        UserDefaultsManagement.appearanceType = .System
        UserDataService.instance.isDark = false
        defer {
            UserDefaultsManagement.appearanceType = previousType
            UserDataService.instance.isDark = previousDark
        }
        let project = Project(url: tempDirectory, label: "appearance-test", isRoot: true)
        let note = Note(url: tempDirectory.appendingPathComponent("a.md"), with: project)
        let preview = ExportTestPreviewView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), note: note, closure: nil)
        let js = downViewBundleURL.appendingPathComponent("js", isDirectory: true)
        let scripts = ["mermaid.min.js", "plantuml-encoder.min.js", "theme-config.js", "common.js", "theme-manager.js", "diagram-handler.js"]
            .map { "<script src=\"\(js.appendingPathComponent($0).absoluteString)\"></script>" }.joined()
        let page = """
            <!doctype html><html><head><meta charset="utf-8">\(scripts)</head><body>
            <div class="markdown-body heti" id="write">
            <pre><code class="language-mermaid">flowchart LR
            A --> B</code></pre>
            <pre><code class="language-plantuml">Alice -> Bob: Hi</code></pre>
            </div>
            <script>
            DiagramHandler.initializeMermaid().then(function() { DiagramHandler.initializePlantUML(); window.__ready = true; });
            </script></body></html>
            """
        let pageURL = tempDirectory.appendingPathComponent("appearance.html")
        try page.write(to: pageURL, atomically: true, encoding: .utf8)
        preview.loadFileURL(pageURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        try await waitFor(preview, "window.__ready === true")

        let state = """
            (function() {
                const write = document.getElementById('write');
                const svg = document.querySelector('.language-mermaid svg');
                const node = window.ThemeColors.getThemeColors(true).primaryColor.toLowerCase();
                return {
                    marked: [document.documentElement, document.body, write].filter((el) => el.classList.contains('darkmode')).length,
                    nodeVariable: document.documentElement.style.getPropertyValue('--mermaid-node-bg').trim().toLowerCase() === node,
                    svgDark: !!svg && svg.outerHTML.toLowerCase().includes(node),
                    plantuml: Array.from(document.querySelectorAll('img.plantuml-image'), (img) => img.getAttribute('src'))
                };
            })();
            """
        let lightRaw = try await preview.evaluateJavaScript(state)
        let light = try XCTUnwrap(lightRaw as? [String: Any])
        XCTAssertEqual(light["marked"] as? Int, 0)
        XCTAssertEqual(light["svgDark"] as? Bool, false)

        UserDataService.instance.isDark = true
        preview.updateAppearance()
        try await waitFor(preview, "document.querySelector('.language-mermaid[data-processed=\"true\"] svg') !== null && document.documentElement.classList.contains('darkmode')")
        let darkRaw = try await preview.evaluateJavaScript(state)
        let dark = try XCTUnwrap(darkRaw as? [String: Any])
        XCTAssertEqual(dark["marked"] as? Int, 3, "html, body and #write")
        XCTAssertEqual(dark["nodeVariable"] as? Bool, true)
        XCTAssertEqual(dark["svgDark"] as? Bool, true, "the flowchart is drawn again in the dark palette")
        let before = try XCTUnwrap(light["plantuml"] as? [String])
        let after = try XCTUnwrap(dark["plantuml"] as? [String])
        XCTAssertEqual(after.count, 1)
        XCTAssertNotEqual(after, before, "the PlantUML image is asked for again with the dark skin")
        XCTAssertEqual(rgb(preview.value(forKey: "underPageBackgroundColor") as? NSColor), resolved(Theme.previewDarkBackgroundColor, in: preview))
        XCTAssertEqual(rgb(preview.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))), resolved(Theme.previewDarkBackgroundColor, in: preview))

        UserDataService.instance.isDark = false
        preview.updateAppearance()
        try await waitFor(preview, "!document.documentElement.classList.contains('darkmode')")
        XCTAssertEqual(rgb(preview.value(forKey: "underPageBackgroundColor") as? NSColor), resolved(Theme.backgroundColor, in: preview))
        XCTAssertEqual(rgb(preview.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))), resolved(Theme.backgroundColor, in: preview))
    }

    private func rgb(_ color: NSColor?) -> String? {
        guard let srgb = color?.usingColorSpace(.sRGB) else { return nil }
        return String(format: "%.3f %.3f %.3f", srgb.redComponent, srgb.greenComponent, srgb.blueComponent)
    }

    @MainActor
    private func resolved(_ color: NSColor, in view: NSView) -> String? {
        var value: String?
        view.effectiveAppearance.performAsCurrentDrawingAppearance { value = self.rgb(color) }
        return value
    }

    @MainActor
    private func waitFor(_ webView: WKWebView, _ condition: String) async throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if (try? await webView.evaluateJavaScript(condition) as? Bool) == true { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("timed out waiting for \(condition)")
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
