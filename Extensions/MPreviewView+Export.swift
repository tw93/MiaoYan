import AppKit
import Carbon.HIToolbox
import CryptoKit
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
        exportAction: @escaping (ExportCache.ExportData) -> Void
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
        }

        // Check cache first
        if let cachedData = ExportCache.shared.getCachedData(for: note),
            cachedData.isImageLoaded
        {
            DispatchQueue.main.async {
                exportAction(cachedData)
                resetExportFlag()
            }
            return
        }

        // Need fresh export
        waitForWebViewReady { [weak self] in
            guard let self else {
                resetExportFlag()
                viewController.toastExport(status: false)
                return
            }

            self.waitForImagesLoaded { [weak self] in
                guard let self else {
                    resetExportFlag()
                    viewController.toastExport(status: false)
                    return
                }

                // Get the actual rendered HTML from WebView
                self.evaluateJavaScript("document.documentElement.outerHTML.toString()") { htmlResult, _ in
                    let renderedHTML = htmlResult as? String ?? note.getPrettifiedContent()

                    if !needsDimensions {
                        let exportData = self.createExportData(note: note, processedHTML: renderedHTML)
                        ExportCache.shared.setCachedData(exportData, for: note)
                        exportAction(exportData)
                        resetExportFlag()
                    } else {
                        self.getContentDimensions { height, width in
                            let exportData = self.createExportData(note: note, height: height, width: width, processedHTML: renderedHTML)
                            ExportCache.shared.setCachedData(exportData, for: note)
                            exportAction(exportData)
                            resetExportFlag()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Export Methods
    public func exportPdf() {
        guard let vc = ViewController.shared(),
            let note = vc.notesTableView.getSelectedNote()
        else { return }

        performExport(note: note, viewController: vc, needsDimensions: true) { [weak self] exportData in
            guard let self else {
                Self.isExporting = false
                vc.toastExport(status: false)
                return
            }

            let pdfConfiguration = WKPDFConfiguration()
            pdfConfiguration.rect = CGRect(x: 0, y: 0, width: self.bounds.width, height: exportData.contentHeight)

            self.createPDF(configuration: pdfConfiguration) { result in
                Self.isExporting = false
                switch result {
                case .success(let pdfData):
                    self.saveToDownloads(data: pdfData, extension: "pdf", viewController: vc)
                case .failure:
                    vc.toastExport(status: false)
                }
            }
        }
    }

    public func exportImage() {
        guard let vc = ViewController.shared(),
            let note = vc.notesTableView.getSelectedNote()
        else { return }

        performExport(note: note, viewController: vc, needsDimensions: true) { [weak self] exportData in
            guard let self else {
                Self.isExporting = false
                vc.toastExport(status: false)
                return
            }

            let config = WKSnapshotConfiguration()
            config.rect = CGRect(x: 0, y: 0, width: exportData.contentWidth, height: exportData.contentHeight)
            config.afterScreenUpdates = true
            config.snapshotWidth = NSNumber(value: Double(exportData.contentWidth) * 2.0)
            self.frame.size.height = exportData.contentHeight

            self.takeSnapshot(with: config) { image, _ in
                Self.isExporting = false
                if let image = image {
                    self.handleImageExportSuccess(image: image, note: note, viewController: vc)
                } else {
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

                let htmlBody = renderMarkdownHTML(markdown: markdown) ?? markdown

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

    private func waitForImagesLoaded(completion: @escaping () -> Void) {
        let checkImagesScript = HtmlManager.checkImagesScript

        func checkImages() {
            evaluateJavaScript(checkImagesScript) { result, _ in
                if let allImagesLoaded = result as? Bool, allImagesLoaded {
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

    // MARK: - Content Size Helpers
    private func getContentHeight(completion: @escaping (CGFloat?) -> Void) {
        // Robust height calculation using several DOM properties
        let js = "(function(){var b=document.body,e=document.documentElement;return Math.max(b.scrollHeight,b.offsetHeight,e.clientHeight,e.scrollHeight,e.offsetHeight);})()"
        evaluateJavaScript(js) { result, _ in
            if let h = result as? CGFloat {
                completion(h)
            } else if let h = result as? Double {
                completion(CGFloat(h))
            } else if let h = result as? Int {
                completion(CGFloat(h))
            } else {
                completion(nil)
            }
        }
    }

    private func getContentDimensions(completion: @escaping (_ height: CGFloat, _ width: CGFloat) -> Void) {
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
}
