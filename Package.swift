// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexUsageAlert",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"]),
        .executable(name: "CodexUsageAlert", targets: ["CodexUsageAlert"]),
        .executable(name: "codex-usage", targets: ["CodexUsageCLI"]),
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(
            name: "CodexUsageAlert",
            dependencies: ["UsageCore"]
        ),
        .executableTarget(
            name: "CodexUsageCLI",
            dependencies: ["UsageCore"]
        ),
        .testTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
