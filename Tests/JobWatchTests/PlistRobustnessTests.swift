import XCTest
@testable import JobWatch

/// 다양한/이상한 plist 입력에서 분류·스케줄 계산이 안 깨지는지 (다른 환경 견고성).
final class PlistRobustnessTests: XCTestCase {

    // MARK: - classifyKind

    func testClassifyScheduled() {
        XCTAssertEqual(Launchd.classifyKind(["StartInterval": 600], runAtLoad: false), .scheduled)
        XCTAssertEqual(Launchd.classifyKind(["StartCalendarInterval": ["Hour": 3]], runAtLoad: false), .scheduled)
    }
    func testClassifyDaemonAndWatch() {
        XCTAssertEqual(Launchd.classifyKind(["KeepAlive": true], runAtLoad: true), .daemon)
        XCTAssertEqual(Launchd.classifyKind(["WatchPaths": ["/tmp"]], runAtLoad: false), .watch)
    }
    func testClassifyLoginAndManual() {
        XCTAssertEqual(Launchd.classifyKind([:], runAtLoad: true), .onceAtLogin)
        XCTAssertEqual(Launchd.classifyKind([:], runAtLoad: false), .manual)
    }
    func testClassifyScheduledWinsOverKeepAlive() {
        // 스케줄 + KeepAlive 동시 → 스케줄 우선 (발사대에 올라야 함)
        XCTAssertEqual(Launchd.classifyKind(["StartInterval": 60, "KeepAlive": true], runAtLoad: true), .scheduled)
    }
    func testClassifyHandlesWrongTypes() {
        // 값 타입이 이상해도 크래시 없이 분류 (키 존재만 봄)
        XCTAssertEqual(Launchd.classifyKind(["StartInterval": "oops"], runAtLoad: false), .scheduled)
        XCTAssertEqual(Launchd.classifyKind(["KeepAlive": ["x": 1]], runAtLoad: false), .daemon)
    }

    // MARK: - nextCalendarDate (요일 매핑 / 엣지)

    func testWeekdaySundayBothZeroAndSeven() {
        // launchd Weekday 0과 7 모두 일요일 → 같은 날 계산돼야 함
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let d0 = Launchd.nextCalendarDate(["Weekday": 0, "Hour": 9, "Minute": 0], after: base)
        let d7 = Launchd.nextCalendarDate(["Weekday": 7, "Hour": 9, "Minute": 0], after: base)
        XCTAssertNotNil(d0); XCTAssertEqual(d0, d7)
        XCTAssertEqual(Calendar.current.component(.weekday, from: d0!), 1)  // 1 = 일요일
    }
    func testNextCalendarIsFuture() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let next = Launchd.nextCalendarDate(["Hour": 3, "Minute": 0], after: base)
        XCTAssertNotNil(next)
        XCTAssertGreaterThan(next!, base)
    }
    func testEmptyCalendarIsNil() {
        // 아무 필드 없는 캘린더 → nil (계산 불가), 크래시 없음
        XCTAssertNil(Launchd.nextCalendarDate([:], after: Date()))
    }
    func testCalendarIgnoresJunkKeys() {
        // 알 수 없는 키가 섞여도 유효 필드로 계산
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let next = Launchd.nextCalendarDate(["Hour": 12, "Bogus": "x", "Weekday": 3], after: base)
        XCTAssertNotNil(next)
    }
}
