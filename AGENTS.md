# MiaoYan Agent Guide

> `CLAUDE.md` is a symlink to this file. Claude Code and Codex (and any other
> agent reading `AGENTS.md`) share this single source so the guide stays
> in sync.
>
> Claude-specific assets:
> - 全局规则: `~/.claude/CLAUDE.md`
> - Swift 通用规则: `~/.claude/rules/swift.md` (项目级补充 `.claude/rules/swift.md`)
> - 发版 runbook: `.claude/skills/release` (`/release`)
> - Lint: `.claude/skills/lint`
> - App Store 流程: `.claude/skills/appstore`

## Project

MiaoYan is a lightweight Markdown editor built with Swift. The main app is macOS/AppKit, and the repository also contains an iOS target under `MiaoYanMobile/`.

## Tech Stack

- **Markdown rendering**: `swift-cmark-gfm` parses GitHub Flavored Markdown.
- **Syntax highlight**: `Highlightr`.
- **Math / diagrams**: LaTeX formulas, Mermaid, PlantUML supported via the preview renderer.
- **Slide mode**: based on Reveal.js. `---` separators delimit slides.
- **Note storage**: filesystem-backed with folder nesting, file-system watch, auto-save, and version history.
- **Editor**: live preview, syntax highlight, keyboard shortcuts, Prettier-integrated auto-format.
- **iOS target**: SwiftUI under `MiaoYanMobile/`, sharing core models in `Business/` with the macOS app.

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
- `.github/RELEASE_NOTES.md` - public release note source for GitHub release and appcast body generation.
- `.github/workflows/` - sponsor asset maintenance workflows; release builds are not currently driven by a tracked release workflow.

## Commands

```bash
xcodebuild -project MiaoYan.xcodeproj -scheme MiaoYan -configuration Debug build
xcodebuild clean
xcodebuild test -project MiaoYan.xcodeproj -scheme MiaoYan -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
swiftlint lint --strict
swift-format lint --recursive .
bash scripts/build.sh
bash scripts/build-appstore.sh
ruby scripts/add_tests_target.rb     # only when re-wiring MiaoYanTests after pbxproj reset
ruby scripts/wire_helper_files.rb    # only when re-wiring orphan Diagnostics/UIDelay/AppEnvironment
```

Use the narrowest relevant command first. Full app builds are the default verification for Swift or project changes.

## Testing

Unit tests live under `MiaoYanTests/`. Coverage targets pure-logic surfaces
(`ImageLinkParser`, `WikilinkIndex.updateNote`, `String+`, etc.). UI flows are
verified by manual smoke after build, not by XCUITest.

Add a new test:

1. Create `MiaoYanTests/<Subject>Tests.swift` (XCTest, `@MainActor` if it
   touches a `@MainActor`-isolated singleton).
2. If `MiaoYanTests` target is already in the project, drag the file into the
   target in Xcode. Otherwise run `ruby scripts/add_tests_target.rb` which
   picks up every `MiaoYanTests/*.swift` it sees.
3. Run `xcodebuild test ...` locally, then push.

`CODE_SIGNING_ALLOWED=NO` is required on the local test command because
the dev signing identity used for `MiaoYan.app` and the per-developer
identity used for `MiaoYanTests.xctest` end up with different Team IDs,
which makes dyld refuse to load the test bundle into the host app. CI
uses a clean runner where signing is consistent, so `ci.yml` does not
pass this flag.

## CI

`.github/workflows/ci.yml` runs on every PR and push to `main`:

- macOS Debug build (no signing required)
- iOS Debug build for `MiaoYanMobile`
- SwiftLint (`--strict`) + swift-format lint
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
- **Markdown 预览里图片 / 视频 / iframe / 表格必须 `max-width: 100%`**, 禁止横向滚动。任何引入 raw HTML 渲染的改动都要复查这一条。
- **设计参考**: UI / CSS 抄不出来时去看 `~/www/weekly` 和 `~/www/tw93.github.io`, 那里有维护者已经满意的样式。不要凭空发挥。
- **目标视觉风格**: macOS 26 风格的 sidebar (玻璃态、透明、SF Symbols 最新一代) 是长期方向, 不是经典 Big Sur 风格。
- **不要再提议整套 macOS 26 / Liquid Glass 重设计**。一次实机改造 (侧栏换原生 `.sidebar` 半透明材质 + 选中态改强调色玻璃 pill + 图标整体迁 SF Symbols + 自绘 pill `ChromeToolbarButton`) 已被维护者否决, 原话"还不如之前好看, 不强求这个"。要打磨侧栏 / 按钮就在现有不透明设计上做小步增量: 间距、对齐、hover、focus、字重。不要整体换材质或换图标体系, 除非维护者在当前回合明确要求。
- **`cmd+3` 是专注模式核心快捷键**, 不要冲突。新增任何 cmd-数字快捷键前先 grep 现有 keyBindings。打字机滚动 / 链接相关另开模式或子开关即可。

## Working Rules

- Follow existing Swift and AppKit patterns.
- Keep UI updates on the main thread.
- Avoid force unwraps unless the invariant is obvious and local.
- Prefer `AppEnvironment.current.<service>` over direct singleton access in
  new code. The SwiftLint `no_direct_singleton_in_new_code` rule warns on the
  raw form. Existing call sites are grandfathered.
- Keep file writes scoped to user documents or app-controlled locations.
- Do not add network calls, shell execution, or broad file access without clear user need.
- Keep AppKit patterns in the macOS app and SwiftUI patterns in `MiaoYanMobile/`; do not mix frameworks across targets without a clear task reason.
- Preserve recoverability for delete flows. Notes and attachments should move through the app Trash or system Trash path that matches the current context, not disappear through direct deletion.
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

- Wikilinks and backlinks depend on `Business/WikilinkIndex.swift`, note loading, search, and sidebar refresh behavior. Keep `[[note]]` parsing, recursive search, and Trash exclusions consistent.
- iCloud sync spans macOS storage, `Business/CloudSyncManager.swift`, and `MiaoYanMobile/Services/CloudSyncManager.swift`. Verify fallback behavior when iCloud is unavailable.
- `MiaoYanMobile/` is a real iOS target, not sample code. Keep SwiftUI, file reading, mobile rendering, and target membership aligned.
- Trash handling spans `Business/Storage.swift`, `Business/Note.swift`, sidebar drag/drop, attachment cleanup, and system Trash fallback.
- Version history lives in `Business/NoteVersionManager.swift` and `Controllers/VersionHistoryViewController.swift`; keep file IO off the main thread and UI updates on the main thread.
- Mermaid and PDF export span `Business/HtmlManager.swift`, `Helpers/PdfExportController.swift`, and `Extensions/MPreviewView+Export.swift`. Wait for images and Mermaid rendering before capture.
- Async note/image/file loading is intentional. Do not reintroduce blocking reads on the main thread for large notes or previews.
- Directory symlinks are supported by storage scanning. Avoid recursion loops and duplicate notes when following symlinked directories.
- Image upload posts to a local PicGo/PicList HTTP endpoint at `127.0.0.1:36677` (`Helpers/ClipboardManager.swift`). The macOS `Info.plist` ATS permits this via `NSAllowsLocalNetworking`; do not widen it back to `NSAllowsArbitraryLoads`. The markdown preview loads through `loadFileURL` (file://), not a local web server, so ATS does not gate preview rendering.
- iOS user-facing strings live in `MiaoYanMobile/Resources/Localizable.xcstrings` and ship `en` + `zh-Hans` only (the macOS app ships five languages). Add a `zh-Hans` value for every new iOS string, or Chinese users fall back to English.

## Release Notes

- Tag format is uppercase `Vx.y.z`.
- Version changes must keep both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `MiaoYan.xcodeproj/project.pbxproj` aligned with the release tag. Sparkle compares `sparkle:version` in appcast.xml against `CFBundleVersion` (mapped from `CURRENT_PROJECT_VERSION`), not `CFBundleShortVersionString`. If the two diverge, users get an infinite update prompt loop (V3.5.1 incident, #524).
- `.github/RELEASE_NOTES.md` is the public release note source. Release scripts under `scripts/release-ci/` render it for GitHub release and appcast content, including the current sectionless format.
- Direct-download Sparkle signing must use the MiaoYan release key, not the default Sparkle Keychain account. Before pushing appcast changes, verify the signature against the published ZIP and the app's embedded `SUPublicEDKey` with `scripts/release-ci/verify_sparkle_signature.sh`; a signature-only appcast fix is valid only when ZIP bytes and length are unchanged.
- Direct-download release builds use repository scripts. The tracked GitHub workflows currently maintain sponsor assets, not release packaging.
- Release automation depends on maintainer-managed signing, notarization, and Sparkle credentials. Do not document or commit local credential paths, private key filenames, or secret values.

## Verification

- Swift changes: run the Debug `xcodebuild` command above.
- Lint or formatting changes: run SwiftLint and swift-format checks.
- iOS changes: inspect `MiaoYanMobile/` target membership and run the narrowest relevant Xcode build or project check available.
- Release or signing changes: verify version alignment and inspect the relevant repository script; do not assume a tracked `release.yml` exists.
- Release note changes: inspect `.github/RELEASE_NOTES.md` and the affected `scripts/release-ci/` renderer.
- Export changes: verify Mermaid, images, PDF pagination, and async readiness behavior together.
- Documentation-only changes: check links and command accuracy.
