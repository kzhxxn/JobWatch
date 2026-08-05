import XCTest
@testable import JobWatch

/// jobwatch-runner 바이너리를 실제로 실행해 SQLite 기록·보존정책·RunStore 읽기를 검증.
final class RunnerIntegrationTests: XCTestCase {

    var tmpDir: URL!
    var dbPath: String!
    var runnerPath: String!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jobwatch-test-\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        dbPath = tmpDir.appendingPathComponent("test.sqlite").path
        runnerPath = try Self.findRunner()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    /// 빌드된 jobwatch-runner 실행파일 찾기 (테스트 번들과 같은 빌드 디렉토리에 있음).
    static func findRunner() throws -> String {
        let bundleDir = Bundle(for: RunnerIntegrationTests.self).bundleURL.deletingLastPathComponent()
        let candidates = [
            bundleDir.appendingPathComponent("jobwatch-runner").path,
            bundleDir.deletingLastPathComponent().appendingPathComponent("jobwatch-runner").path,
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        throw XCTSkip("jobwatch-runner 실행파일을 찾지 못함 (candidates: \(candidates))")
    }

    @discardableResult
    private func runOnce(job: String, command: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: runnerPath)
        p.arguments = ["run", job, "--"] + command
        var env = ProcessInfo.processInfo.environment
        env["JOBWATCH_DB"] = dbPath
        p.environment = env
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus
    }

    // MARK: - 기록 + exit 전파

    func testRecordsRunAndPropagatesExit() throws {
        let code = runOnce(job: "test.record", command: ["/bin/sh", "-c", "echo hi; exit 3"])
        XCTAssertEqual(code, 3, "runner가 자식 종료코드를 전파해야 함")

        let hist = RunStore.loadAll(path: dbPath)
        let h = try XCTUnwrap(hist["test.record"])
        XCTAssertEqual(h.count, 1)
        XCTAssertEqual(h.last?.exitCode, 3)
        XCTAssertFalse(h.last!.success)
        XCTAssertEqual(h.last?.stdoutTail?.trimmingCharacters(in: .whitespacesAndNewlines), "hi")
    }

    // MARK: - 보존정책 (제2의 turbo 캐시 방지)

    func testRetentionCapsAt50Runs() throws {
        // 55회 실행 → 최근 50개만 남아야 함
        for i in 1...55 {
            runOnce(job: "test.cap", command: ["/bin/sh", "-c", "echo \(i)"])
        }
        // RunStore는 잡당 최대 20개만 읽으므로, 실제 DB 행 수를 직접 확인
        let total = Self.rowCount(dbPath: dbPath, jobID: "test.cap")
        XCTAssertLessThanOrEqual(total, 50, "보존정책이 50회로 캡해야 함 (무한 누적 방지)")
        XCTAssertGreaterThanOrEqual(total, 45, "정상 기록은 유지돼야 함")
    }

    // MARK: - 여러 잡 격리

    func testMultipleJobsIsolated() throws {
        runOnce(job: "test.a", command: ["/bin/sh", "-c", "true"])
        runOnce(job: "test.b", command: ["/bin/sh", "-c", "true"])
        let hist = RunStore.loadAll(path: dbPath)
        XCTAssertEqual(hist["test.a"]?.count, 1)
        XCTAssertEqual(hist["test.b"]?.count, 1)
    }

    // 직접 SQLite로 특정 잡의 총 행 수 조회
    static func rowCount(dbPath: String, jobID: String) -> Int {
        let (out, _) = shell("/usr/bin/sqlite3",
                             [dbPath, "SELECT COUNT(*) FROM runs WHERE job_id='\(jobID)';"])
        return Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
    }
    static func shell(_ path: String, _ args: [String]) -> (String, Int32) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe
        try? p.run(); p.waitUntilExit()
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: d, encoding: .utf8) ?? "", p.terminationStatus)
    }
}
