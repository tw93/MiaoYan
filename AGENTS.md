# MiaoYan Agent Guide

> Claude Code and Codex (and any other agent reading `AGENTS.md`) share this
> single file; there is no `CLAUDE.md`.
>
> Claude-specific assets:
> - 全局规则: `~/.claude/CLAUDE.md`
> - Swift 通用规则: `~/.claude/rules/swift.md` (项目级补充 `.claude/rules/swift.md`)
> - 项目 skill: `.claude/skills/weekly-audit` (全面体检: 过时沉淀与代码、性能、功能、编辑与预览体验, 运行记录在 `docs/weekly-audit.md`); release 的事实在 `.claude/rules/release.md`，review、lint 的在本文件

## Project

MiaoYan is a lightweight Markdown editor built with Swift. This open-source repository is the only Mac codebase and is actively developed (maintainer, 2026-10-11, reversing the 2026-09-28 maintenance-only split): every Mac feature and fix lands here first. The Mac app is moving from an AppKit shell to a SwiftUI one while keeping its AppKit editor and preview. The iPhone and iPad app and the App Store packaging live in the private `tw93/MiaoYan-Pro`, which merges this repository's `main` to build the App Store Mac app; nothing is pushed from that repository to this one. The App Store purchase is the recommended way to get MiaoYan, one purchase covering iPhone, iPad and Mac; the Mac app stays free here.

## Repository Map

- `Controllers/` - view controllers and window controllers.
- `Views/` - UI components.
- `Business/` - models and business logic.
- `Helpers/` - utilities and services.
- `Extensions/` - Swift extensions.
- `Resources/` - bundled resources.
- `Shell/` - the SwiftUI main window in progress (`-MiaoYanShell YES`), see `.claude/rules/shell.md`.
- `MiaoYan.xcodeproj/` - Xcode project and version settings.
- `Package.swift` - a reference list of the Swift package dependencies; no Xcode project reads it, the real package references live in `project.pbxproj`.
- `Packages/MiaoYanCore/` - local Swift package with the logic the Mac app and the iPhone app in MiaoYan-Pro must agree on (frontmatter, search matching, note text decoding, list-row and card previews), with its own tests (`swift test --package-path Packages/MiaoYanCore`). It imports Foundation only; a change here reaches the iPhone app when Pro merges `main`, so keep its API stable.
- `scripts/` - local build, release, and project maintenance scripts.
- `scripts/release-ci/` - release note rendering, appcast, notarization, and package helpers.
- `skills/miaoyan/` - published Agent Skill (tracked) describing MiaoYan's Markdown, PPT, and `miao` CLI surfaces to outside agents; it restates product syntax, so it drifts when those surfaces change.
- `.github/RELEASE_NOTES.md` - public release note source for GitHub release and appcast body generation.
- `.github/workflows/` - holds `ci.yml` only; release builds are not driven by a tracked release workflow.
- `vercel.json` - `main` is also deployed as static files to `cdn.miaoyan.app` (Vercel project `miao-yan`, team Faberon), because exported HTML sets `<base href>` to `https://cdn.miaoyan.app/Resources/DownView.bundle/` (`HtmlManager.cdnBaseURL`); keep those paths stable. The file only adds `X-Robots-Tag: noindex`, since search engines were indexing that host's listing of this repository.

## Commands

```bash
xcodebuild -project MiaoYan.xcodeproj -scheme MiaoYan -configuration Debug build
xcodebuild clean
xcodebuild test -project MiaoYan.xcodeproj -scheme MiaoYan -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
swiftlint lint --strict
swift-format lint --recursive . --strict   # --strict is what CI runs; without it a local pass can still fail CI
swift test --package-path Packages/MiaoYanCore
python3 scripts/check_incidents.py      # docs/incidents.md rows hold
python3 scripts/risk_tier.py [path ...]  # extra gates a change needs, from its paths
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

## CI

`.github/workflows/ci.yml` runs on every PR and push to `main`:

- macOS Debug build, then `xcodebuild test` for the unit suite (no signing required), then `swift test` for `Packages/MiaoYanCore`
- SwiftLint and swift-format, both `--strict`, so any warning is a merge gate
- Release-notes rendering smoke (`scripts/release-ci/notes_to_html.sh` and
  `render_release_body.sh`) so a broken `.github/RELEASE_NOTES.md` is caught
  before release time, not during it
- The same job checks that the Chinese and English release-note lists have
  the same number of items, and runs `bash -n` plus `shellcheck -S error` on
  `scripts/*.sh`, `scripts/release-ci/*.sh` and `scripts/miaoyan`. ShellCheck
  does not flag a helper called before its definition (the install.sh `warn`
  bug), so keep script helpers at the top.
- Review gates: `scripts/check_incidents.py` on full history plus the unit
  tests of it and `scripts/risk_tier.py` (`scripts/test_review_gates.py`)
- On tag pushes (`V*`): version-triplet consistency check
  (`MARKETING_VERSION == CURRENT_PROJECT_VERSION == tag`) to prevent the
  V3.5.1 / #524 incident recurrence

CI builds with Xcode 16.3 (Swift 6.1), whose concurrency checks are stricter
than the local Xcode 27: reading a main-actor static from a nonisolated
override, sending `self` into `Task.detached`, or a test calling a helper of a
type inferred `@MainActor` (anything conforming to `WKScriptMessageHandler`)
builds locally and fails there. After every push, read the run's result with
`gh run view`; CI failed unnoticed for a whole batch in 2026-10. A test of the
1.5s save debounce must let the timer fire on its own: `flushPendingSave`
writes current content and hides a queued stale write.

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
- **设计参考**: UI / CSS 抄不出来时去看 `~/www/weekly` 和 `~/www/tw93.github.io`, 那里有维护者已经满意的样式。不要凭空发挥。
- **目标视觉风格**: macOS 26 风格的 sidebar (玻璃态、透明、SF Symbols 最新一代) 是长期方向, 不是经典 Big Sur 风格。
- **不要再提议整套 macOS 26 / Liquid Glass 重设计**。一次实机改造 (侧栏换原生 `.sidebar` 半透明材质 + 选中态改强调色玻璃 pill + 图标整体迁 SF Symbols + 自绘 pill `ChromeToolbarButton`) 已被维护者否决, 原话"还不如之前好看, 不强求这个"。要打磨侧栏 / 按钮就在现有不透明设计上做小步增量: 间距、对齐、hover、focus、字重。不要整体换材质或换图标体系, 除非维护者在当前回合明确要求。
- **App 图标保持原插画 (维护者 2026-10-14)**: 底色是家族统一的暖白 `#F3ECE2` (2026-11-11 起, 此前是近白 `#FEFEFE`, 在白色背景上整块融掉; 同时试过把红雀降饱和两成、四成和改单色剪影, 都判定不如原色, 不再试)。`Resources/app.icon` 用 `Assets/43.png` 的完整红雀插画 (太阳、红雀、树枝、叶子)。同日试过两次简化都被否: 去掉太阳和叶子后尖冠孤零零戳在底色上「太尖」, 只放回太阳后像一顶「太阳帽」。原图里右上的太阳和右下的叶子互相配平, 拆掉一半就失衡。要再动图标, 在完整插画上一次只改一个属性 (底色、比例、玻璃), 并排渲染给维护者挑, 改前先读 `~/www/Kata/rules/icon.md`。
- **设置窗口按 Mole 的排布 (维护者 2026-10-15)**: 一个固定尺寸的普通窗口 (568pt 宽, 所有标签同一高度, 内容超出就在窗口内滚动), 标题栏居中三个标签 通用 · 编辑器 · 字体, 选中用沙色底; 不要侧栏, 不要半透明材质。分区只用细线隔开, 不加标题和卡片; 每一行左边是标题, 右边是控件, 控件只有小开关、胶囊下拉框、小按钮三种, 下拉和小按钮同一个灰底、常规字重, 不用品牌绿也不加粗; 每一行标题下都有一行说明, 写清这项设置管什么或有什么后果 (重启后生效、只作用于代码块), 有的行有说明有的没有反而让人看不懂 (维护者 2026-10-23 晚, 推翻同日上午「没有说明的行标题居中」的做法)。行标题用 `Theme.Ink.primary`, 浅色是产品站同款长石灰 `#363433`, `#141413` 在纸色上太黑。需要重启的设置在行内出「重启」按钮, 不弹窗。新增设置照这个行结构加, 标题和说明在五种语言下都要一行放得下。实现在 `Controllers/*PrefsViewController.swift` 和 `Views/PrefsControls.swift`, 颜色在 `Theme.Settings`。
- **确认框 (维护者 2026-10-23)**: `MiaoYanAlert.style` 把弹窗放到纸色上: macOS 26 弹窗底下是一层 `NSGlassView` 玻璃, 透出后面窗口显得灰, `backgroundColor` 会被系统重置, 所以在内容层铺 `Theme.paper` 并按玻璃的 `cornerRadius` (26) 走连续圆角, 旧系统没有玻璃就不动; 标题改成 `Theme.Ink.primary`。图标是 `alertIcon`, 只有红雀插画本身, 直接放在纸色上: 不用带底板和阴影的 App 图标, 圆盘包裹 (照 Mole 试过纸色和沙色) 也被维护者否了, 弹窗铺了纸色后裸鸟更好看。按钮保持系统默认样式: macOS 26 的弹窗按钮不接受 `bezelColor`, 系统的 `hasDestructiveAction` 红色按钮试过, 维护者嫌太吓人, 东西进的是废纸篓能恢复, 不要再提。
- **README 首屏图按语言分开是有意的**: `README_CN.md` 和 `README_TW.md` 用中文界面, 其余语言用英文界面, 审查和改稿时不要统一成一张 (维护者 2026-10-10)。2026-11-06 起首屏是一张 Mac、iPad、iPhone 拼图 (`readme-zh.webp` / `readme-en.webp`, 设备换了细边框, 铺 Mac 壁纸模糊出的底, 维护者从深色 Mac、预览模式、壁纸底三个方案里选了壁纸底), 不再是 11 到 16 MB 的 GIF; 它和分栏截图都放在官网 `vercel` 分支的 `assets/shots/`, README 用 `https://miaoyan.app/assets/shots/` 引用, 官网截图重拍后在 `vercel` 分支跑 `python3 -I scripts/build-readme-shot.py`, 从同一组 `{lang}-edit-2400` / `-ipad` / `-iphone` 重新拼, 再把 README 里两张图地址的 `?v=` 改成当天日期, GitHub 的图片代理按完整 URL 缓存, 官网又给图片一天缓存加七天过期可用, 不改地址 README 会一直显示旧图。
- **cmd-数字快捷键已占满 0-5**, 不要冲突: 1 侧栏, 2 笔记列表, 3 Toggle Preview, 4 Toggle Presentation, 5 TOC, 0 Actual Size。`⌘\` 只给 Toggle Split View, 用户已经记住了, 不要改; Window 菜单的 Main Window 原先也绑 `⌘\`, 被分栏抢先从来触发不了, 2026-10-11 改为 `⌥⌘0`。新增前先 `grep 'keyEquivalent="N"' Resources/Localization/Base.lproj/Main.storyboard` 核对, 绑定只存在于 storyboard, 代码里没有 keyBindings 表。打字机滚动 / 链接相关另开模式或子开关即可。

## Working Rules

- Prefer `AppEnvironment.current.<service>` over direct singleton access in
  new code. The SwiftLint `no_direct_singleton_in_new_code` rule is `severity: warning`
  in `.swiftlint.yml`, but CI runs `swiftlint lint --strict`, which promotes it
  to a merge gate. Existing call sites are grandfathered.
- Keep file writes scoped to user documents or app-controlled locations.
- Do not add network calls, shell execution, or broad file access without clear user need.

## Investigation Order

When scope is incomplete, start with `ARCHITECTURE.md`, the real top-level dependency map.

## Where the detail lives

Claude Code loads each `.claude/rules/*.md` when a file matching its `paths:` is read. On another runtime, read the matching file before working there. A new rule goes in the file for its area, and this file only takes what a conversation can trigger without reading a file.

- `.claude/rules/testing.md`: read before adding a test; a green exit code does not prove the new test ran, and a local test command needs extra flags.
- `.claude/rules/shell.md`: SwiftUI shell, sidebar, colour.
- `.claude/rules/storage.md`: read before changing anything that moves or deletes a note, folder or attachment.
- `.claude/rules/preview.md`: preview, Mermaid, PDF and PNG export, frontmatter, fonts.
- `.claude/rules/editor.md`: editor, key handling, search, menus, `.lproj`.
- `.claude/rules/release.md`: read before any release or release note, including the version-triplet rule (V3.5.1 / #524) that the CI tag check cites.

## Verification

- UI or interaction fixes: launch the built app and exercise the changed flow before reporting done (two builds that share the `com.tw93.miaoyan.qa` bundle id share the `wkPreview` copy of `DownView.bundle`, which is refreshed only from a newer file, so clear that folder when switching between them, or the page runs the other build's scripts); a green build is not visual proof. If the first fix attempt does not hold, stop guessing and add `#if DEBUG` runtime logging to capture evidence before the next code change.
- Handing a change to the maintainer to test (maintainer, 2026-10-25): replace the installed `/Applications/MiaoYan.app` with the new build without asking, because that copy is both the maintainer's daily app and the test build. Build Release with the project's own signing (`xcodebuild -project MiaoYan.xcodeproj -scheme MiaoYan -configuration Release -derivedDataPath <scratch> build`), check it with `codesign --verify --deep --strict`, quit the running copy through `osascript -e 'tell application id "com.tw93.miaoyan" to quit'` (its normal quit saves notes; never kill it), move the old bundle to the Trash under a distinct name so it can be restored, `ditto` the new one in, reopen it, and report the commit it was built from. The build is Developer ID signed but not notarized, which is fine on this Mac because a local copy carries no quarantine flag; notarized packages for users still come from `scripts/build.sh`.
- Release or signing changes: verify version alignment and inspect the relevant repository script; do not assume a tracked `release.yml` exists.
- Release note changes: inspect `.github/RELEASE_NOTES.md` and the affected `scripts/release-ci/` renderer.
- Export changes: verify Mermaid, images, PDF pagination, and async readiness behavior together.
- Incidents and risk: a fix for a defect that reached users in a release or the maintainer's daily build (`/Applications/MiaoYan.app`) adds its `docs/incidents.md` row in the same commit (or the docs commit right after it, when the row has to name the fix's own hash), naming the earliest layer that should have caught it and the test or CI job that catches it now; `scripts/check_incidents.py` fails a row whose commits, layer or catcher do not hold, and a defect with no catcher gets a test red on the old code or stays out of the table. The verification a change needs follows its paths, not its author: `scripts/risk_tier.py` names the extra gates for release, installer, note-writing, sync, export and shared-core paths (pass your own files when the worktree holds other work), and a commit in the release or notes tier says in its body how it was verified and how to revert it.
