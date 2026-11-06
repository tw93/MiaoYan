# Incidents

Defects that reached users in a published release or the maintainer's daily build (the installed
`/Applications/MiaoYan.app`, which AGENTS.md makes the test copy), kept as the eval set for every review layer
("incidents are the eval", from the Claude Code team's code review write-up). Every release is reviewed against this
table first (AGENTS.md, Release Notes). A row is added in the same change that fixes the defect:
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
| I-08 | 2026-02-28 | Command-C stopped working system-wide on macOS Tahoe while MiaoYan was running, because the window's key monitor swallowed keys it handled (#491) | unknown | 47f42adf | field | `test_the_editor_key_monitor_passes_every_key_on_but_return_from_the_list` |
| I-09 | 2026-03-31 | After opening one .md file, the library's notes and folders were gone on the next launch, since a quit kept single-file mode stored (#503) | unknown | 5741a5f8 | hand-test | `test_single_mode_is_cleared_before_launch_loads_the_library_and_on_quit` |
| I-10 | 2026-05-22 | Opening .md files from two folders in quick succession saved one note's text over the other (#532) | unknown | 205dde53 | review | `testRefusesCrossNoteWholeBufferSave` |
| I-11 | 2026-07-01 | Closing the window in preview mode with Command-W and reopening it showed a blank preview (#541) | unknown | f9fc608a | hand-test | `test_the_preview_is_sized_against_the_preview_pane_first` |
| I-12 | 2026-10-28 | Multi-line `\[ \]`, `\( \)` and mid-paragraph `$$` math showed as raw TeX under the default MiaoYan line-break mode, which Typora rendered | unknown | 4cff5e28 | unit | `testMultiLineMathRendersInTheMiaoYanLineBreakMode`, `testMathLineBreaksDoNotDependOnTheLineBreakMode` |
| I-13 | 2026-11-01 | Picking a folder or file in File > Single Mode crashed the app, because the menu's stand-in controller reloaded with nil outlets (#572) | 20b4e8f1 | 29c83d33 | hand-test | `testSingleModeReloadOnTheStandInDoesNotTrap` |
| I-14 | 2026-11-04 | PDF export dropped its print styles, and images the reader had not scrolled to printed blank or collapsed, because backticks in the print sheet's comments ended the template literal carrying it | 7bf089c9 | f2ad6725 | unit | `testPrintSetupRunsWithTheRealSheetAndUnlazesImages`, `testScriptsDoNotInterpolateSwiftTextIntoTemplateLiterals` |
| I-15 | 2026-11-04 | The sidebar showed no folders in the daily build after the title row moved onto the traffic lights' line: the header was ordered above the folder list, and AppKit then made no row views | 4e081958 | 48d05fae | hand-test | `testFolderListStaysAboveTheHeader` |
| I-16 | 2026-11-04 | An image with only a width, as Weekly notes write `<img width="800">`, held a square box until it loaded, since only both sides counted as a size | unknown | f59238a0 | write-time | `testAnImageWithOnlyAWidthTakesItsOwnRatio` |
| I-17 | 2026-11-04 | Videos showed an empty player and slow images blank paper until they had loaded | unknown | 37f0d4f4 | hand-test | `testVideosWaitForThePageAndAreMarkedForTheirFirstFrame`, `testMediaHoldATintedBoxUntilTheyCanShowSomething` |
| I-18 | 2026-11-04 | A remote image never opened before held a square or 16:9 box for the seconds its file took to arrive, and nothing said it was still loading | unknown | 6f0f56d8 | hand-test | `testRemoteImageProbeAsksForTheHeaderOnly`, `testMediaHoldATintedBoxUntilTheyCanShowSomething` |
| I-19 | 2026-11-05 | When a table image above the view took its probed size before anything had painted, the text in view jumped up about 13px, since the row grew a line less than the image | 6f0f56d8 | 878c31b9 | unit | `testMediaHoldATintedBoxUntilTheyCanShowSomething` |
| I-20 | 2026-11-05 | Notes deleted or renamed outside MiaoYan (Finder, git, a sync client) stayed listed until relaunch, since the watcher read the type of a file that was gone and dropped every removal and rename | unknown | 15ec8bfe | unit | `testNoteDeletedOrRenamedOutsideMiaoYanLeavesTheList` |
| I-21 | 2026-11-05 | Command-Z after Format replayed earlier typing at stale ranges in the reformatted text, and autosave saved the result, since Format wrote the storage outside the undo stack in both windows | 93f9346e | 93fc8a84 | write-time | `testUndoAfterFormatRestoresTheTextBeforeIt` |
| I-22 | 2026-11-05 | A note with a local video and no image lost its player on the first edit in split view, because the live update resolved media paths only when the note had an image | unknown | e0088b1d | write-time | `testALiveUpdateResolvesALocalVideoInANoteWithoutImages` |
| I-23 | 2026-11-05 | Typing `$5 and $10` in split view rendered it as math, and new headings had no id or TOC entry, because a live update skipped steps a load runs | unknown | 73244c52 | write-time | `testALiveUpdateRendersNewBlocksAsALoadDoes` |
| I-24 | 2026-11-05 | PNG export captured a PlantUML diagram below the view blank and did not wait for Mermaid or Markmap still drawing, which PDF export already handled | unknown | 169f65ec | write-time | `testImageExportWaitsForLazyDiagramsAsPDFDoes` |
| I-25 | 2026-11-05 | Images or files dragged from Finder into the editor became an attachment that was never copied to `i/`, so the note saved without them, since a73f4585 removed the editor's drag handling while it stayed rich text with `importsGraphics` on | a73f4585 | 38bf0f0d | write-time | `testDroppedFileIsCopiedAndLinkedAtTheDropPoint` |
| I-26 | 2026-11-05 | A folder named like `Trash Talk`, or any folder under a library whose path contained "Trash", never appeared in the sidebar, because the subfolder scan skipped every path containing that text | unknown | 394a513f | write-time | `testFolderNamedLikeTrashIsListedButTrashIsNot` |
| I-27 | 2026-11-05 | Deleting a folder within 1.5s of typing in one of its notes lost that edit: both sidebars moved the folder to the Trash before its notes were flushed, so the save found its file gone | unknown | faafa0a9 | write-time | `testDeletingAFolderWritesWaitingEditsBeforeTheMove` |
| I-28 | 2026-11-05 | Note list titles, dates and sidebar folder names set their last character apart (`系统配置SO P`, `妙言 PP T`), because the label tracking stopped one character short and the system face, default since 2026-10-11, spaced the split-off run | 90399d1a | 4bcde409 | write-time | `testLabelTrackingCoversTheLastCharacter` |
| I-29 | 2026-11-05 | With a note open in the preview or split view, an edit to it from the iPhone moved the Mac's view: the preview jumped to earlier text and split view reloaded at the top, because the update held only the top block in view and fell back to an old line number | unknown | 2ec308a2 | write-time | `testAnOutsideEditToTheTopBlockInViewKeepsTheReaderInPlace` |
| I-30 | 2026-11-06 | Offline, formulas in the preview and in PDF and PNG exports fell back to Times: `katex.min.css` fetched every KaTeX font from gw.alipayobjects.com and the bundle carried none, while the blog said math needs no network | unknown | 9e65e3b5 | write-time | `testKatexFontsShipInsideThePreviewBundle` |
| I-31 | 2026-11-06 | After the iPhone emptied the shared library Trash, the Mac's Trash list went empty but its sidebar row stayed until the next sidebar rebuild: the watcher rebuilt the sidebar only when a note arrived, and 71d00a01 made the row depend on the Trash folder's contents | 71d00a01 | 65d596eb | write-time | `testTrashFilesRemovedElsewhereRefreshTheSidebar` |
