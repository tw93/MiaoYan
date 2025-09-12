// swift-tools-version: 5.9
// MiaoYan - A lightweight Markdown editor for macOS
// This Package.swift file documents the dependencies used in the Xcode project
// The actual build is handled by the Xcode project, not this Package.swift
import PackageDescription

let package = Package(
    name: "MiaoYan",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v11)
    ],
    dependencies: [
        // Auto-update framework for macOS apps
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.7.3"),
        // Privacy-first analytics for Apple platforms
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.9.4"),
        // HTTP networking library
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.10.2"),
        // JSON parsing library
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.2"),
        // Syntax highlighting for code blocks
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.3.0"),
        // ZIP file compression and decompression
        .package(url: "https://github.com/ZipArchive/ZipArchive.git", from: "2.6.0"),
        // GitHub Flavored Markdown parsing library
        .package(url: "https://github.com/stackotter/swift-cmark-gfm", from: "1.0.2"),
        // Global keyboard shortcuts for macOS
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.3.0"),
        // Swift wrapper for Prettier code formatter
        .package(url: "https://github.com/simonbs/Prettier.git", from: "0.2.1"),
    ],
    targets: [
        // No targets defined - this package is used only for dependency management
        // The actual app is built using the MiaoYan.xcodeproj Xcode project
    ]
)
