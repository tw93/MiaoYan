import SwiftUI
import UIKit
import WebKit

enum ReaderFontSize: String, CaseIterable {
    case small
    case medium
    case large

    /// Three tiers with deliberate 3pt jumps between them (15 -> 18 -> 22).
    /// Earlier four-tier scale stepped 1-2pt at a time which was visually
    /// indistinguishable on a phone screen and felt as if the setting did
    /// nothing.
    var points: CGFloat {
        let base: CGFloat
        switch self {
        case .small: base = 15
        case .medium: base = 18
        case .large: base = 22
        }
        return UIFontMetrics(forTextStyle: .body).scaledValue(for: base)
    }

    var cssPoints: Int {
        Int(points.rounded())
    }

    var label: String {
        switch self {
        case .small: return String(localized: "Small")
        case .medium: return String(localized: "Medium")
        case .large: return String(localized: "Large")
        }
    }
}

/// System-font families offered for both the editor and the reader.
/// Deliberately system-only: bundling the macOS app's licensed CJK font
/// into the iOS binary is not covered by its license.
enum ReaderFontFamily: String, CaseIterable {
    case serif
    case sans
    case rounded

    var label: String {
        switch self {
        case .serif: return String(localized: "Serif")
        case .sans: return String(localized: "Sans Serif")
        case .rounded: return String(localized: "Rounded")
        }
    }

    /// CSS font stack override for the reader. Serif returns nil because
    /// mobile-reader.css already declares the Charter/Songti serif stack
    /// as its :root default.
    var cssStack: String? {
        switch self {
        case .serif:
            return nil
        case .sans:
            return #"-apple-system, "SF Pro Text", "PingFang SC", "Heiti SC", system-ui, sans-serif"#
        case .rounded:
            return #"ui-rounded, "SF Pro Rounded", -apple-system, "PingFang SC", system-ui, sans-serif"#
        }
    }

    /// Editor body font. CJK glyphs fall back to PingFang automatically
    /// through the system cascade for every design.
    func uiFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let design: UIFontDescriptor.SystemDesign
        switch self {
        case .serif: design = .serif
        case .sans: design = .default
        case .rounded: design = .rounded
        }
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}

enum ReaderChromeIntent {
    case show
    case hide
}

// MARK: - Local asset scheme

/// URL mapping between markdown-local asset references and the custom
/// `miaoyan-asset` scheme. The reader loads notes with `loadHTMLString`,
/// which grants no local-file read access, so `MobileHtmlRenderer` rewrites
/// local image srcs to this scheme and `LocalAssetSchemeHandler` serves the
/// bytes from disk.
enum LocalAssetURL {
    static let scheme = "miaoyan-asset"

    static let allowedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "svg", "avif",
        "mp4", "mov", "m4v", "mp3", "m4a", "wav",
    ]

    private static let mimeTypes: [String: String] = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "gif": "image/gif", "webp": "image/webp", "heic": "image/heic",
        "heif": "image/heif", "bmp": "image/bmp", "svg": "image/svg+xml",
        "avif": "image/avif", "mp4": "video/mp4", "mov": "video/quicktime",
        "m4v": "video/x-m4v", "mp3": "audio/mpeg", "m4a": "audio/mp4",
        "wav": "audio/wav",
    ]

    /// Markdown img src → custom-scheme URL string, or nil when the src
    /// must be left alone (remote URLs, data URIs, non-asset extensions,
    /// or paths escaping the note's folder).
    ///
    /// Path semantics mirror macOS `Note.getImageUrl`: a leading `/` (the
    /// `/i/...` convention) and plain relative paths both resolve against
    /// the note's folder.
    static func absoluteString(forMarkdownSrc src: String, noteFolder: URL) -> String? {
        let lower = src.lowercased()
        guard
            !lower.hasPrefix("http://"), !lower.hasPrefix("https://"),
            !lower.hasPrefix("data:"), !lower.hasPrefix("file://"),
            !lower.hasPrefix(scheme + ":")
        else { return nil }

        // cmark HTML-escapes attribute values; markdown authors usually
        // percent-encode too (the macOS app writes encoded `/i/` paths).
        let unescaped = src.replacingOccurrences(of: "&amp;", with: "&")
        let decoded = unescaped.removingPercentEncoding ?? unescaped
        var relative = decoded
        if relative.hasPrefix("/") { relative.removeFirst() }
        if relative.hasPrefix("./") { relative.removeFirst(2) }
        guard !relative.isEmpty else { return nil }

        let resolved = noteFolder.appendingPathComponent(relative).standardizedFileURL
        guard allowedExtensions.contains(resolved.pathExtension.lowercased()) else { return nil }
        // `../` escapes must not leave the note's folder.
        let folderPath = noteFolder.standardizedFileURL.path
        guard resolved.path.hasPrefix(folderPath + "/") else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = ""
        components.path = resolved.path
        return components.url?.absoluteString
    }

    /// Custom-scheme URL → on-disk file URL (handler side).
    static func fileURL(from url: URL) -> URL? {
        guard url.scheme == scheme else { return nil }
        let path = url.path
        guard !path.isEmpty else { return nil }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL
        guard allowedExtensions.contains(standardized.pathExtension.lowercased()) else { return nil }
        return standardized
    }

    static func mimeType(for fileURL: URL) -> String {
        mimeTypes[fileURL.pathExtension.lowercased()] ?? "application/octet-stream"
    }
}

/// Serves `miaoyan-asset://` subresource requests from disk. Registered on
/// every reader WKWebView configuration. WKURLSchemeHandler callbacks
/// arrive on the main thread.
@MainActor
final class LocalAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    /// Only files under this root are served. AppState keeps it pointed at
    /// the current library root, so a crafted note (raw HTML + script can
    /// pass through cmark's UNSAFE mode) cannot read files outside the
    /// user's chosen library.
    static var allowedRoot: URL?

    /// Tasks that are still allowed to receive callbacks. WebKit throws
    /// if a handler touches a urlSchemeTask after `stop` was called for it.
    private var activeTasks = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask)
        activeTasks.insert(taskID)

        guard
            let requestURL = urlSchemeTask.request.url,
            let fileURL = LocalAssetURL.fileURL(from: requestURL),
            Self.isAllowed(fileURL)
        else {
            finish(urlSchemeTask, taskID: taskID) { task in
                task.didFailWithError(CocoaError(.fileReadNoSuchFile))
            }
            return
        }

        Task { [weak self] in
            let data = await Self.readData(at: fileURL)
            guard let self else { return }
            self.finish(urlSchemeTask, taskID: taskID) { task in
                guard let data else {
                    task.didFailWithError(CocoaError(.fileReadNoSuchFile))
                    return
                }
                let response = URLResponse(
                    url: fileURL,
                    mimeType: LocalAssetURL.mimeType(for: fileURL),
                    expectedContentLength: data.count,
                    textEncodingName: nil
                )
                task.didReceive(response)
                task.didReceive(data)
                task.didFinish()
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        activeTasks.remove(ObjectIdentifier(urlSchemeTask))
    }

    /// Off-main file read; iCloud/file-provider materialisation can block.
    nonisolated private static func readData(at url: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value
    }

    private static func isAllowed(_ fileURL: URL) -> Bool {
        guard let root = allowedRoot?.standardizedFileURL.resolvingSymlinksInPath() else { return false }
        let path = fileURL.resolvingSymlinksInPath().path
        return path == root.path || path.hasPrefix(root.path + "/")
    }

    /// Run `body` only if the task hasn't been stopped, then retire it.
    private func finish(
        _ task: WKURLSchemeTask, taskID: ObjectIdentifier, _ body: (WKURLSchemeTask) -> Void
    ) {
        guard activeTasks.remove(taskID) != nil else { return }
        body(task)
    }
}

struct NoteReaderView: View {
    let note: NoteFile

    var body: some View {
        NoteDetailView(note: note)
    }
}

@MainActor
enum ReaderWebViewFactory {
    static let warmupHTML = """
        <!doctype html>
        <html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { background: #f9f7f0; }
        @media (prefers-color-scheme: dark) { :root { background: #161716; } }
        </style>
        </head><body></body></html>
        """

    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // Local note attachments (images pasted on macOS/iOS) are served
        // through this handler; loadHTMLString grants no file:// access.
        config.setURLSchemeHandler(LocalAssetSchemeHandler(), forURLScheme: LocalAssetURL.scheme)
        // Suppress incremental rendering so WebView waits for the full
        // HTML + CSS to be parsed before painting. Without this, the
        // first frame shows a white/light background before dark-mode
        // CSS kicks in, producing a visible flash on the first and
        // second note open.
        config.suppressesIncrementalRendering = true
        return config
    }

    static func makeWebView() -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: makeConfiguration())
        webView.isOpaque = true
        // Paint the webview itself with paper so bounce overscroll past the
        // bottom edge doesn't expose a white default. Reader CSS also paints
        // the same colour over the content area; matching here just means the
        // overscroll region is consistent.
        webView.backgroundColor = MobileTheme.paperUIColor
        webView.scrollView.backgroundColor = MobileTheme.paperUIColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive
        return webView
    }
}

@MainActor
final class ReaderWebViewStore: ObservableObject {
    private var idleWebView: WKWebView?
    private var isWarming = false

    func warmUp() {
        guard idleWebView == nil, !isWarming else { return }
        isWarming = true

        let webView = ReaderWebViewFactory.makeWebView()
        webView.loadHTMLString(ReaderWebViewFactory.warmupHTML, baseURL: nil)
        idleWebView = webView
        isWarming = false
    }

    func checkoutWebView() -> WKWebView {
        let webView: WKWebView
        if let idleWebView {
            self.idleWebView = nil
            webView = idleWebView
        } else {
            webView = ReaderWebViewFactory.makeWebView()
        }

        Task { @MainActor [weak self] in
            await Task.yield()
            self?.warmUp()
        }

        return webView
    }
}

struct WebReaderView: UIViewRepresentable {
    let html: String
    var baseURL: URL?
    let webViewStore: ReaderWebViewStore
    var onChromeIntent: (ReaderChromeIntent) -> Void
    var onTap: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let webView = webViewStore.checkoutWebView()
        webView.scrollView.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.delegate = context.coordinator
        webView.addGestureRecognizer(tap)
        context.coordinator.tapRecognizer = tap

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onChromeIntent = onChromeIntent
        context.coordinator.onTap = onTap
        // Empty html is the "warm but no content yet" state used while cmark
        // is still rendering. Skip loadHTMLString so the webview stays in its
        // prewarmed configuration; the next call with real HTML will drive
        // the actual load.
        guard !html.isEmpty else { return }
        if context.coordinator.lastHTML != html || context.coordinator.lastBaseURL != baseURL {
            context.coordinator.lastHTML = html
            context.coordinator.lastBaseURL = baseURL
            context.coordinator.resetScrollTracking()
            webView.stopLoading()
            webView.scrollView.setContentOffset(.zero, animated: false)
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        if uiView.scrollView.delegate === coordinator {
            uiView.scrollView.delegate = nil
        }
        if let tap = coordinator.tapRecognizer {
            uiView.removeGestureRecognizer(tap)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChromeIntent: onChromeIntent, onTap: onTap)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var onChromeIntent: (ReaderChromeIntent) -> Void
        var onTap: () -> Void
        var lastHTML = ""
        var lastBaseURL: URL?
        weak var tapRecognizer: UITapGestureRecognizer?
        private let hideDistance: CGFloat = 48
        private let showDistance: CGFloat = 28
        private let topRevealOffset: CGFloat = 18
        private let noiseThreshold: CGFloat = 0.5
        private var lastOffsetY: CGFloat?
        private var accumulatedDown: CGFloat = 0
        private var accumulatedUp: CGFloat = 0

        init(onChromeIntent: @escaping (ReaderChromeIntent) -> Void, onTap: @escaping () -> Void) {
            self.onChromeIntent = onChromeIntent
            self.onTap = onTap
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let maxOffset = scrollView.contentSize.height - scrollView.bounds.height
            guard maxOffset > 0 else {
                resetScrollTracking()
                return
            }

            let offsetY = max(0, min(scrollView.contentOffset.y, maxOffset))
            guard scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating else {
                lastOffsetY = offsetY
                accumulatedDown = 0
                accumulatedUp = 0
                return
            }

            if offsetY <= topRevealOffset {
                lastOffsetY = offsetY
                accumulatedDown = 0
                accumulatedUp = 0
                onChromeIntent(.show)
                return
            }

            guard let previousOffsetY = lastOffsetY else {
                lastOffsetY = offsetY
                return
            }

            let delta = offsetY - previousOffsetY
            lastOffsetY = offsetY
            guard abs(delta) > noiseThreshold else { return }

            if delta > 0 {
                accumulatedDown += delta
                accumulatedUp = 0
                if accumulatedDown >= hideDistance {
                    accumulatedDown = 0
                    onChromeIntent(.hide)
                }
            } else {
                accumulatedUp += abs(delta)
                accumulatedDown = 0
                if accumulatedUp >= showDistance {
                    accumulatedUp = 0
                    onChromeIntent(.show)
                }
            }
        }

        @objc func handleTap() {
            onTap()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func resetScrollTracking() {
            lastOffsetY = nil
            accumulatedDown = 0
            accumulatedUp = 0
        }
    }
}
