# Incidents

Defects that reached users in a published release, kept as the eval set for every review layer ("incidents are the
eval", from the Claude Code team's code review write-up). A row is added in the same change that fixes the defect:
the fix commit, the commit that introduced it when known, the earliest layer that should have caught it, and the
test or gate that catches it now. `scripts/check_incidents.py` (run by CI's Review gates job) fails a row whose
commit does not resolve, whose layer is not one of the names below, or whose catcher is not defined in the code.

A catcher is written in backticks and is one of: an XCTest method (`func test...`) under `MiaoYanTests/` or
`Packages/MiaoYanCore/Tests/`, a Python `test_*` function under `scripts/`, a job id in `.github/workflows/`, or the
repository path of a gate file.

Layers, earliest first:

- `write-time`: the author's own check before committing, a sweep of same-shape sites and the narrowest command
  in AGENTS.md.
- `unit`: `xcodebuild test` and `swift test --package-path Packages/MiaoYanCore`, locally and in CI.
- `ci`: the rest of `.github/workflows/ci.yml`: the Debug build under CI's older Swift, SwiftLint, swift-format,
  ShellCheck and the release-notes smoke.
- `review`: a diff review against AGENTS.md's Current Risk Areas.
- `release-check`: the steps before a tag: version alignment, the release-notes source, Sparkle signature
  verification.
- `hand-test`: launching the built app and running the changed flow, including the maintainer's daily copy.
- `field`: only a user's own library, hardware or macOS version shows it.

When a review prompt, skill or model changes, rerun it on the files each fix touched as they were at `<Fixed>^` and
note which rows it finds. `Introduced` is kept when known, for the time a defect stayed in.

## Incidents

| ID | Reported | Symptom | Introduced | Fixed | Layer | Caught by |
|---|---|---|---|---|---|---|
| I-01 | 2026-05-06 | V3.5.1 shipped with CURRENT_PROJECT_VERSION still 3.5.0, so Sparkle offered the same update forever (#524) | dd137718 | 5a65863f | release-check | `version-consistency` |
| I-02 | 2026-07-17 | A note opened with another note's text after a save from preview mode, and the original text was lost (#543) | unknown | 205dde53 | review | `testRefusesCrossNoteWholeBufferSave`, `testRefusesSaveFromClearedBuffer` |
| I-03 | 2026-07-27 | PDF export appended a Mermaid syntax error diagram after a diagram that rendered correctly (#548) | unknown | 0f7a346b | unit | `testRenderedMermaidSurvivesExportReloadWithoutOrphanError`, `testInvalidMermaidFallsBackWithoutOrphanError` |
| I-04 | 2026-08-03 | A note deleted from the Trash folder came back as a new file (#549) | unknown | 3b4efb04 | unit | `testRemovedTrashMarkerIsHiddenOnlyWhileInsideTrash`, `testMissingLoadedNoteCannotBeRecreatedBeforeWatcherRetiresIt` |
| I-05 | 2026-10-10 | Clean Unused Attachments moved images that unopened notes still referenced to the Trash | unknown | c47c4af8 | unit | `testImagesOfNotesInUnopenedSubfoldersAreNotOrphans` |
| I-06 | 2026-10-11 | A note whose file could not be read (an offline iCloud placeholder) was saved over with an empty buffer | unknown | 652811ea | unit | `testUnreadableNoteIsNeverOverwrittenByItsEmptyBuffer` |
| I-07 | 2026-10-19 | MiaoYan PPT was greyed out in the note list's context menu in 4.5.0 (#571) | unknown | 95eec53a | hand-test | `testNoteListContextMenuTargetsItsOwnScene` |
