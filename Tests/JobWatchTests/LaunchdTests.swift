import XCTest
@testable import JobWatch

final class LaunchdTests: XCTestCase {

    // MARK: - unwrapRunner: 러너 래퍼 벗기기

    func testUnwrapTrackedJob() {
        let raw = ["/Users/x/bin/jobwatch-runner", "run", "com.x.job", "--", "/bin/sh", "-c", "echo hi"]
        let (args, tracked) = Launchd.unwrapRunner(raw)
        XCTAssertTrue(tracked)
        XCTAssertEqual(args, ["/bin/sh", "-c", "echo hi"])
    }

    func testUnwrapPlainJobUnchanged() {
        let raw = ["/bin/bash", "backup.sh"]
        let (args, tracked) = Launchd.unwrapRunner(raw)
        XCTAssertFalse(tracked)
        XCTAssertEqual(args, raw)
    }

    func testUnwrapRunnerWithoutSeparator() {
        // 래퍼처럼 보여도 "--"가 없으면 벗기지 않음 (안전)
        let raw = ["/bin/jobwatch-runner", "run", "com.x.job"]
        let (args, tracked) = Launchd.unwrapRunner(raw)
        XCTAssertFalse(tracked)
        XCTAssertEqual(args, raw)
    }

    func testUnwrapEmpty() {
        let (args, tracked) = Launchd.unwrapRunner([])
        XCTAssertFalse(tracked)
        XCTAssertTrue(args.isEmpty)
    }

    // MARK: - intervalRun: 주기 잡 다음 실행 roll-forward

    func testIntervalRunFutureIsWithinOnePeriod() {
        // 마지막 실행이 아주 오래 전이어도, 다음 실행은 항상 미래이며 한 주기 이내
        let now = Date(timeIntervalSince1970: 1_000_000)
        let last = now.addingTimeInterval(-7 * 24 * 3600)   // 일주일 전
        let next = Launchd.intervalRun(interval: 600, lastRun: last, now: now)!
        XCTAssertGreaterThan(next, now)                       // 미래
        XCTAssertLessThanOrEqual(next.timeIntervalSince(now), 600)  // 10분(주기) 이내
    }

    func testIntervalRunPreservesPhase() {
        // 위상 보존: (다음 - 마지막)이 주기의 정수배
        let now = Date(timeIntervalSince1970: 1_000_000)
        let last = now.addingTimeInterval(-905)              // 15분 5초 전, 주기 600
        let next = Launchd.intervalRun(interval: 600, lastRun: last, now: now)!
        let delta = next.timeIntervalSince(last)
        XCTAssertEqual(delta.truncatingRemainder(dividingBy: 600), 0, accuracy: 0.001)
    }

    func testIntervalRunZeroIntervalIsNil() {
        XCTAssertNil(Launchd.intervalRun(interval: 0, lastRun: Date(), now: Date()))
    }
}
