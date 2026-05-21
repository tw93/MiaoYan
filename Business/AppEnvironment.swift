import Foundation

/// Single read-only entry point for app-level singletons.
///
/// Why this exists: the codebase grew several independent singletons
/// (`Storage.sharedInstance()`, `WikilinkIndex.shared`,
/// `NoteVersionManager.shared`, `UserDataService.instance`, etc.) and 22
/// direct call sites that bypass `AppContext`. The cure for that is not
/// "rip them all out" (Storage is correctly a file-system singleton, ripping
/// it costs more than it returns), but to give new code one place to look
/// and to make the SwiftLint custom rule meaningful.
///
/// Scope: macOS target only. iOS `MiaoYanMobile` has its own service
/// composition (e.g. `CloudSyncManager`) and is not folded into this facade.
///
/// `AppEnvironment.current` is a facade, not a container. It does not own
/// these objects, it merely names them.
@MainActor
struct AppEnvironment {

    static let current = AppEnvironment()

    let storage: Storage = Storage.sharedInstance()
    let wikilinkIndex: WikilinkIndex = WikilinkIndex.shared
    let versionManager: NoteVersionManager = NoteVersionManager.shared
    let userData: UserDataService = UserDataService.instance
    let session: EditorSessionState = AppContext.shared.sessionState
}
