import Foundation

/// launchd 잡을 스캔·조작하는 순수 유틸리티. 모든 함수는 nonisolated + Sendable 반환이라
/// 백그라운드 Task.detached에서 안전하게 호출할 수 있다.
enum Launchd {

    static let uid = getuid()

    private static var userAgentsDir: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents")
    }
    private static let globalAgentsDir = "/Library/LaunchAgents"

    // MARK: - 셸 실행

    /// 프로세스를 동기 실행하고 (표준출력, 종료코드)를 반환.
    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> (output: String, status: Int32) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
        } catch {
            return ("실행 실패: \(error.localizedDescription)", -1)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "", proc.terminationStatus)
    }

    private static func launchctl(_ args: [String]) -> (String, Int32) {
        run("/bin/launchctl", args)
    }

    // MARK: - 스캔

    /// 사용자/시스템 LaunchAgents의 모든 plist를 파싱하고 launchctl 실시간 상태와 병합.
    static func scanAll() -> [LaunchJob] {
        let live = liveState()
        var jobs: [LaunchJob] = []
        jobs += scan(dir: userAgentsDir, domain: .userAgent, live: live)
        jobs += scan(dir: globalAgentsDir, domain: .globalAgent, live: live)
        return jobs.sorted { lhs, rhs in
            // 문제 있는(로드 안 됨/실패) 잡을 위로, 그다음 이름순
            if lhs.healthy != rhs.healthy { return !lhs.healthy }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    private static func scan(dir: String, domain: JobDomain, live: [String: (pid: Int?, code: Int?)]) -> [LaunchJob] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        return entries.filter { $0.hasSuffix(".plist") }.compactMap { name in
            let path = (dir as NSString).appendingPathComponent(name)
            return parsePlist(path: path, domain: domain, name: name, live: live)
        }
    }

    private static func parsePlist(path: String, domain: JobDomain, name: String, live: [String: (pid: Int?, code: Int?)]) -> LaunchJob? {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any]
        else { return nil }

        let label = (dict["Label"] as? String) ?? (name as NSString).deletingPathExtension
        let args = (dict["ProgramArguments"] as? [String])
            ?? (dict["Program"] as? String).map { [$0] }
            ?? []
        let runAtLoad = (dict["RunAtLoad"] as? Bool) ?? false
        let schedule = describeSchedule(dict)
        let kind: JobKind
        if dict["StartCalendarInterval"] != nil || dict["StartInterval"] != nil { kind = .scheduled }
        else if dict["KeepAlive"] != nil { kind = .daemon }
        else if dict["WatchPaths"] != nil || dict["QueueDirectories"] != nil { kind = .watch }
        else if runAtLoad { kind = .onceAtLogin }
        else { kind = .manual }
        let state = live[label]
        let stdout = dict["StandardOutPath"] as? String
        let stderr = dict["StandardErrorPath"] as? String
        let lastRun = approxLastRun(stdout: stdout, stderr: stderr)

        return LaunchJob(
            label: label,
            plistPath: path,
            domain: domain,
            programArguments: args,
            scheduleText: schedule,
            stdoutPath: stdout,
            stderrPath: stderr,
            runAtLoad: runAtLoad,
            kind: kind,
            isLoaded: state != nil,
            pid: state?.pid,
            lastExitCode: state?.code,
            lastRunApprox: lastRun,
            nextRun: computeNextRun(dict, lastRun: lastRun),
            scriptSummary: readScriptSummary(args)
        )
    }

    // MARK: - 스크립트 헤더 주석 → "진짜 목적"

    /// 실행되는 스크립트 파일의 맨 위 주석/docstring을 읽어 한 줄 설명으로.
    /// 파일이 없거나 주석이 없으면 nil → 상위에서 키워드 추론으로 폴백.
    private static func readScriptSummary(_ args: [String]) -> String? {
        guard let path = scriptPath(args),
              let content = try? String(contentsOfFile: path, encoding: .utf8)
        else { return nil }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(30).map { $0.trimmingCharacters(in: .whitespaces) }

        for (i, line) in lines.enumerated() {
            if line.isEmpty || line.hasPrefix("#!") { continue }         // 빈 줄·셰뱅 건너뜀
            if line.hasPrefix("#") || line.hasPrefix("//") {            // 셸/JS 주석
                let text = line.drop { $0 == "#" || $0 == "/" }.trimmingCharacters(in: .whitespaces)
                if isMeaningfulComment(text) { return clip(text) }
                continue
            }
            if line.hasPrefix("\"\"\"") || line.hasPrefix("'''") {       // 파이썬 docstring
                let q = String(line.prefix(3))
                let inline = line.dropFirst(3)
                if let end = inline.range(of: q) {
                    let doc = inline[..<end.lowerBound].trimmingCharacters(in: .whitespaces)
                    return doc.isEmpty ? nil : clip(doc)
                }
                for j in (i + 1)..<lines.count {                        // 여러 줄 docstring
                    let l = lines[j]
                    if l.isEmpty { continue }
                    if l.hasPrefix(q) { return nil }
                    return clip(l)
                }
                return nil
            }
            break   // 주석 없이 코드 시작 → 헤더 없음
        }
        return nil
    }

    private static func scriptPath(_ args: [String]) -> String? {
        for arg in args {
            if arg.hasPrefix("-") || !arg.contains("/") { continue }
            let stem = ((arg as NSString).lastPathComponent as NSString).deletingPathExtension
            if Inference.interpreters.contains(stem.lowercased()) { continue }
            let path = (arg as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    private static func isMeaningfulComment(_ text: String) -> Bool {
        if text.count < 4 { return false }
        let lower = text.lowercased()
        // 인코딩·린터·툴 지시자 등 설명이 아닌 주석 제외
        let noise = ["coding:", "shellcheck", "noqa", "eslint", "prettier",
                     "vim:", "-*-", "type:", "pylint", "flake8", "usr/bin", "bin/"]
        return !noise.contains { lower.contains($0) }
    }

    private static func clip(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: " \t.\"'"))
        return trimmed.count > 100 ? String(trimmed.prefix(100)) + "…" : trimmed
    }

    // MARK: - 마지막 실행 근사 (로그 파일 mtime)

    /// StandardOutPath/ErrorPath 로그 파일의 수정 시각을 "마지막 실행 ≈ 언제"로 근사.
    /// 잡이 로그를 남기지 않으면 nil (그래서 UI에서 "추정"으로 표기).
    private static func approxLastRun(stdout: String?, stderr: String?) -> Date? {
        for raw in [stdout, stderr].compactMap({ $0 }) {
            let path = (raw as NSString).expandingTildeInPath
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let date = attrs[.modificationDate] as? Date {
                return date
            }
        }
        return nil
    }

    // MARK: - 다음 실행 시각 계산

    private static func computeNextRun(_ dict: [String: Any], lastRun: Date?) -> Date? {
        let now = Date()
        if let cal = dict["StartCalendarInterval"] {
            let items = (cal as? [[String: Any]]) ?? (cal as? [String: Any]).map { [$0] } ?? []
            return items.compactMap { nextCalendarDate($0, after: now) }.min()
        }
        // StartInterval은 로드 시각을 알 수 없어 마지막 실행 위상으로 근사.
        // 추정 다음 실행이 과거면 다음 미래 주기로 굴림(roll-forward) → "now" 방지.
        if let interval = dict["StartInterval"] as? Int, interval > 0, let last = lastRun {
            let iv = TimeInterval(interval)
            let k = max(1, ceil(now.timeIntervalSince(last) / iv))
            return last.addingTimeInterval(k * iv)
        }
        return nil
    }

    private static func nextCalendarDate(_ c: [String: Any], after date: Date) -> Date? {
        var comps = DateComponents()
        if let m = c["Minute"] as? Int { comps.minute = m }
        if let h = c["Hour"] as? Int { comps.hour = h }
        if let d = c["Day"] as? Int { comps.day = d }
        if let mo = c["Month"] as? Int { comps.month = mo }
        if let wd = c["Weekday"] as? Int {
            comps.weekday = (wd % 7) + 1  // launchd 0/7=일 → Calendar 1=일
        }
        guard comps.minute != nil || comps.hour != nil || comps.day != nil
                || comps.weekday != nil || comps.month != nil else { return nil }
        return Calendar.current.nextDate(after: date, matching: comps, matchingPolicy: .nextTime)
    }

    /// `launchctl list` 출력을 label -> (pid, 마지막 exit코드)로 파싱.
    private static func liveState() -> [String: (pid: Int?, code: Int?)] {
        let (out, _) = launchctl(["list"])
        var map: [String: (pid: Int?, code: Int?)] = [:]
        for line in out.split(separator: "\n").dropFirst() { // 첫 줄은 헤더
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            let pid = Int(cols[0])                 // "-"면 nil
            let code = Int(cols[1])                // 마지막 종료 코드
            let label = String(cols[2])
            map[label] = (pid, code)
        }
        return map
    }

    // MARK: - 스케줄 사람이 읽게 (다국어)

    private static func describeSchedule(_ dict: [String: Any]) -> String {
        if let interval = dict["StartInterval"] as? Int {
            if interval % 3600 == 0 { return t("sched.everyHours", interval / 3600) }
            if interval % 60 == 0 { return t("sched.everyMinutes", interval / 60) }
            return t("sched.everySeconds", interval)
        }
        if let cal = dict["StartCalendarInterval"] {
            let items = (cal as? [[String: Any]]) ?? [(cal as? [String: Any]).map { [$0] } ?? []].flatMap { $0 }
            let parts = items.map { describeCalendar($0) }
            if !parts.isEmpty { return parts.joined(separator: ", ") }
        }
        if (dict["WatchPaths"] as? [String]) != nil { return t("sched.watchPaths") }
        if (dict["QueueDirectories"] as? [String]) != nil { return t("sched.watchDirs") }
        if (dict["RunAtLoad"] as? Bool) == true { return t("sched.atLogin") }
        if dict["KeepAlive"] != nil { return t("sched.keepAlive") }
        return t("sched.manual")
    }

    private static func describeCalendar(_ c: [String: Any]) -> String {
        var pieces: [String] = []
        if let wd = c["Weekday"] as? Int {
            pieces.append(t("sched.weeklyPrefix", t("weekday.\((wd % 7 + 7) % 7)")))
        }
        if let day = c["Day"] as? Int {
            pieces.append(t("sched.monthlyPrefix", day))
        }
        let h = c["Hour"] as? Int
        let m = c["Minute"] as? Int
        if h != nil || m != nil {
            pieces.append(String(format: "%02d:%02d", h ?? 0, m ?? 0))
        }
        return pieces.isEmpty ? t("sched.schedule") : pieces.joined(separator: " ")
    }

    // MARK: - 조작 (사용자 에이전트 전용)

    static func kickstart(_ label: String) -> (String, Int32) {
        launchctl(["kickstart", "-k", "gui/\(uid)/\(label)"])
    }

    static func unload(_ plistPath: String) -> (String, Int32) {
        launchctl(["bootout", "gui/\(uid)", plistPath])
    }

    static func load(_ plistPath: String) -> (String, Int32) {
        launchctl(["bootstrap", "gui/\(uid)", plistPath])
    }

    static func revealInFinder(_ path: String) {
        run("/usr/bin/open", ["-R", path])
    }

    static func openFile(_ path: String) {
        run("/usr/bin/open", [path])
    }
}
