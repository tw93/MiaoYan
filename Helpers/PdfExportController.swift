import AppKit
import PDFKit
import WebKit

// Drives a single paginated PDF export end-to-end using an offscreen WKWebView + NSPrintOperation.
//
// Why offscreen: WKWebView.printOperation(with:) crashes with "WKPrintingView frame not initialized"
// when called against a web view whose layout is under split-view pressure. A dedicated webview in a
// hidden NSWindow sidesteps that entirely.
//
// Why runModal (not run()): synchronous NSPrintOperation.run() is documented to blank or crash for
// WKWebView. runModal gives WebKit a runloop tick to set up WKPrintingView before knowsPageRange:.
//
// Why explicit op.view.frame: AppKit does not auto-size WKPrintingView; the crash above fires unless
// we assign a non-zero frame between printOperation(with:) and runModal.
//
// See Apple DevForums 705138 for the canonical recipe.
@MainActor
final class PdfExportController: NSObject {
    private let note: Note
    private let html: String
    private let baseURL: URL
    private weak var viewController: ViewController?

    private var window: NSWindow?
    private var webView: WKWebView?
    private var navigationDelegate: Delegate?
    private var completion: ((Bool) -> Void)?
    private var headings: MPreviewView.HeadingExtractResult = MPreviewView.HeadingExtractResult(items: [], totalHeight: 0)
    private var tempURL: URL?
    private var indexURL: URL?
    private var mediaWaitAttempts = 0
    private static let mediaWaitMaxAttempts = 80  // 80 * 120ms ≈ 9.6s
    private static let pageSize = NSSize(width: 595.2, height: 841.8)  // A4 at 72dpi

    init(note: Note, html: String, baseURL: URL, viewController: ViewController) {
        self.note = note
        self.html = html
        self.baseURL = baseURL
        self.viewController = viewController
        super.init()
    }

    func run(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        buildOffscreenWebView()
        loadHTML()
    }

    // MARK: - Setup

    private func buildOffscreenWebView() {
        let userContent = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = userContent
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.suppressesIncrementalRendering = false
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let frame = NSRect(origin: .zero, size: Self.pageSize)
        let web = WKWebView(frame: frame, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        let delegate = Delegate(owner: self)
        web.navigationDelegate = delegate
        self.navigationDelegate = delegate
        self.webView = web

        // On-screen origin, fully transparent. WebKit needs the window to be composited to
        // render images; an alpha-zero window satisfies that without flashing the screen the
        // way makeKeyAndOrderFront + setIsVisible(false) briefly would.
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        win.alphaValue = 0
        win.isOpaque = false
        win.backgroundColor = .clear
        win.contentView = web
        win.orderFrontRegardless()
        self.window = win
    }

    private func loadHTML() {
        // Write HTML to a sibling of the preview bundle so <link> css and <img> relative paths
        // resolve the same way the live preview resolves them. loadFileURL grants sandbox access.
        let url = baseURL.appendingPathComponent("pdf-export-\(UUID().uuidString).html")
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            fail()
            return
        }
        indexURL = url
        webView?.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    // MARK: - Post-load pipeline

    fileprivate func didFinishNavigation() {
        injectPrintStylesAndTitle { [weak self] in
            self?.waitForMedia()
        }
    }

    fileprivate func didFailNavigation() {
        fail()
    }

    private func injectPrintStylesAndTitle(completion: @escaping () -> Void) {
        guard let web = webView else {
            completion()
            return
        }
        let css = HtmlManager.paginatedPrintCSS()
        let safeTitle = escapeForJS(note.getExportTitle())
        // Un-lazy: MiaoYan's preview keeps non-first images on a placeholder GIF + data-src
        // until the user scrolls them into view. The offscreen print webview never scrolls, so
        // those placeholders would render as blank boxes. Swap data-src back to src before print.
        // Also kick off an async Promise.all of img.decode() and park the completion flag on
        // window so waitForMedia can poll it.
        let script = """
            (function() {
                var s = document.createElement('style');
                s.id = 'miaoyan-pdf-print-style';
                s.innerHTML = `\(css)`;
                document.head.appendChild(s);

                var container = document.getElementById('write') || document.body;
                if (container && !document.getElementById('export-generated-title')) {
                    var h = document.createElement('h1');
                    h.id = 'export-generated-title';
                    h.innerText = '\(safeTitle)';
                    h.style.cssText = 'font-size: 2em !important; font-weight: bold !important; margin: 0 0 18px 0 !important; padding: 0 0 10px 0 !important; border-bottom: 1px solid #eee !important;';
                    container.insertBefore(h, container.firstChild);
                }

                document.querySelectorAll('img[data-src]').forEach(function(img) {
                    var real = img.getAttribute('data-src');
                    if (real) img.src = real;
                    img.removeAttribute('loading');
                    img.removeAttribute('data-src');
                    img.classList.remove('lazy-image');
                });
                document.querySelectorAll('img[loading]').forEach(function(img) {
                    img.removeAttribute('loading');
                });

                var toc = document.querySelector('.toc-nav');
                var tocTrigger = document.querySelector('.toc-hover-trigger');
                if (toc) toc.style.display = 'none';
                if (tocTrigger) tocTrigger.style.display = 'none';

                void document.body.offsetHeight;
                return true;
            })();
            """
        web.evaluateJavaScript(script) { _, _ in
            completion()
        }
    }

    private func waitForMedia() {
        guard let web = webView else {
            fail()
            return
        }
        // After un-lazy swap, every image has its real src. complete + naturalWidth>0 is
        // enough: it means the image finished downloading and is a valid bitmap. Skipping
        // img.decode() cuts a couple of seconds on note pages with many images.
        let probe = """
            (function() {
                var imgs = Array.prototype.slice.call(document.images || []);
                var imgsReady = imgs.every(function(i) { return i.complete && i.naturalWidth > 0; });
                var pendingMermaid = document.querySelectorAll('.miaoyan-mermaid:not(.rendered), svg.mermaid-unrendered').length;
                return imgsReady && pendingMermaid === 0;
            })();
            """
        web.evaluateJavaScript(probe) { [weak self] result, _ in
            guard let self else { return }
            let ready = (result as? Bool) ?? false
            if ready || self.mediaWaitAttempts >= Self.mediaWaitMaxAttempts {
                self.extractHeadings()
            } else {
                self.mediaWaitAttempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    self?.waitForMedia()
                }
            }
        }
    }

    private func extractHeadings() {
        guard let web = webView else {
            fail()
            return
        }
        web.evaluateJavaScript(MPreviewView.pdfHeadingExtractionScript) { [weak self] result, _ in
            guard let self else { return }
            self.headings = MPreviewView.parseHeadingExtractResult(result)
            // One runloop tick so WebKit finalizes layout before print.
            DispatchQueue.main.async { [weak self] in
                self?.runPrint()
            }
        }
    }

    // MARK: - Print

    private func runPrint() {
        guard let web = webView, let win = window else {
            fail()
            return
        }

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("miaoyan-pdf-\(UUID().uuidString).pdf")
        self.tempURL = tempURL

        let printInfo = NSPrintInfo()
        printInfo.paperSize = Self.pageSize
        // 14mm top, 17mm bottom, 16mm sides. Tighter than the earlier 18/20/16/16 defaults so
        // the first-page title sits closer to the top without feeling cramped.
        printInfo.topMargin = 40
        printInfo.bottomMargin = 48
        printInfo.leftMargin = 45
        printInfo.rightMargin = 45
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = tempURL as NSURL

        let op = web.printOperation(with: printInfo)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        // Required: AppKit does not auto-size WKPrintingView; assigning a non-zero frame here
        // prevents the "frame was not initialized properly before knowsPageRange:" crash.
        op.view?.frame = NSRect(origin: .zero, size: printInfo.paperSize)

        op.runModal(
            for: win,
            delegate: self,
            didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
            contextInfo: nil
        )
    }

    // NSPrintOperation invokes this on a background thread when runModal finishes.
    // Mark nonisolated so Swift Concurrency doesn't trap the executor mismatch; hop to main
    // before touching any @MainActor state.
    @objc nonisolated
    private func printOperationDidRun(_ printOperation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        Task { @MainActor [weak self] in
            self?.handlePrintCompletion(success: success)
        }
    }

    private func handlePrintCompletion(success: Bool) {
        guard success, let url = tempURL, let data = try? Data(contentsOf: url), data.count > 1024 else {
            fail()
            return
        }

        let finalData = MPreviewView.buildPdfOutline(
            pdfData: data,
            headings: headings.items,
            totalHeight: headings.totalHeight)

        if let vc = viewController {
            // Reuse the live preview's save helper (requires an MPreviewView instance for routing).
            if let preview = vc.editArea?.markdownView {
                preview.saveToDownloadsWithFilename(
                    data: finalData,
                    extension: "pdf",
                    filename: note.getExportTitle(),
                    viewController: vc)
            } else {
                saveFallback(data: finalData, viewController: vc)
            }
        }

        try? FileManager.default.removeItem(at: url)
        tempURL = nil
        teardown()
        completion?(true)
        completion = nil
    }

    private func saveFallback(data: Data, viewController vc: ViewController) {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            vc.toastExport(status: false)
            return
        }
        let target = downloads.appendingPathComponent("\(note.getExportTitle()).pdf")
        do {
            try data.write(to: target)
            vc.toastExport(status: true)
        } catch {
            vc.toastExport(status: false)
        }
    }

    private func fail() {
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url)
            tempURL = nil
        }
        teardown()
        completion?(false)
        completion = nil
    }

    private func teardown() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        webView = nil
        navigationDelegate = nil
        if let url = indexURL {
            try? FileManager.default.removeItem(at: url)
            indexURL = nil
        }
    }

    private func escapeForJS(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    // Navigation delegate held off-self so the controller can remain @MainActor and stay clean.
    private final class Delegate: NSObject, WKNavigationDelegate {
        weak var owner: PdfExportController?
        init(owner: PdfExportController) { self.owner = owner }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor [weak owner] in owner?.didFinishNavigation() }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor [weak owner] in owner?.didFailNavigation() }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor [weak owner] in owner?.didFailNavigation() }
        }
    }
}
