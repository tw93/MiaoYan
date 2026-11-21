---
paths:
  - "MiaoYanTests/**"
  - "Packages/MiaoYanCore/Tests/**"
  - "scripts/add_tests_target.rb"
---

# Unit tests

Unit tests live under `MiaoYanTests/`. Coverage targets pure-logic surfaces
(`ImageLinkParser`, `WikilinkIndex.updateNote`, `String+`, etc.). UI flows are
verified by manual smoke after build, not by XCUITest.

Add a new test:

1. Create `MiaoYanTests/<Subject>Tests.swift` (XCTest, `@MainActor` on the
   test methods if they touch `@MainActor`-isolated types; `setUp()` overrides
   cannot be `@MainActor`, construct isolated objects inside the tests).
2. Register the file manually at the same 4 pbxproj sites as an app source,
   but into the `MiaoYanTests` group and the `MiaoYanTests` target's
   `PBXSourcesBuildPhase`. Mimic the `NoteFrontmatterTests.swift` sibling
   entries. `scripts/add_tests_target.rb` is a no-op once the target exists
   (it only bootstraps the target after a pbxproj reset), and the `xcodeproj`
   gem it needs is not installed on this machine anyway.
3. Run `xcodebuild test ...` locally, then push.

A green exit code does not prove a new test ran. Check that `Executed N tests`
grew and that the new test's `Test Case ... passed` line is in the log: a
method-level `-only-testing:` that matches nothing exits 0 having run zero
tests, and a test appended to the end of a file holding two `XCTestCase`
classes lands in the second one. For a regression test, red-run it once on
the old code and see it fail.

`EditorKeyFuzzTests` runs 1000 seeded random runs of Return, Tab, their
Shift forms, the Format and Table commands, typing and Backspace through a
real `EditTextView` (about 1.5s), and fails when a run cannot undo back to its
note or redo forward again, or when structural keys alone lose a letter. Run
it deeper after touching `TextFormatter`, `ListContinuation`, `TableEditing`
or `EditTextView.keyDown`: prefix the test command with
`TEST_RUNNER_MIAOYAN_FUZZ_RUNS=20000` (about 50s; `TEST_RUNNER_MIAOYAN_FUZZ_SEED`
picks the first seed). A failure prints its seed, note and steps. Any edit the
editor makes must go through `insertText(_:replacementRange:)` or another call
that registers undo: writing `textStorage` directly is what the undo check
catches. Both checks were red-run on 2026-11-21, once with Tab writing to the
storage directly and once with Bold dropping a character.

The tests run inside the app, and the app opens its notes library at
launch: under XCTest `UserDefaultsManagement.storageUrl` is always an empty
folder of the test process's own (`testLibrary`), whatever the test build's
settings say. Until 2026-11-21 it opened the library the `com.tw93.miaoyan.qa`
settings named, and when that folder was gone (another session's deleted
scratch library) it fell back to the iCloud library and loaded the
maintainer's own notes; the editor's owner guard refused the saves, the test
process exited mid-run twice, and nothing on disk changed.
`testTheTestsNeverOpenTheLibraryTheSettingsName` holds it. Version history
goes to a temporary folder for the same reason.

`CODE_SIGNING_ALLOWED=NO` is required on the local test command because
the dev signing identity used for `MiaoYan.app` and the per-developer
identity used for `MiaoYanTests.xctest` end up with different Team IDs,
which makes dyld refuse to load the test bundle into the host app. `ci.yml`
passes the same flag on every xcodebuild invocation, so it is not a
local-only workaround.

While `/Applications/MiaoYan.app` is running, which on the maintainer's Mac
is always, the test host shares its bundle id and `xcodebuild test` ends with
"The test runner hung before establishing connection". Add
`PRODUCT_BUNDLE_IDENTIFIER=com.tw93.miaoyan.qa` to the local command; never
quit the running app for a test.
