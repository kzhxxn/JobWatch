import Foundation

/// 새 잡의 스케줄 종류.
enum JobSchedule: Sendable {
    case interval(minutes: Int)
    case daily(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)   // weekday: 0=일 … 6=토
}

/// 새 launchd 잡을 runner 경유로 만들어 ~/Library/LaunchAgents에 설치하고 등록.
enum JobCreator {
    static func slugify(_ s: String) -> String {
        var out = ""
        for ch in s.lowercased() {
            // ASCII 영숫자만 허용 (라벨/파일명 안전) — 한글 등 비ASCII는 구분자로 처리
            if ch.isASCII && (ch.isLetter || ch.isNumber) { out.append(ch) }
            else { out.append("-") }
        }
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// 실행마다 안정적인(재현 가능) 짧은 해시 — 비ASCII 이름의 폴백 슬러그용.
    static func stableHash(_ s: String) -> String {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) &+ UInt64(b) }
        return String(h % 0xFFFFFF, radix: 36)
    }

    static func create(name: String, command: String, schedule: JobSchedule,
                       runner: String) -> (label: String?, message: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return (nil, "이름을 입력하세요") }
        guard !cmd.isEmpty else { return (nil, "명령을 입력하세요") }

        // 비ASCII 이름(한글 등)이면 슬러그가 비므로 안정적 폴백 사용
        var slug = slugify(trimmedName)
        if slug.isEmpty { slug = "job-" + stableHash(trimmedName) }

        let label = "com.jobwatch.user.\(slug)"
        let agents = (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents")
        try? FileManager.default.createDirectory(atPath: agents, withIntermediateDirectories: true)
        let plistPath = "\(agents)/\(label).plist"
        guard !FileManager.default.fileExists(atPath: plistPath) else {
            return (nil, "같은 이름의 잡이 이미 있음: \(label)")
        }

        let logDir = AnnotationStore.directory.appendingPathComponent("logs")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let logPath = logDir.appendingPathComponent("\(label).log").path

        var dict: [String: Any] = [
            "Label": label,
            // 처음부터 runner 경유 → 생성 즉시 정밀 추적
            "ProgramArguments": [runner, "run", label, "--", "/bin/sh", "-c", cmd],
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
        ]
        switch schedule {
        case .interval(let m):
            dict["StartInterval"] = max(1, m) * 60
        case .daily(let h, let mi):
            dict["StartCalendarInterval"] = ["Hour": h, "Minute": mi]
        case .weekly(let wd, let h, let mi):
            dict["StartCalendarInterval"] = ["Weekday": wd, "Hour": h, "Minute": mi]
        }

        guard let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        else { return (nil, "plist 생성 실패") }
        do { try data.write(to: URL(fileURLWithPath: plistPath)) }
        catch { return (nil, "plist 쓰기 실패: \(error.localizedDescription)") }

        let uid = getuid()
        let (out, status) = Launchd.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistPath])
        if status != 0 {
            return (label, "생성됨(등록 경고): \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return (label, "잡 생성됨: \(label)")
    }
}
