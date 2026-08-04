import Foundation

/// 잡 트리거 종류 — 섹션 분류용.
enum JobKind: String, Sendable {
    case scheduled    // 반복 예약 (자주 동작)
    case daemon       // 상시 유지 (KeepAlive)
    case onceAtLogin  // 로그인 시 1회
    case watch        // 경로 변경 감지
    case manual       // 수동/기타
}

/// launchd 잡이 정의된 위치 (권한 범위가 다름).
enum JobDomain: String, Sendable {
    case userAgent      // ~/Library/LaunchAgents  — 내 권한으로 관리 가능
    case globalAgent    // /Library/LaunchAgents    — root 필요 (읽기 전용 취급)

    var label: String {
        switch self {
        case .userAgent: return "사용자"
        case .globalAgent: return "시스템"
        }
    }
}

/// 한 개의 launchd 잡 (plist + 실시간 상태를 합친 뷰 모델).
struct LaunchJob: Identifiable, Sendable, Hashable {
    var id: String { plistPath }   // 라벨은 중복될 수 있어(같은 파일이 user/global 양쪽) 경로로 식별

    let label: String
    let plistPath: String
    let domain: JobDomain

    // plist에서 파싱한 정적 정보
    let programArguments: [String]
    let scheduleText: String
    let stdoutPath: String?
    let stderrPath: String?
    let runAtLoad: Bool
    let kind: JobKind
    let isTracked: Bool   // runner로 감싸져 정밀 추적 중

    // launchctl에서 가져온 실시간 상태
    var isLoaded: Bool
    var pid: Int?
    var lastExitCode: Int?

    // 근사/계산 시간 정보 (Observed 잡이라 "추정치". runner 도입 후 Managed 잡은 정밀값으로 승급)
    var lastRunApprox: Date?   // 로그 파일 mtime 기반 근사
    var nextRun: Date?         // 스케줄에서 계산한 다음 실행 예정 시각
    var scriptSummary: String? // 스크립트 헤더 주석에서 추출한 "진짜 목적"

    /// 마지막 실행이 정상 종료였는지. exit 0 = 정상, nil = 미확인, 그 외 = 실패/시그널.
    var healthy: Bool {
        guard isLoaded else { return false }
        if let code = lastExitCode { return code == 0 }
        return true
    }

    var commandPreview: String {
        programArguments.isEmpty ? "(명령 없음)" : programArguments.joined(separator: " ")
    }

    var isManageable: Bool { domain == .userAgent }
}

/// 디스크 사용 현황 (헤더 표시용).
struct DiskInfo: Sendable {
    let totalBytes: Int64
    let freeBytes: Int64

    var usedBytes: Int64 { totalBytes - freeBytes }
    var usedFraction: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }

    static func current() -> DiskInfo {
        let path = NSHomeDirectory()
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path)
        let total = (attrs?[.systemSize] as? NSNumber)?.int64Value ?? 0
        let free = (attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        return DiskInfo(totalBytes: total, freeBytes: free)
    }
}

extension Int64 {
    /// 사람이 읽는 용량 문자열 (예: 423 GB).
    var humanSize: String {
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = [.useGB, .useMB]
        fmt.countStyle = .file
        return fmt.string(fromByteCount: self)
    }
}
