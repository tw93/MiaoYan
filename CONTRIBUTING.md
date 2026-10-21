## How to contribute to MiaoYan

**Thanks for helping MiaoYan grow!** Bug fixes, features, docs, localisation, performance tuning, accessibility, and any other improvements are welcome through [pull requests](https://github.com/tw93/MiaoYan/compare/).

## Branch Workflow

- `main` holds day-to-day development and every release is tagged from it. Branch from the latest `main` and target your PRs back to it.
- `vercel` publishes the miaoyan.app website; app changes do not go there.

## Prerequisites

- macOS 13 or newer (Sonoma recommended)
- Xcode 16+ with the Swift 6 toolchain (the project builds with `SWIFT_VERSION = 6.0`)
- [SwiftLint](https://github.com/realm/SwiftLint) and [swift-format](https://github.com/apple/swift-format) available on your PATH (e.g. via Homebrew)

## Local Setup

1. Clone the repository and check out the latest `main` branch.
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

- Start commit subjects with a lowercase type such as `fix:`, `feat:`, `test:` or `docs:`, as the history does.
- Squash unrelated changes into separate commits/PRs.
- Ensure your branch is rebased on the latest `main` before requesting review.
- Fill in the PR template and describe testing steps (manual or automated).

## Issues & Feature Ideas

- For sizeable features, open a discussion/issue first so we can align on scope and UX.
- Typos or minor doc fixes can go straight to PRs without an issue.
- When reporting bugs, include the macOS version, app version, reproduction steps, and relevant logs if available.

## Release Build

This repository ships the direct-download Mac app: GitHub Release assets
plus a Sparkle appcast entry, also picked up by Homebrew. The App Store builds
for iPhone, iPad and Mac are packaged elsewhere from this repository's `main`.
Keep the tag, release notes, DMG, ZIP, and Sparkle appcast aligned before
announcing the release.

### Release Checklist

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `MiaoYan.xcodeproj/project.pbxproj` to the same version; Sparkle compares `CURRENT_PROJECT_VERSION`
2. Confirm `.github/RELEASE_NOTES.md` matches the intended uppercase tag, for example `Vx.y.z`
3. Create Git tag: `git tag V<version> && git push origin V<version>`
4. Build and notarize the direct-download DMG and ZIP with `scripts/build.sh`, then update the Sparkle appcast
5. Create GitHub Release with release notes plus the DMG and ZIP assets

> **Self-build path still works.** `scripts/build.sh` produces a runnable Release build for local use or CI. Sparkle integration remains active for direct-download users.

Thank you for investing time in MiaoYan ❤️
