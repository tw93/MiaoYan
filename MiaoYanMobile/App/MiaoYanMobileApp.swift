import SwiftUI

@main
struct MiaoYanMobileApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            FolderListView()
                .environmentObject(appState)
        }
    }
}
