# MiaoYan Dependencies

This document is the source of truth for runtime dependencies. Nothing
enforces it, so keep the table below aligned with the package references in
`MiaoYan.xcodeproj/project.pbxproj` by hand, in the same commit. Removals matter as much as additions.

## Swift Package Manager

The Xcode project declares its Swift dependencies as package references in
`MiaoYan.xcodeproj/project.pbxproj` (`XCRemoteSwiftPackageReference`), and the
table follows those. No Xcode project reads `Package.swift`; it is only a
reference list (the `targets:` array is intentionally empty) and its versions
may differ.

| Package                                                            | Constraint | Purpose                                                |
| ------------------------------------------------------------------ | ---------- | ------------------------------------------------------ |
| [Sparkle](https://github.com/sparkle-project/Sparkle)              | 2.7.3+     | macOS auto-update (non-AppStore builds only)           |
| [Highlightr](https://github.com/raspu/Highlightr)                  | 2.3.0+     | Native syntax highlighting in `Helpers/NotesTextProcessor.swift` |
| [swift-cmark-gfm](https://github.com/stackotter/swift-cmark-gfm)   | 1.0.0+     | GitHub Flavored Markdown parsing (preview + export)    |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | 2.3.0+ | Global keyboard shortcut registration (window activation) |
| [Prettier](https://github.com/simonbs/Prettier.git)                | 0.2.1+     | Markdown formatting from the Format command                            |

## Conditional Compilation

- This repository builds the direct-download app with Sparkle. The Mac App Store
  build is packaged outside this repository, where Sparkle is stripped and Apple's
  update mechanism is used instead; no `#if !APPSTORE` gate exists here.

## Bundled Frontend Assets

MiaoYan renders previews inside a `WKWebView` that loads bundled HTML/CSS/JS
from `Resources/DownView.bundle/`. These are vendored, not pulled by SPM, so
they are documented in a separate manifest:

- See `Resources/DownView.bundle/js/vendor/MANIFEST.json` for the exact
  version, source URL, license and SHA-256 of each vendored `.min.js`.
- Update flow: replace the file, regenerate the manifest hash via
  `shasum -a 256 path/to/file.min.js`, bump the manifest entry, and commit.

## Open Source Licenses

`THIRD-PARTY-NOTICES.md` is bundled into the app and shown at MiaoYan > Open
Source Licenses. Adding, removing or bumping a Swift package or a vendored
preview file updates its entry there in the same commit, including copyright
lines and any library the file bundles (Mermaid carries DOMPurify and, in its
ELK layout, elkjs under EPL-2.0); `scripts/test_notices.py` fails when a
`MANIFEST.json` file or a `Package.resolved` version has no entry.

## Platform Requirements

- macOS host target: 12.0+ (Monterey)
- Swift toolchain: 6.0
- Xcode: 16.0+ (matches the build setting in `MiaoYan.xcodeproj`)

## Working with Dependencies

Add a new SPM dependency via Xcode (File > Add Package Dependencies...) and
add a row to the table above in the same commit (and a line to `Package.swift`
if you keep that reference list current).

Updating versions:

```bash
# Resolve latest within the declared constraints
xcodebuild -project MiaoYan.xcodeproj -scheme MiaoYan -resolvePackageDependencies

# Show the resolved dependency tree
swift package show-dependencies
```

Remove a dependency by deleting it from the Xcode project's package references
(and from `Package.swift`), then delete `Package.resolved` and re-resolve.

## History

- 2025: Migrated off CocoaPods. `Podfile` and `Podfile.lock` removed.
  `libcmark_gfm` replaced with `swift-cmark-gfm`. `SSZipArchive` import
  renamed to `ZipArchive`. AppCenter, Alamofire, SwiftyJSON, and MASShortcut
  were removed in this transition; if you find references to them in older
  documentation or commit messages, that is why.
