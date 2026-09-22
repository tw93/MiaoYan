# MiaoYan Agent Guide

> `CLAUDE.md` is a symlink to this file. Claude Code and Codex (and any other
> agent reading `AGENTS.md`) share this single source so the guide stays
> in sync.
>
> Claude-specific assets:
> - 全局规则: `~/.claude/CLAUDE.md`
> - Swift 通用规则: `~/.claude/rules/swift.md` (项目级补充 `.claude/rules/swift.md`)
> - 项目 skills 的 tracked canonical source: `.agents/skills/` - `release`, `appstore`, `lint`, `code-review`, `github-ops`
> - `.claude/skills/` 是 gitignored 的本机兼容镜像，可使用指向对应 canonical 目录的软链或文件拷贝；只编辑 `.agents/skills/`，再运行 `bash scripts/sync-agent-skills.sh --write` 和 `--check`

## Project

MiaoYan is a lightweight Markdown editor built with Swift. The main app is macOS/AppKit, and the repository also contains an iOS target under `MiaoYanMobile/`.

## Tech Stack

- **Markdown rendering**: `swift-cmark-gfm` parses GitHub Flavored Markdown.
- **Syntax highlight**: `Highlightr`.
- **Math / diagrams**: LaTeX formulas, Mermaid, PlantUML supported via the preview renderer.
- **Slide mode**: based on Reveal.js. `---` separators delimit slides.
- **Note storage**: filesystem-backed with folder nesting, file-system watch, auto-save, and version history.
- **Editor**: live preview, syntax highlight, keyboard shortcuts, Prettier-integrated auto-format.
- **iOS target**: SwiftUI under `MiaoYanMobile/`, using its own models and services; both apps share filesystem conventions.

## Repository Map

- `Controllers/` - view controllers and window controllers.
- `Views/` - UI components.
- `Business/` - models and business logic.
- `Helpers/` - utilities and services.
- `Extensions/` - Swift extensions.
- `Resources/` - bundled resources.
- `MiaoYanMobile/` - iOS app target, SwiftUI views, mobile services, and mobile resources.
- `MiaoYan.xcodeproj/` - Xcode project and version settings.
- `Package.swift` - Swift package dependency declarations and supported platforms.
- `scripts/` - local build, App Store, release, and project maintenance scripts.
- `scripts/release-ci/` - release note rendering, appcast, notarization, and package helpers.
- `skills/miaoyan/` - published Agent Skill (tracked) describing MiaoYan's Markdown, PPT, and `miao` CLI surfaces to outside agents; it restates product syntax, so it drifts when those surfaces change.
- `.github/RELEASE_NOTES.md` - public release note source for GitHub release and appcast body generation.
- `.github/workflows/` - holds `ci.yml` only; release builds are not driven by a tracked release workflow.

## Commands

```bash
xcodebuild -project MiaoYan.xcodeproj -scheme MiaoYan -configuration Debug build
xcodebuild clean
xcodebuild test -project MiaoYan.xcodeproj -scheme MiaoYan -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild -project MiaoYan.xcodeproj -scheme MiaoYanMobile -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
swiftlint lint --strict
swift-format lint --recursive . --strict   # --strict is what CI runs; without it a local pass can still fail CI
bash scripts/sync-agent-skills.sh --check  # compare the gitignored local Claude mirror; use --write first if absent
bash scripts/build.sh
bash scripts/build-appstore.sh
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

- macOS Debug build, then `xcodebuild test` for the unit suite (no signing required)
- iOS Debug build for `MiaoYanMobile`. This job pins `runs-on: macos-26` while
  every other job is `macos-15`; if that runner is unavailable, wait for it
  rather than downgrading the iOS code
- SwiftLint and swift-format, both `--strict`, so any warning is a merge gate
- Release-notes rendering smoke (`scripts/release-ci/notes_to_html.sh` and
  `render_release_body.sh`) so a broken `.github/RELEASE_NOTES.md` is caught
  before release time, not during it
- On tag pushes (`V*`): version-triplet consistency check
  (`MARKETING_VERSION == CURRENT_PROJECT_VERSION == tag`) to prevent the
  V3.5.1 / #524 incident recurrence

CI does NOT run the App Store packaging or notarization scripts; those need
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
- Keep the macOS editor core, preview pipeline, and existing storyboard scenes on AppKit. A new self-contained panel may host SwiftUI through `NSHostingView`; that is not licence to push SwiftUI into `EditTextView` / `MPreviewView` / `ViewController`. `MiaoYanMobile/` is SwiftUI throughout, and UI layers are not shared across the two targets.
- Preserve recoverability for delete flows. Notes and attachments should move through the app Trash or system Trash path that matches the current context, not disappear through direct deletion.
- The app Trash may resolve to the same directory as the volume's system Trash. Calling `FileManager.trashItem` on an item already there renames it in place and makes it reappear. Mark it with `AppIdentifier.removedFromTrashKey` and exclude that marker only inside Trash projects, so Finder recovery into a normal project remains visible.
- Treat iCloud sync and symlinked directories as file-system-sensitive surfaces; resolve paths deliberately and avoid loops or duplicate indexing.

## Investigation Order

When scope is incomplete, start with:

1. `ARCHITECTURE.md` for the real top-level dependency map
2. `Controllers/AppDelegate.swift`
3. `Controllers/MainWindowController.swift`
4. `Controllers/ViewController.swift`
5. `MiaoYanMobile/` when the task touches iOS, sync, mobile reading, or mobile editing behavior
6. Narrow related files under `Helpers/`, `Views/`, `Business/`, or `Extensions/`
7. Relevant Xcode project settings only when build, signing, target membership, or version behavior is involved

Avoid broad scans of `build/`, `.build/`, `dist/`, and bundled web assets unless the task targets them.

## Current Risk Areas

- Editor buffer ownership (#543): in preview/presentation/PPT modes `EditTextView.note` follows the list selection while `textStorage` keeps the last edited note, so the two legitimately diverge. `EditTextView.storageNote` records which note the buffer belongs to; every wholesale storage assignment must go through `publishStorage(_:owner:)`, and every whole-buffer persist through `saveTextStorageContent(to:)`, which refuses cross-note targets. Never persist the buffer based on `EditTextView.note` or the table selection alone, and never compare `EditTextView.note` against itself as a guard (that tautology is how the V4.0.0 content-swap shipped).
- Sidebar horizontal layout is owned by `SidebarProjectView.tile()`: after reloads and resizes, the outline frame and first column must match the clip-view width and the clip-view horizontal origin must stay at zero. Do not replace this invariant with event-specific width resets.
- Wikilinks and backlinks depend on `Business/WikilinkIndex.swift`, note loading, search, and sidebar refresh behavior. Keep `[[note]]` parsing, recursive search, and Trash exclusions consistent.
- iCloud sync spans macOS storage, `Business/CloudSyncManager.swift`, and `MiaoYanMobile/Services/CloudSyncManager.swift`. Verify fallback behavior when iCloud is unavailable.
- `MiaoYanMobile/` is a real iOS target, not sample code. Keep SwiftUI, file reading, mobile rendering, and target membership aligned.
- Trash handling spans `Business/Storage.swift`, `Business/Note.swift`, sidebar drag/drop, attachment cleanup, and system Trash fallback.
- A successfully removed note must retire its `Note` instance before any watcher, editor, lifecycle flush, or upload callback can save it again. Existing-note writes must fail closed if the file disappears, and UI rows may be removed only for filesystem operations that succeeded.
- Version history lives in `Business/NoteVersionManager.swift` and `Controllers/VersionHistoryViewController.swift`; keep file IO off the main thread and UI updates on the main thread.
- PNG export must prepare the current DOM, inject export styles and wait for media on every invocation. Cleanup removes those styles, so cached note content never proves a subsequent export is ready.
- Mermaid and PDF export span `Business/HtmlManager.swift`, `Helpers/PdfExportController.swift`, and `Extensions/MPreviewView+Export.swift`. Wait for images and Mermaid rendering before capture.
- Async note/image/file loading is intentional. Do not reintroduce blocking reads on the main thread for large notes or previews.
- Directory symlinks are supported by storage scanning. Avoid recursion loops and duplicate notes when following symlinked directories.
- The iOS editor is `MiaoYanMobile/Views/MarkdownEditorView.swift` + `Services/MarkdownHighlighter.swift`: plain-markdown UITextView with regex highlighting. Never mutate `textStorage` attributes while `markedTextRange != nil` (breaks CJK IME composition), and keep `lineBreakStrategy = []` (re-enabling push-out reintroduces premature CJK line wraps).
- Note attachments follow the shared `i/` convention: images live in an `i/` folder next to the note, referenced as `![](/i/<name>)` on both platforms. The iOS reader cannot load `file://` subresources (`loadHTMLString`), so `MobileHtmlRenderer` rewrites local srcs to the `miaoyan-asset://` scheme served by `LocalAssetSchemeHandler`, which only serves files under the current library root (`allowedRoot`). Keep that root restriction when touching the handler.
- Image upload posts to a local PicGo/PicList HTTP endpoint at `127.0.0.1:36677` (`Helpers/ClipboardManager.swift`). The macOS `Info.plist` ATS permits this via `NSAllowsLocalNetworking`; do not widen it back to `NSAllowsArbitraryLoads`. The markdown preview loads through `loadFileURL` (file://), not a local web server, so ATS does not gate preview rendering.
- iOS user-facing strings live in `MiaoYanMobile/Resources/Localizable.xcstrings` and ship `en` + `zh-Hans` only (the macOS app ships five languages). Add a `zh-Hans` value for every new iOS string, or Chinese users fall back to English.
- `renderMarkdownHTML` in `Business/Markdown.swift` is the single markdown-to-HTML funnel for preview, split view, export, PPT, and actions. Post-render transforms (the GitHub Alerts callout rewrite lives there) belong at the end of that function, never in individual call sites. Alert styling lives in `DownView.bundle/css/typography.css` with dark overrides in `theme-dark.css` (the `.darkmode *` color rule forces explicit dark restatements).
- Frontmatter stripping is a per-surface invariant, not a two-file rule: every surface that outputs note or markdown content (macOS preview/export, iOS preview, appcast/release-notes rendering, any future export) must strip leading YAML frontmatter, and a new rendering surface adds its stripping in the same commit (`---date/image---` has leaked verbatim through both the appcast body and the iOS preview). The copies are deliberately duplicated per platform: `Note.cleanMetaData` (macOS), `MobileHtmlRenderer.stripFrontmatter` (iOS preview) and the private `stripFrontmatter` in `MiaoYanMobile/Services/FileReader.swift` must keep identical semantics; change all three in the same commit. CRLF gotcha all copies share: `"\r\n"` is one Swift grapheme, so `range(of: "\n---")` never matches inside it; search both `"\n---"` and `"\r\n---"`.
- `Helpers/TypographyCleaner.swift` (Edit → Clean Typography) must never rewrite protected regions: fenced/inline code, math, link targets, wikilinks, bare URLs, frontmatter. Extend the segment parser, don't bypass it. `Helpers/HtmlToMarkdown.swift` converts pasted HTML only when block-structure tags are present, so plain-text paste stays authoritative for code copied from editors; keep that gate.
- New macOS menu items need the storyboard entry plus an ObjectID-keyed `.title` line in all four `Main.strings` (es/ja/zh-Hans/zh-Hant); new toasts need the English text as key in all four `Localizable.strings` (Base has no Localizable.strings, English falls back to the key itself). Missing a file silently ships English to that locale.

## Release Channels

MiaoYan ships through two independent channels. Publishing one never updates the other: one version means two separate publishes, and release readiness must be reported per channel.

| | Direct download (GitHub) | Mac App Store |
|---|---|---|
| Build | `scripts/build.sh`, Developer ID + notarization, Sparkle included | `scripts/build-appstore.sh`, App Store entitlements, no Sparkle |
| Publish surface | GitHub Release assets + appcast entry | App Store Connect submission + review |
| How users update | Sparkle in-app update via `https://miaoyan.app/appcast.xml` | App Store update after review approval |

- `appcast.xml` lives on the miaoyan.app site, not in this repository. `scripts/release-ci/update_appcast.sh` produces the entry and `scripts/build.sh` prints the enclosure line. The enclosure URL printed by `scripts/build.sh` defaults to `miaoyan.app/Release/`; new entries must instead point to the published GitHub release asset. Historical entries retain their original URLs.
- Both install paths fetch release assets, never the tag tarball: homebrew-cask's `url` is `releases/download/V4.3.0/MiaoYan_V4.3.0.zip` and the appcast enclosure is the same shape. Nothing pins a hash of `archive/refs/tags/*.tar.gz`, so a tag that has no release yet can be deleted and recut without breaking a consumer. Deleting a tag that does have a release breaks `brew install --cask miaoyan` immediately, because the cask names that asset.
- App Store users never see the appcast. After a direct-download release, the App Store version stays old until a separate submission passes review; do not report a version as "released" without naming which channel it reached.
- When an App Store build is prepared, deliver ready-to-paste submission copy with it: Promotional Text (170-char limit) and What's New, in en and zh-Hans, derived from `.github/RELEASE_NOTES.md`. Do not wait for the maintainer to ask from the Connect submission page.

## Fonts And Preview Rendering

- Font menus refresh when opened because the preferences controller is reused. Cache classification by the installed family set, not its count, and preserve the selected stored family when rebuilding a menu.
- Font preferences hold two different spellings. The shipped defaults in `Business/FontConfiguration.swift` are PostScript names (`PingFangSC-Regular`), while every value the font popups write is a family name (`PingFang SC`), because the popups are built from `availableFontFamilies`. Anything comparing a stored value against a default, or matching it to a popup row, has to resolve both sides through `FontCatalog.familyName(forStored:)` first. Comparing the raw strings made the preview's Latin ordering unreachable the moment the user opened the popup, with both states rendering the same selected row.
- `FontCatalog.fontStack(forStored:)` decides who sets Latin, and the test is whether the user picked the face, not whether it is a CJK face. PingFang's Latin is drawn for interface labels and yields to `ui-sans-serif, system-ui, -apple-system`; a face someone chose leads its own stack and sets the whole line, because TsangerJinKai02 and its like draw Latin to match their Chinese.
- A CSS property's minimum version has to clear `MACOSX_DEPLOYMENT_TARGET`, currently 12.0. Use the supported `font-synthesis` shorthand: a real heavier face disables only weight synthesis (`style`), while ordinary families keep `weight style`. Do not use `none`, which also removes synthetic italics. When declarations have different minimum versions, retain a supported fallback and verify the absent-variable behavior on both engines.
- `ppt.html` loads reveal's stylesheets, not `base.css` or `typography.css`, so none of the `--text-font*` variables reach it. `--r-main-font` is the only one reveal reads. A preview font change is not done until the PPT branch of `previewStyle()` has been checked too.

## Release Notes

- Tag format is uppercase `Vx.y.z`.
- One release per batch. Shipping cadence here is roughly monthly (V4.0.0 to V4.1.0 to V4.2.0 were 29 and 28 days apart); once a version is out, further work waits for the next one. Only a regression that version introduced, or a fix users cannot otherwise obtain, justifies a follow-up tag. V4.3.0 and V4.3.1 went out 1.4 hours apart because a batch of font work landed right after a release and was tagged on the spot instead of being held, which prompted every Sparkle user to update twice in one afternoon.
- Version changes must keep both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `MiaoYan.xcodeproj/project.pbxproj` aligned with the release tag. Sparkle compares `sparkle:version` in appcast.xml against `CFBundleVersion` (mapped from `CURRENT_PROJECT_VERSION`), not `CFBundleShortVersionString`. If the two diverge, users get an infinite update prompt loop (V3.5.1 incident, #524).
- `.github/RELEASE_NOTES.md` is the public release note source. Release scripts under `scripts/release-ci/` render it for GitHub release and appcast content, including the current sectionless format.
- Release titles follow `V{x.y.z} {Codename} {emoji}` (e.g. `V4.0.0 Valstrax 🚀`). Before drafting notes, `gh release view` the previous release and mirror its exact body shape instead of rebuilding it from memory; the full format and reaction ritual live in `.agents/skills/release/SKILL.md`.
- Publishing ends with the six positive reactions (`+1`, `laugh`, `heart`, `hooray`, `rocket`, `eyes`) added via `gh api` and read back to confirm. Never add `-1` or `confused`.
- Direct-download Sparkle signing must use the MiaoYan release key, not the default Sparkle Keychain account. Before pushing appcast changes, verify the signature against the published ZIP and the app's embedded `SUPublicEDKey` with `scripts/release-ci/verify_sparkle_signature.sh`; a signature-only appcast fix is valid only when ZIP bytes and length are unchanged.
- Direct-download release builds use repository scripts; no tracked workflow packages a release.
- Release automation depends on maintainer-managed signing, notarization, and Sparkle credentials. Do not document or commit local credential paths, private key filenames, or secret values.

## Verification

- Swift changes: run the Debug `xcodebuild` command above.
- UI or interaction fixes: launch the built app and exercise the changed flow before reporting done; a green build is not visual proof. If the first fix attempt does not hold, stop guessing and add `#if DEBUG` runtime logging to capture evidence before the next code change.
- Lint or formatting changes: run SwiftLint and swift-format checks.
- Project Skill changes: edit `.agents/skills/` only, then run `bash scripts/sync-agent-skills.sh --write` followed by `bash scripts/sync-agent-skills.sh --check`. The checker accepts links only to the corresponding canonical skill directory and compares copied files while preserving unrelated private Claude skills. For sync-script changes, run `python3 scripts/test-sync-agent-skills.py`.
- iOS changes: verification bar equals macOS. Inspect `MiaoYanMobile/` target membership, build, then run the affected flow in the Simulator (for example the new-note title flow or preview first frame) before reporting done; a green build alone is not done. Performance complaints need a measurable budget in the fix (for example: detail-page first frame past the budget shows a skeleton instead of blocking).
- Release or signing changes: verify version alignment and inspect the relevant repository script; do not assume a tracked `release.yml` exists.
- Release note changes: inspect `.github/RELEASE_NOTES.md` and the affected `scripts/release-ci/` renderer.
- Export changes: verify Mermaid, images, PDF pagination, and async readiness behavior together.
- Documentation-only changes: check links and command accuracy.
