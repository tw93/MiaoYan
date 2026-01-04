## How to contribute to MiaoYan

**Thanks for helping MiaoYan grow!** Bug fixes, features, docs, localisation, performance tuning, accessibility, and any other improvements are welcome through [pull requests](https://github.com/tw93/MiaoYan/compare/).

## Branch Workflow

```txt
main        <--- Releases / production builds
 ↑
dev         <--- Default branch for all PRs
```

- `dev` holds day-to-day development. Please branch from the latest `dev` and target your PRs back to it.
- `main` is the release branch. We tag releases from `main`. Small documentation-only fixes can target `main` directly, but most changes should flow through `dev` first.

## Prerequisites

- macOS 13 or newer (Sonoma recommended)
- Xcode 16+ with the Swift 6 toolchain (the project builds with `SWIFT_VERSION = 6.0`)
- [SwiftLint](https://github.com/realm/SwiftLint) and [swift-format](https://github.com/apple/swift-format) available on your PATH (e.g. via Homebrew)

## Local Setup

1. Clone the repository and check out the latest `dev` branch.
2. Resolve Swift Package Manager dependencies once via Xcode (`File → Packages → Resolve Package Versions`) or `xcodebuild -resolvePackageDependencies`.
3. Open `MiaoYan.xcodeproj` in Xcode **or** work from VS Code using the tracked `.vscode/launch.json` and `.vscode/tasks.json`.

### Code Signing Setup (First Time)

When you first open the project in Xcode, you'll see a signing error:

```
Signing for "MiaoYan" requires a development team.
Select a development team in the Signing & Capabilities editor.
```

**To fix:**

1. Select the `MiaoYan` target in Xcode
2. Go to the "Signing & Capabilities" tab
3. Choose your Apple ID in the "Team" dropdown
   - If you don't have one, click "Add an Account..." to add your free Apple ID
   - No paid developer account needed for local development

**Why no DEVELOPMENT_TEAM in project.pbxproj?**

To make the DMG easier for users to open (avoid strict macOS Gatekeeper blocking), we removed the hardcoded `DEVELOPMENT_TEAM` from the project file. Xcode will save your Team selection locally in `xcuserdata/` (which is gitignored), so each developer uses their own Apple ID without affecting others.

## Build & Run

- **Xcode**: Open the project and use `⌘B` / `⌘R` to build and run.
- **Command line**: `xcodebuild -scheme MiaoYan -configuration Debug -destination "platform=macOS" build`
- **VS Code**: Trigger `Run Build Task` to execute `.vscode/tasks.json`, then use the `Debug MiaoYan (LLDB DAP)` launch config.

Build artifacts land in `.vscode/DerivedData/` (VS Code) or your default DerivedData path (Xcode). Both are ignored by git.

## Code Style & Quality

- Run `swift format --configuration .swift-format --in-place <folders>` on the files you touched before committing.
- Run `swiftlint lint --strict` to surface style and analyser warnings; address any issues it raises.
- Keep diffs focused: avoid committing files from `.build/`, DerivedData, or other generated content. Only `.vscode/launch.json` and `.vscode/tasks.json` are tracked from the `.vscode` directory.
- If you modify UI, include a screenshot or short video in your PR description so reviewers can verify the change quickly.

## Commit & Pull Requests

- Use the emoji-based commit convention from <https://github.com/tw93/cz-emoji-chinese> (or run Commitizen with that adapter).
- Squash unrelated changes into separate commits/PRs.
- Ensure your branch is rebased on the latest `dev` before requesting review.
- Fill in the PR template and describe testing steps (manual or automated).

## Issues & Feature Ideas

- For sizeable features, open a discussion/issue first so we can align on scope and UX.
- Typos or minor doc fixes can go straight to PRs without an issue.
- When reporting bugs, include the macOS version, app version, reproduction steps, and relevant logs if available.

## Release Build

MiaoYan releases are **unsigned** to avoid strict macOS Gatekeeper blocking (signed but not notarized apps are blocked more strictly than unsigned ones).

### Build Release DMG

```bash
# Update version in Xcode first: Target → General → Version
./scripts/build-release.sh 2.5.0
```

The script automatically cleans, archives without signing, creates DMG, and provides next steps.

### Release Checklist

1. Test DMG on a clean macOS (right-click → Open on first launch)
2. Create Git tag: `git tag V2.5.0 && git push origin V2.5.0`
3. Create GitHub Release and upload DMG
4. Update appcast.xml for Sparkle auto-update

Thank you for investing time in MiaoYan ❤️
