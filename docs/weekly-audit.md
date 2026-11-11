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

Follow-up the same day, after the maintainer asked for every open item that could be improved:
- The storyboard window switches light and dark in place in preview and split mode (`6223461f`),
  and a PlantUML retheme keeps the drawn image until the new one loads, or for good when it fails
  (`157cb205`).
- Clean Typography refuses a read-only note with its notice (`5828a325`); the damaged notice says
  the encoding could not be determined (`42b68257`); the storyboard's move clears the editor only
  when a note moved (`c6652cdd`).
- Note list fonts are cached (`ba6a2bde`); the tripwire (`d35db779`), `.todo` with
  `unLoadCheckboxes` and `.preferencesChanged` (`4d21a4f1`) are gone; the pbxproj links each
  package once (`a89a11bc`, S4).
- Format undo on the storyboard editor and drops through `performDragOperation` are tested
  (`ffd1d88b`).
- iPhone: local `<audio>` goes through the asset scheme.
- Dropped: the version snapshot per note switch; `saveVersion` already skips content equal to the
  latest snapshot, so nothing is written.

### Open

- Whether Restore may overwrite a read-only damaged note with a clean version (`decide` 1105-42;
  Duplicate is the way out today).
- Changing Light or Dark in Settings still reloads the preview (`recreatePreviewView`); a Mermaid
  diagram shows its source for a moment while it redraws in the new theme.
- Real-app checks: P3 and P4, the hover anchor, the light zoom backdrop after a switch, E6, and a
  system appearance switch while reading in preview and in split mode.
- iPhone: Trash with iCloud lands in iCloud Drive's Recently Deleted, which the app never lists
  (`decide` 1105-47); video, audio and KaTeX need a device check.

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

## 2026-11-11 (before V4.9.0, whole tree)

- Audited: MiaoYan `9446d4f2` (window `49da1f67..9446d4f2`, 72 commits), MiaoYan-Pro `e1e40cf3`. Five Opus
  agents, read-only; five fix agents in separate worktrees; one independent review of each merged stack.
- Mechanical: `check_incidents.py` 35 rows, 0 problems; SwiftLint and swift-format `--strict` clean.
- Verified by the main session before reporting: the iPhone's Empty Trash deleting every entry (read both sides).
- Next window from: the last commit of this run.

### Fixed (MiaoYan)

- Replace kept rewriting a word whose replacement still matched (`63ae724c`, I-36); Tab on an item from 10 up
  left the caret on the next line (`2d2ff0ca`, I-37); an edit inside a match left part of it highlighted
  (`797c7fba`).
- PDF from a dark preview: PlantUML in dark colours (`3cd69888`, I-38), dark rules and checkboxes when the app
  is dark (`8ff196e9`, I-39), the `Rendering ...` loader printed (`b8d62732`, I-40).
- MiaoYanCore, for the iPhone and iPad keyboard: indent under an ordered item nests at its content column
  (`012c8a0b`), Toggle Task keeps a quote prefix (`7fe4484a`), Return on a line holding U+2028 no longer deletes
  it (`c8befc23`).
- Stale: ARCHITECTURE.md's Trash line, five dangling section pointers, DEPENDENCIES.md (`4895543d`); 19 dead
  symbols and `PreviewTextField.swift` (`dad4341e`, `99ee2f68`).
- From the review: the 0.15s find-bar debounce added in `797c7fba` let Find Next and Replace act on positions
  from before the edit, so it was removed again (`5b276c9b`).

Fixed (iPhone and iPad, MiaoYan-Pro): Empty Trash deletes only the notes its page lists, so a folder the Mac
put in the library Trash keeps its notes; a note renamed, moved or trashed elsewhere while being typed in is
kept as a copy instead of written back or dropped, Keep Mine included; one formatter for Yesterday; an undrawn
Mermaid block keeps its lines.

Follow-up the same day, after the maintainer decided both open questions: Return on the Mac runs
MiaoYanCore's `ListContinuation`, the iPhone's rule, extended so both continue `> ` quotes and `1) `, skip
fenced code and keep CRLF (`5cf1323e`); the iPhone reader draws Mermaid with the Mac's warm palette, held to
`theme-config.js` by a source gate; a pinned note on the iPhone keeps its pin through a save (MiaoYan #575).

### Refuted

- "Open in MiaoYan on a library note imports a copy": `standardizedFileURL` already drops `/private` for an
  existing path, measured on macOS and in an iOS simulator.

### Open

- Whether the sandboxed App Store Mac build finds the system Trash in `Storage.systemTrashDestination` or
  always falls back to the library Trash: delete a folder in that build and look in both places.
- Real-app checks: a PDF from a dark preview with PlantUML, `---`, a footnote and a task, online and offline
  (offline now waits the full 9.6s, as a light preview already did); PNG and HTML export once each.
- Mac Tab pads three spaces under any numbered item; under `10.` CommonMark needs four (MiaoYanCore now does).
- Replace wraps to the first match after the last one, so a lone `cat` to `cats` still grows on a second press.
- `TaskMarker.itemRegex` still anchors inside a line holding U+2028.
- Pasting code copied from a web page inside a fenced block may add a second fence (clipboard not measured).
- Performance, low: the shell window does not coalesce disk events; `NoteCellView.draw` rebuilds row text;
  a find-bar search per keystroke on a long note (a delayed refresh needs the four find commands to flush first).
- iPhone, device checks: every typing pause reloads the mounted lists after the app's own save; the reader
  keeps its place by pixel offset after an outside edit; whether a non-system body face re-highlights the note
  per key on iPad; a brief absence during an iCloud download raising a false conflict; an undownloaded note in
  the Trash is deleted through its placeholder; the reader never notices its note was renamed elsewhere until
  the user types.
- Diagrams on a phone: a gantt chart's date labels overlap at phone width, and a dark pie chart takes Mermaid's
  own near-black and maroon slices, as the Mac's does.
- The Mac still continues an en dash, an em dash, `•` and `| ` on Return and the iPhone does not; the Mac
  highlighter does not see a CRLF fence that Return now does.

### Decided, do not re-report

- Everything in the 2026-11-05 list.
- Empty Trash on the iPhone leaves folders, images and other files in the library Trash, by design.

### Checked and fine

The library Trash wiring on the Mac (sidebar, backlinks, attachments, the row rebuilt after an outside empty);
deletes flush the pending save first and undo checks the file's identity; a failed save is reported once; the
14 new strings in all four languages and the new menu item in both windows; the print-only CSS cannot reach
PNG, HTML or PPT export; every `renderPage` step also runs in `renderBlocks`; 911 quoted tokens in the guides
checked, 8 stale; no uncalled function in the six non-vendored preview scripts.
