# MiaoYan Dependencies

This document describes the dependencies used in the MiaoYan project and their migration from CocoaPods to Swift Package Manager.

## Swift Package Manager Dependencies

The project now uses Swift Package Manager for all dependencies. The `Package.swift` file in the root directory documents all dependencies used by the Xcode project.

### Current Dependencies

| Package                                                       | Version | Purpose                                |
| ------------------------------------------------------------- | ------- | -------------------------------------- |
| [Sparkle](https://github.com/sparkle-project/Sparkle)         | 2.7.1+  | Auto-update framework for macOS apps   |
| [AppCenter](https://github.com/microsoft/appcenter-sdk-apple) | 5.0.6+  | App analytics and crash reporting      |
| [Alamofire](https://github.com/Alamofire/Alamofire)           | 5.10.2+ | HTTP networking library                |
| [SwiftyJSON](https://github.com/SwiftyJSON/SwiftyJSON)        | 5.0.2+  | JSON parsing library                   |
| [Highlightr](https://github.com/raspu/Highlightr)             | 2.3.0+  | Syntax highlighting for code blocks    |
| [ZipArchive](https://github.com/ZipArchive/ZipArchive)        | 2.6.0+  | ZIP file compression and decompression |
| [swift-cmark-gfm](https://github.com/stackotter/swift-cmark-gfm) | 1.0.2+  | GitHub Flavored Markdown parsing      |
| [MASShortcut](https://github.com/shpakovski/MASShortcut)      | master  | Global keyboard shortcuts for macOS    |

### Migration Notes

#### From CocoaPods to Swift Package Manager (2025)

The project was successfully migrated from CocoaPods to Swift Package Manager:

- ✅ **Removed**: `Podfile`, `Podfile.lock`, and all CocoaPods configurations
- ✅ **Migrated**: All dependencies to SPM equivalents
- ✅ **Replaced**: `libcmark_gfm` with `swift-cmark-gfm` for better Swift integration
- ✅ **Fixed**: Module naming conflicts and import issues

#### Key Changes

1. **Markdown Parser**: Replaced `libcmark_gfm` with `swift-cmark-gfm`

   ```swift
   // Old (libcmark_gfm)
   import libcmark_gfm

   // New (swift-cmark-gfm)
   import CMarkGFM
   
   // Usage remains similar with C API wrapper
   let html = renderMarkdownHTML(markdown: markdownContent)
   ```

2. **ZIP Archive**: Updated import statement

   ```swift
   // Old
   import SSZipArchive

   // New
   import ZipArchive
   ```

3. **AppCenter**: Removed `AppCenterDistribute`, kept `AppCenterAnalytics` and `AppCenterCrashes`

## Building the Project

### Using Xcode (Recommended)

```bash
open MiaoYan.xcodeproj
# Build using Xcode (⌘+B)
```

### Using Package.swift (Documentation Only)

The `Package.swift` file is primarily for documentation and dependency tracking. To work with dependencies:

```bash
# Show dependency tree
swift package show-dependencies

# Resolve dependencies (for reference)
swift package resolve
```

**Note**: The actual app build uses the Xcode project, not the Package.swift file.

## Dependency Management

### Adding New Dependencies

1. **In Xcode**: File → Add Package Dependencies...
2. **Update Package.swift**: Add the new dependency to the dependencies array for documentation

### Updating Dependencies

1. **In Xcode**: File → Packages → Update to Latest Package Versions
2. **Update Package.swift**: Update version numbers to match

### Platform Requirements

- **macOS**: 11.5+ (Big Sur)
- **Swift**: 5.9+
- **Xcode**: 12.0+

## Troubleshooting

### Common Issues

1. **Module not found**: Clean build folder (`⌘+Shift+K`) and rebuild
2. **Package resolution errors**: Delete `Package.resolved` and resolve again
3. **Duplicate dependencies**: Check for conflicting SPM/CocoaPods remnants

### Support

For dependency-related issues, please check:

1. [MiaoYan Issues](https://github.com/tw93/MiaoYan/issues)
2. Individual package documentation
3. Swift Package Manager documentation
