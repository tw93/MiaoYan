---
paths:
  - "Controllers/**"
  - "Helpers/TypographyCleaner*"
  - "Resources/Localization/**"
  - "**/*.storyboard"
---

# Editor, menus and localization

- Editor buffer ownership (#543): in preview/presentation/PPT modes `EditTextView.note` follows the list selection while `textStorage` keeps the last edited note, so the two legitimately diverge. `EditTextView.storageNote` records which note the buffer belongs to; every wholesale storage assignment must go through `publishStorage(_:owner:)`, and every whole-buffer persist through `saveTextStorageContent(to:)`, which refuses cross-note targets. Never persist the buffer based on `EditTextView.note` or the table selection alone, and never compare `EditTextView.note` against itself as a guard (that tautology is how the V4.0.0 content-swap shipped).
- Sidebar horizontal layout is owned by `SidebarProjectView.tile()`: after reloads and resizes, the outline frame and first column must match the clip-view width and the clip-view horizontal origin must stay at zero. Do not replace this invariant with event-specific width resets.
- ViewController's local key monitor runs `handleKeyDown` for every key and passes every key on (#491: swallowing them broke Command-C on macOS Tahoe), except Return pressed in the list or sidebar, which it consumes after moving focus so the newline never reaches the editor. Views must not call `handleKeyDown` again from their own `keyDown`, or list shortcuts fire twice.
- Note-list search (`ViewController+Data.swift`) filters by folder scope first, then hands plain `NoteSearchCandidate` values to `NoteContentMatcher` in a detached task, which reads unloaded bodies from disk; the main thread only snapshots and applies results. Never load or lowercase note bodies on the main thread for search, and match titles without the `.md` extension.
- Async note/image/file loading is intentional. Do not reintroduce blocking reads on the main thread for large notes or previews.
- Image upload posts to a local PicGo/PicList HTTP endpoint at `127.0.0.1:36677` (`Helpers/ClipboardManager.swift`). The macOS `Info.plist` ATS permits this via `NSAllowsLocalNetworking`; do not widen it back to `NSAllowsArbitraryLoads`. The markdown preview loads through `loadFileURL` (file://), not a local web server, so ATS does not gate preview rendering.
- `Helpers/TypographyCleaner.swift` (Edit → Clean Typography) must never rewrite protected regions: fenced/inline code, math, link targets, wikilinks, bare URLs, frontmatter. Extend the segment parser, don't bypass it. `Helpers/HtmlToMarkdown.swift` converts pasted HTML only when block-structure tags are present, so plain-text paste stays authoritative for code copied from editors; keep that gate.
- Every `.lproj` must be listed in the four `PBXVariantGroup`s (`Main.storyboard`, `Localizable.strings`, `InfoPlist.strings`, `ContentViewController.xib`), or the folder never reaches the bundle: Spanish was contributed in 2026-03 and shipped nowhere until it was registered on 2026-10-23. Spanish has no row in the language popup and appears only through the system language, where the popup still reads English.
- New macOS menu items need the storyboard entry plus an ObjectID-keyed `.title` line in all four `Main.strings` (es/ja/zh-Hans/zh-Hant); new toasts need the English text as key in all four `Localizable.strings` (Base has no Localizable.strings, English falls back to the key itself). Missing a file silently ships English to that locale.
