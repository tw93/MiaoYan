import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var rootURL: URL?
    @Published private(set) var isResolvingInitialRoot = true
    @Published private(set) var isUsingExternalFolder = false

    private var securityScopedURL: URL?

    private static let bookmarkKey = "MiaoYanMobile.RootBookmark"
    private static let bookmarkUsesSecurityScopeKey = "MiaoYanMobile.RootBookmarkSecurityScoped"

    init() {
        // Use the persisted scope flag rather than re-deriving via
        // CloudSyncManager — at this point in app launch the iCloud
        // container URL may not yet be resolved, which would misclassify
        // a real external folder as the iCloud container and leave the
        // security-scoped resource unstarted on relaunch.
        if let resolved = loadBookmarkedURL(),
            activate(resolved.url, isExternalFolder: resolved.securityScoped)
        {
            return
        }
        useDefaultCloudFolderIfAvailable()
    }

    func selectRootFolder(_ url: URL) {
        deactivate()
        // User-picked folders from Files require security-scoped access.
        if activate(url, isExternalFolder: true) {
            saveBookmark(for: url, securityScoped: true)
        }
    }

    @discardableResult
    func useDefaultCloudFolderIfAvailable() -> Bool {
        guard rootURL == nil else {
            isResolvingInitialRoot = false
            return true
        }
        guard let url = CloudSyncManager.shared.getNotesDirectory() else {
            isResolvingInitialRoot = false
            return false
        }
        deactivate()
        activate(url, isExternalFolder: false)
        saveBookmark(for: url, securityScoped: false)
        return true
    }

    func finishInitialRootResolution() {
        isResolvingInitialRoot = false
    }

    @discardableResult
    private func activate(_ url: URL, isExternalFolder: Bool) -> Bool {
        if isExternalFolder {
            // Only call security-scoped access for user-picked folders;
            // the iCloud container is read/write without it.
            if url.startAccessingSecurityScopedResource() {
                securityScopedURL = url
            } else {
                // The sandbox refused the scope grant (provider deleted the
                // folder, revoked access, or the bookmark lost its scope).
                // Proceeding would present an unreadable library; clear the
                // stored bookmark so the folder chooser shows instead.
                clearBookmark()
                isUsingExternalFolder = false
                isResolvingInitialRoot = false
                return false
            }
        }
        rootURL = url
        isUsingExternalFolder = isExternalFolder
        isResolvingInitialRoot = false
        // The reader's asset scheme handler only serves files inside the
        // active library; keep it pointed at the current root.
        LocalAssetSchemeHandler.allowedRoot = url
        return true
    }

    private func clearBookmark() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: Self.bookmarkUsesSecurityScopeKey)
    }

    private func deactivate() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
        isUsingExternalFolder = false
    }

    /// Persist a bookmark for the chosen root.
    /// Note: iOS does not expose `.withSecurityScope` (macOS-only); a bookmark
    /// captured while the URL's security-scoped resource is active inherits
    /// that scope automatically. We therefore start access in `activate(...)`
    /// before this is called for external folders.
    private func saveBookmark(for url: URL, securityScoped: Bool) {
        guard
            let data = try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        else { return }
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        UserDefaults.standard.set(securityScoped, forKey: Self.bookmarkUsesSecurityScopeKey)
    }

    private struct ResolvedBookmark {
        let url: URL
        let securityScoped: Bool
    }

    private func loadBookmarkedURL() -> ResolvedBookmark? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var isStale = false
        // `.withoutImplicitStartAccessing` (iOS 14+) keeps scope dormant until
        // we explicitly start it in `activate`, so the stop/start lifecycle
        // stays balanced and external folders don't accumulate dangling
        // accesses across relaunches.
        guard
            let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withoutUI, .withoutImplicitStartAccessing],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        else { return nil }
        let securityScoped = UserDefaults.standard.bool(forKey: Self.bookmarkUsesSecurityScopeKey)
        if isStale {
            // Need scope active to refresh the bookmark on iOS.
            let started = securityScoped ? url.startAccessingSecurityScopedResource() : false
            saveBookmark(for: url, securityScoped: securityScoped)
            if started {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return ResolvedBookmark(url: url, securityScoped: securityScoped)
    }
}
