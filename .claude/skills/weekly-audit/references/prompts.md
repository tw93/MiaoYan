# Weekly Audit Prompts

Fill `<HEAD>`, `<WINDOW>` (from `docs/weekly-audit.md`, "Next window from"), `<SCOPE>` (Phase 1),
`<MECHANICAL>` (the Phase 1 check output), `<DECIDED>` (the "Decided, do not re-report" lists) and
`<PRO>` (the MiaoYan-Pro checkout path when it is in scope, else "not in scope"). Every audit prompt
starts with the shared header; every fix prompt with the fix header.

## Shared audit header

```
Read-only audit of the MiaoYan repository (macOS Markdown editor: AppKit editor EditTextView,
WKWebView preview MPreviewView with Resources/DownView.bundle, a SwiftUI shell in Shell/) at
<HEAD>. Do NOT edit, stage, commit, build or run tests; read, grep and git log only. Exclude
.claude/worktrees, build, .build and the vendored preview files (*.min.js, *.min.css, js/vendor,
js/mermaid-layout-elk*.js, ppt/) from every grep. Scope: <SCOPE>. The iPhone and iPad app:
<PRO> (its MiaoYanMobile/ and AGENTS.md; read-only, and never quote its code into this repo).
Read AGENTS.md and every file in .claude/rules/ first: Working Rules, the risk areas, preview and fonts and the
product preferences record decisions and measurements; before reporting a candidate, grep
AGENTS.md, .claude/rules and docs/incidents.md for its symbol. Never report these decided items:
<DECIDED>. Mechanical checks already run: <MECHANICAL>; do not redo them.
For EACH candidate, try to refute it once (the guard that already blocks it, the test that locks
it, the line that records the decision) and report only survivors. Mark every number as measured
(say where) or reasoned (say from what). Defects that only show in a running app (a flash, a
scroll jump, alignment) cannot be proven by reading: report them as "needs a real-app check" with
the exact steps, not as confirmed.
Output (<= 800 words): ranked findings with severity (high: loses or damages user data, or a
feature does not work; medium: a user notices it in normal use; low: polish or cleanup),
file:line, a concrete failure scenario, why existing guards miss it, the smallest fix, and
whether it needs the maintainer; then a short "checked and fine" list.
```

## 1. Stale

```
Two halves.
Rules and docs: every current-state claim in AGENTS.md, ARCHITECTURE.md, .claude/rules,
docs/ (except incidents.md rows, which are history), skills/miaoyan/SKILL.md and the READMEs
against the code: symbols, file paths, commands, test names, versions, defaults, colours and
sizes quoted as current. Rules deliberately record rejected and removed things; read the
sentence before calling a missing symbol stale. A whole document that describes a past state
as current (an old review, a plan already done) is a finding. Report counts: claims checked /
stale / deliberate.
Code: zero-caller Swift symbols (grep strings, selectors, storyboard and xib connections, and
KVO keys too; separate test-only from unused), JS functions and CSS selectors nothing calls or
matches (check common.js, app.js, the Swift-injected scripts in MPreviewView and HtmlManager,
and the markup Markdown.swift produces), UserDefaults keys no longer read, forward-only
wrappers, duplicated helpers, comments naming removed functions, #if DEBUG scaffolding left
from a finished investigation.
```

## 2. Performance

```
Find work that makes typing, scrolling, switching notes or launching slower than it needs to
be: main-thread file IO or synchronous reads of note bodies, per-keystroke work in the editor
(full-document highlighting, regex compiles inside loops, NSAttributedString rebuilds,
layout invalidation of the whole storage), per-row work in the note list and sidebar (date
formatters, previews, icon loads), search, the preview path (full reloads where patchContent
or showNoteInPlace applies, evaluateJavaScript calls per keystroke, image probes), unbounded
caches, timers and file-watcher handling that can storm, launch work. For each: how often it
runs, its cost, and whether it is already debounced, cached or off the main thread.
Note: highlighting large notes and the 1.5s save debounce are recorded design; judge them
against their own rules before reporting.
```

## 3. Behaviour

```
Find defects that lose, misplace or damage user data, or make a feature not work. Start from
The risk areas in .claude/rules/: buffer ownership (storageNote, publishStorage,
saveTextStorageContent), retiring removed notes, loadFailed, Trash and the
removedFromTrashKey marker, iCloud placeholders, symlinked folders and path aliases, folder
moves, Clean Unused Attachments, frontmatter stripping on every output surface, wikilinks and
backlinks. Then parity: every main-menu command and handleKeyDown shortcut works in both the
storyboard window and the -MiaoYanShell window; every .lproj registered in the four
PBXVariantGroups and every new menu item and toast localised in all four languages. Then error
paths: failures swallowed with try? or print instead of AppDelegate.trackError, writes that do
not fail closed. Name the user action that triggers each defect.
```

## 4. Editing

```
Find what makes writing in the editor worse: input latency on long notes, CJK input (marked
text, IME candidate window position, punctuation), undo grouping and undo after formatting or
auto-format, the cursor or scroll position jumping after save, reload from disk, external
change, highlighting or a mode switch, list continuation and indentation, auto-pairing,
paste (rich text, images, files, HTML to Markdown), formatting commands and their shortcuts,
find and replace, focus after creating, renaming or deleting a note, typewriter or split
scrolling, and CRLF or tab handling. Check both windows where they differ (isShellHosted).
For each, the steps a writer takes and what they see.
```

## 5. Preview

```
Find what makes reading the preview worse: blank or white flashes on load, note switch, mode
switch or appearance change; scroll position lost on edit, switch or reload; images, video and
iframes overflowing or not reserving space; code blocks, inline code, math, Mermaid, PlantUML,
markmap and tables rendering wrong in light or dark; the TOC; split-view scroll sync; PPT
mode; PDF, PNG and HTML export (tables fitting the width, dark export, waiting for images and
diagrams, repeated exports). Check that every renderPage step also runs for patchContent
updates and showNoteInPlace switches, and that CSS declarations clear the 12.0 deployment
target. For each, the note content and steps that show it.
```

## Fix header (Phase 4)

```
Implement in MiaoYan. Read AGENTS.md and .claude/rules/swift.md.
Isolation: never edit the shared checkout. Work in
  git -C <repo> worktree add --detach <SCRATCH>/wt-<n> origin/main
and build with -derivedDataPath <SCRATCH>/dd-<n>. Commit locally as Tw93 <hitw93@gmail.com>
(lowercase type prefix, subject <= 80, body = why and how it was verified, no Co-authored-by);
do NOT push. Only touch: <files>. Other agents own: <files>.
Every behaviour change gets a test that fails on the old code: red-run it by restoring the old
source in your worktree; if it cannot compile on old code, break only the judged condition in
the new code instead and say it was not red-run. New files need the four project.pbxproj
registrations. Run xcodebuild test with CODE_SIGNING_ALLOWED=NO and
PRODUCT_BUNDLE_IDENTIFIER=com.tw93.miaoyan.qa, and confirm the new tests appear as passed.
Return: commit hashes, files, test summaries, red-run evidence, every deviation from this
brief, and anything not done or outside your files.
```
