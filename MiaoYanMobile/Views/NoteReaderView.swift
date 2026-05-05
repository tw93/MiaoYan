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
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}

enum ReaderChromeIntent {
    case show
    case hide
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
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head><body></body></html>
        """

    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.suppressesIncrementalRendering = false
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
