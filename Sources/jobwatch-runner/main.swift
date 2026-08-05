import Foundation
import SQLite3

// jobwatch-runner — 잡 실행을 감싸 실행 이력을 SQLite에 기록하는 헤드리스 바이너리.
//
// 사용법 (plist ProgramArguments 가 이렇게 호출):
//   jobwatch-runner run <job-id> -- <실제 명령> [인자...]
//
// 동작: 시작시각 기록 → 실제 명령 실행(출력은 그대로 통과+tail 저장) →
//       종료시각·duration·exit코드 기록 → SQLite에 append → 보존정책 적용 → 자식과 동일 코드로 종료.

let TAIL_LIMIT = 8 * 1024      // 저장할 stdout/stderr 꼬리 최대 바이트
let KEEP_RUNS = 50             // 잡당 보관할 최근 실행 수
let KEEP_DAYS = 90.0           // 보관 기간(일)

// MARK: - 인자 파싱

let argv = Array(CommandLine.arguments.dropFirst())
guard argv.count >= 4, argv[0] == "run", let sep = argv.firstIndex(of: "--"), sep + 1 < argv.count else {
    FileHandle.standardError.write(Data("usage: jobwatch-runner run <job-id> -- <command> [args...]\n".utf8))
    exit(64)
}
let jobID = argv[1]
let command = Array(argv[(sep + 1)...])

// MARK: - DB 경로

let dbPath: String = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("JobWatch", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base.appendingPathComponent("jobwatch.sqlite").path
}()

// MARK: - 실행 + 출력 tee/tail

final class TailBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    private let sink: FileHandle
    init(sink: FileHandle) { self.sink = sink }
    func append(_ chunk: Data) {
        sink.write(chunk)                       // 원래 로그로 그대로 통과(tee)
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        if data.count > TAIL_LIMIT { data.removeFirst(data.count - TAIL_LIMIT) }
    }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}

let startedAt = Date().timeIntervalSince1970

let proc = Process()
proc.executableURL = URL(fileURLWithPath: command[0])
proc.arguments = Array(command.dropFirst())

let outPipe = Pipe(), errPipe = Pipe()
proc.standardOutput = outPipe
proc.standardError = errPipe
let outTail = TailBuffer(sink: .standardOutput)
let errTail = TailBuffer(sink: .standardError)
outPipe.fileHandleForReading.readabilityHandler = { h in
    let d = h.availableData; if !d.isEmpty { outTail.append(d) }
}
errPipe.fileHandleForReading.readabilityHandler = { h in
    let d = h.availableData; if !d.isEmpty { errTail.append(d) }
}

var exitCode: Int32 = -1
do {
    try proc.run()
    proc.waitUntilExit()
    exitCode = proc.terminationStatus
    if proc.terminationReason == .uncaughtSignal { exitCode = 128 + proc.terminationStatus }
} catch {
    FileHandle.standardError.write(Data("jobwatch-runner: 실행 실패: \(error.localizedDescription)\n".utf8))
    exitCode = 127
}
outPipe.fileHandleForReading.readabilityHandler = nil
errPipe.fileHandleForReading.readabilityHandler = nil
// 남은 데이터 flush
outTail.append(outPipe.fileHandleForReading.availableData)
errTail.append(errPipe.fileHandleForReading.availableData)

let endedAt = Date().timeIntervalSince1970

// MARK: - SQLite 기록

func record(jobID: String, dbPath: String, startedAt: Double, endedAt: Double,
            exitCode: Int32, stdoutTail: String, stderrTail: String) {
    var db: OpaquePointer?
    guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return }
    defer { sqlite3_close(db) }

    sqlite3_exec(db, """
        CREATE TABLE IF NOT EXISTS runs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          job_id TEXT NOT NULL,
          started_at REAL NOT NULL,
          ended_at REAL,
          exit_code INTEGER,
          duration REAL,
          stdout_tail TEXT,
          stderr_tail TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_runs_job ON runs(job_id, started_at DESC);
        """, nil, nil, nil)

    let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    var stmt: OpaquePointer?
    let sql = """
        INSERT INTO runs (job_id, started_at, ended_at, exit_code, duration, stdout_tail, stderr_tail)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
    if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
        sqlite3_bind_text(stmt, 1, jobID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, startedAt)
        sqlite3_bind_double(stmt, 3, endedAt)
        sqlite3_bind_int(stmt, 4, exitCode)
        sqlite3_bind_double(stmt, 5, endedAt - startedAt)
        sqlite3_bind_text(stmt, 6, stdoutTail, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, stderrTail, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }
    sqlite3_finalize(stmt)

    // 보존정책: 잡당 최근 KEEP_RUNS개만 + KEEP_DAYS 이내만 (제2의 turbo 캐시 방지)
    // 모두 파라미터 바인딩 — 문자열 조립 SQL 금지 (인젝션 방어)
    let cutoff = Date().timeIntervalSince1970 - KEEP_DAYS * 86400
    if sqlite3_prepare_v2(db, "DELETE FROM runs WHERE started_at < ?;", -1, &stmt, nil) == SQLITE_OK {
        sqlite3_bind_double(stmt, 1, cutoff); sqlite3_step(stmt)
    }
    sqlite3_finalize(stmt)
    let capSQL = """
        DELETE FROM runs WHERE job_id = ?1 AND id NOT IN (
          SELECT id FROM runs WHERE job_id = ?1 ORDER BY started_at DESC LIMIT ?2);
        """
    if sqlite3_prepare_v2(db, capSQL, -1, &stmt, nil) == SQLITE_OK {
        sqlite3_bind_text(stmt, 1, jobID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(KEEP_RUNS))
        sqlite3_step(stmt)
    }
    sqlite3_finalize(stmt)
}
record(jobID: jobID, dbPath: dbPath, startedAt: startedAt, endedAt: endedAt,
       exitCode: exitCode, stdoutTail: outTail.text, stderrTail: errTail.text)

exit(exitCode)
