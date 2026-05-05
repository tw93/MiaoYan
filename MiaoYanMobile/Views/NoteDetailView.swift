import SwiftUI
import UIKit

enum NoteSaveState: Equatable {
    case saved
    case unsaved
    case saving
    case failed(String)
    case conflict

    var label: String {
        switch self {
        case .saved: return "Saved"
        case .unsaved: return "Unsaved"
        case .saving: return "Saving"
        case .failed: return "Save failed"
        case .conflict: return "Updated elsewhere"
        }
    }
}

private struct ReaderHTMLCacheKey: Hashable {
    let path: String
    let modifiedAt: TimeInterval
    let fontSize: Int

    init(noteURL: URL, modifiedDate: Date, fontSize: Int) {
        self.path = noteURL.standardizedFileURL.path
        self.modifiedAt = modifiedDate.timeIntervalSinceReferenceDate
        self.fontSize = fontSize
    }
}

/// Tiny LRU keyed on (note, modificationDate, fontSize).
/// Cache validity intentionally piggybacks on `modifiedDate`: write paths
/// always refresh `lastKnownModifiedDate` on the caller side, so the key
/// changes whenever the rendered HTML could differ.
private actor ReaderHTMLCache {
    static let shared = ReaderHTMLCache()

    private let limit = 8
    private var entries: [ReaderHTMLCacheKey: Node] = [:]
    private var head: Node?
    private var tail: Node?

    private final class Node {
        let key: ReaderHTMLCacheKey
        var html: String
        var prev: Node?
        var next: Node?

        init(key: ReaderHTMLCacheKey, html: String) {
            self.key = key
            self.html = html
        }
    }

    func html(for key: ReaderHTMLCacheKey) -> String? {
        guard let node = entries[key] else { return nil }
        moveToHead(node)
        return node.html
    }

    func store(_ html: String, for key: ReaderHTMLCacheKey) {
        if let existing = entries[key] {
            // Same key (e.g. font size scrubbed back and forth on the same
            // note): mutate the existing node in place and bump it to the
            // head. Allocating a replacement node and re-splicing was prone
            // to leaving the old node attached as `head`, which corrupted
            // eviction order on repeat writes.
            existing.html = html
            moveToHead(existing)
        } else {
            let node = Node(key: key, html: html)
            entries[key] = node
            insertAtHead(node)
        }

        while entries.count > limit, let oldest = tail {
            tail = oldest.prev
            tail?.next = nil
            oldest.prev = nil
            entries.removeValue(forKey: oldest.key)
            if head === oldest { head = nil }
        }
    }

    private func insertAtHead(_ node: Node) {
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
        if tail == nil { tail = node }
    }

    private func moveToHead(_ node: Node) {
        guard head !== node else { return }
        node.prev?.next = node.next
        node.next?.prev = node.prev
        if tail === node { tail = node.prev }
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
    }
}

struct NoteDetailView: View {
    let note: NoteFile

    @AppStorage("MiaoYanMobile.FontSize") private var fontSizeRaw = ReaderFontSize.medium.rawValue
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var readerWebViewStore: ReaderWebViewStore
    @State private var content = ""
    @State private var saveState: NoteSaveState = .saved
    @State private var hasLoadedContent = false
    @State private var lastKnownModifiedDate = Date.distantPast
    @State private var saveTask: Task<Void, Never>?
    @State private var loadTask: Task<Void, Never>?
    @State private var renderTask: Task<Void, Never>?
    @State private var skeletonTask: Task<Void, Never>?
    @State private var renderedHTML: String?
    @State private var showSkeleton = false
    @State private var isApplyingLoadedContent = false
    @State private var chromeVisible = true
    @State private var showEditor = false
    @State private var showDeleteAlert = false
    @State private var showConflictAlert = false
    @State private var toastMessage: String?

    /// Slack in seconds for "another device modified the file" detection.
    private static let conflictTimestampSlack: TimeInterval = 0.5
    /// How long to wait before showing the loading skeleton; cache hits typically
    /// complete well under this, so the user sees a clean paper background flash
    /// instead of a skeleton fade-in.
    private static let skeletonRevealDelay: Duration = .milliseconds(200)

    private var fontSize: ReaderFontSize {
        ReaderFontSize(rawValue: fontSizeRaw) ?? .medium
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // WebReaderView is mounted unconditionally so that WKWebView init
            // (process spawn, view-hierarchy attach) runs in parallel with
            // cmark rendering during the navigation transition. The
            // placeholder above hides the empty webview until the real HTML
            // lands, then fades out. WebReaderView no-ops loadHTMLString
            // while `html` is empty, so this costs nothing extra.
            WebReaderView(
                html: renderedHTML ?? "",
                baseURL: note.url.deletingLastPathComponent(),
                webViewStore: readerWebViewStore,
                onChromeIntent: handleChromeIntent,
                onTap: toggleChrome
            )
            .ignoresSafeArea(edges: .bottom)
            .opacity(renderedHTML == nil ? 0 : 1)
            .animation(.easeOut(duration: 0.18), value: renderedHTML == nil)

            if renderedHTML == nil {
                NoteDetailLoadingView()
                    .opacity(showSkeleton ? 1 : 0)
                    .animation(.easeOut(duration: 0.18), value: showSkeleton)
            }

            if let toastMessage {
                Text(toastMessage)
                    .font(MobileTheme.font(.caption, weight: .semibold))
                    .foregroundStyle(MobileTheme.ink)
                    .mobileGlassControl()
                    .padding(.bottom, 30)
                    .contentTransition(.opacity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Cover all edges: with the tab bar hidden in reader, the bottom safe
        // area is transparent and the webview's bounce overscroll exposes
        // whatever sits behind. Paint paper everywhere so the underlying
        // SwiftUI window default never peeks through. WKWebView backgroundColor
        // is also set to paper as a second layer of defence in
        // ReaderWebViewFactory.makeWebView.
        .background(MobileTheme.paper.ignoresSafeArea())
        // The hero title at the top of the rendered HTML (or the user's own
        // first-line H1) already shows the note title; an inline nav-bar copy
        // would be visible duplication during the first scroll. Match Apple
        // Notes / Bear / Things and keep the nav bar text-free.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(chromeVisible ? .visible : .hidden, for: .navigationBar)
        // Hide the tab bar only on iPhone (compact width) where it sits at
        // the bottom and competes for reading space — Apple Notes / Bear
        // do the same. On iPad (regular width) iPadOS 26's floating tab
        // bar lives at the very top as a small pill; hiding it would
        // play a fade-in animation on pop back that reads as a "flash"
        // when the user returns from a note. Keep it visible on iPad.
        .toolbar(horizontalSizeClass == .compact ? .hidden : .automatic, for: .tabBar)
        .toolbarBackground(MobileTheme.paper, for: .navigationBar)
        .toolbarBackground(chromeVisible ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Both icons share the same ink colour so the trailing toolbar
                // reads as one cohesive action cluster. The edit button being
                // primary is conveyed by its position and weight, not hue —
                // mixing accent+ink here looked fragmented in practice (see
                // discussion 2026-05).
                HStack(spacing: 12) {
                    Button {
                        Haptics.tap()
                        showEditor = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }

                    // Menu intentionally only carries Font size + destructive
                    // Trash. ShareLink used to live here but its eager
                    // evaluation (serialising content + scanning available
                    // share targets + LinkPresentation metadata) made the
                    // first ellipsis tap visibly stutter. iOS already exposes
                    // file-level sharing via the Files app long-press, so an
                    // in-app Share button was redundant.
                    Menu {
                        Picker("Font size", selection: $fontSizeRaw) {
                            ForEach(ReaderFontSize.allCases, id: \.rawValue) { size in
                                Text(size.label).tag(size.rawValue)
                            }
                        }

                        Divider()
                        Button {
                            Haptics.warning()
                            showDeleteAlert = true
                        } label: {
                            Text("Move to Trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                .foregroundStyle(MobileTheme.ink)
            }
        }
        .sheet(isPresented: $showEditor) {
            NoteEditorView(
                note: note,
                content: $content,
                saveState: saveState,
                onDone: {
                    Haptics.tap()
                    flushSave()
                    showEditor = false
                    renderContent()
                }
            )
        }
        .alert("Move note to Trash?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) { deleteNote() }
        } message: {
            Text("You can recover \u{201C}\(note.title)\u{201D} from Trash.")
        }
        .alert("This note changed elsewhere", isPresented: $showConflictAlert) {
            Button("Reload", role: .cancel) { reloadFromDisk() }
            Button("Keep Mine") { flushSave(force: true) }
        } message: {
            Text("Another device updated this file before your edits were saved.")
        }
        .onAppear {
            loadContent()
        }
        .onDisappear {
            flushSave()
            loadTask?.cancel()
            renderTask?.cancel()
            skeletonTask?.cancel()
            saveTask?.cancel()
        }
        .onChange(of: fontSizeRaw) {
            renderContent()
        }
        .onChange(of: content) {
            guard hasLoadedContent, !isApplyingLoadedContent else { return }
            scheduleAutosave()
            if !showEditor {
                renderContent()
            }
        }
        .onChange(of: showEditor) { _, isShowing in
            if !isShowing {
                // Catch swipe-to-dismiss as well as the explicit Done button:
                // make sure any pending edits land on disk before re-rendering.
                flushSave()
                renderContent()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                checkForRemoteChange()
            }
        }
    }

    // MARK: - Loading

    private func loadContent() {
        hasLoadedContent = false
        renderedHTML = nil
        isApplyingLoadedContent = true
        loadTask?.cancel()
        renderTask?.cancel()
        scheduleSkeletonReveal()

        let note = note
        let fontSize = fontSize.cssPoints
        let title = note.title

        loadTask = Task { @MainActor in
            let resolvedModifiedDate = await NoteFileStore.modificationDateOffMain(for: note.url)
            let cacheKey = ReaderHTMLCacheKey(
                noteURL: note.url,
                modifiedDate: resolvedModifiedDate,
                fontSize: fontSize
            )

            if let cachedHTML = await ReaderHTMLCache.shared.html(for: cacheKey) {
                let resolvedContent: String
                do {
                    resolvedContent = try await NoteFileStore.readContent(of: note)
                } catch {
                    guard !Task.isCancelled else { return }
                    saveState = .failed(error.localizedDescription)
                    isApplyingLoadedContent = false
                    showToast("Reload")
                    return
                }
                guard !Task.isCancelled else { return }
                content = resolvedContent
                lastKnownModifiedDate = resolvedModifiedDate
                saveState = .saved
                hasLoadedContent = true
                installRenderedHTML(cachedHTML)
                isApplyingLoadedContent = false
                return
            }

            let resolvedContent: String
            do {
                resolvedContent = try await NoteFileStore.readContent(of: note)
            } catch {
                guard !Task.isCancelled else { return }
                saveState = .failed(error.localizedDescription)
                isApplyingLoadedContent = false
                showToast("Reload")
                return
            }
            let html = await Task.detached(priority: .userInitiated) {
                MobileHtmlRenderer.render(markdown: resolvedContent, title: title, fontSize: fontSize)
            }.value
            await ReaderHTMLCache.shared.store(html, for: cacheKey)

            guard !Task.isCancelled else { return }
            content = resolvedContent
            lastKnownModifiedDate = resolvedModifiedDate
            saveState = .saved
            hasLoadedContent = true
            installRenderedHTML(html)
            isApplyingLoadedContent = false
        }
    }

    private func renderContent() {
        guard hasLoadedContent else { return }
        renderTask?.cancel()

        let markdown = content
        let fontSize = fontSize.cssPoints
        let title = note.title
        let cacheKey = ReaderHTMLCacheKey(
            noteURL: note.url,
            modifiedDate: lastKnownModifiedDate,
            fontSize: fontSize
        )

        renderTask = Task { @MainActor in
            let html = await Task.detached(priority: .userInitiated) {
                MobileHtmlRenderer.render(markdown: markdown, title: title, fontSize: fontSize)
            }.value
            await ReaderHTMLCache.shared.store(html, for: cacheKey)

            guard !Task.isCancelled else { return }
            installRenderedHTML(html)
        }
    }

    private func installRenderedHTML(_ html: String) {
        skeletonTask?.cancel()
        showSkeleton = false
        renderedHTML = html
    }

    /// Most cache hits resolve in well under `skeletonRevealDelay`, so the
    /// skeleton stays hidden and the user sees a brief paper-coloured background
    /// instead of a flickering placeholder. Cache misses (cmark render) fade
    /// the skeleton in so the wait isn't visually empty.
    private func scheduleSkeletonReveal() {
        skeletonTask?.cancel()
        showSkeleton = false
        skeletonTask = Task { @MainActor in
            do { try await Task.sleep(for: Self.skeletonRevealDelay) } catch { return }
            guard !Task.isCancelled, renderedHTML == nil else { return }
            showSkeleton = true
        }
    }

    // MARK: - Save

    private func scheduleAutosave() {
        saveState = .unsaved
        saveTask?.cancel()
        saveTask = Task {
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            await MainActor.run {
                flushSave()
            }
        }
    }

    private func flushSave(force: Bool = false) {
        guard hasLoadedContent, saveState != .saved, saveState != .saving else { return }
        saveTask?.cancel()

        let snapshot = content
        let url = note.url
        let knownDate = lastKnownModifiedDate

        Task { @MainActor in
            let diskDate = await NoteFileStore.modificationDateOffMain(for: url)
            if !force, diskDate > knownDate.addingTimeInterval(Self.conflictTimestampSlack) {
                saveState = .conflict
                showConflictAlert = true
                showToast("Updated elsewhere")
                Haptics.warning()
                return
            }

            saveState = .saving
            do {
                try await NoteFileStore.write(content: snapshot, to: url)
                let updatedDate = await NoteFileStore.modificationDateOffMain(for: url)
                lastKnownModifiedDate = updatedDate
                saveState = .saved
                // No haptic on successful autosave: this fires every 800ms while
                // the user is typing and would buzz the phone constantly. The
                // SaveStatusPill in the editor sheet already shows progress.
            } catch {
                saveState = .failed(error.localizedDescription)
                showToast("Save failed")
                Haptics.error()
            }
        }
    }

    // MARK: - Conflict / reload

    private func reloadFromDisk() {
        hasLoadedContent = false
        loadContent()
    }

    private func checkForRemoteChange() {
        guard hasLoadedContent else { return }
        Task { @MainActor in
            let diskDate = await NoteFileStore.modificationDateOffMain(for: note.url)
            guard diskDate > lastKnownModifiedDate.addingTimeInterval(Self.conflictTimestampSlack) else {
                return
            }
            switch saveState {
            case .saved:
                // No pending edits: silently pull the newest version.
                reloadFromDisk()
            case .unsaved, .saving, .failed, .conflict:
                showConflictAlert = true
            }
        }
    }

    private func deleteNote() {
        Task { @MainActor in
            do {
                try await NoteFileStore.trash(note)
                Haptics.success()
                dismiss()
            } catch {
                saveState = .failed(error.localizedDescription)
                showToast("Move failed")
                Haptics.error()
            }
        }
    }

    // MARK: - Chrome visibility

    private func handleChromeIntent(_ intent: ReaderChromeIntent) {
        switch intent {
        case .show:
            setChromeVisible(true, duration: 0.18)
        case .hide:
            setChromeVisible(false, duration: 0.16)
        }
    }

    private func toggleChrome() {
        // Reading is a calm context; tapping the page to peek the toolbar
        // shouldn't fire a haptic.
        setChromeVisible(!chromeVisible, duration: 0.18)
    }

    private func setChromeVisible(_ visible: Bool, duration: Double) {
        guard chromeVisible != visible else { return }
        withAnimation(.easeInOut(duration: duration)) {
            chromeVisible = visible
        }
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.18)) {
            toastMessage = message
        }
        Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            await MainActor.run {
                guard toastMessage == message else { return }
                withAnimation(.easeIn(duration: 0.18)) {
                    toastMessage = nil
                }
            }
        }
    }
}

private struct NoteDetailLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SkeletonLine(width: .infinity, height: 28)
            SkeletonLine(width: 220, height: 18)
            SkeletonLine(width: .infinity, height: 14)
            SkeletonLine(width: .infinity, height: 14)
            SkeletonLine(width: 280, height: 14)
            SkeletonLine(width: .infinity, height: 14)
            SkeletonLine(width: 200, height: 14)
            Spacer()
        }
        .padding(.horizontal, MobileTheme.pagePadding + 4)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MobileTheme.paper)
    }
}

struct SkeletonLine: View {
    let width: CGFloat?
    let height: CGFloat
    @State private var phase: Double = 0

    init(width: CGFloat? = nil, height: CGFloat = 14) {
        self.width = width
        self.height = height
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(MobileTheme.hairline)
            .overlay(
                LinearGradient(
                    colors: [.clear, MobileTheme.surface.opacity(0.55), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(0.7)
                .offset(x: phase)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            )
            .frame(maxWidth: width == .infinity ? .infinity : width)
            .frame(height: height)
            .onAppear {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 220
                }
            }
    }
}

// MARK: - Haptics

/// Cached, pre-warmed haptic generators.
///
/// Why this matters: `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator`
/// allocated fresh on every call pay an engine-warmup cost on first use
/// (~50-100ms on real devices). Without `prepare()` the haptic engine
/// is cold-spun even on subsequent calls, so the first tap of any
/// session feels noticeably laggy. Apple's Human Interface Guidelines
/// explicitly recommend reusing generators and calling `prepare()`
/// shortly before the haptic.
///
/// Strategy:
///  - Generators live as `static let` so we allocate exactly once.
///  - `Haptics.warmUp()` is called from the app entry point so the
///    engine is already warm before the first user interaction.
///  - Each trigger calls `prepare()` after firing so the engine stays
///    warm for the next tap.
@MainActor
enum Haptics {
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let notification = UINotificationFeedbackGenerator()

    /// Pre-warm the haptic engine. Call once from the app's
    /// scene-active entry so the user's first tap is instant.
    static func warmUp() {
        lightImpact.prepare()
        notification.prepare()
    }

    static func tap() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
    }

    static func success() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    static func warning() {
        notification.notificationOccurred(.warning)
        notification.prepare()
    }

    static func error() {
        notification.notificationOccurred(.error)
        notification.prepare()
    }
}
