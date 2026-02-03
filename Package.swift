// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeUsage",
            path: "ClaudeUsage",
            sources: [
                "ClaudeUsageApp.swift",
                "Models/UsageData.swift",
                "Views/UsageMenuView.swift",
                "Views/ClaudeLogo.swift"
            ]
        )
    ]
)
