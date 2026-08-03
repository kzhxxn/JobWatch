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
        ),
        // 잡 실행을 감싸 시작/종료/duration/exit/출력을 SQLite에 기록하는 헤드리스 러너.
        .executableTarget(
            name: "jobwatch-runner",
            path: "Sources/jobwatch-runner"
        )
    ]
)
