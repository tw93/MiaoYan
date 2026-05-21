# MiaoYan Dependencies

This document is the source of truth for runtime dependencies. It is verified
against `Package.swift` in CI (see `.github/workflows/ci.yml`); divergence
fails the build.

## Swift Package Manager

All Swift dependencies are managed through `Package.swift`. The Xcode project
consumes them via the standard SPM integration, not the `Package.swift` build
itself (the `targets:` array is intentionally empty; the file is a manifest
of declared versions only).

| Package                                                            | Constraint | Purpose                                                |
| ------------------------------------------------------------------ | ---------- | ------------------------------------------------------ |
| [Sparkle](https://github.com/sparkle-project/Sparkle)              | 2.8.0+     | macOS auto-update (non-AppStore builds only)           |
| [Highlightr](https://github.com/raspu/Highlightr)                  | 2.3.0+     | Native syntax highlighting in `Helpers/NotesTextProcessor.swift` |
| [ZipArchive](https://github.com/ZipArchive/ZipArchive)             | 2.6.0+     | Note attachment + version archive zip/unzip            |
| [swift-cmark-gfm](https://github.com/stackotter/swift-cmark-gfm)   | 1.0.2+     | GitHub Flavored Markdown parsing (preview + export)    |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | 2.4.0+ | Global keyboard shortcut registration (window activation) |
| [Prettier](https://github.com/simonbs/Prettier.git)                | 0.2.1+     | Markdown auto-format on save                           |

## Conditional Compilation

- `#if !APPSTORE` gates Sparkle imports; the Mac App Store target ships without
  the auto-update path and relies on Apple's update mechanism instead.

## Bundled Frontend Assets

MiaoYan renders previews inside a `WKWebView` that loads bundled HTML/CSS/JS
from `Resources/DownView.bundle/`. These are vendored, not pulled by SPM, so
they are documented in a separate manifest:

- See `Resources/DownView.bundle/js/vendor/MANIFEST.json` for the exact
  version, source URL, license and SHA-256 of each vendored `.min.js`.
- Update flow: replace the file, regenerate the manifest hash via
  `shasum -a 256 path/to/file.min.js`, bump the manifest entry, and commit.

## Platform Requirements

- macOS host target: 11.5+ (Big Sur)
- iOS Mobile target: 18.0+
- Swift toolchain: 6.0
- Xcode: 16.0+ (matches the build setting in `MiaoYan.xcodeproj`)

## Working with Dependencies

Add a new SPM dependency via Xcode (File > Add Package Dependencies...) and
**also** add a line to `Package.swift` in the same commit. CI fails if the
two diverge.

Updating versions:

```bash
# Resolve latest within the declared constraints
xcodebuild -project MiaoYan.xcodeproj -scheme MiaoYan -resolvePackageDependencies

# Show the resolved dependency tree
swift package show-dependencies
```

Remove a dependency by deleting it from both `Package.swift` and the Xcode
project's package references, then delete `Package.resolved` and re-resolve.

## History

- 2025: Migrated off CocoaPods. `Podfile` and `Podfile.lock` removed.
  `libcmark_gfm` replaced with `swift-cmark-gfm`. `SSZipArchive` import
  renamed to `ZipArchive`. AppCenter, Alamofire, SwiftyJSON, and MASShortcut
  were removed in this transition; if you find references to them in older
  documentation or commit messages, that is why.
