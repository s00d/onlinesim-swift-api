// swift-tools-version: 5.9
import PackageDescription

// Complete concurrency checking on every toolchain (5.9 language mode); Swift 6 toolchains also build it in
// the Swift 6 language mode in CI (`-Xswiftc -swift-version -Xswiftc 6`).
let strictConcurrency: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

let package = Package(
    name: "OnlineSim",
    platforms: [.macOS(.v12), .iOS(.v15), .tvOS(.v15), .watchOS(.v8)],
    products: [
        .library(name: "OnlineSim", targets: ["OnlineSim"])
    ],
    targets: [
        .target(name: "OnlineSim", swiftSettings: strictConcurrency),
        .testTarget(
            name: "OnlineSimTests",
            dependencies: ["OnlineSim"],
            resources: [.copy("Fixtures")],
            swiftSettings: strictConcurrency
        ),
    ]
)
