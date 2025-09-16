import AppKit
import Carbon.HIToolbox
import CryptoKit
import PDFKit
import WebKit

// MARK: - Export Cache Manager
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
            self?.cache[key] = data
            self?.cleanupCacheIfNeeded()
        }
    }

    func invalidateCache(for note: Note) {
        let key = getCacheKey(for: note)
        cacheQueue.async { [weak self] in
            self?.cache.removeValue(forKey: key)
        }
    }

    private func getCacheKey(for note: Note) -> String {
        let content = note.getPrettifiedContent()
        let appearanceKey = UserDataService.instance.isDark ? "dark" : "light"
        let settingsKey = "\(UserDefaultsManagement.previewFontSize)_\(UserDefaultsManagement.previewFontName)"
        let combinedData = "\(content)_\(appearanceKey)_\(settingsKey)".data(using: .utf8) ?? Data()
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

    // MARK: - Export Methods

    public func exportPdf() {
        guard let vc = ViewController.shared() else { return }
        guard #available(macOS 11.0, *) else {
            vc.toastExport(status: false)
            return
        }

        // Get the currently selected note from the ViewController
        guard let note = vc.notesTableView.getSelectedNote() else { return }

        // Check if we have valid cached data AND the WebView content matches
        if let cachedData = ExportCache.shared.getCachedData(for: note),
            cachedData.isImageLoaded,
            self.isCurrentContentMatchingCache(cachedData, for: note)
        {
            // Use cached dimensions for immediate export without triggering preview refresh
            DispatchQueue.main.async {
                let pdfConfiguration = WKPDFConfiguration()
                pdfConfiguration.rect = CGRect(x: 0, y: 0, width: self.bounds.width, height: cachedData.contentHeight)
                self.createPDF(configuration: pdfConfiguration) { result in
                    self.handlePDFExportResult(result, viewController: vc)
                }
            }
            return
        }

        // No valid cache or content changed, need to ensure images are loaded first
        waitForImagesLoaded { [weak self] in
            guard let self else { return }
            self.getContentHeight { contentHeight in
                guard let height = contentHeight else {
                    vc.toastExport(status: false)
                    return
                }

                // Cache the content dimensions and mark images as loaded
                let exportData = ExportCache.ExportData(
                    contentHash: "",
                    contentHeight: height,
                    contentWidth: self.bounds.width,
                    processedHTML: note.getPrettifiedContent(),
                    timestamp: Date(),
                    isImageLoaded: true
                )
                ExportCache.shared.setCachedData(exportData, for: note)

                DispatchQueue.main.async {
                    let pdfConfiguration = WKPDFConfiguration()
                    pdfConfiguration.rect = CGRect(x: 0, y: 0, width: self.bounds.width, height: height)
                    self.createPDF(configuration: pdfConfiguration) { result in
                        self.handlePDFExportResult(result, viewController: vc)
                    }
                }
            }
        }
    }

    public func exportImage() {
        guard let vc = ViewController.shared() else { return }

        // Get the currently selected note from the ViewController
        guard let note = vc.notesTableView.getSelectedNote() else { return }

        // Check if we have valid cached data AND the WebView content matches
        if let cachedData = ExportCache.shared.getCachedData(for: note),
            cachedData.isImageLoaded,
            self.isCurrentContentMatchingCache(cachedData, for: note)
        {
            // Use cached dimensions for immediate export without triggering preview refresh
            DispatchQueue.main.async {
                let config = WKSnapshotConfiguration()
                config.rect = CGRect(x: 0, y: 0, width: cachedData.contentWidth, height: cachedData.contentHeight)
                config.afterScreenUpdates = true
                config.snapshotWidth = NSNumber(value: Double(cachedData.contentWidth) * 2.0)
                self.frame.size.height = cachedData.contentHeight
                self.takeSnapshot(with: config) { image, error in
                    self.handleImageExportResult(image: image, error: error, viewController: vc)
                }
            }
            return
        }

        // No valid cache or content changed, need to ensure images are loaded first
        waitForImagesLoaded { [weak self] in
            guard let self else { return }
            self.getContentDimensions { contentHeight, contentWidth in
                // Cache the content dimensions and mark images as loaded
                let exportData = ExportCache.ExportData(
                    contentHash: "",
                    contentHeight: contentHeight,
                    contentWidth: contentWidth,
                    processedHTML: note.getPrettifiedContent(),
                    timestamp: Date(),
                    isImageLoaded: true
                )
                ExportCache.shared.setCachedData(exportData, for: note)

                DispatchQueue.main.async {
                    let config = WKSnapshotConfiguration()
                    config.rect = CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
                    config.afterScreenUpdates = true
                    config.snapshotWidth = NSNumber(value: Double(contentWidth) * 2.0)
                    self.frame.size.height = contentHeight
                    self.takeSnapshot(with: config) { image, error in
                        self.handleImageExportResult(image: image, error: error, viewController: vc)
                    }
                }
            }
        }
    }

    public func exportHtml() {
        guard let vc = ViewController.shared() else { return }

        // Get the currently selected note from the ViewController
        guard let note = vc.notesTableView.getSelectedNote() else { return }

        // Generate HTML directly without WebView - completely bypassing preview system
        self.generateHtmlDirectly(note: note, viewController: vc)
    }

    // MARK: - Export Helper Methods

    private func generateHtmlDirectly(note: Note, viewController: ViewController) {
        // Get the title on main thread first
        let currentName = viewController.titleLabel.stringValue

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                // Use cached data if available
                if let cachedData = ExportCache.shared.getCachedData(for: note) {
                    let completeHtml = try self.generateCompleteHtml(
                        content: cachedData.processedHTML,
                        currentName: currentName
                    )
                    DispatchQueue.main.async {
                        self.saveToDownloadsWithFilename(content: completeHtml, extension: "html", filename: note.getExportTitle(), viewController: viewController)
                    }
                    return
                }

                // Generate fresh HTML - First convert markdown to HTML
                let markdownString = note.getPrettifiedContent()

                guard let htmlString = renderMarkdownHTML(markdown: markdownString) else {
                    throw NSError(domain: "HtmlExport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to convert markdown to HTML"])
                }

                let completeHtml = try self.generateCompleteHtml(
                    content: htmlString,
                    currentName: currentName
                )

                // Cache the result with the converted HTML
                let exportData = ExportCache.ExportData(
                    contentHash: "",
                    contentHeight: 0,
                    contentWidth: 0,
                    processedHTML: htmlString,
                    timestamp: Date(),
                    isImageLoaded: false
                )
                ExportCache.shared.setCachedData(exportData, for: note)

                DispatchQueue.main.async {
                    self.saveToDownloadsWithFilename(content: completeHtml, extension: "html", filename: note.getExportTitle(), viewController: viewController)
                }

            } catch {
                // Only fall back to WebView if absolutely necessary
                DispatchQueue.main.async {
                    self.exportHtmlFallback(vc: viewController)
                }
            }
        }
    }

    private func generateCompleteHtml(content: String, currentName: String) throws -> String {
        let css = HtmlManager.previewStyle()
        return try HtmlManager.htmlFromTemplate(content, css: css, currentName: currentName)
    }

    private func exportHtmlFallback(vc: ViewController) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.executeJavaScriptWhenReady(
                "",
                completion: {
                    self.evaluateJavaScript("document.documentElement.outerHTML.toString()") { html, error in
                        guard let contentHtml = html as? String, error == nil else {
                            vc.toastExport(status: false)
                            return
                        }
                        self.saveToDownloads(content: contentHtml, extension: "html", viewController: vc)
                    }
                })
        }
    }

    private func waitForImagesLoaded(completion: @escaping () -> Void) {
        let checkImagesScript = HtmlManager.checkImagesScript

        func checkImages() {
            evaluateJavaScript(checkImagesScript) { result, _ in
                if let allImagesLoaded = result as? Bool, allImagesLoaded {
                    completion()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        checkImages()
                    }
                }
            }
        }

        checkImages()
    }

    private func isCurrentContentMatchingCache(_ cachedData: ExportCache.ExportData, for note: Note) -> Bool {
        let currentContent = note.getPrettifiedContent()
        return currentContent == cachedData.processedHTML
    }

    // MARK: - Export Result Handlers

    private func handlePDFExportResult(_ result: Result<Data, Error>, viewController: Any) {
        guard let vc = viewController as? ViewController else { return }
        switch result {
        case .success(let pdfData):
            saveToDownloads(data: pdfData, extension: "pdf", viewController: vc)
        case .failure:
            vc.toastExport(status: false)
        }
    }

    private func handleImageExportResult(image: NSImage?, error: Error?, viewController: Any) {
        guard let vc = viewController as? ViewController else { return }

        if let image = image {
            // Get the currently selected note to get the correct filename
            guard let note = vc.notesTableView.getSelectedNote() else {
                vc.toastExport(status: false)
                return
            }

            // Convert image to PNG data
            guard let tiffData = image.tiffRepresentation,
                let bitmapImage = NSBitmapImageRep(data: tiffData),
                let imageData = bitmapImage.representation(using: .png, properties: [:])
            else {
                vc.toastExport(status: false)
                return
            }

            // Use the unified save method with correct filename
            saveToDownloadsWithFilename(data: imageData, extension: "png", filename: note.getExportTitle(), viewController: vc)
        } else {
            vc.toastExport(status: false)
        }
    }

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

        // Perform file save on background queue
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard self != nil else { return }

            guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                DispatchQueue.main.async {
                    vc.toastExport(status: false)
                }
                return
            }

            // Prefer current selected note's export title
            let currentName = vc.notesTableView.getSelectedNote()?.getExportTitle() ?? "MiaoYan"
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
