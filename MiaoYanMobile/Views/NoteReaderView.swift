import SwiftUI
import WebKit

enum ReaderFontSize: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"

    var points: Int {
        switch self {
        case .small: return 15
        case .medium: return 17
        case .large: return 19
        }
    }

    var label: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }
}

struct NoteReaderView: View {
    let note: NoteFile

    @AppStorage("MiaoYanMobile.FontSize") private var fontSizeRaw = ReaderFontSize.medium.rawValue
    @State private var scrollProgress: CGFloat = 0
    @State private var chromeVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var cachedHTML: String = ""

    private var fontSize: ReaderFontSize {
        ReaderFontSize(rawValue: fontSizeRaw) ?? .medium
    }

    private func buildHTML() -> String {
        let content = FileReader.readContent(of: note)
        return MobileHtmlRenderer.render(markdown: content, fontSize: fontSize.points)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            WebReaderView(
                html: cachedHTML,
                onScrollProgress: { progress in
                    scrollProgress = progress
                },
                onTap: { toggleChrome() }
            )
            .ignoresSafeArea(edges: .bottom)

            progressBar
        }
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(chromeVisible ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("字号", selection: $fontSizeRaw) {
                        ForEach(ReaderFontSize.allCases, id: \.rawValue) { size in
                            Text(size.label).tag(size.rawValue)
                        }
                    }
                    ShareLink(item: cachedHTML, subject: Text(note.title))
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            cachedHTML = buildHTML()
            scheduleAutoHide()
        }
        .onChange(of: fontSizeRaw) { _ in cachedHTML = buildHTML() }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: geo.size.width * scrollProgress, height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(false)
    }

    private func toggleChrome() {
        hideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            chromeVisible.toggle()
        }
        if chromeVisible {
            scheduleAutoHide()
        }
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        hideTask = Task {
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    chromeVisible = false
                }
            }
        }
    }
}

struct WebReaderView: UIViewRepresentable {
    let html: String
    var onScrollProgress: (CGFloat) -> Void
    var onTap: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.delegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.delegate = context.coordinator
        webView.addGestureRecognizer(tap)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onScrollProgress = onScrollProgress
        context.coordinator.onTap = onTap
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollProgress: onScrollProgress, onTap: onTap)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var onScrollProgress: (CGFloat) -> Void
        var onTap: () -> Void
        var lastHTML: String = ""

        init(onScrollProgress: @escaping (CGFloat) -> Void, onTap: @escaping () -> Void) {
            self.onScrollProgress = onScrollProgress
            self.onTap = onTap
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let maxOffset = scrollView.contentSize.height - scrollView.bounds.height
            guard maxOffset > 0 else { return }
            let progress = max(0, min(1, scrollView.contentOffset.y / maxOffset))
            onScrollProgress(progress)
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
    }
}
