import XCTest
@testable import JobWatch

final class L10nTests: XCTestCase {
    // 번들 위치와 무관하게 t()는 절대 크래시하지 않고 비어있지 않은 문자열을 반환해야 한다.
    func testTNeverCrashesAndReturnsNonEmpty() {
        XCTAssertFalse(t("kind.scheduled").isEmpty)
        XCTAssertFalse(t("section.issues").isEmpty)
    }
    // 존재하지 않는 키는 키 자체를 반환(크래시 대신 폴백).
    func testUnknownKeyFallsBackToKey() {
        XCTAssertEqual(t("this.key.does.not.exist.zzz"), "this.key.does.not.exist.zzz")
    }
    // 포맷 인자 치환도 크래시 없이 동작.
    func testFormatArgs() {
        XCTAssertFalse(t("detail.lastExit", 3).isEmpty)
    }
}
