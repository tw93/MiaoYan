import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum MobileTab: Hashable {
    case notes
    case folders
    case search
}

struct FolderListView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var syncManager = CloudSyncManager.shared
    @State private var selectedTab: MobileTab = .notes
    @State private var folderPickerError: String?

    var body: some View {
        ZStack {
            // Gate to TabView opens when EITHER iCloud finished gathering
            // OR a persisted snapshot exists for this root. The cache
            // path lets returning users skip the syncing screen entirely
            // — the snapshot renders cards instantly inside RecentNotesView
            // while the real reload runs in the background.
            if let root = appState.rootURL,
                syncManager.hasFinishedInitialGathering
                    || RecentNotesCache.shared.hasSnapshot(for: root)
            {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        RecentNotesView(root: root, openPicker: openFolderPicker)
                            .environmentObject(appState)
                    }
                    .tabItem { Label("Notes", systemImage: "note.text") }
                    .tag(MobileTab.notes)

                    NavigationStack {
                        FoldersHomeView(root: root, openPicker: openFolderPicker)
                            .environmentObject(appState)
                    }
                    .tabItem { Label("Folders", systemImage: "folder") }
                    .tag(MobileTab.folders)

                    NavigationStack {
                        SearchView(root: root)
                    }
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag(MobileTab.search)
                }
                .tint(MobileTheme.accent)
                .transition(.opacity)
            } else if appState.rootURL != nil && !syncManager.hasFinishedInitialGathering {
                // Have a folder bookmark but iCloud catalog is still gathering.
                // Show a calm full-screen syncing view at the top level — no
                // ScrollView/refreshable underneath — so iPad doesn't show
                // pull-to-refresh bounce while content is still landing.
                MobileSyncingLibraryView()
                    .transition(.opacity)
            } else if appState.isResolvingInitialRoot || !syncManager.didFinishInitialSetup {
                NavigationStack {
                    MobileResolvingLibraryView()
                }
            } else {
                NavigationStack {
                    MobileEmptyLibraryView(openPicker: openFolderPicker)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: syncManager.hasFinishedInitialGathering)
        .mobilePaperBackground()
        .alert(
            "Could not open folder",
            isPresented: Binding(
                get: { folderPickerError != nil },
                set: { if !$0 { folderPickerError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                folderPickerError = nil
            }
        } message: {
            Text(folderPickerError ?? "Try choosing the folder again.")
        }
        .onAppear {
            resolveInitialLibrary()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                resolveInitialLibrary()
                syncManager.notifyExternalChange()
            }
        }
        .onChange(of: syncManager.iCloudAvailable) {
            resolveInitialLibrary()
        }
        .onChange(of: syncManager.didFinishInitialSetup) {
            resolveInitialLibrary()
        }
    }

    private func openFolderPicker() {
        FolderPickerService.shared.present(
            onSelect: { url in
                appState.selectRootFolder(url)
            },
            onError: { error in
                folderPickerError = error.localizedDescription
            }
        )
    }

    private func resolveInitialLibrary() {
        guard appState.rootURL == nil else { return }
        if appState.useDefaultCloudFolderIfAvailable() { return }
        if syncManager.didFinishInitialSetup {
            appState.finishInitialRootResolution()
        }
    }
}

// MARK: - Recent

private struct RecentNotesView: View {
    let root: URL
    let openPicker: () -> Void

    @EnvironmentObject private var readerWebViewStore: ReaderWebViewStore
    @ObservedObject private var syncManager = CloudSyncManager.shared
    @State private var notes: [NoteFile] = []
    @State private var hasLoadedOnce = false
    @State private var showNewNote = false
    @State private var pendingDeletion: NoteFile?
    @State private var loadTask: Task<Void, Never>?
    @State private var isReloading = false
    @State private var pendingReload = false

    private var rootFolder: FolderItem {
        FolderItem(url: root, name: "All Notes", noteCount: notes.count, isVirtualAll: true)
    }

    var body: some View {
        // Always mount the real list shell. The full-screen syncing view is
        // owned exclusively by the parent FolderListView — re-mounting it
        // here would produce a visible icon-position jump during the
        // parent's crossfade because TabView's floating tab bar adds a top
        // safe-area inset that the parent layer doesn't have.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                MobileLibraryHeader(
                    title: "MiaoYan",
                    refreshAction: refreshNotes,
                    newNoteAction: {
                        Haptics.tap()
                        showNewNote = true
                    },
                    openPicker: openPicker
                )

                if hasLoadedOnce && notes.isEmpty {
                    MobileEmptyContentView(
                        systemImage: "text.page",
                        title: "No notes yet",
                        message: "Create a note on Mac or start one here."
                    )
                    .padding(.horizontal, MobileTheme.pagePadding)
                } else if !hasLoadedOnce && notes.isEmpty {
                    // Reload still in flight. Real-world cold start with a
                    // large iCloud library can stretch this window past the
                    // ~100ms we'd hoped for (iCloud throttles directory
                    // enumeration), so give a subtle inline signal rather
                    // than leaving the card area completely blank.
                    InlineLoadingHint(text: "Loading your notes…")
                } else {
                    ForEach(notes) { note in
                        NoteCardLink(note: note) {
                            pendingDeletion = note
                        }
                    }
                }
            }
            .padding(.vertical, 18)
        }
        .refreshable { await reload() }
        .background(MobileTheme.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNewNote, onDismiss: { triggerLoad() }) {
            NewNoteView(folder: rootFolder)
        }
        .alert(
            "Move note to Trash?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { note in
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Move to Trash", role: .destructive) {
                Task {
                    do {
                        try await NoteFileStore.trash(note)
                        Haptics.success()
                        triggerLoad()
                    } catch {
                        Haptics.error()
                    }
                }
            }
        } message: { note in
            Text("You can recover \u{201C}\(note.title)\u{201D} from Trash.")
        }
        .onAppear {
            // Hydrate from the on-disk snapshot first (synchronous, sub-ms),
            // so cold-start returning users see real cards immediately
            // instead of the InlineLoadingHint. The background reload
            // still fires below and overwrites with fresh data once
            // NSMetadataQuery / disk enumeration return.
            if !hasLoadedOnce, notes.isEmpty,
                let snap = RecentNotesCache.shared.snapshot(for: root)
            {
                notes = snap.notes.map { NoteFile(snapshotEntry: $0) }
                hasLoadedOnce = true
            }
            triggerLoad()
            // Warm a WKWebView in the background while the list renders so the
            // first note tap doesn't pay process-spawn cost during navigation.
            readerWebViewStore.warmUp()
        }
        .onDisappear { loadTask?.cancel() }
        .onChange(of: syncManager.revision) { triggerLoad() }
    }

    /// Coalesce revision-driven reloads instead of cancel-and-restart.
    /// During iCloud first-sync NSMetadataQuery fires bursts of updates,
    /// each bumping `syncManager.revision`. The old cancel pattern killed
    /// the in-flight reload before it could ever set `hasLoadedOnce = true`,
    /// so the skeleton stayed forever and pull-to-refresh appeared stuck.
    /// Now we let the current reload finish; if more triggers came in
    /// during it, a single follow-up runs after.
    private func triggerLoad() {
        guard !isReloading else {
            pendingReload = true
            return
        }
        runLoad()
    }

    private func runLoad() {
        isReloading = true
        loadTask = Task {
            await reload()
            isReloading = false
            if pendingReload {
                pendingReload = false
                runLoad()
            }
        }
    }

    private func reload() async {
        let loaded = await NoteFileStore.recentNotes(in: root)
        notes = loaded
        hasLoadedOnce = true
        // Persist the snapshot for the next cold start. Skip when the
        // load returned empty so a one-off failure (transient iCloud
        // hiccup, etc.) doesn't wipe a known-good cache.
        if !loaded.isEmpty {
            RecentNotesCache.shared.save(loaded, for: root)
        }
    }

    private func refreshNotes() {
        Haptics.tap()
        triggerLoad()
        syncManager.notifyExternalChange()
    }
}

// MARK: - Folders

private struct FoldersHomeView: View {
    let root: URL
    let openPicker: () -> Void

    @EnvironmentObject private var readerWebViewStore: ReaderWebViewStore
    @ObservedObject private var syncManager = CloudSyncManager.shared
    @State private var folders: [FolderItem] = []
    @State private var hasLoadedOnce = false
    @State private var loadTask: Task<Void, Never>?
    @State private var isReloading = false
    @State private var pendingReload = false

    var body: some View {
        // Always mount the real list shell; the parent FolderListView owns
        // the syncing view. See RecentNotesView for the full rationale.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                MobileLibraryHeader(
                    title: "Folders",
                    refreshAction: refreshFolders,
                    newNoteAction: nil,
                    openPicker: openPicker
                )

                ForEach(folders) { folder in
                    NavigationLink {
                        NotesListView(folder: folder)
                    } label: {
                        FolderCard(folder: folder)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, MobileTheme.pagePadding)
                }
            }
            .padding(.vertical, 18)
        }
        .refreshable { await reload() }
        .background(MobileTheme.paper)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            triggerLoad()
            readerWebViewStore.warmUp()
        }
        .onDisappear { loadTask?.cancel() }
        .onChange(of: syncManager.revision) { triggerLoad() }
    }

    /// Same coalesce pattern as RecentNotesView — see that comment.
    private func triggerLoad() {
        guard !isReloading else {
            pendingReload = true
            return
        }
        runLoad()
    }

    private func runLoad() {
        isReloading = true
        loadTask = Task {
            await reload()
            isReloading = false
            if pendingReload {
                pendingReload = false
                runLoad()
            }
        }
    }

    private func reload() async {
        let loaded = await NoteFileStore.folders(in: root)
        folders = loaded
        hasLoadedOnce = true
    }

    private func refreshFolders() {
        Haptics.tap()
        triggerLoad()
        syncManager.notifyExternalChange()
    }
}

// MARK: - Header / buttons

private struct MobileLibraryHeader: View {
    let title: String
    let refreshAction: () -> Void
    let newNoteAction: (() -> Void)?
    let openPicker: () -> Void

    @ObservedObject private var syncManager = CloudSyncManager.shared

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(MobileTheme.editorialFont(size: 34, weight: .semibold))
                    .foregroundStyle(MobileTheme.ink)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                SyncRefreshButton(
                    status: syncManager.status,
                    action: refreshAction
                )

                if let newNoteAction {
                    MobileHeaderIconButton(
                        systemName: "square.and.pencil",
                        accessibilityLabel: "New note",
                        tint: MobileTheme.ink,
                        action: newNoteAction
                    )
                }

                MobileHeaderIconButton(
                    systemName: "folder.badge.gearshape",
                    accessibilityLabel: "Choose folder",
                    tint: MobileTheme.ink,
                    action: openPicker
                )
            }
        }
        .padding(.horizontal, MobileTheme.pagePadding)
        .padding(.top, 12)
    }
}

private struct MobileHeaderIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 42, height: 42)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .background(.thinMaterial, in: Circle())
        .overlay(
            Circle()
                .strokeBorder(MobileTheme.hairline, lineWidth: 0.5)
        )
        .glassEffectIfAvailable()
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

private struct SyncRefreshButton: View {
    let status: CloudSyncStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            icon
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 42, height: 42)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(color)
        .background(.thinMaterial, in: Circle())
        .overlay(
            Circle()
                .strokeBorder(MobileTheme.hairline, lineWidth: 0.5)
        )
        .glassEffectIfAvailable()
        .accessibilityLabel(Text("\(label). Refresh library"))
    }

    @ViewBuilder
    private var icon: some View {
        if isSyncing {
            Image(systemName: "arrow.triangle.2.circlepath")
                .symbolEffect(.rotate, options: .repeating, isActive: true)
        } else {
            Image(systemName: iconName)
        }
    }

    private var isSyncing: Bool {
        if case .syncing = status { return true }
        return false
    }

    private var iconName: String {
        switch status {
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "arrow.triangle.2.circlepath"
        case .offline: return "wifi.slash"
        case .error: return "exclamationmark"
        }
    }

    private var label: String {
        switch status {
        case .syncing: return "Syncing"
        case .synced: return "Synced"
        case .offline: return "Offline"
        case .error: return "Sync issue"
        }
    }

    private var color: Color {
        switch status {
        case .syncing, .synced: return MobileTheme.ink
        case .offline: return MobileTheme.secondaryInk
        case .error: return .red
        }
    }
}

// MARK: - Cards

private struct NoteCardLink: View {
    let note: NoteFile
    let onTrash: () -> Void

    var body: some View {
        NavigationLink {
            NoteDetailView(note: note)
        } label: {
            NoteCard(note: note)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MobileTheme.pagePadding)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Haptics.warning()
                onTrash()
            } label: {
                Label("Trash", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                Haptics.warning()
                onTrash()
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        }
    }
}

/// Process-wide cache for the lazily-loaded preview text. Keys are file URLs;
/// entries persist for the lifetime of the process so scrolling back to a
/// previously visible card never re-reads the file. Bounded loosely by note
/// count which is small (<<1000 in practice for personal note libraries).
@MainActor
final class NotePreviewCache {
    static let shared = NotePreviewCache()
    private var cache: [URL: String] = [:]

    func preview(for url: URL) -> String? { cache[url] }
    func store(_ preview: String, for url: URL) { cache[url] = preview }
}

struct NoteCard: View {
    let note: NoteFile
    @State private var lazyPreview: String?

    private var displayedPreview: String {
        if !note.preview.isEmpty { return note.preview }
        return lazyPreview ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(MobileTheme.warmAccent)
                }
                Text(note.title)
                    .font(MobileTheme.editorialFont(.headline, weight: .semibold))
                    .foregroundStyle(MobileTheme.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            if !displayedPreview.isEmpty {
                Text(displayedPreview)
                    .font(MobileTheme.font(.subheadline))
                    .foregroundStyle(MobileTheme.secondaryInk)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .transition(.opacity)
            }

            HStack(spacing: 8) {
                Text(note.modifiedDate, style: .date)
                if note.byteSize > 0 {
                    Text("·")
                    Text(byteCount(note.byteSize))
                }
            }
            .font(MobileTheme.font(.caption, weight: .medium))
            .foregroundStyle(MobileTheme.secondaryInk.opacity(0.75))
        }
        .mobileCard()
        .animation(.easeOut(duration: 0.18), value: displayedPreview.isEmpty)
        .onAppear {
            // Hot path: cache hit returns the preview immediately without
            // hitting the filesystem.
            if lazyPreview == nil {
                lazyPreview = NotePreviewCache.shared.preview(for: note.url)
            }
        }
        // Include modifiedDate in task id so the task re-fires after the file
        // is downloaded by NSMetadataQuery (download lands → mtime changes
        // → list reloads → new NoteFile struct → task id changes → re-runs).
        .task(id: "\(note.url.absoluteString)#\(note.modifiedDate.timeIntervalSinceReferenceDate)") {
            if !note.preview.isEmpty { return }
            if lazyPreview != nil { return }
            let url = note.url
            // .background priority: previews never compete with user-driven
            // navigation or rendering. previewIfDownloaded returns nil for
            // not-yet-downloaded iCloud files so we don't trigger downloads
            // just to render a snippet.
            let preview = await Task.detached(priority: .background) {
                NoteFileStore.previewIfDownloaded(for: url) ?? ""
            }.value
            guard !preview.isEmpty else { return }
            NotePreviewCache.shared.store(preview, for: url)
            lazyPreview = preview
        }
    }

    private func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct FolderCard: View {
    let folder: FolderItem

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(folder.isTrash ? MobileTheme.secondaryInk.opacity(0.12) : MobileTheme.accent.opacity(0.12))
                Image(systemName: folder.isTrash ? "trash" : "folder")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(folder.isTrash ? MobileTheme.secondaryInk : MobileTheme.accent)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(MobileTheme.editorialFont(.headline, weight: .semibold))
                    .foregroundStyle(MobileTheme.ink)
                Text("\(folder.noteCount) notes")
                    .font(MobileTheme.font(.caption, weight: .medium))
                    .foregroundStyle(MobileTheme.secondaryInk)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MobileTheme.secondaryInk.opacity(0.55))
        }
        .mobileCard()
    }
}

// MARK: - Folder picker bridge

@MainActor
private final class FolderPickerService: NSObject, UIDocumentPickerDelegate {
    static let shared = FolderPickerService()

    private var onSelect: ((URL) -> Void)?
    private var onError: ((Error) -> Void)?
    private var isPresenting = false

    func present(
        onSelect: @escaping (URL) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard !isPresenting else { return }
        guard let presenter = UIApplication.shared.topMostViewController else {
            onError(FolderPickerError.noPresenter)
            return
        }

        self.onSelect = onSelect
        self.onError = onError
        isPresenting = true

        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType.folder],
            asCopy: false
        )
        picker.allowsMultipleSelection = false
        picker.delegate = self
        // Hint the picker to land in our iCloud Documents folder when iCloud
        // is available. Without this, iOS opens the picker at "On My iPhone"
        // (the user's last-visited Files location) — not what most users
        // expect for an iCloud-first notes app. iOS treats `directoryURL`
        // as a non-binding hint, so the user can still navigate elsewhere.
        if let iCloudDocs = CloudSyncManager.shared.getNotesDirectory() {
            picker.directoryURL = iCloudDocs
        }
        presenter.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        defer { reset() }
        guard let url = urls.first else { return }
        onSelect?(url)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        reset()
    }

    private func reset() {
        onSelect = nil
        onError = nil
        isPresenting = false
    }
}

private enum FolderPickerError: LocalizedError {
    case noPresenter

    var errorDescription: String? {
        switch self {
        case .noPresenter:
            return "Could not find the active window to open Files."
        }
    }
}

@MainActor
extension UIApplication {
    fileprivate var topMostViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }?
            .rootViewController?
            .topMostPresentedViewController
    }
}

extension UIViewController {
    fileprivate var topMostPresentedViewController: UIViewController {
        if let navigationController = self as? UINavigationController,
            let visibleViewController = navigationController.visibleViewController
        {
            return visibleViewController.topMostPresentedViewController
        }

        if let tabBarController = self as? UITabBarController,
            let selectedViewController = tabBarController.selectedViewController
        {
            return selectedViewController.topMostPresentedViewController
        }

        if let presentedViewController {
            return presentedViewController.topMostPresentedViewController
        }

        return self
    }
}

// MARK: - Empty / loading states

private struct MobileResolvingLibraryView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SkeletonLine(width: 220, height: 30)
            SkeletonLine(width: 160, height: 18)
            Spacer().frame(height: 8)
            SkeletonNoteList()
            Spacer()
        }
        .padding(.horizontal, MobileTheme.pagePadding)
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .mobilePaperBackground()
    }
}

private struct MobileEmptyLibraryView: View {
    let openPicker: () -> Void
    @ObservedObject private var syncManager = CloudSyncManager.shared

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: syncManager.iCloudAvailable ? "icloud.and.arrow.down" : "folder")
                .font(.system(size: 58, weight: .light))
                .foregroundStyle(MobileTheme.accent)
            VStack(spacing: 8) {
                Text(syncManager.iCloudAvailable ? "iCloud Drive is ready" : "Choose your notes folder")
                    .font(MobileTheme.editorialFont(.title2, weight: .semibold))
                    .foregroundStyle(MobileTheme.ink)
                Text(syncManager.iCloudAvailable ? "MiaoYan will read your Markdown notes from iCloud Drive." : "Pick the folder that stores your Markdown notes.")
                    .font(MobileTheme.font(.body))
                    .foregroundStyle(MobileTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 28)

            Button(action: {
                Haptics.tap()
                openPicker()
            }) {
                Text("Choose folder")
                    .font(MobileTheme.font(.body, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(MobileTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mobilePaperBackground()
    }
}

struct MobileEmptyContentView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(MobileTheme.secondaryInk)
            Text(title)
                .font(MobileTheme.editorialFont(.headline, weight: .semibold))
                .foregroundStyle(MobileTheme.ink)
            Text(message)
                .font(MobileTheme.font(.subheadline))
                .foregroundStyle(MobileTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .mobileCard()
    }
}

/// Subtle inline "still loading" hint used inside list views while their
/// first reload hasn't returned yet. Lighter weight than the full-screen
/// `MobileSyncingLibraryView` (which is owned by the parent and must NOT
/// be remounted here — see that view's docs) but still gives a clear
/// signal in the empty card area.
struct InlineLoadingHint: View {
    let text: String

    var body: some View {
        VStack(spacing: 14) {
            IndeterminateProgressBar()
                .frame(maxWidth: 200)
            Text(text)
                .font(MobileTheme.font(.footnote, weight: .medium))
                .foregroundStyle(MobileTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.horizontal, MobileTheme.pagePadding)
    }
}

/// Continuously animating indeterminate linear bar. SwiftUI's built-in
/// `ProgressView().progressViewStyle(.linear)` indeterminate mode is known
/// to render as a static line on iPad (iPadOS 18+ regression), so we drive
/// the indicator manually with `TimelineView` and time-based math —
/// guaranteed to animate every frame regardless of SwiftUI animation state.
struct IndeterminateProgressBar: View {
    /// One full sweep cycle, seconds.
    private let cycle: Double = 1.4

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geo in
                let trackWidth = geo.size.width
                let indicatorWidth = max(40, trackWidth * 0.32)
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = (t.truncatingRemainder(dividingBy: cycle)) / cycle
                let travel = trackWidth + indicatorWidth
                let offset = CGFloat(phase) * travel - indicatorWidth

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MobileTheme.hairline.opacity(0.7))
                    Capsule()
                        .fill(MobileTheme.accent)
                        .frame(width: indicatorWidth)
                        .offset(x: offset)
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// First-launch placeholder shown while NSMetadataQuery is still gathering the
/// iCloud catalog. Renders full-screen at the top level (no TabView, no
/// ScrollView, no `.refreshable`) so iPad doesn't show pull-to-refresh
/// bounce or scroll-rubber-band animation while content is still landing.
/// Once `hasFinishedInitialGathering` flips true, the parent transitions
/// straight into the real TabView with cached results.
///
/// What this view actually represents (matters for honest copy):
/// iCloud's NSMetadataQuery enumerates the catalog (file names + metadata)
/// but does NOT download file contents — files stay as `.icloud`
/// placeholders until something reads them. So the only honest thing to
/// surface here is INDEXING progress (count of notes discovered), not
/// download percentage. The bar is intentionally indeterminate so it
/// animates continuously even with no measurable phase progress.
///
/// IMPORTANT — single-mount invariant: this view is owned exclusively by
/// `FolderListView` (the parent ZStack). Do NOT remount it inside any
/// child list view (RecentNotesView / FoldersHomeView / NotesListView).
/// TabView's floating tab bar applies a top safe-area inset that doesn't
/// exist at the parent layer; a second mount inside TabView would render
/// the icon ~88pt lower, and during the parent's opacity crossfade both
/// instances are briefly visible — the user reads that as a position jump.
/// Child views should always mount their real list shell directly and
/// rely on `hasLoadedOnce` to gate their empty-state copy instead.
struct MobileSyncingLibraryView: View {
    @ObservedObject private var syncManager = CloudSyncManager.shared

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(MobileTheme.accent.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(MobileTheme.accent)
                    .symbolEffect(.pulse, options: .repeating)
            }

            VStack(spacing: 10) {
                Text("Setting up your library")
                    .font(MobileTheme.editorialFont(.title3, weight: .semibold))
                    .foregroundStyle(MobileTheme.ink)
                Text("Downloading your iCloud notes. Next launch will be instant.")
                    .font(MobileTheme.font(.subheadline))
                    .foregroundStyle(MobileTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 10) {
                IndeterminateProgressBar()
                    .frame(maxWidth: 280)
                Text(countText)
                    .font(MobileTheme.font(.footnote, weight: .medium))
                    .foregroundStyle(MobileTheme.secondaryInk)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 40)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mobilePaperBackground()
    }

    private var countText: String {
        let count = syncManager.discoveredItemCount
        if count == 0 {
            return "Connecting to iCloud…"
        }
        if count == 1 {
            return "Found 1 note…"
        }
        return "Found \(count) notes…"
    }
}

// MARK: - Skeleton placeholders

struct SkeletonNoteList: View {
    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    SkeletonLine(width: 200, height: 16)
                    SkeletonLine(width: .infinity, height: 12)
                    SkeletonLine(width: 260, height: 12)
                    HStack(spacing: 8) {
                        SkeletonLine(width: 70, height: 10)
                        SkeletonLine(width: 50, height: 10)
                    }
                }
                .mobileCard()
            }
        }
    }
}

struct SkeletonFolderList: View {
    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(MobileTheme.hairline)
                        .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonLine(width: 140, height: 16)
                        SkeletonLine(width: 80, height: 12)
                    }
                    Spacer()
                }
                .mobileCard()
            }
        }
    }
}
