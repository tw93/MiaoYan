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
/// `AppEnvironment.current` is therefore a facade, not a container. It does
/// not own these objects, it merely names them. Future Phase work can swap
/// the storage backing without touching call sites.
@MainActor
struct AppEnvironment {

    /// Current process-wide environment. Mutable only to allow tests to
    /// substitute a sandboxed environment via `withOverride`; production
    /// callers should treat this as read-only.
    static var current = AppEnvironment()

    let storage: Storage
    let wikilinkIndex: WikilinkIndex
    let versionManager: NoteVersionManager
    let userData: UserDataService
    let session: EditorSessionState

    init(
        storage: Storage = Storage.sharedInstance(),
        wikilinkIndex: WikilinkIndex = WikilinkIndex.shared,
        versionManager: NoteVersionManager = NoteVersionManager.shared,
        userData: UserDataService = UserDataService.instance,
        session: EditorSessionState = AppContext.shared.sessionState
    ) {
        self.storage = storage
        self.wikilinkIndex = wikilinkIndex
        self.versionManager = versionManager
        self.userData = userData
        self.session = session
    }

    /// Run `body` against an overridden environment, restoring the previous
    /// one on completion. Intended for unit tests that need a stub Storage.
    /// Throws are forwarded so tests can use `XCTAssertThrowsError`.
    static func withOverride<T>(_ override: AppEnvironment, body: () throws -> T) rethrows -> T {
        let previous = current
        current = override
        defer { current = previous }
        return try body()
    }
}
