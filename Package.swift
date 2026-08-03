// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JobWatch",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "JobWatch",
            path: "Sources/JobWatch",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
