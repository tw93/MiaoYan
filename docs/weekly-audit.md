# Weekly Audit Log

Each run of `.claude/skills/weekly-audit` appends an entry. The next run reads the newest entry's
"Next window from", "Decided, do not re-report" and "Open" lists first. iPhone and iPad findings
are summarised without code paths, since that code lives in the private MiaoYan-Pro repository.

## 2026-11-05 (first run, whole tree)

- Audited: MiaoYan `2c979d33` (after V4.7.0), MiaoYan-Pro `d4936fb5`. Five Opus agents, read-only.
- Mechanical: `check_incidents.py` 19 rows, 0 problems; SwiftLint and swift-format `--strict` clean.
- Verified by the main session before reporting: B1 (a `typeIdentifier` read on a deleted file
  returns nil in a standalone test), E1 and P1 (read the code paths).
- Next window from: `49da1f67` (the last fix of this run).

### Findings as reported

Behaviour
- B1 high: notes deleted or renamed outside MiaoYan stay listed. `FileSystemEventManager.isValidFileType`
  calls `Storage.isValidUTI`, which reads `typeIdentifier`; for a path that is gone it is nil, so
  every removal and rename event is dropped before `handleFileRemoval`. Only Trash projects
  reconcile (`retireMissingNotes`). Typing into the stale row is refused at save with only a
  `trackError`. Fix: skip the UTI check when the file no longer exists; toast a refused save; test.
- B2 medium: deleting a folder leaves its registered subfolders in `Storage.projects`
  (`removeBy(project:)`); a later "Move to" that subfolder can recreate the deleted path.
- B3 medium: a UTF-8 note with one bad byte opens through a lossy fallback encoding and the next
  save writes the garbled text back (`MiaoYanCore` `NoteText`). Needs a decision: open read-only,
  or keep a backup before the first write.
- B4 medium, rare: Clean Unused Attachments treats `<img src="../i/x.png">` and `[a](../files/a.pdf)`
  from a subfolder note as unused (`Note.swift` resolution bounded to the note's own folder).
- B5 low: `NotesTableView.unDelete` drops the note from storage before the move, so a failed
  restore hides it until reload.

Editing
- E1 high: Format replaces the whole storage without `shouldChangeText`/`didChangeText` in both
  windows (`replaceEditorStorage`, `ShellEditor.apply`), since 93f9346e; Command-Z afterwards
  replays earlier typing at stale ranges in the reformatted text. Fix as Clean Typography does.
- E2 medium: dropping an image or file on the editor inserts an attachment that is never saved
  to `i/` (drag handling removed in a73f4585, `importsGraphics` still on). Needs a decision:
  refuse file drops or import them.
- E3 medium: Return after `- [x] done` starts `- [x] ` (`TextFormatter.newLine`).
- E4 medium: Command-T on an indented task rewrites the first six characters
  (`  - [x] a` becomes `- [ ] ] a`).
- E5 low: Command-K and image insertion compare the selection length to the literal's length
  (4 / 5) instead of 0; list continuation fails on CRLF notes; Tab's selection uses
  `String.count` instead of UTF-16 length.
- E6 low, needs a real-app check: `refillEditArea` restores the cursor without clamping after an
  outside edit shortens the note.

Preview
- P1 high: a note with a local `<video>` and no image breaks its video on the first live update:
  `MPreviewView` runs `processImages` (which also rewrites video sources) only when the HTML
  contains `<img`.
- P2 medium: `buildUpdateScript` skips four `renderPage` steps (`escapeCurrencyLikeMath`, emoji,
  header anchors and image zoom, `MiaoYanTOC.refresh`), so `$5 and $10` typed in split view
  renders as math and new headings miss the TOC.
- P3 medium, needs a real-app check: the shell preview keeps the old theme after a system
  appearance change (`updateAppearance` swaps only the body class).
- P4 medium, needs a real-app check: PNG export does not un-lazy PlantUML images or wait for
  pending diagrams the way PDF export does.
- P5 low: the first edit after a remote image's size is learnt re-inserts its paragraph; an
  appearance change in the storyboard preview reloads to the top; heading ids are raw text
  (in-note `#slug` links never match; needs a decision); diagram palettes keep pre-warm cool
  greys (`theme-config.js`; needs a decision).

Performance
- F1 medium: every typing pause starts an uncancellable chain of disk re-checks of the open note,
  each ending in a main-thread `getContent()` once the save lands (`ViewController+Data`,
  `ShellWindowController`, `FileSystemEventManager.recheckNote`). Keep one cancellable re-check.
- F2 medium: `convertAppLinks` rescans fenced blocks from the top once per wikilink on every
  preview update; reuse `fencedCodeBlockRanges(in:)` as 7b38471a did for emoji.
- F3 low: Return re-marks links across the whole note; every note switch writes a version
  snapshot even when nothing was edited (needs a decision); every full preview load walks the
  47 bundle files on the main thread; `preLoadNoteTitles` does nothing; `NoteCellView.draw`
  rebuilds fonts per redraw.

Stale
- S1: `docs/MiaoYan-linus-code-review.md` (local only) describes 2026-05 as current; delete or mark
  historical (needs a decision).
- S2: CONTRIBUTING.md says `DEVELOPMENT_TEAM` was removed (it is set) and calls macOS 13 Sonoma;
  ARCHITECTURE.md quotes two drifted line numbers and the old "URL drift tripwire" name;
  DEPENDENCIES.md places the `#if !APPSTORE` Sparkle gate in this repo; the bundled
  Introduction note says Command-O opens a separate window (it opens Single Mode).
- S3: about 115 Swift declarations with no reference (list kept outside the repo), including
  `Storage.cleanTrash()`, which would permanently empty the system Trash if anything called it,
  and `ViewController.saveHtmlAtClipboard`, which skips frontmatter stripping; dead preview message
  channels (`newSelectionDetected`, `notification`, `logging`); two unused `common.js` helpers;
  `internalLogDebug` writing to `~/Downloads` instead of `trackError`; the 2026-05-07 tripwire
  in `ViewController+Action` past its two-release removal condition (needs a decision).
- S4: pbxproj keeps four orphan package references and links each package two to four times
  (builds today; clean up in Xcode, needs a decision).

iPhone and iPad (fix in MiaoYan-Pro)
- Typing during a sync conflict is lost if iOS ends the app in the background; Delete, Rename and
  Move do nothing without feedback while that conflict shows.
- Every keystroke restyles every code block's font in notes with fences.
- The new-note body hint draws over CJK marked text.
- Local `<video>` in the reader cannot load; GitHub alerts, KaTeX, PlantUML and markmap are not
  rendered (product scope, needs a decision); Mermaid keeps its first theme; a size-class change
  reloads the reader to the top.
- Not re-checked by the main session: a title starting with "." makes a hidden file; search skips
  undownloaded notes whose title matches; a case-only rename becomes "Note 1"; a folder named
  like "Trash Talk" is hidden; Trash with iCloud may land in a hidden `.Trash`.
- Stale: AGENTS.md lists card dates under caption (they use subheadline); three dead symbols.

### Outcome

The maintainer approved every fix on 2026-11-05: drops import files, damaged UTF-8 opens read-only,
heading ids keep their text with a hover anchor (no GitHub slugs), diagrams take the warm palette,
the iPhone reader gets alerts and KaTeX, and the old review document goes. Five fix agents worked in
separate worktrees; three review rounds on the merged stack found ten more problems, fixed below.

Fixed (MiaoYan)
- B1 `15ec8bfe`, B2 `c730fcc1`, B3 `8430694b` with `da9687e6` and `ec507b2d`: decode shows U+FFFD
  only at four good UTF-8 sequences per bad one (short GB18030 and EUC-KR titles were read as
  damaged), while any note with at least as many good as bad stays read-only, since a short damaged
  note shown in its legacy reading and saved wrote mojibake over itself. Read-only notes duplicate
  (`f6a3daf5`), refuse Move with a toast, have Restore disabled, and are refused at `save` before
  their buffer changes. B4 `55004c43`, B5 `a562362c`.
- E1 `93fc8a84`, E2 `38bf0f0d` with `3dc82e63` (a note dragged from the list is not imported), E3
  `dc42ff2c`, E4 `02d6159d`, E5 `fb4ae907`, E6 `ac0d88bc`.
- P1 `e0088b1d`, P2 `73244c52`, P3 `77a4dc7b` (shell window), P4 `169f65ec`, P5 `8c629f49`, hover
  anchor `421a25e9` with batched reads `af63deb5`, warm diagrams `a9fffaa7`.
- F1 `f0931802`, F2 `ab393e8c`, F3 `70dcbc33`, `13b1258a`, `fe151058`.
- S1 moved to the Trash (local file), S2 `ed5c72f5`, S3 `fe24644d` `7fa91f63` `b35f92cb`, and the
  `Trash Talk` folder `394a513f`.
- From the review: a folder delete wrote its last edit after the move (`faafa0a9`, I-27); the
  missing-file notice was marked even with no window to show it (`733651d9`); the zoom backdrop
  stayed dark after an in-place switch to light (`af63deb5`).
- A V4.7.0 user's report: list titles, dates and folder names set their last character apart
  (`系统配置SO P`), fixed in `4bcde409` (I-28).
- Incident rows I-20 to I-28.

Fixed (iPhone and iPad, MiaoYan-Pro): typing kept through a background exit during a conflict;
Delete, Rename and Move open the conflict choice; fences resweep only when they change; the new-note
hint steps aside for marked text; titles starting with "."; case-only renames; folders named like
"Trash Talk"; search finds undownloaded notes by title; Move and Restore download first; local video,
GitHub alerts and bundled KaTeX in the reader; Mermaid follows the appearance; a size-class change no
longer reloads the reader; three dead symbols removed.

### Open

- The storyboard window still reloads its preview on an appearance change
  (`EditTextView.applySystemAppearance`); the shell switches in place.
- PlantUML is fetched again from its server on an appearance change, so offline it shows source.
- Whether Restore may overwrite a read-only damaged note with a clean version (recorded in
  `decide`; Duplicate is the way out today).
- Every note switch writes a version snapshot even when nothing was edited (needs a decision).
- `NoteCellView.draw` builds fonts on every redraw.
- The 2026-05-07 tripwire in `ViewController+Action` (needs a decision); `.todo` readers in the
  text storage and highlighter are dead now that nothing sets `.todo`; `.preferencesChanged` is
  posted with no observer checked.
- Clean Typography on a read-only note still shows its success toast; a valid short legacy note
  held read-only reads "has invalid characters"; the storyboard's move clears the editor even when
  a read-only note refused to move.
- S4 pbxproj orphan package references (clean up in Xcode).
- Format undo is tested in the shell only, and the drop test calls `dropFiles` directly rather than
  through `performDragOperation`.
- Real-app checks: P3 and P4, the hover anchor, the light zoom backdrop after a switch, E6.
- iPhone: Trash with iCloud may land in a system `.Trash` the app never lists (needs a decision);
  `<audio>` is not routed through the asset scheme; video and KaTeX need a device check.

### Decided, do not re-report

- Everything AGENTS.md records as a maintainer decision.
- Heading ids keep the heading's text; in-note `#slug` links written GitHub-style do not match, by
  choice (2026-11-05).
- PPT diagrams are not themed (ppt.html loads no ThemeConfig), so they need no redraw on a switch.
- Mermaid and markmap keep `#E7E9EA` diagram text while the dark body text is `#D6D1C6` (2026-11-05).
- Methods called only from tests (`hasVersions`, `waitForPendingWork`, `queuedCount`,
  `Project.saveSettings`, `getOutlinks`, `getAllImageLinks`) are test seams.

### Checked and fine

Saves refuse retired, moving and `loadFailed` notes and fail closed; #543 ownership guards in both
windows; every `.lproj` in the four variant groups and every menu title and literal toast in all
four languages (measured); frontmatter stripped on every live output; search filters scope first
and matches off the main thread; partial highlighting and the size tiers; KaTeX and Mermaid
throttled; PDF export fits tables, loads lazy images and waits for diagrams; IME composition skips
Return, Tab and split updates; Clean Typography is undoable; AGENTS.md's 452 quoted symbols checked,
none stale.
