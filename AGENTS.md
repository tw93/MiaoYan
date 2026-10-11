# MiaoYan Agent Guide

> `CLAUDE.md` is a symlink to this file. Claude Code and Codex (and any other
> agent reading `AGENTS.md`) share this single source so the guide stays
> in sync.
>
> Claude-specific assets:
> - 全局规则: `~/.claude/CLAUDE.md`
> - Swift 通用规则: `~/.claude/rules/swift.md` (项目级补充 `.claude/rules/swift.md`)
> - 本仓库没有项目 skill；release、review、lint 的项目事实都在本文件

## Project

MiaoYan is a lightweight Markdown editor built with Swift. This open-source repository is the only Mac codebase and is actively developed (maintainer, 2026-10-11, reversing the 2026-09-28 maintenance-only split): every Mac feature and fix lands here first. The Mac app is moving from an AppKit shell to a SwiftUI one while keeping its AppKit editor and preview. The iPhone and iPad app and the App Store packaging live in the private `tw93/MiaoYan-Pro`, which merges this repository's `main` to build the App Store Mac app; nothing is pushed from that repository to this one. The App Store purchase is the recommended way to get MiaoYan, one purchase covering iPhone, iPad and Mac; the Mac app stays free here.

## Tech Stack

- **Markdown rendering**: `swift-cmark-gfm` parses GitHub Flavored Markdown.
- **Syntax highlight**: `Highlightr`.
- **Math / diagrams**: LaTeX formulas, Mermaid, PlantUML supported via the preview renderer.
- **Slide mode**: based on Reveal.js. `---` separators delimit slides.
- **Note storage**: filesystem-backed with folder nesting, file-system watch, auto-save, and version history.
- **Editor**: live preview, syntax highlight, keyboard shortcuts, Prettier-integrated auto-format.
- **App shell**: the storyboard window today; a SwiftUI main window under `Shell/` opens instead with `-MiaoYanShell YES` until it reaches parity.

## Repository Map

- `Controllers/` - view controllers and window controllers.
- `Views/` - UI components.
- `Business/` - models and business logic.
- `Helpers/` - utilities and services.
- `Extensions/` - Swift extensions.
- `Resources/` - bundled resources.
- `Shell/` - the SwiftUI main window in progress (`-MiaoYanShell YES`), see the SwiftUI shell rules below.
- `MiaoYan.xcodeproj/` - Xcode project and version settings.
- `Package.swift` - Swift package dependency declarations and supported platforms.
- `Packages/MiaoYanCore/` - local Swift package with the logic the Mac app and the iPhone app in MiaoYan-Pro must agree on (frontmatter, search matching, note text decoding, list-row and card previews), with its own tests (`swift test --package-path Packages/MiaoYanCore`). It imports Foundation only; a change here reaches the iPhone app when Pro merges `main`, so keep its API stable.
- `scripts/` - local build, release, and project maintenance scripts.
- `scripts/release-ci/` - release note rendering, appcast, notarization, and package helpers.
- `skills/miaoyan/` - published Agent Skill (tracked) describing MiaoYan's Markdown, PPT, and `miao` CLI surfaces to outside agents; it restates product syntax, so it drifts when those surfaces change.
- `.github/RELEASE_NOTES.md` - public release note source for GitHub release and appcast body generation.
- `.github/workflows/` - holds `ci.yml` only; release builds are not driven by a tracked release workflow.

## Commands

```bash
xcodebuild -project MiaoYan.xcodeproj -scheme MiaoYan -configuration Debug build
xcodebuild clean
xcodebuild test -project MiaoYan.xcodeproj -scheme MiaoYan -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
swiftlint lint --strict
swift-format lint --recursive . --strict   # --strict is what CI runs; without it a local pass can still fail CI
swift test --package-path Packages/MiaoYanCore
bash scripts/build.sh
ruby scripts/add_tests_target.rb     # only when re-wiring MiaoYanTests after pbxproj reset
```

Use the narrowest relevant command first. Full app builds are the default verification for Swift or project changes.

The Xcode project uses classic pbxproj groups (no filesystem-synchronized
groups). Adding a new source file requires manual registration at 4 sites in
`MiaoYan.xcodeproj/project.pbxproj`: a `PBXBuildFile` entry, a
`PBXFileReference` entry, the owning group's `children` list, and the target's
`PBXSourcesBuildPhase` files list. Mimic an existing sibling entry and use a
fresh unique 24-hex ID for each new object.

## Testing

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

`CODE_SIGNING_ALLOWED=NO` is required on the local test command because
the dev signing identity used for `MiaoYan.app` and the per-developer
identity used for `MiaoYanTests.xctest` end up with different Team IDs,
which makes dyld refuse to load the test bundle into the host app. `ci.yml`
passes the same flag on every xcodebuild invocation, so it is not a
local-only workaround.

## CI

`.github/workflows/ci.yml` runs on every PR and push to `main`:

- macOS Debug build, then `xcodebuild test` for the unit suite (no signing required), then `swift test` for `Packages/MiaoYanCore`
- SwiftLint and swift-format, both `--strict`, so any warning is a merge gate
- Release-notes rendering smoke (`scripts/release-ci/notes_to_html.sh` and
  `render_release_body.sh`) so a broken `.github/RELEASE_NOTES.md` is caught
  before release time, not during it
- On tag pushes (`V*`): version-triplet consistency check
  (`MARKETING_VERSION == CURRENT_PROJECT_VERSION == tag`) to prevent the
  V3.5.1 / #524 incident recurrence

CI does NOT run the notarization or Sparkle signing scripts; those need
maintainer-managed signing keys and run only on the maintainer's machine.

## Error Reporting

`AppDelegate.trackError` is the single funnel for runtime errors:

- DEBUG: still prints to stdout (kept for Xcode console workflow).
- RELEASE: routes through `Helpers/Diagnostics.swift`, which writes a
  `.fault` os_log entry plus a JSON-line ring buffer at
  `~/Library/Logs/MiaoYan/diagnostics.log` (50 entries max).
- Users can attach the diagnostics log to bug reports without us running an
  analytics SDK (local-first stance).

When wiring a new failure path, call `AppDelegate.trackError(error, context:)`
rather than `print(...)` or silently swallowing with `try?`. The `context`
string is the only breadcrumb the maintainer has when triaging.

## 产品偏好

- **付费用户视角**: 默认按 App Store 付费版的精致度做。每次视觉 / 交互改动思考"对得起付费用户吗"。能精致一分就精致一分。
- Preview images, videos and iframes must stay within `max-width: 100%`. Wide tables may scroll inside `.table-scroll`, but must not widen the page. PDF and PNG exports must fit tables to the output width because exported content cannot scroll. Recheck these bounds when adding raw HTML rendering; verify initial rendering, incremental updates and repeated exports when changing table layout.
- **设计参考**: UI / CSS 抄不出来时去看 `~/www/weekly` 和 `~/www/tw93.github.io`, 那里有维护者已经满意的样式。不要凭空发挥。
- **目标视觉风格**: macOS 26 风格的 sidebar (玻璃态、透明、SF Symbols 最新一代) 是长期方向, 不是经典 Big Sur 风格。
- **不要再提议整套 macOS 26 / Liquid Glass 重设计**。一次实机改造 (侧栏换原生 `.sidebar` 半透明材质 + 选中态改强调色玻璃 pill + 图标整体迁 SF Symbols + 自绘 pill `ChromeToolbarButton`) 已被维护者否决, 原话"还不如之前好看, 不强求这个"。要打磨侧栏 / 按钮就在现有不透明设计上做小步增量: 间距、对齐、hover、focus、字重。不要整体换材质或换图标体系, 除非维护者在当前回合明确要求。
- **README 首屏 GIF 按语言分开是有意的**: `README_CN.md` 和 `README_TW.md` 用中文界面的 `newmiaoyan.gif`, 其余语言用英文界面的 `miaoyan.gif`, 审查和改稿时不要统一成一张 (维护者 2026-10-10)。
- **cmd-数字快捷键已占满 0-5**, 不要冲突: 1 侧栏, 2 笔记列表, 3 Toggle Preview, 4 Toggle Presentation, 5 TOC, 0 Actual Size。新增前先 `grep 'keyEquivalent="N"' Resources/Localization/Base.lproj/Main.storyboard` 核对, 绑定只存在于 storyboard, 代码里没有 keyBindings 表。打字机滚动 / 链接相关另开模式或子开关即可。

## Working Rules

- Keep UI updates on the main thread.
- Avoid force unwraps unless the invariant is obvious and local.
- Prefer `AppEnvironment.current.<service>` over direct singleton access in
  new code. The SwiftLint `no_direct_singleton_in_new_code` rule is `severity: warning`
  in `.swiftlint.yml`, but CI runs `swiftlint lint --strict`, which promotes it
  to a merge gate. Existing call sites are grandfathered.
- Keep file writes scoped to user documents or app-controlled locations.
- Do not add network calls, shell execution, or broad file access without clear user need.
- The Mac app shell (window, sidebar, note list, settings, toolbar, menu commands) moves to SwiftUI. The editor (`EditTextView`, an `NSTextView` with regex highlighting) and the preview (`MPreviewView`, a `WKWebView`) stay AppKit behind `NSViewRepresentable`: SwiftUI's text editing on macOS cannot carry the highlighting, CJK input handling or large-note performance, and a TextKit 2 rewrite is out of scope. The SwiftUI shell lives in `Shell/` inside the same MiaoYan target and opens instead of the storyboard window only when the app is launched with `-MiaoYanShell YES` (add it to the Xcode scheme's arguments), so the AppKit app stays shippable until the new one reaches parity. Same target rather than a second one keeps the bundle id, preferences, sandbox bookmarks, entitlements, resources and the localized storyboard main menu shared. The shell needs macOS 14 (`@Observable`); the deployment target stays 12.0 until the switch-over release decides otherwise.
- The SwiftUI sidebar must reproduce today's opaque sidebar, not `NavigationSplitView`'s default translucent material; a glass sidebar was tried on the AppKit app and rejected by the maintainer.
- Colour (maintainer's pick, 2026-09-28): one warm paper tone through every column, `#FDFCF9` light and `#1E1D1B` dark, columns split by a 7% hairline only; selection is Kami's warm sand (`#E8E6DC` sidebar, `#EFEDE4` list, white 8% / 7% in dark); MiaoYan green stays for the brand row and active buttons. A grey sidebar against a white body and grey selection were both rejected. A dark graphite sidebar (Bear's) was tried and rejected as too loud and too derivative. The editor's highlight colours are Kaku's palette so MiaoYan, Kaku and Mole read as one family: `title` purple `#5E3DB3`, `html` (bold, inline code) gold `#9A7400`, `link` and `highlight` teal `#24837B`, `list` and markup muted `#7A7872`, body text `#403E3C` (`Theme.editorTextColor` / `editorMarkupColor`), dark values from Kaku's dark theme. Shell text uses Kami's solid warm greys, titles at weight 500, selection by sand fill alone and list rows parted by space, not lines. The sidebar's brand row stands for all notes but never takes the selection plate (a plate on the logo read as odd): it is green while all notes are shown and grey while a folder is open. The tone lives in `Shell/ShellPalette.swift`, the `mainBackground` and `selectionBackground` assets, `Theme.previewDarkBackgroundColor`, the `--bg-color` / `--code-bg` / `--diagram-bg` / `--border-color` values in `DownView.bundle` (`theme-light.css`, `theme-dark.css`, `base.css`, `index.html`) and `HtmlManager.darkModeExportCSS`; change them together or split mode shows two whites. Light export stays white on purpose.
- The shell's columns are an AppKit `NSSplitViewController` (`ShellSplitViewController`) with plain `NSSplitViewItem`s hosting SwiftUI panes. `NavigationSplitView` brings the translucent sidebar material plus a window toolbar that `.toolbar(removing:)` and `.toolbar(.hidden, for: .windowToolbar)` did not remove, and `HSplitView` ignores ideal widths and cannot autosave dividers. Each pane's `NSHostingController` needs `sizingOptions = []`, and the window's content size must be set again after assigning the controller, or the window collapses to its minimum size.
- Any editor or preview code that reaches `AppContext.shared.viewController` or `ViewController` does nothing in the shell, where there is none. `MPreviewView.load` falls back to the note's own title. The shell's editor is an `EditTextView` created in code by `ShellEditorController` with `isShellHosted = true`: `fill()` then runs without a `ViewController`, the editor always behaves as the plain edit view (preview and split live in the shell's own panes), and `ShellEditorController.textDidChange` repeats the storyboard window's owner guard before saving (#543). Keep new `EditTextView` changes working with the flag both ways.
- Menu commands: the storyboard menu targets stand-in `ViewController` and `EditTextView` objects in the Application scene that forward to `ViewController.shared()`, which is nil in the shell. `ShellWindowController.retargetMainMenu()` points those items at the first responder when the shell opens; the real editor then takes formatting commands, `EditTextView.responds(to:)` declines the mode commands (`togglePreview:`, `togglePresentation:`, `toggleTOC:`, `formatText:`, `cleanTypography:`) while shell-hosted, and `ShellWindowController` implements them plus new note, delete, rename, pin, reveal, sort and search. A command no one answers stays disabled, which is the parity to-do list. Disk changes reach either window through `FileSystemEventHost` (`Helpers/FileSystemEventManager.swift`), including the edit-time pause and conflict backups; renaming by title goes through `Note.renameFile(to:)` in both.
- Parity paths that differ from the storyboard window: `miaoyan://` and `nv://` routes (wikilink clicks, goto, find, new/make) go to `ShellModel` when the shell is open, and ones that arrive before the window are replayed after it opens. Single-file mode is left in place with `Storage.reconfigureForLibrary()` rather than a relaunch, which would drop `-MiaoYanShell`; the storyboard window's own Command-Shift-W handler still relaunches, so tests that exercise single mode in the test host must hide the default from it. Import adds each copy to storage itself, because an APFS clone reaches the file watcher as a change event, never a creation. PPT PDF export sets `UserDefaultsManagement.isOnExportPPT` before the deck renders; `ppt.html` only switches Reveal to print layout at render time, and without it the PDF is one blank page. Backlinks in the shell come from every note, with unloaded bodies read from disk, not from the listed notes as in the storyboard window. Subfolders come from `Storage.subfolders(of:)` in both sidebars.
- The shell's title bar is an empty unified `NSToolbar`, which centres the traffic lights in a 52pt band (`ShellStyle.headerHeight`); each column draws its own controls on that line, and clicks there reach the SwiftUI panes (checked by hit-testing), not the toolbar. Mode buttons persist to `UserDefaultsManagement.preview` / `splitViewMode`, the same keys the storyboard window restores from. Shell code refers to `SwiftUI.Color`, `SwiftUI.Font` and `SwiftUI.Image` by full name because the app target declares module-wide `Color`, `Font` and `Image` typealiases for the AppKit types.
- Preserve recoverability for delete flows. Notes and attachments should move through the app Trash or system Trash path that matches the current context, not disappear through direct deletion.
- The app Trash may resolve to the same directory as the volume's system Trash. Calling `FileManager.trashItem` on an item already there renames it in place and makes it reappear. Mark it with `AppIdentifier.removedFromTrashKey` and exclude that marker only inside Trash projects, so Finder recovery into a normal project remains visible.
- Treat iCloud sync and symlinked directories as file-system-sensitive surfaces; resolve paths deliberately and avoid loops or duplicate indexing.

## Investigation Order

When scope is incomplete, start with:

1. `ARCHITECTURE.md` for the real top-level dependency map
2. `Controllers/AppDelegate.swift`
3. `Controllers/MainWindowController.swift`
4. `Controllers/ViewController.swift`
5. Narrow related files under `Helpers/`, `Views/`, `Business/`, or `Extensions/`
6. Relevant Xcode project settings only when build, signing, target membership, or version behavior is involved

Avoid broad scans of `build/`, `.build/`, `dist/`, and bundled web assets unless the task targets them.

## Current Risk Areas

- Editor buffer ownership (#543): in preview/presentation/PPT modes `EditTextView.note` follows the list selection while `textStorage` keeps the last edited note, so the two legitimately diverge. `EditTextView.storageNote` records which note the buffer belongs to; every wholesale storage assignment must go through `publishStorage(_:owner:)`, and every whole-buffer persist through `saveTextStorageContent(to:)`, which refuses cross-note targets. Never persist the buffer based on `EditTextView.note` or the table selection alone, and never compare `EditTextView.note` against itself as a guard (that tautology is how the V4.0.0 content-swap shipped).
- Sidebar horizontal layout is owned by `SidebarProjectView.tile()`: after reloads and resizes, the outline frame and first column must match the clip-view width and the clip-view horizontal origin must stay at zero. Do not replace this invariant with event-specific width resets.
- Wikilinks and backlinks depend on `Business/WikilinkIndex.swift`, note loading, search, and sidebar refresh behavior. Keep `[[note]]` parsing, recursive search, and Trash exclusions consistent.
- iCloud sync lives in macOS storage and `Business/CloudSyncManager.swift`. Verify fallback behavior when iCloud is unavailable.
- Trash handling spans `Business/Storage.swift`, `Business/Note.swift`, sidebar drag/drop, attachment cleanup, and system Trash fallback.
- A successfully removed note must retire its `Note` instance before any watcher, editor, lifecycle flush, or upload callback can save it again. Existing-note writes must fail closed if the file disappears, and UI rows may be removed only for filesystem operations that succeeded.
- Note bodies load only when a note is opened (and for Trash), so `note.content` is empty for most notes. Anything deciding whether a note refers to something reads unloaded bodies from disk: Clean Unused Attachments trashed every image of an unopened note until `Storage.findOrphanAttachments` did, and it now returns nil, cleaning nothing, when any note cannot be read.
- Version history lives in `Business/NoteVersionManager.swift` and `Controllers/VersionHistoryViewController.swift`; keep file IO off the main thread and UI updates on the main thread.
- PNG export must prepare the current DOM, inject export styles and wait for media on every invocation. Cleanup removes those styles, so cached note content never proves a subsequent export is ready.
- Mermaid and PDF export span `Business/HtmlManager.swift`, `Helpers/PdfExportController.swift`, and `Extensions/MPreviewView+Export.swift`. Wait for images and Mermaid rendering before capture.
- Note-list search (`ViewController+Data.swift`) filters by folder scope first, then hands plain `NoteSearchCandidate` values to `NoteContentMatcher` in a detached task, which reads unloaded bodies from disk; the main thread only snapshots and applies results. Never load or lowercase note bodies on the main thread for search, and match titles without the `.md` extension.
- Async note/image/file loading is intentional. Do not reintroduce blocking reads on the main thread for large notes or previews.
- Directory symlinks are supported by storage scanning. Avoid recursion loops and duplicate notes when following symlinked directories.
- Note attachments follow the shared `i/` convention: images live in an `i/` folder next to the note, referenced as `![](/i/<name>)`; the iPhone app in MiaoYan-Pro reads the same convention, so keep it stable.
- Image upload posts to a local PicGo/PicList HTTP endpoint at `127.0.0.1:36677` (`Helpers/ClipboardManager.swift`). The macOS `Info.plist` ATS permits this via `NSAllowsLocalNetworking`; do not widen it back to `NSAllowsArbitraryLoads`. The markdown preview loads through `loadFileURL` (file://), not a local web server, so ATS does not gate preview rendering.
- `renderMarkdownHTML` in `Business/Markdown.swift` is the single markdown-to-HTML funnel for preview, split view, export, PPT, and actions. Post-render transforms (the GitHub Alerts callout rewrite lives there) belong at the end of that function, never in individual call sites. Alert styling lives in `DownView.bundle/css/typography.css` with dark overrides in `theme-dark.css` (the `.darkmode *` color rule forces explicit dark restatements).
- Frontmatter stripping is a per-surface invariant, not a two-file rule: every surface that outputs note or markdown content (macOS preview/export, appcast/release-notes rendering, any future export) must strip leading YAML frontmatter, and a new rendering surface adds its stripping in the same commit (`---date/image---` has leaked verbatim through the appcast body). `Note.cleanMetaData` calls `Frontmatter.body(of:)` in `Packages/MiaoYanCore`, which the iPhone app uses too, so a rule change is one edit plus `swift test --package-path Packages/MiaoYanCore`. CRLF gotcha: `"\r\n"` is one Swift grapheme, so `range(of: "\n---")` never matches inside it; search both `"\n---"` and `"\r\n---"`.
- `Helpers/TypographyCleaner.swift` (Edit → Clean Typography) must never rewrite protected regions: fenced/inline code, math, link targets, wikilinks, bare URLs, frontmatter. Extend the segment parser, don't bypass it. `Helpers/HtmlToMarkdown.swift` converts pasted HTML only when block-structure tags are present, so plain-text paste stays authoritative for code copied from editors; keep that gate.
- New macOS menu items need the storyboard entry plus an ObjectID-keyed `.title` line in all four `Main.strings` (es/ja/zh-Hans/zh-Hant); new toasts need the English text as key in all four `Localizable.strings` (Base has no Localizable.strings, English falls back to the key itself). Missing a file silently ships English to that locale.

## Release Channels

This repository ships the direct-download app: GitHub Release assets plus an appcast entry, updated in place by Sparkle from `https://miaoyan.app/appcast.xml`, and picked up by Homebrew. Build with `scripts/build.sh` (Developer ID, notarization, Sparkle). The App Store Mac and iPhone builds come from the private `tw93/MiaoYan-Pro`, which merges this repository's `main` first, so App Store users never see this channel's appcast. miaoyan.app recommends the App Store and links only to the App Store and this repository, never to a Mac download (maintainer, 2026-10-11); the release assets stay for Sparkle and Homebrew users.

- `appcast.xml` lives on the miaoyan.app site, not in this repository. `scripts/release-ci/update_appcast.sh` produces the entry and `scripts/build.sh` prints the enclosure line. The enclosure URL printed by `scripts/build.sh` defaults to `miaoyan.app/Release/`; new entries must instead point to the published GitHub release asset. Historical entries retain their original URLs.
- Both install paths fetch release assets, never the tag tarball: homebrew-cask's `url` is `releases/download/V4.3.0/MiaoYan_V4.3.0.zip` and the appcast enclosure is the same shape. Nothing pins a hash of `archive/refs/tags/*.tar.gz`, so a tag that has no release yet can be deleted and recut without breaking a consumer. Deleting a tag that does have a release breaks `brew install --cask miaoyan` immediately, because the cask names that asset.

## Fonts And Preview Rendering

- Font menus refresh when opened because the preferences controller is reused. Cache classification by the installed family set, not its count, and preserve the selected stored family when rebuilding a menu.
- The default editor, preview and interface face is the system pairing (maintainer, 2026-10-11, after comparing it with TsangerJinKai02, Hiragino Sans GB, New York with Songti and Charter with Kaiti): SF for Latin and the system's CJK face for the user's languages, PingFang for Chinese and Hiragino for a Japanese-first user. It is stored as `FontConfiguration.fallbackFont` (`PingFangSC-Regular`); `FontConfiguration.textFont(named:size:)` turns that value, PingFang picked from the popup, or a face that is not installed into `NSFont.systemFont`, whose hidden family still resolves through `NSFontManager`, so the editor's family-based bold and italic keep working, and the preview gets the same pairing from `FontCatalog.fontStack`. TsangerJinKai02 (`TsangerJinKai02-W04`) was the default before that; it is not bundled because redistribution needs a licence from Tsanger (personal non-commercial use is free), installs from that time still store it, and it stays a recommended face with a not-installed row. A stored font choice is never rewritten, not by a migration and not because the face is missing at read time; `ViewController` watches `NSFont.fontSetChangedNotification` and applies a chosen face the moment it appears. The download button opens the foundry's direct `.ttf` URL (`FontCatalog.retiredBundledDownloadURL`); MiaoYan never hosts the file.
- Tracking is one figure, `UserDefaultsManagement.letterSpacingEm` (0.02em), shared by the editor kern, interface labels (scaled by each label's point size) and `.heti` in typography.css. The earlier fixed 0.5pt/0.6pt and 0.04em were tuned in 2022 for LXGW WenKai and spread PingFang and all Latin apart; change the three together.
- Font preferences hold two different spellings. The defaults and fallback in `Business/FontConfiguration.swift` are PostScript names (`PingFangSC-Regular`, and `TsangerJinKai02-W04` in older installs), while every value the font popups write is a family name (`PingFang SC`), because the popups are built from `availableFontFamilies`. Anything comparing a stored value against a default, or matching it to a popup row, has to resolve both sides through `FontCatalog.familyName(forStored:)` first. Comparing the raw strings made the preview's Latin ordering unreachable the moment the user opened the popup, with both states rendering the same selected row.
- `FontCatalog.fontStack(forStored:)` decides who sets Latin, and the test is whether the user picked the face, not whether it is a CJK face. PingFang, the default, has Latin drawn for interface labels and yields it to `ui-sans-serif, system-ui, -apple-system`; a face someone chose leads its own stack and sets the whole line, because TsangerJinKai02 and its like draw Latin to match their Chinese.
- A CSS property's minimum version has to clear `MACOSX_DEPLOYMENT_TARGET`, currently 12.0. When declarations have different minimum versions, retain a supported fallback and verify the absent-variable behavior on both engines.
- The preview keeps the chosen face for bold. Swapping TsangerJinKai02 W05 in for headings and strong text (V4.3.1) made them visibly lighter than the W04 synthetic bold people were used to, and the maintainer asked for W04 back; do not reintroduce a heavier-face substitution. Body text uses `-webkit-font-smoothing: subpixel-antialiased`; `antialiased` on `html` thinned every paragraph in the same release.
- The code font reaches fenced code blocks only (`pre code`, and not inside `blockquote`). Inline code and quoted code inherit the surrounding text face. The stored default is `FontConfiguration.followTextFont`, which means the editor font in the editor and the preview stack in the preview; check `UserDefaultsManagement.codeFollowsText` before treating `codeFontName` as a face. Raw HTML tags in the editor go through `CodeBlockHighlighter.highlightInlineHTML`, never `highlightCode`, which would give them the code font and the `.codeBlock` mark: it sets each `<…>` in `NotesTextProcessor.htmlTagFont` (system face, two points down) and the markup colour and leaves text between tags as prose. Markdown's own punctuation (`#`, `**`, `>`, list markers, link and image brackets, autolink `< >`) takes `NotesTextProcessor.markupFont` (system face, one point down) through `markSyntax` in `MarkdownRuleHighlighter`, because TsangerJinKai draws `<`, `>`, `*` and `"` wide and heavy (maintainer's pick, 2026-09-28). Chinese punctuation stays in TsangerJinKai's own half-width marks; the maintainer prefers them.
- `ppt.html` loads reveal's stylesheets, not `base.css` or `typography.css`, so none of the `--text-font*` variables reach it. `--r-main-font` is the only one reveal reads. A preview font change is not done until the PPT branch of `previewStyle()` has been checked too.

## Release Notes

- Tag format is uppercase `Vx.y.z`.
- One release per batch. Shipping cadence here is roughly monthly (V4.0.0 to V4.1.0 to V4.2.0 were 29 and 28 days apart); once a version is out, further work waits for the next one. Only a regression that version introduced, or a fix users cannot otherwise obtain, justifies a follow-up tag. V4.3.0 and V4.3.1 went out 1.4 hours apart because a batch of font work landed right after a release and was tagged on the spot instead of being held, which prompted every Sparkle user to update twice in one afternoon.
- Version changes must keep both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `MiaoYan.xcodeproj/project.pbxproj` aligned with the release tag. Sparkle compares `sparkle:version` in appcast.xml against `CFBundleVersion` (mapped from `CURRENT_PROJECT_VERSION`), not `CFBundleShortVersionString`. If the two diverge, users get an infinite update prompt loop (V3.5.1 incident, #524).
- `.github/RELEASE_NOTES.md` is the public release note source: a `# V{x.y.z} {Codename} {emoji}` heading, a Chinese numbered list, a `---` separator, then an English numbered list mapped one-to-one. `scripts/release-ci/render_release_body.sh` renders it into the GitHub release body and appcast content; codenames follow the list in `scripts/release-ci/generate_release_content.sh`.
- Release titles follow `V{x.y.z} {Codename} {emoji}` (e.g. `V4.0.0 Valstrax 🚀`). Before drafting notes, `gh release view` the previous release and mirror its exact body shape instead of rebuilding it from memory.
- Publishing ends with the six positive reactions (`+1`, `laugh`, `heart`, `hooray`, `rocket`, `eyes`) added via `gh api` and read back to confirm. Never add `-1` or `confused`.
- Direct-download Sparkle signing must use the MiaoYan release key, not the default Sparkle Keychain account. Before pushing appcast changes, verify the signature against the published ZIP and the app's embedded `SUPublicEDKey` with `scripts/release-ci/verify_sparkle_signature.sh`; a signature-only appcast fix is valid only when ZIP bytes and length are unchanged. The DMG, ZIP, and Sparkle metadata carry the same version, and the ZIP the appcast points at is the exact file that was signed, never a re-zipped copy.
- Direct-download release builds use repository scripts; no tracked workflow packages a release.
- Release automation depends on maintainer-managed signing, notarization, and Sparkle credentials. Do not document or commit local credential paths, private key filenames, or secret values.

## Verification

- Swift changes: run the Debug `xcodebuild` command above.
- UI or interaction fixes: launch the built app and exercise the changed flow before reporting done; a green build is not visual proof. If the first fix attempt does not hold, stop guessing and add `#if DEBUG` runtime logging to capture evidence before the next code change.
- Lint or formatting changes: run SwiftLint and swift-format checks.
- Release or signing changes: verify version alignment and inspect the relevant repository script; do not assume a tracked `release.yml` exists.
- Release note changes: inspect `.github/RELEASE_NOTES.md` and the affected `scripts/release-ci/` renderer.
- Export changes: verify Mermaid, images, PDF pagination, and async readiness behavior together.
- Documentation-only changes: check links and command accuracy.
