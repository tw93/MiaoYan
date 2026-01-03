import AppKit
import Carbon.HIToolbox
import CryptoKit
import ObjectiveC.runtime
import PDFKit
import WebKit

// MARK: - Export Cache Manager
@MainActor
class ExportCache {
    static let shared = ExportCache()
    private var cache: [String: ExportData] = [:]
    private let cacheQueue = DispatchQueue(label: "export.cache", qos: .utility)
    private let maxCacheSize = 50

    struct ExportData {
        let contentHash: String
        let contentHeight: CGFloat
        let contentWidth: CGFloat
        let processedHTML: String
        let timestamp: Date
        let isImageLoaded: Bool

        var isValid: Bool {
            Date().timeIntervalSince(timestamp) < 300  // 5 minutes cache
        }
    }

    private init() {}

    func getCachedData(for note: Note) -> ExportData? {
        let key = getCacheKey(for: note)
        return cacheQueue.sync {
            guard let data = cache[key], data.isValid else {
                cache.removeValue(forKey: key)
                return nil
            }
            return data
        }
    }

    func setCachedData(_ data: ExportData, for note: Note) {
        let key = getCacheKey(for: note)
        cacheQueue.async { [weak self] in
            Task { @MainActor [weak self] in
                self?.cache[key] = data
                self?.cleanupCacheIfNeeded()
            }
        }
    }

    func invalidateCache(for note: Note) {
        let key = getCacheKey(for: note)
        cacheQueue.async { [weak self] in
            Task { @MainActor [weak self] in
                self?.cache.removeValue(forKey: key)
            }
        }
    }

    private func getCacheKey(for note: Note) -> String {
        let content = note.getPrettifiedContent()
        let appearanceKey = UserDataService.instance.isDark ? "dark" : "light"
        let settingsKey = "\(UserDefaultsManagement.previewFontSize)_\(UserDefaultsManagement.previewFontName)"
        let combinedString = "\(content)_\(appearanceKey)_\(settingsKey)"
        let combinedData = Data(combinedString.utf8)
        return SHA256.hash(data: combinedData).compactMap { String(format: "%02x", $0) }.joined()
    }

    private func cleanupCacheIfNeeded() {
        if cache.count > maxCacheSize {
            let sortedCache = cache.sorted { $0.value.timestamp < $1.value.timestamp }
            let itemsToRemove = sortedCache.prefix(cache.count - maxCacheSize)
            for (key, _) in itemsToRemove {
                cache.removeValue(forKey: key)
            }
        }
    }
}

// MARK: - Export Extensions
@MainActor
extension MPreviewView {

    private static var isExporting = false
    private static var exportStartTime: Date?
    private static let exportTimeout: TimeInterval = 30.0

    // MARK: - Export Data Creation Helper
    private func createExportData(note: Note, height: CGFloat = 0, width: CGFloat = 0, processedHTML: String? = nil) -> ExportCache.ExportData {
        return ExportCache.ExportData(
            contentHash: "",
            contentHeight: height,
            contentWidth: width == 0 ? self.bounds.width : width,
            processedHTML: processedHTML ?? note.getPrettifiedContent(),
            timestamp: Date(),
            isImageLoaded: true
        )
    }

    // MARK: - Unified Export Base Method
    private func performExport(
        note: Note,
        viewController: ViewController,
        needsDimensions: Bool,
        exportAction: @escaping (ExportCache.ExportData, @escaping () -> Void) -> Void
    ) {
        // Check if already exporting
        if Self.isExporting {
            // Check if previous export is stuck (timeout exceeded)
            if let startTime = Self.exportStartTime,
                Date().timeIntervalSince(startTime) > Self.exportTimeout
            {
                Self.isExporting = false
                Self.exportStartTime = nil
                // Continue to perform export after reset
            } else {
                viewController.toastExport(status: false)
                return
            }
        }

        Self.isExporting = true
        Self.exportStartTime = Date()

        // Show progress toast immediately
        viewController.toastPersistent(message: "\(I18n.str("Exporting...")) 0%")

        // Setup timeout protection
        let timeoutWorkItem = DispatchWorkItem { [weak viewController] in
            if Self.isExporting {
                Self.isExporting = false
                Self.exportStartTime = nil
                viewController?.toastExport(status: false)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.exportTimeout, execute: timeoutWorkItem)

        let resetExportFlag = {
            Self.isExporting = false
            Self.exportStartTime = nil
            timeoutWorkItem.cancel()
            self.removePrintStyles()
        }

        // Check cache first
        if let cachedData = ExportCache.shared.getCachedData(for: note),
            cachedData.isImageLoaded
        {
            DispatchQueue.main.async {
                exportAction(cachedData, resetExportFlag)
            }
            return
        }

        // Need fresh export
        viewController.toastUpdate(message: "\(I18n.str("Exporting...")) 10%")
        waitForWebViewReady { [weak self] in
            guard let self else {
                resetExportFlag()
                viewController.toastDismiss()
                viewController.toastExport(status: false)
                return
            }

            viewController.toastUpdate(message: "\(I18n.str("Exporting...")) 20%")
            self.injectPrintStylesIfNeeded(
                needsDimensions: needsDimensions,
                adjustLayout: false,
                forceLightMode: false
            ) { [weak self] in
                guard let self else {
                    resetExportFlag()
                    viewController.toastDismiss()
                    viewController.toastExport(status: false)
                    return
                }

                viewController.toastUpdate(message: "\(I18n.str("Exporting...")) 30%")
                self.waitForImagesLoaded(
                    progressUpdate: { message in
                        viewController.toastUpdate(message: message)
                    },
                    completion: { [weak self] in
                        guard let self else {
                            resetExportFlag()
                            viewController.toastDismiss()
                            viewController.toastExport(status: false)
                            return
                        }

                        viewController.toastUpdate(message: "\(I18n.str("Exporting...")) 85%")
                        self.evaluateJavaScript("document.documentElement.outerHTML.toString()") { htmlResult, _ in
                            let renderedHTML = htmlResult as? String ?? note.getPrettifiedContent()

                            if renderedHTML.count < 50 {
                                print("Export Error: Rendered HTML is too short/invalid")
                                resetExportFlag()
                                viewController.toastDismiss()
                                viewController.toastExport(status: false)
                                return
                            }
                            viewController.toastUpdate(message: "\(I18n.str("Exporting...")) 95%")

                            if !needsDimensions {
                                let exportData = self.createExportData(note: note, processedHTML: renderedHTML)
                                ExportCache.shared.setCachedData(exportData, for: note)
                                exportAction(exportData, resetExportFlag)
                            } else {
                                self.getContentDimensions { height, width in
                                    guard height > 0 && width > 0 else {
                                        print("Export Error: Invalid dimensions h:\(height) w:\(width)")
                                        resetExportFlag()
                                        viewController.toastExport(status: false)
                                        return
                                    }

                                    let exportData = self.createExportData(note: note, height: height, width: width, processedHTML: renderedHTML)
                                    ExportCache.shared.setCachedData(exportData, for: note)
                                    exportAction(exportData, resetExportFlag)
                                }
                            }
                        }
                    }
                )
            }
        }
    }

    // MARK: - Style Injection
    private func injectPrintStylesIfNeeded(
        needsDimensions: Bool,
        applyToScreen: Bool = true,
        adjustLayout: Bool = true,
        forceLightMode: Bool = true,
        completion: @escaping () -> Void
    ) {
        if UserDefaultsManagement.magicPPT || UserDefaultsManagement.isOnExportPPT {
            completion()
            return
        }

        let baseCSS: String
        if forceLightMode {
            baseCSS = HtmlManager.lightModeExportCSS()
        } else {
            baseCSS = UserDataService.instance.isDark
                ? HtmlManager.darkModeExportCSS()
                : HtmlManager.lightModeExportCSS()
        }
        let mediaCSS =
            applyToScreen
            ? baseCSS
            : baseCSS.replacingOccurrences(of: "@media print, screen", with: "@media print")
        let layoutCSS =
            adjustLayout
            ? """
                   #write {
                       max-width: 90% !important;
                       width: 100% !important;
                       margin: 0 auto !important;
                       padding-top: 20px !important;
                       padding-bottom: 20px !important;
                   }
            """
            : ""
        let exportLayoutCSS = """
               \(layoutCSS)
               .toc-hover-trigger,
               .toc-pin-btn,
               .toc-nav {
                   display: none !important;
                   pointer-events: none !important;
               }
            """
        // Remove trailing whitespace and closing brace from mediaCSS to insert exportLayoutCSS inside the media query
        let trimmedMediaCSS = mediaCSS.trimmingCharacters(in: .whitespacesAndNewlines).dropLast()
        let printCSS = """
                (function() {
                    var style = document.createElement('style');
                    style.id = 'miaoyan-export-style';
                    style.innerHTML = `\(trimmedMediaCSS)
                           \(exportLayoutCSS)
                        }
                    `;
                    document.head.appendChild(style);
                    void document.body.offsetHeight;
                    return true;
                })();
            """

        evaluateJavaScript(printCSS) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                completion()
            }
        }
    }

    private func removePrintStyles() {
        let removeScript = "var s = document.getElementById('miaoyan-export-style'); if(s) s.remove();"
        evaluateJavaScript(removeScript, completionHandler: nil)
    }

    private func escapeForJavaScriptString(_ value: String) -> String {
        return
            value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    private func hideTOCTriggersForExport() {
        let script = """
                (function() {
                    var selectors = ['.toc-hover-trigger', '.toc-pin-btn', '.toc-nav'];
                    selectors.forEach(function(sel) {
                        document.querySelectorAll(sel).forEach(function(el) {
                            el.dataset.exportOriginalDisplay = el.style.display || '';
                            el.style.display = 'none';
                            el.style.pointerEvents = 'none';
                        });
                    });
                })();
            """
        evaluateJavaScript(script, completionHandler: nil)
    }

    private func restoreTOCTriggers() {
        let script = """
                (function() {
                    var selectors = ['.toc-hover-trigger', '.toc-pin-btn', '.toc-nav'];
                    selectors.forEach(function(sel) {
                        document.querySelectorAll(sel).forEach(function(el) {
                            if (typeof el.dataset.exportOriginalDisplay !== 'undefined') {
                                el.style.display = el.dataset.exportOriginalDisplay;
                                delete el.dataset.exportOriginalDisplay;
                            } else {
                                el.style.display = '';
                            }
                            el.style.pointerEvents = '';
                        });
                    });
                })();
            """
        evaluateJavaScript(script, completionHandler: nil)
    }
    // MARK: - Export Methods
    public func exportPdf() {
        guard let vc = ViewController.shared(),
            let note = vc.notesTableView.getSelectedNote()
        else { return }

        // Show progress toast immediately
        vc.toastPersistent(message: "\(I18n.str("Exporting...")) 0%")

        self.preparePPTExportIfNeeded()

        vc.toastUpdate(message: "\(I18n.str("Exporting...")) 10%")

        self.injectPrintStylesIfNeeded(
            needsDimensions: true,
            applyToScreen: false
        ) { [weak self] in
            guard let self else {
                vc.toastDismiss()
                vc.toastExport(status: false)
                return
            }

            vc.toastUpdate(message: "\(I18n.str("Exporting...")) 30%")

            self.evaluateJavaScript("window.scrollTo(0,0)", completionHandler: nil)

            // Wait for images to load with progress
            self.waitForImagesLoaded(
                progressUpdate: { message in
                    vc.toastUpdate(message: message)
                },
                completion: { [weak self] in
                    guard let self else {
                        vc.toastDismiss()
                        vc.toastExport(status: false)
                        return
                    }

                    vc.toastUpdate(message: "\(I18n.str("Exporting...")) 90%")

                    let safeTitle = self.escapeForJavaScriptString(note.getExportTitle())
                    let titleScript = """
                            (function() {
                                var container = document.getElementById('write') || document.body;
                                if (container && !document.getElementById('export-generated-title')) {
                                    var h1 = document.createElement('h1');
                                    h1.innerText = '\(safeTitle)';
                                    h1.id = 'export-generated-title';
                                    h1.style.cssText = 'font-size: 2em; font-weight: bold; margin-bottom: 24px; padding-bottom: 12px; border-bottom: 1px solid #eee; display: block;';
                                    container.insertBefore(h1, container.firstChild);
                                }
                            })();
                        """
                    self.evaluateJavaScript(titleScript) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            let pdfConfig = WKPDFConfiguration()

                            vc.toastUpdate(message: "\(I18n.str("Exporting...")) 95%")

                            self.createPDF(configuration: pdfConfig) { [weak self] result in
                                guard let self else { return }

                                // Cleanup: remove injected title and print styles
                                self.evaluateJavaScript(
                                    "var t = document.getElementById('export-generated-title'); if(t) t.remove();",
                                    completionHandler: nil)
                                self.removePrintStyles()
                                vc.toastDismiss()

                                switch result {
                                case .success(let data):
                                    self.saveToDownloadsWithFilename(data: data, extension: "pdf", filename: note.getExportTitle(), viewController: vc)
                                case .failure:
                                    vc.toastExport(status: false)
                                }

                                Self.isExporting = false
                            }
                        }
                    }
                }
            )
        }
    }

    public func exportImage() {
        guard let vc = ViewController.shared(),
            let note = vc.notesTableView.getSelectedNote()
        else { return }

        performExport(note: note, viewController: vc, needsDimensions: true) { [weak self] _, cleanup in
            guard let self else {
                cleanup()
                vc.toastExport(status: false)
                return
            }

            // Inject title at top of content
            let exportTitle = note.getExportTitle()
            let safeTitle = escapeForJavaScriptString(exportTitle)
            let titleScript = """
                (function() {
                    var container = document.getElementById('write') || document.body;
                        if (container && !document.getElementById('export-generated-title')) {
                            var h1 = document.createElement('h1');
                            h1.innerText = '\(safeTitle)';
                            h1.id = 'export-generated-title';
                            h1.style.cssText = 'font-size: 2em; font-weight: bold; margin-bottom: 24px; padding-bottom: 12px; border-bottom: 1px solid #eee; display: block;';
                            container.insertBefore(h1, container.firstChild);
                        }
                    })();
                """

            self.evaluateJavaScript(titleScript) { _, _ in
                // Recalculate dimensions after title injection
                self.getContentDimensions { height, width in
                    let config = WKSnapshotConfiguration()
                    config.rect = CGRect(x: 0, y: 0, width: width, height: height)
                    config.afterScreenUpdates = true
                    config.snapshotWidth = NSNumber(value: Double(width) * 2.0)
                    let originalFrame = self.frame
                    self.frame.size.height = height

                    // Scroll to top and force layout recalculation before snapshot
                    let scrollScript = """
                            (function() {
                                window.scrollTo(0, 0);
                                document.documentElement.scrollTop = 0;
                                document.body.scrollTop = 0;
                                document.body.offsetHeight; // Force layout
                                return true;
                            })();
                        """
                    self.evaluateJavaScript(scrollScript) { _, _ in
                        // Wait for layout to stabilize after frame change
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.takeSnapshot(with: config) { image, _ in
                                self.frame = originalFrame

                                // Cleanup: remove injected title
                                self.evaluateJavaScript(
                                    "var t = document.getElementById('export-generated-title'); if(t) t.remove();",
                                    completionHandler: nil)
                                cleanup()
                                vc.toastDismiss()

                                if let image = image {
                                    self.handleImageExportSuccess(image: image, note: note, viewController: vc)
                                } else {
                                    vc.toastExport(status: false)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    public func exportPPTOptimized() {
        guard let vc = ViewController.shared(),
            let note = vc.notesTableView.getSelectedNote()
        else { return }

        // Show progress toast immediately
        vc.toastPersistent(message: "\(I18n.str("Exporting...")) 0%")

        self.hideTOCTriggersForExport()
        self.preparePPTExportIfNeeded()

        vc.toastUpdate(message: "\(I18n.str("Exporting...")) 20%")

        // Wait for Reveal.js layout to stabilize
        self.waitForWebViewReady { [weak self] in
            guard let self = self else {
                vc.toastDismiss()
                vc.toastExport(status: false)
                if vc.shouldDisablePPTAfterExport {
                    vc.disableMiaoYanPPT()
                    vc.shouldDisablePPTAfterExport = false
                }
                return
            }

            vc.toastUpdate(message: "\(I18n.str("Exporting...")) 60%")

            let pdfConfig = WKPDFConfiguration()
            pdfConfig.rect = .null

            vc.toastUpdate(message: "\(I18n.str("Exporting...")) 80%")

            self.createPDF(configuration: pdfConfig) { [weak self] result in
                guard let self = self else { return }

                // Cleanup state
                UserDefaultsManagement.isOnExportPPT = false
                self.evaluateJavaScript(
                    """
                    document.documentElement.classList.remove('print-pdf');
                    document.body.classList.remove('print-pdf');
                    """, completionHandler: nil)
                self.restoreTOCTriggers()
                vc.toastDismiss()

                if vc.shouldDisablePPTAfterExport {
                    vc.disableMiaoYanPPT()
                    vc.shouldDisablePPTAfterExport = false
                }

                switch result {
                case .success(let data):
                    let filename = note.getExportTitle() + "_PPT"
                    self.saveToDownloadsWithFilename(data: data, extension: "pdf", filename: filename, viewController: vc)
                case .failure:
                    vc.toastExport(status: false)
                }
            }
        }
    }

    public func exportHtml() {
        guard let vc = ViewController.shared(),
            let note = vc.notesTableView.getSelectedNote()
        else { return }

        // HTML export does not depend on WebView layout; generate directly
        if Self.isExporting {
            // Check if previous export is stuck
            if let startTime = Self.exportStartTime,
                Date().timeIntervalSince(startTime) > Self.exportTimeout
            {
                Self.isExporting = false
                Self.exportStartTime = nil
                // Continue to perform export after reset
            } else {
                vc.toastExport(status: false)
                return
            }
        }
        Self.isExporting = true
        Self.exportStartTime = Date()

        let exportData = self.createExportData(note: note)
        self.generateHtmlDirectly(note: note, viewController: vc, exportData: exportData)
    }

    // MARK: - Export Helper Methods
    private func generateHtmlDirectly(note: Note, viewController: ViewController, exportData: ExportCache.ExportData) {
        let currentName = viewController.titleLabel.stringValue

        Task { [weak self] in
            guard let self = self else {
                Self.isExporting = false
                Self.exportStartTime = nil
                viewController.toastExport(status: false)
                return
            }

            let completeHtml = await MainActor.run {
                // For HTML export, render Markdown to HTML first, then wrap with template
                let markdown = note.getPrettifiedContent()
                let css = HtmlManager.previewStyle()

                // Set export flag to apply proper styling (fonts, width, CDN base)
                UserDefaultsManagement.isOnExportHtml = true
                defer { UserDefaultsManagement.isOnExportHtml = false }

                let useGithubLineBreak = UserDefaultsManagement.editorLineBreak == "Github"
                let htmlBody = renderMarkdownHTML(markdown: markdown, useGithubLineBreak: useGithubLineBreak) ?? markdown

                do {
                    return try HtmlManager.htmlFromTemplate(htmlBody, css: css, currentName: currentName)
                } catch {
                    // Fallback to simple HTML body if template fails
                    return htmlBody
                }
            }

            await MainActor.run {
                Self.isExporting = false
                Self.exportStartTime = nil
                self.saveToDownloadsWithFilename(content: completeHtml, extension: "html", filename: note.getExportTitle(), viewController: viewController)
            }
        }
    }

    private func handleImageExportSuccess(image: NSImage, note: Note, viewController: ViewController) {
        guard let tiffData = image.tiffRepresentation,
            let bitmapImage = NSBitmapImageRep(data: tiffData),
            let imageData = bitmapImage.representation(using: .png, properties: [:])
        else {
            viewController.toastExport(status: false)
            return
        }

        saveToDownloadsWithFilename(data: imageData, extension: "png", filename: note.getExportTitle(), viewController: viewController)
    }

    // (obsolete) previously used helper methods removed after direct HTML export refactor

    private func waitForImagesLoaded(progressUpdate: ((String) -> Void)? = nil, completion: @escaping () -> Void) {
        let checkImagesScript = HtmlManager.checkImagesScript
        var checkCount = 0
        let maxChecks = 6  // 3 seconds max (6 * 0.5s)

        func checkImages() {
            checkCount += 1

            // Update progress message (30% to 80% range for image loading)
            if let progressUpdate = progressUpdate {
                let percent = min(30 + Int((Double(checkCount) / Double(maxChecks)) * 50), 80)
                progressUpdate("\(I18n.str("Exporting...")) \(percent)%")
            }

            if checkCount >= maxChecks {
                print("[Export] Image loading timeout after \\(checkCount) checks, proceeding anyway")
                completion()
                return
            }

            evaluateJavaScript(checkImagesScript) { result, _ in
                if let allImagesLoaded = result as? Bool, allImagesLoaded {
                    // Images loaded, show final progress
                    if let progressUpdate = progressUpdate {
                        progressUpdate("\(I18n.str("Exporting...")) 82%")
                    }
                    // Add additional delay to ensure layout and rendering are complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        completion()
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        checkImages()
                    }
                }
            }
        }

        checkImages()
    }

    private func waitForWebViewReady(completion: @escaping () -> Void) {
        // Check if WebView has finished loading and rendering
        let readyScript = """
                (function() {
                    if (document.readyState !== 'complete') return false;
                    if (document.body.offsetHeight === 0) return false;
                    if (window.Reveal) {
                        // Force print-friendly layout when exporting PPT
                        if (!document.documentElement.classList.contains('print-pdf')) {
                            document.documentElement.classList.add('print-pdf');
                            document.body.classList.add('print-pdf');
                        }
                        if (typeof Reveal.layout === 'function') {
                            Reveal.layout();
                        }
                    }
                    return true;
                })()
            """

        func checkReady() {
            evaluateJavaScript(readyScript) { result, _ in
                if let isReady = result as? Bool, isReady {
                    // Additional small delay for final layout stabilization
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        completion()
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        checkReady()
                    }
                }
            }
        }

        checkReady()
    }

    // MARK: - Legacy Support
    // Removed old export result handlers - now integrated into unified export system

    // MARK: - File Save Methods
    private func saveToDownloads(content: String, extension: String, viewController: Any) {
        let data = content.data(using: .utf8) ?? Data()
        saveToDownloads(data: data, extension: `extension`, viewController: viewController)
    }

    private func saveToDownloadsWithFilename(content: String, extension: String, filename: String, viewController: Any) {
        let data = content.data(using: .utf8) ?? Data()
        saveToDownloadsWithFilename(data: data, extension: `extension`, filename: filename, viewController: viewController)
    }

    private func saveToDownloads(data: Data, extension: String, viewController: Any) {
        guard let vc = viewController as? ViewController else { return }

        // Get the selected note on main thread first
        let currentName = vc.notesTableView.getSelectedNote()?.getExportTitle() ?? "MiaoYan"

        // Perform file save on background queue
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard self != nil else { return }

            guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                DispatchQueue.main.async {
                    vc.toastExport(status: false)
                }
                return
            }
            var fileURL = downloadsURL.appendingPathComponent(currentName + "." + `extension`)

            // Check if file exists and create unique name if needed
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let timestamp = formatter.string(from: Date())
                let uniqueFilename = "\(currentName)_\(timestamp)"
                fileURL = downloadsURL.appendingPathComponent(uniqueFilename + "." + `extension`)
            }

            do {
                try data.write(to: fileURL, options: .atomic)
                DispatchQueue.main.async {
                    vc.toastExport(status: true)
                }
            } catch {
                DispatchQueue.main.async {
                    vc.toastExport(status: false)
                }
            }
        }
    }

    private func saveToDownloadsWithFilename(data: Data, extension: String, filename: String, viewController: Any) {
        guard let vc = viewController as? ViewController else { return }

        // Perform file save on background queue
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard self != nil else { return }

            guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                DispatchQueue.main.async {
                    vc.toastExport(status: false)
                }
                return
            }

            var fileURL = downloadsURL.appendingPathComponent(filename + "." + `extension`)

            // Check if file exists and create unique name if needed
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let timestamp = formatter.string(from: Date())
                let uniqueFilename = "\(filename)_\(timestamp)"
                fileURL = downloadsURL.appendingPathComponent(uniqueFilename + "." + `extension`)
            }

            do {
                try data.write(to: fileURL, options: .atomic)
                DispatchQueue.main.async {
                    vc.toastExport(status: true)
                }
            } catch {
                DispatchQueue.main.async {
                    vc.toastExport(status: false)
                }
            }
        }
    }

    private func getContentHeight(completion: @escaping (CGFloat?) -> Void) {
        // Robust height calculation using several DOM properties
        let js = "(function(){var b=document.body,e=document.documentElement;return Math.max(b.scrollHeight,b.offsetHeight,e.clientHeight,e.scrollHeight,e.offsetHeight);})()"
        evaluateJavaScript(js) { result, _ in
            let height: CGFloat? = {
                if let h = result as? CGFloat { return h }
                if let h = result as? Double { return CGFloat(h) }
                if let h = result as? Int { return CGFloat(h) }
                return nil
            }()

            completion(height)
        }
    }

    private func getContentDimensions(completion: @escaping (_ height: CGFloat, _ width: CGFloat) -> Void) {
        // Special handling for PPT/reveal exports to avoid only capturing the first slide
        if UserDefaultsManagement.magicPPT || UserDefaultsManagement.isOnExportPPT {
            let js = """
                    (function() {
                        var slidesRoot = document.querySelector('.reveal .slides');
                        var config = window.Reveal && typeof Reveal.getConfig === 'function'
                            ? Reveal.getConfig()
                            : { height: 700, width: 960 };
                        var revealHeight = config.height || 700;
                        var revealWidth = config.width || 960;
                        var totalSlides = window.Reveal && typeof Reveal.getTotalSlides === 'function'
                            ? Reveal.getTotalSlides()
                            : 0;
                        var estimatedHeight = totalSlides > 0 ? totalSlides * revealHeight * 1.2 : 0;
                        var contentHeight = slidesRoot ? Math.max(slidesRoot.scrollHeight, slidesRoot.offsetHeight, estimatedHeight) : Math.max(document.body.scrollHeight, estimatedHeight);
                        var contentWidth = slidesRoot ? Math.max(slidesRoot.scrollWidth, slidesRoot.offsetWidth, revealWidth) : Math.max(document.body.scrollWidth, revealWidth);
                        return { h: contentHeight, w: contentWidth };
                    })();
                """
            evaluateJavaScript(js) { result, _ in
                if let dict = result as? [String: Any],
                    let hVal = dict["h"] as? Double,
                    let wVal = dict["w"] as? Double
                {
                    completion(CGFloat(hVal), CGFloat(wVal))
                    return
                }
                // Fallback if bridging fails
                self.getContentDimensionsFallback(completion: completion)
            }
            return
        }

        getContentDimensionsFallback(completion: completion)
    }

    // Prepare Reveal.js layout for accurate PDF capture
    private func preparePPTExportIfNeeded() {
        guard UserDefaultsManagement.magicPPT || UserDefaultsManagement.isOnExportPPT else {
            return
        }
        guard !hasPreparedPPTExport else { return }
        hasPreparedPPTExport = true

        let script = """
                (function() {
                    document.documentElement.classList.add('print-pdf');
                    document.body.classList.add('print-pdf');
                    if (window.Reveal) {
                        if (typeof Reveal.configure === 'function') {
                            Reveal.configure({ pdfMaxPagesPerSlide: 1 });
                        }
                        if (typeof Reveal.layout === 'function') {
                            Reveal.layout();
                        }
                    }
                })();
            """
        evaluateJavaScript(script, completionHandler: nil)
    }

    private func getContentDimensionsFallback(completion: @escaping (_ height: CGFloat, _ width: CGFloat) -> Void) {
        // Compute height first, then width to keep bridging simple and reliable
        getContentHeight { height in
            let h = height ?? self.bounds.height
            let jsWidth = "(function(){var b=document.body,e=document.documentElement;return Math.max(b.scrollWidth,b.offsetWidth,e.clientWidth,e.scrollWidth,e.offsetWidth);})()"
            self.evaluateJavaScript(jsWidth) { result, _ in
                var w: CGFloat = self.bounds.width
                if let ww = result as? CGFloat { w = ww } else if let ww = result as? Double { w = CGFloat(ww) } else if let ww = result as? Int { w = CGFloat(ww) }
                completion(h, w)
            }
        }
    }

    private func combinePDFs(pdfDatas: [Data]) -> Data? {
        let pdfDocument = PDFDocument()
        for pdfData in pdfDatas {
            if let dataDocument = PDFDocument(data: pdfData) {
                for pageIndex in 0..<dataDocument.pageCount {
                    if let page = dataDocument.page(at: pageIndex) {
                        pdfDocument.insert(page, at: pdfDocument.pageCount)
                    }
                }
            }
        }
        return pdfDocument.dataRepresentation()
    }

    // Stored property emulation for extensions
    private var hasPreparedPPTExport: Bool {
        get {
            (objc_getAssociatedObject(self, &AssociatedKeys.preparedPPTExport) as? Bool) ?? false
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.preparedPPTExport, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    @MainActor
    private enum AssociatedKeys {
        static var preparedPPTExport: UInt8 = 0
    }
}

// MARK: - WKScriptMessageHandler Implementation for MPreviewView
extension MPreviewView: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Handle 'logging' messages for debugging
        if message.name == "logging", let body = message.body as? String {
            #if DEBUG
                print("[JS Log] \(body)")
            #endif
        }
    }
}
