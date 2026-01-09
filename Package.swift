// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiaoYan",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v11)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.8.0"),
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.3.0"),
        .package(url: "https://github.com/ZipArchive/ZipArchive.git", from: "2.6.0"),
        .package(url: "https://github.com/stackotter/swift-cmark-gfm", from: "1.0.2"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0"),
        .package(url: "https://github.com/simonbs/Prettier.git", from: "0.2.1"),
    ],
    targets: []
)
