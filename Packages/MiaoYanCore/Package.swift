// swift-tools-version: 6.0
import PackageDescription

// Logic the Mac and iPhone apps must agree on, kept free of AppKit and UIKit
// so one implementation serves both targets and tests run with `swift test`.
let package = Package(
    name: "MiaoYanCore",
    platforms: [
        .macOS(.v12),
        .iOS(.v18),
    ],
    products: [
        .library(name: "MiaoYanCore", targets: ["MiaoYanCore"])
    ],
    targets: [
        .target(name: "MiaoYanCore"),
        .testTarget(name: "MiaoYanCoreTests", dependencies: ["MiaoYanCore"]),
    ]
)
