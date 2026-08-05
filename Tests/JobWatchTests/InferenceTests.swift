import XCTest
@testable import JobWatch

/// 순수 로직(로케일·번들 비의존) 단위 테스트.
final class InferenceTests: XCTestCase {

    // MARK: - prettify: 슬러그 → 사람이 읽는 이름

    func testPrettifyKebabAndSnake() {
        XCTAssertEqual(Inference.prettify("turbo-cache-cleanup"), "Turbo Cache Cleanup")
        XCTAssertEqual(Inference.prettify("sync_notion"), "Sync Notion")
        XCTAssertEqual(Inference.prettify("daily.summary"), "Daily Summary")
    }

    func testPrettifyCapitalizesEachWord() {
        // 입력이 소문자면 각 단어 첫 글자만 대문자화 (약어 특수처리는 원본 대문자일 때만)
        XCTAssertEqual(Inference.prettify("db-backup"), "Db Backup")
        XCTAssertEqual(Inference.prettify("DB-backup"), "DB Backup")   // 원본이 대문자면 보존
    }

    func testPrettifyEmptyFallsBack() {
        XCTAssertEqual(Inference.prettify(""), "")
    }

    // MARK: - JobCreator.slugify: 이름 → 라벨 슬러그 (ASCII만)

    func testSlugifyBasic() {
        XCTAssertEqual(JobCreator.slugify("Backup DB"), "backup-db")
        XCTAssertEqual(JobCreator.slugify("나의 작업"), "")          // 비ASCII 제거 → 빈 슬러그
        XCTAssertEqual(JobCreator.slugify("A  B--C"), "a-b-c")       // 중복 구분자 축약
    }

    func testSlugifyTrimsSeparators() {
        XCTAssertEqual(JobCreator.slugify("--hello--"), "hello")
        XCTAssertEqual(JobCreator.slugify("  spaced  "), "spaced")
    }

    func testStableHashIsDeterministicAndAscii() {
        // 비ASCII 이름 폴백 — 같은 입력이면 항상 같은 슬러그
        XCTAssertEqual(JobCreator.stableHash("나의 작업"), JobCreator.stableHash("나의 작업"))
        XCTAssertTrue(JobCreator.stableHash("작업").allSatisfy { $0.isASCII })
    }

    // MARK: - humanSize: 바이트 → 사람이 읽는 크기

    func testHumanSizeNonEmpty() {
        XCTAssertFalse(Int64(1_500_000_000).humanSize.isEmpty)
        XCTAssertTrue(Int64(0).humanSize.contains("0"))
    }

    // MARK: - category: 명령 → 카테고리 추론

    func testCategoryFromCommand() {
        XCTAssertEqual(cat(["/bin/bash", "backup.sh"]).name, "Backup")
        XCTAssertEqual(cat(["/usr/bin/python3", "x.py"]).name, "Python")
        XCTAssertEqual(cat(["/opt/homebrew/bin/claude", "-p", "hi"]).name, "AI")   // homebrew 경로여도 AI
        XCTAssertEqual(cat(["/opt/homebrew/bin/brew", "cleanup"]).name, "Homebrew")
        XCTAssertEqual(cat(["/bin/sh", "-c", "echo hi"]).name, "Shell")
    }

    private func cat(_ args: [String]) -> Inference.Category {
        Inference.category(for: makeJob(args: args))
    }

    private func makeJob(args: [String]) -> LaunchJob {
        LaunchJob(label: "test.job", plistPath: "/tmp/test.plist", domain: .userAgent,
                  programArguments: args, scheduleText: "manual",
                  stdoutPath: nil, stderrPath: nil, runAtLoad: false,
                  kind: .manual, isTracked: false, isLoaded: true,
                  pid: nil, lastExitCode: nil, lastRunApprox: nil,
                  nextRun: nil, scriptSummary: nil)
    }
}
