import Foundation
import SQLite3

/// jobwatch-runner가 기록한 정밀 실행 이력 (Recorded). 로그 mtime 근사(Estimated)와 구분됨.
struct JobRun: Sendable, Identifiable, Hashable {
    let id: Int64
    let startedAt: Date
    let endedAt: Date?
    let exitCode: Int32?
    let duration: Double?
    let stdoutTail: String?
    let stderrTail: String?
    var success: Bool { (exitCode ?? -1) == 0 }
    var hasOutput: Bool { !(stdoutTail ?? "").isEmpty || !(stderrTail ?? "").isEmpty }
}

struct JobHistory: Sendable {
    let runs: [JobRun]              // 최신순
    var last: JobRun? { runs.first }
    var count: Int { runs.count }
    var successRate: Double {
        guard !runs.isEmpty else { return 0 }
        return Double(runs.filter(\.success).count) / Double(runs.count)
    }
}

/// jobwatch.sqlite 읽기 전용 조회. runner와 같은 파일을 공유.
enum RunStore {
    static var dbPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JobWatch/jobwatch.sqlite").path
    }

    static func loadAll(limitPerJob: Int = 20, path: String? = nil) -> [String: JobHistory] {
        let dbPath = path ?? self.dbPath
        guard FileManager.default.fileExists(atPath: dbPath) else { return [:] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_close(db) }

        var byJob: [String: [JobRun]] = [:]
        var stmt: OpaquePointer?
        let sql = "SELECT id, job_id, started_at, ended_at, exit_code, duration, stdout_tail, stderr_tail FROM runs ORDER BY started_at DESC;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let cJob = sqlite3_column_text(stmt, 1) else { continue }
                let jobID = String(cString: cJob)
                if (byJob[jobID]?.count ?? 0) >= limitPerJob { continue }
                let run = JobRun(
                    id: sqlite3_column_int64(stmt, 0),
                    startedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                    endedAt: sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil
                        : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
                    exitCode: sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil
                        : sqlite3_column_int(stmt, 4),
                    duration: sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil
                        : sqlite3_column_double(stmt, 5),
                    stdoutTail: sqlite3_column_text(stmt, 6).map { String(cString: $0) },
                    stderrTail: sqlite3_column_text(stmt, 7).map { String(cString: $0) }
                )
                byJob[jobID, default: []].append(run)
            }
        }
        sqlite3_finalize(stmt)
        return byJob.mapValues { JobHistory(runs: $0) }
    }
}
