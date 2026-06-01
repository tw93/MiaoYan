import XCTest

@testable import MiaoYan

/// Regression coverage for V3.5.1+ fix `13964acd`: when an existing user with
/// non-empty noteList launched the app, `hasCreatedInitContent` was never set
/// to true. Deleting the bundled `Guide/Examples/Notes/Ideas` folders and
/// relaunching then re-seeded them, which a non-fresh user definitely does
/// not want. The fix records the flag whenever noteList is non-empty.
///
/// The decision logic was extracted into `Storage.decideInitContent` so the
/// matrix can be tested without spinning up a real Storage instance.
@MainActor
final class StorageInitContentDecisionTests: XCTestCase {

    func testEmptyNoteListUnsetFlagSeedsInitFolders() {
        XCTAssertEqual(
            Storage.decideInitContent(noteListIsEmpty: true, hasCreatedInitContent: false),
            .createInitFolders)
    }

    func testEmptyNoteListFlagAlreadySetSkips() {
        XCTAssertEqual(
            Storage.decideInitContent(noteListIsEmpty: true, hasCreatedInitContent: true),
            .skip)
    }

    func testExistingUserWithNotesAndUnsetFlagGetsMarkedInitialized() {
        // The exact regression in cb46c987 / 13964acd: a returning user has
        // notes on disk but the flag was never set. Old code seeded the demo
        // folders on every launch; new code marks them initialized so the
        // next "delete + relaunch" no longer triggers re-seeding.
        XCTAssertEqual(
            Storage.decideInitContent(noteListIsEmpty: false, hasCreatedInitContent: false),
            .markInitialized)
    }

    func testExistingUserWithNotesAndSetFlagGetsMarkedInitialized() {
        // Setting the flag is idempotent; the return value still says "do
        // nothing about init folders" via .markInitialized.
        XCTAssertEqual(
            Storage.decideInitContent(noteListIsEmpty: false, hasCreatedInitContent: true),
            .markInitialized)
    }
}
