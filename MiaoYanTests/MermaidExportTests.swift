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
            <script>\(Self.plantumlStub)</script>
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
        XCTAssertEqual(light["plantuml"] as? [String], [Self.plantumlLight])
        // The light image stays until the dark one has loaded.
        try await waitFor(preview, "document.querySelector('img.plantuml-image').getAttribute('src') === \(HtmlManager.jsStringLiteral(Self.plantumlDark))")
        let afterRaw = try await preview.evaluateJavaScript(state)
        let after = try XCTUnwrap(afterRaw as? [String: Any])
        XCTAssertEqual(after["plantuml"] as? [String], [Self.plantumlDark], "the PlantUML image is asked for again with the dark skin")
        XCTAssertEqual(rgb(preview.value(forKey: "underPageBackgroundColor") as? NSColor), resolved(Theme.previewDarkBackgroundColor, in: preview))
        XCTAssertEqual(rgb(preview.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))), resolved(Theme.previewDarkBackgroundColor, in: preview))

        UserDataService.instance.isDark = false
        preview.updateAppearance()
        try await waitFor(preview, "!document.documentElement.classList.contains('darkmode')")
        XCTAssertEqual(rgb(preview.value(forKey: "underPageBackgroundColor") as? NSColor), resolved(Theme.backgroundColor, in: preview))
        XCTAssertEqual(rgb(preview.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))), resolved(Theme.backgroundColor, in: preview))
    }

    /// A light or dark switch asked the PlantUML server for every diagram
    /// again and took the drawn image down while it did; offline, or when
    /// the request failed, the diagram turned back into source text.
    @MainActor
    func testPlantUMLRethemeKeepsTheDrawnImageUntilTheNewOneLoads() async throws {
        let webView = makeWebView()
        let js = downViewBundleURL.appendingPathComponent("js", isDirectory: true)
        let scripts = ["plantuml-encoder.min.js", "theme-config.js", "theme-manager.js", "diagram-handler.js"]
            .map { "<script src=\"\(js.appendingPathComponent($0).absoluteString)\"></script>" }.joined()
        let page = """
            <!doctype html><html><head><meta charset="utf-8">\(scripts)</head><body>
            <div class="markdown-body" id="write"><pre><code class="language-plantuml">Alice -> Bob: Hi</code></pre></div>
            <script>\(Self.plantumlStub)</script>
            <script>DiagramHandler.initializePlantUML(); window.__ready = true;</script>
            </body></html>
            """
        let pageURL = tempDirectory.appendingPathComponent("plantuml.html")
        try page.write(to: pageURL, atomically: true, encoding: .utf8)
        webView.loadFileURL(pageURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        try await waitFor(webView, "window.__ready === true && (function(img) { return !!img && img.complete && img.naturalWidth > 0; })(document.querySelector('img.plantuml-image'))")

        let state = """
            (function() {
                const images = document.querySelectorAll('img.plantuml-image');
                const code = document.querySelector('code.language-plantuml');
                return {
                    images: images.length,
                    kept: images.length === 1 && images[0].__mark === 'light',
                    src: images.length ? images[0].getAttribute('src') : null,
                    shown: images.length === 1 && images[0].style.display !== 'none',
                    sourceShown: code.style.display !== 'none',
                    loaders: document.querySelectorAll('.diagram-loading').length
                };
            })();
            """
        let failing = tempDirectory.appendingPathComponent("missing.svg").absoluteString
        let switchRaw = try await webView.evaluateJavaScript(
            """
            window.__plantumlServe.DARK = \(HtmlManager.jsStringLiteral(failing));
            document.querySelector('img.plantuml-image').__mark = 'light';
            ThemeConfig.applyTheme(true);
            \(state)
            """)
        let switching = try XCTUnwrap(switchRaw as? [String: Any])
        XCTAssertEqual(switching["kept"] as? Bool, true, "the drawn image stays while the dark one loads")
        XCTAssertEqual(switching["loaders"] as? Int, 0)
        XCTAssertEqual(switching["sourceShown"] as? Bool, false)

        try await Task.sleep(nanoseconds: 500_000_000)
        let failedRaw = try await webView.evaluateJavaScript(state)
        let failed = try XCTUnwrap(failedRaw as? [String: Any])
        XCTAssertEqual(failed["kept"] as? Bool, true, "a failed request keeps the light image")
        XCTAssertEqual(failed["shown"] as? Bool, true)
        XCTAssertEqual(failed["sourceShown"] as? Bool, false, "the diagram does not fall back to source text")
        XCTAssertEqual(failed["src"] as? String, Self.plantumlLight)

        _ = try await webView.evaluateJavaScript("window.__plantumlServe.DARK = \(HtmlManager.jsStringLiteral(Self.plantumlDark)); DiagramHandler.retheme(); true")
        try await waitFor(webView, "document.querySelector('img.plantuml-image').getAttribute('src') === \(HtmlManager.jsStringLiteral(Self.plantumlDark))")
        let darkRaw = try await webView.evaluateJavaScript(state)
        let dark = try XCTUnwrap(darkRaw as? [String: Any])
        XCTAssertEqual(dark["images"] as? Int, 1)
        XCTAssertEqual(dark["shown"] as? Bool, true)
        XCTAssertEqual(dark["sourceShown"] as? Bool, false)
        XCTAssertEqual(dark["loaders"] as? Int, 0)
    }

    private static let plantumlLight =
        "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%2240%22%20height%3D%2220%22%3E"
        + "%3Crect%20width%3D%2240%22%20height%3D%2220%22%20fill%3D%22%23F5F4ED%22%2F%3E%3C%2Fsvg%3E"
    private static let plantumlDark =
        "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%2240%22%20height%3D%2220%22%3E"
        + "%3Crect%20width%3D%2240%22%20height%3D%2220%22%20fill%3D%22%23282724%22%2F%3E%3C%2Fsvg%3E"

    /// Serves PlantUML images from the page instead of the PlantUML server:
    /// the encoder names the skin it was given (the dark one carries the
    /// dark diagram background), and image sources naming a skin load the
    /// image `__plantumlServe` holds for it. Lazy loading is off, since a
    /// web view outside a window never scrolls an image into view.
    private static let plantumlStub = """
        window.__plantumlServe = { LIGHT: \(HtmlManager.jsStringLiteral(plantumlLight)), DARK: \(HtmlManager.jsStringLiteral(plantumlDark)) };
        window.plantumlEncoder.encode = function(text) { return text.indexOf('#282724') !== -1 ? 'DARK' : 'LIGHT'; };
        (function() {
            const src = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, 'src');
            Object.defineProperty(HTMLImageElement.prototype, 'src', {
                configurable: true,
                get() { return src.get.call(this); },
                set(value) {
                    const skin = /~1(LIGHT|DARK)$/.exec(value);
                    src.set.call(this, skin ? window.__plantumlServe[skin[1]] : value);
                }
            });
            const loading = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, 'loading');
            Object.defineProperty(HTMLImageElement.prototype, 'loading', {
                configurable: true,
                get() { return loading.get.call(this); },
                set(value) { loading.set.call(this, 'eager'); }
            });
        })();
        """

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
