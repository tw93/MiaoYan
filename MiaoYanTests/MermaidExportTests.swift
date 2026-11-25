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

    /// A light or dark switch in the storyboard window loaded the preview
    /// again (the editor's `applySystemAppearance` refilled it), which put
    /// the reader back at the top of the note. A page already showing the
    /// note now switches in place, as the shell window's does.
    @MainActor
    func testStoryboardAppearanceSwitchKeepsThePreviewPage() async throws {
        let previous = (
            type: UserDefaultsManagement.appearanceType, dark: UserDataService.instance.isDark,
            preview: UserDefaultsManagement.preview, split: UserDefaultsManagement.splitViewMode,
            presentation: UserDefaultsManagement.presentation, ppt: UserDefaultsManagement.magicPPT,
            note: EditTextView.note
        )
        // The modes are one setting underneath: turning PPT off resets it.
        UserDefaultsManagement.appearanceType = .System
        UserDataService.instance.isDark = false
        UserDefaultsManagement.magicPPT = false
        UserDefaultsManagement.splitViewMode = false
        UserDefaultsManagement.preview = true
        defer {
            UserDefaultsManagement.appearanceType = previous.type
            UserDataService.instance.isDark = previous.dark
            UserDefaultsManagement.magicPPT = previous.ppt
            if !previous.ppt {
                UserDefaultsManagement.presentation = previous.presentation
                UserDefaultsManagement.preview = previous.preview
            }
            UserDefaultsManagement.splitViewMode = previous.split
            EditTextView.note = previous.note
        }
        let project = Project(url: tempDirectory, label: "appearance-test", isRoot: true)
        let noteURL = tempDirectory.appendingPathComponent("long.md")
        let paragraphs = (1...80).map { "Paragraph \($0) of a note long enough to scroll." }.joined(separator: "\n\n")
        try "# Title\n\n\(paragraphs)".write(to: noteURL, atomically: true, encoding: .utf8)
        let note = Note(url: noteURL, with: project)
        note.load()

        let preview = LoadCountingPreviewView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), note: note, closure: nil)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !preview.canUpdateAppearanceInPlace(showing: note) {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(preview.canUpdateAppearanceInPlace(showing: note), "the preview loaded the note")
        try await waitFor(preview, "document.readyState === 'complete' && !!window.ThemeConfig && document.querySelectorAll('#write p').length > 40")
        let scrolledRaw = try await preview.evaluateJavaScript(
            """
            window.__samePage = true;
            window.__rethemes = 0;
            const retheme = DiagramHandler.retheme.bind(DiagramHandler);
            DiagramHandler.retheme = function() { window.__rethemes += 1; return retheme(); };
            window.scrollTo(0, 900);
            window.scrollY
            """)
        let scrolled = try XCTUnwrap(scrolledRaw as? Double)
        XCTAssertGreaterThan(scrolled, 0)

        let controller = ExportTestViewController()
        let editor = EditTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        controller.editArea = editor
        controller.notesTableView = NotesTableView(frame: .zero)
        controller.notesListCustomView = NSView()
        editor.viewDelegate = controller
        editor.markdownView = preview
        EditTextView.note = note
        XCTAssertTrue(editor.isPreviewModeActive)
        let loads = preview.loads

        editor.appearance = NSAppearance(named: .darkAqua)
        editor.applySystemAppearance()
        try await waitFor(preview, "document.documentElement.classList.contains('darkmode') && document.body.classList.contains('darkmode')")
        let afterRaw = try await preview.evaluateJavaScript("({ same: window.__samePage === true, y: window.scrollY })")
        let after = try XCTUnwrap(afterRaw as? [String: Any])
        XCTAssertEqual(after["same"] as? Bool, true, "the page was not loaded again")
        XCTAssertEqual(after["y"] as? Double, scrolled, "the reader stays where they were")
        XCTAssertEqual(preview.loads, loads)
        XCTAssertTrue(UserDataService.instance.isDark)

        // MainWindowController asks the preview for the same switch again
        // after the editor did; the page draws its diagrams once.
        preview.updateAppearance()
        _ = try await preview.evaluateJavaScript("true")
        let rethemes = try await preview.evaluateJavaScript("window.__rethemes")
        XCTAssertEqual(rethemes as? Int, 1)
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

    /// WebKit paints a positioned box inside an SVG foreignObject from the
    /// SVG's own origin, and KaTeX builds a formula out of positioned boxes:
    /// `## Two $x^2$` in a Markmap drew its x² in the map's top-left corner
    /// while the node kept only "Two". Judged on the painted pixels, since
    /// the DOM reports the formula's box at the node either way.
    @MainActor
    func testMarkmapFormulaIsDrawnInsideItsNode() async throws {
        let js = downViewBundleURL.appendingPathComponent("js", isDirectory: true)
        let css = downViewBundleURL.appendingPathComponent("css", isDirectory: true)
        let index = try String(contentsOf: downViewBundleURL.appendingPathComponent("index.html"), encoding: .utf8)
        let loaderSettings = index.components(separatedBy: "\n")
            .filter { $0.contains("<script>window.markmap") }
            .joined(separator: "\n")
        let styles = ["katex.min.css", "diagrams.css"]
            .map { "<link rel=\"stylesheet\" href=\"\(css.appendingPathComponent($0).absoluteString)\">" }
            .joined()
        let scripts = ["katex.min.js", "frame-fallback.js", "d3.min.js", "markmap.min.js", "markmap-view.min.js", "theme-config.js", "diagram-handler.js"]
            .map { "<script src=\"\(js.appendingPathComponent($0).absoluteString)\"></script>" }
            .joined()
        let page = """
            <!doctype html><html><head><meta charset="utf-8">
            <base href="\(downViewBundleURL.absoluteString)">
            <style>body { margin: 0; background: #FDFCF9; color: #262626; }</style>
            \(styles)
            <script>
            window.requestAnimationFrame = (cb) => setTimeout(() => cb(performance.now()), 16);
            window.ThemeConfig = { isDarkMode: () => false };
            </script>
            \(loaderSettings)
            \(scripts)
            </head><body><pre><code class="language-markmap"># Root
            ## Two $x^2$
            ## Plain node
            ## Frac $\\frac{a}{b}$</code></pre>
            <script>window.addEventListener('load', () => DiagramHandler.initializeMarkmap());</script>
            </body></html>
            """
        // markmap preloads its scripts by the page-relative js/ path, and
        // until they load it never adds the style that shows the map.
        let url = tempDirectory.appendingPathComponent("markmap-math.html")
        try page.write(to: url, atomically: true, encoding: .utf8)

        let webView = makeWebView()
        let window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        webView.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        try await waitFor(webView, "document.querySelector('.language-markmap')?.dataset.markmapShown === 'true'")

        let measured = try await webView.evaluateJavaScript(
            """
            (() => {
              const r = (e) => { const b = e.getBoundingClientRect(); return [b.left, b.top, b.width, b.height]; };
              const svg = document.querySelector('.language-markmap svg');
              const formulas = [...svg.querySelectorAll('foreignObject .katex')].map(r);
              return { svg: r(svg), formulas };
            })()
            """)
        let boxes = try XCTUnwrap(measured as? [String: Any])
        let formulas = try XCTUnwrap(boxes["formulas"] as? [[Double]])
        let svg = try XCTUnwrap(boxes["svg"] as? [Double])
        XCTAssertEqual(formulas.count, 2, "\(boxes)")

        let snapshot = try await webView.takeSnapshot(configuration: nil)
        let rep = try XCTUnwrap(snapshot.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let scale = Double(rep.pixelsWide) / Double(webView.bounds.width)
        func ink(_ box: [Double]) -> Int {
            var count = 0
            let x0 = max(0, Int(box[0] * scale)), y0 = max(0, Int(box[1] * scale))
            let x1 = min(rep.pixelsWide, Int((box[0] + box[2]) * scale)), y1 = min(rep.pixelsHigh, Int((box[1] + box[3]) * scale))
            guard x0 < x1, y0 < y1 else { return 0 }
            for y in y0..<y1 {
                for x in x0..<x1 {
                    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    if c.redComponent + c.greenComponent + c.blueComponent < 1.2 { count += 1 }
                }
            }
            return count
        }
        XCTAssertGreaterThan(ink(svg), 500, "the map itself is drawn, so the checks below read a real paint")
        for box in formulas {
            XCTAssertGreaterThan(ink(box), 20, "a formula's own box holds its ink, \(box)")
        }
        XCTAssertEqual(ink([svg[0], svg[1], 80, 60]), 0, "nothing is drawn in the map's top-left corner")
    }

    /// markmap's plugins carry jsdelivr URLs: a formula in a node added
    /// KaTeX 0.16.0's stylesheet and webfontloader, and code in a node loaded
    /// prism-core, its autoloader and then each language's grammar, script
    /// run in the preview. The preview loads nothing from the network, and
    /// code in a node is highlighted by the bundled highlight.js.
    @MainActor
    func testMarkmapLoadsNothingFromTheNetwork() async throws {
        let js = downViewBundleURL.appendingPathComponent("js", isDirectory: true)
        let css = downViewBundleURL.appendingPathComponent("css", isDirectory: true)
        let index = try String(contentsOf: downViewBundleURL.appendingPathComponent("index.html"), encoding: .utf8)
        let loaderSettings = index.components(separatedBy: "\n")
            .filter { $0.contains("<script>window.markmap") }
            .joined(separator: "\n")
        let styles = ["typography.css", "katex.min.css", "diagrams.css"]
            .map { "<link rel=\"stylesheet\" href=\"\(css.appendingPathComponent($0).absoluteString)\">" }
            .joined()
        let scripts = ["katex.min.js", "highlight.min.js", "frame-fallback.js", "d3.min.js", "markmap.min.js", "markmap-view.min.js", "theme-config.js", "diagram-handler.js"]
            .map { "<script src=\"\(js.appendingPathComponent($0).absoluteString)\"></script>" }
            .joined()
        let page = """
            <!doctype html><html><head><meta charset="utf-8">
            <base href="\(downViewBundleURL.absoluteString)">
            \(styles)
            <script>
            window.requestAnimationFrame = (cb) => setTimeout(() => cb(performance.now()), 16);
            window.ThemeConfig = { isDarkMode: () => false };
            </script>
            \(loaderSettings)
            \(scripts)
            </head><body><pre><code class="language-markmap"># Root
            ## Two $x^2$
            ## Code
            ```js
            const answer = 42
            ```</code></pre>
            <script>window.addEventListener('load', () => DiagramHandler.initializeMarkmap());</script>
            </body></html>
            """
        let url = tempDirectory.appendingPathComponent("markmap-offline.html")
        try page.write(to: url, atomically: true, encoding: .utf8)

        let webView = makeWebView()
        webView.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        try await waitFor(webView, "document.querySelector('.language-markmap')?.dataset.markmapShown === 'true'")

        let found = try await webView.evaluateJavaScript(
            """
            (() => ({
              remote: [...document.querySelectorAll('link[href], script[src]')]
                .map((e) => e.getAttribute('href') || e.getAttribute('src'))
                .filter((u) => /^(https?:)?\\/\\//i.test(u)),
              keywords: document.querySelectorAll('.language-markmap svg foreignObject .hljs-keyword').length,
              code: (() => { const b = document.querySelector('.language-markmap svg foreignObject pre').getBoundingClientRect(); return [b.width, b.height]; })(),
              formulas: document.querySelectorAll('.language-markmap svg foreignObject .katex').length
            }))()
            """)
        let result = try XCTUnwrap(found as? [String: Any])
        XCTAssertEqual(result["remote"] as? [String], [], "\(result)")
        XCTAssertEqual(result["formulas"] as? Int, 1, "\(result)")
        XCTAssertGreaterThan(result["keywords"] as? Int ?? 0, 0, "code in a node is highlighted, \(result)")
        let code = try XCTUnwrap(result["code"] as? [Double])
        XCTAssertGreaterThan(code[0], code[1] * 3, "one line of code is drawn as one line, not a letter per line, \(code)")
    }

    /// markmap's KaTeX plugin loads KaTeX by itself when a node holds a
    /// formula and `window.katex` is not there yet, from its own
    /// `preloadScripts`: jsdelivr's katex.min.js, which the shim's filter of
    /// the plugins' assets never saw. It loads the bundled copy, and the
    /// formula is still drawn.
    @MainActor
    func testAMarkmapFormulaLoadsKaTeXFromTheBundle() async throws {
        let remote = """
            [...document.querySelectorAll('link[href], script[src]')]
              .map((e) => e.getAttribute('href') || e.getAttribute('src'))
              .filter((u) => /^(https?:)?\\/\\//i.test(u))
            """
        let js = downViewBundleURL.appendingPathComponent("js", isDirectory: true)
        let index = try String(contentsOf: downViewBundleURL.appendingPathComponent("index.html"), encoding: .utf8)
        let loaderSettings = index.components(separatedBy: "\n").filter { $0.contains("<script>window.markmap") }.joined(separator: "\n")
        let scripts = ["frame-fallback.js", "d3.min.js", "markmap.min.js", "markmap-view.min.js", "theme-config.js", "diagram-handler.js"]
            .map { "<script src=\"\(js.appendingPathComponent($0).absoluteString)\"></script>" }
            .joined()
        let page = """
            <!doctype html><html><head><meta charset="utf-8">
            <base href="\(downViewBundleURL.absoluteString)">
            <script>
            window.requestAnimationFrame = (cb) => setTimeout(() => cb(performance.now()), 16);
            window.ThemeConfig = { isDarkMode: () => false };
            </script>
            \(loaderSettings)
            \(scripts)
            </head><body><pre><code class="language-markmap"># Root
            ## Two $x^2$</code></pre>
            <script>window.addEventListener('load', () => DiagramHandler.initializeMarkmap());</script>
            </body></html>
            """
        let url = tempDirectory.appendingPathComponent("markmap-no-katex.html")
        try page.write(to: url, atomically: true, encoding: .utf8)
        let webView = makeWebView()
        webView.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        try await waitFor(webView, "document.querySelector('.language-markmap')?.dataset.markmapShown === 'true'")
        let pageRemote = try await webView.evaluateJavaScript(remote) as? [String]
        XCTAssertEqual(pageRemote, [], "a page without KaTeX")
        try await waitFor(webView, "document.querySelectorAll('.language-markmap svg foreignObject .katex').length === 1")
    }

    /// The deck's PDF waited a fixed 1.2s and then only for `readyState`, so
    /// a Mermaid slide could print before it was drawn. The wait now holds
    /// until the export's `?print-pdf` page, reveal and every diagram are in.
    @MainActor
    func testADeckPrintsOnlyOnceItsDiagramsAreDrawn() async throws {
        let deck = """
            # Flow

            ```mermaid
            graph TD
              A[Start] --> B[Ship]
            ```

            ---

            # Map

            ```markmap
            # Root
            ## One
            ## Two
            ```
            """
        let (webView, window) = try loadSlides(deck, printing: true)
        defer { window.orderOut(nil) }
        let ready = MPreviewView.deckReadyScript(awaitingPrintPage: true)
        let deadline = Date().addingTimeInterval(20)
        var isReady = false
        while Date() < deadline, !isReady {
            isReady = (try? await webView.evaluateJavaScript(ready) as? Bool) == true
            if !isReady { try await Task.sleep(nanoseconds: 25_000_000) }
        }
        XCTAssertTrue(isReady, "the deck became ready")
        let found = try await webView.evaluateJavaScript(
            """
            [/print-pdf/.test(location.search),
             [...document.querySelectorAll('code.language-mermaid')].map((c) => !!c.querySelector('svg')),
             [...document.querySelectorAll('code.language-markmap')].map((c) => c.dataset.markmapShown === 'true' && !!c.querySelector('.markmap-node'))]
            """)
        let result = try XCTUnwrap(found as? [Any])
        XCTAssertEqual(result[0] as? Bool, true, "the export's own page, \(result)")
        XCTAssertEqual(result[1] as? [Bool], [true], "the flowchart is drawn when the deck reads ready, \(result)")
        XCTAssertEqual(result[2] as? [Bool], [true], "the map is drawn and settled, \(result)")
    }

    /// A slide's code block that only reads like a map ("markmap is…") is
    /// tagged as one by the fallback; drawn by markmap's loader or not, it
    /// ends shown or failed, so the deck still reads ready. A page not reloaded for the export does
    /// not read ready to an export that awaits that reload.
    @MainActor
    func testADeckWaitEndsForABlockThatIsNoMap() async throws {
        let (webView, window) = try loadSlides("# Tools\n\n```\nmarkmap is the tool we use\n```\n\n---\n\n# Next\n")
        defer { window.orderOut(nil) }
        try await waitFor(webView, "!!window.Reveal && Reveal.isReady()")
        let deadline = Date().addingTimeInterval(15)
        var isReady = false
        while Date() < deadline, !isReady {
            isReady = (try? await webView.evaluateJavaScript(MPreviewView.deckReadyScript(awaitingPrintPage: false)) as? Bool) == true
            if !isReady { try await Task.sleep(nanoseconds: 50_000_000) }
        }
        XCTAssertTrue(isReady, "the wait ends")
        let marker = try await webView.evaluateJavaScript(
            "(() => { const c = document.querySelector('code.language-markmap'); return c ? (c.dataset.markmapShown || c.dataset.markmapFailed || '') : 'no block' })()")
        XCTAssertEqual(marker as? String, "true", "the block carries one of the two markers")
        let awaiting = try await webView.evaluateJavaScript(MPreviewView.deckReadyScript(awaitingPrintPage: true)) as? Bool
        XCTAssertEqual(awaiting, false, "this page is not the export's ?print-pdf reload")
    }

    /// A video written as an image (`![](/files/clip.mov)`) drew as a
    /// broken image on its slide: reveal's markdown makes every `![](…)` an
    /// `<img>`. The slide shows a player.
    @MainActor
    func testASlideVideoIsAPlayer() async throws {
        let files = tempDirectory.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        try Data([0]).write(to: files.appendingPathComponent("clip.mov"))
        let (webView, window) = try loadSlides("# Clip\n\n![](/files/clip.mov)\n\n---\n\n# Next\n")
        defer { window.orderOut(nil) }
        try await waitFor(webView, "!!window.Reveal && Reveal.isReady()")

        let found = try await webView.evaluateJavaScript(
            """
            [document.querySelectorAll('.reveal video').length,
             document.querySelectorAll('.reveal img').length,
             document.querySelector('.reveal video')?.getAttribute('preload') || '']
            """)
        let result = try XCTUnwrap(found as? [Any])
        XCTAssertEqual(result[0] as? Int, 1, "\(result)")
        XCTAssertEqual(result[1] as? Int, 0, "no image stands for the video, \(result)")
        XCTAssertEqual(result[2] as? String, "none", "\(result)")
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

    /// The deck page MPreviewView loads for `markdown`, in a window off
    /// screen so reveal lays it out and its diagrams draw. `printing` renders
    /// it as a PPT export does, and the page reloads itself with `?print-pdf`.
    @MainActor
    private func loadSlides(_ markdown: String, printing: Bool = false) throws -> (WKWebView, NSWindow) {
        let previous = (
            preview: UserDefaultsManagement.preview, presentation: UserDefaultsManagement.presentation,
            ppt: UserDefaultsManagement.magicPPT, exporting: UserDefaultsManagement.isOnExportPPT
        )
        UserDefaultsManagement.magicPPT = true
        UserDefaultsManagement.isOnExportPPT = printing
        defer {
            UserDefaultsManagement.magicPPT = previous.ppt
            if !previous.ppt {
                UserDefaultsManagement.presentation = previous.presentation
                UserDefaultsManagement.preview = previous.preview
            }
            UserDefaultsManagement.isOnExportPPT = previous.exporting
        }
        let processed = HtmlManager.processImagesInMarkdown(markdown, imagesStorage: tempDirectory)
        let page = try HtmlManager.htmlFromTemplate(processed, css: HtmlManager.previewStyle(), currentName: "deck")
        let index = try XCTUnwrap(HtmlManager.createTemporaryBundle(pageHTMLString: page))
        addTeardownBlock { try? FileManager.default.removeItem(at: index) }
        // A window off screen gets no animation frames, which the deck on
        // screen has; frames come from a timer, as the other Markmap tests
        // here run them, or d3's transitions on a map never end.
        let webView = makeWebView()
        webView.configuration.userContentController.addUserScript(
            WKUserScript(
                source: "window.requestAnimationFrame = (cb) => setTimeout(() => cb(performance.now()), 16);",
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.orderBack(nil)
        webView.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        return (webView, window)
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
private final class LoadCountingPreviewView: MPreviewView {
    private(set) var loads = 0

    override func load(note: Note, force: Bool = false, completion: (() -> Void)? = nil) {
        loads += 1
        super.load(note: note, force: force, completion: completion)
    }
}

@MainActor
private final class ExportTestPreviewView: MPreviewView {
    override func load(note: Note, force: Bool = false, completion: (() -> Void)? = nil) {}
}
