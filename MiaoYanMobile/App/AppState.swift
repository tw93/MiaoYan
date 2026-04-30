import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var rootURL: URL?

    private var securityScopedURL: URL?

    init() {
        if let url = loadBookmarkedURL() {
            activate(url)
        }
    }

    func selectRootFolder(_ url: URL) {
        deactivate()
        saveBookmark(for: url)
        activate(url)
    }

    private func activate(_ url: URL) {
        let started = url.startAccessingSecurityScopedResource()
        if started {
            securityScopedURL = url
        }
        rootURL = url
    }

    private func deactivate() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }

    private func saveBookmark(for url: URL) {
        guard let data = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(data, forKey: "MiaoYanMobile.RootBookmark")
    }

    private func loadBookmarkedURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: "MiaoYanMobile.RootBookmark") else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withoutUI,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        if isStale {
            saveBookmark(for: url)
        }
        return url
    }
}
