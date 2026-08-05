import Foundation

/// AI가 만든 잡 초안.
struct AIJobDraft: Sendable {
    var name: String
    var command: String
    var schedule: JobSchedule
}

enum AIResult: Sendable {
    case ok(AIJobDraft)
    case fail(String)
}

/// 설치된 claude / codex CLI를 감지하고, 자연어 → 잡 스펙(JSON)으로 변환.
/// 출력은 "제안"일 뿐 — 사용자가 폼에서 확인 후 생성한다 (human-in-the-loop).
enum AIProvider {
    /// 로그인 셸로 PATH를 로드해 CLI 경로를 찾는다.
    static func path(_ name: String) -> String? {
        let (out, status) = shell("/bin/zsh", ["-lc", "command -v \(name)"], env: nil)
        let p = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return (status == 0 && !p.isEmpty && FileManager.default.isExecutableFile(atPath: p)) ? p : nil
    }

    /// 사용 가능한 provider 표시 이름 (claude 우선).
    static func available() -> String? {
        if path("claude") != nil { return "Claude Code" }
        if path("codex") != nil { return "Codex" }
        return nil
    }

    static func generate(request: String) -> AIResult {
        let cliPath: String, cmdName: String
        if let c = path("claude") { cliPath = c; cmdName = "claude" }
        else if let c = path("codex") { cliPath = c; cmdName = "codex" }
        else { return .fail("claude 또는 codex CLI가 필요합니다") }

        let prompt = promptText(request, cliPath: cliPath, cmdName: cmdName)
        let invokeArgs = cmdName == "claude" ? ["-p", prompt] : ["exec", prompt]
        let (out, status) = runProvider(cliPath, invokeArgs)
        guard status == 0 else {
            // 실제 에러(로그인 필요 등)를 그대로 노출 → 별도 검증 UI 불필요
            let snip = out.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)
            return .fail("\(cmdName) 실행 실패 (로그인 상태 확인): \(snip)")
        }
        return parse(out)
    }

    private static func promptText(_ req: String, cliPath: String, cmdName: String) -> String {
        // 헤드리스에서 실제 동작하도록 도구 권한을 미리 부여 (claude는 -p에서 도구가 기본 차단됨)
        let invoke = cmdName == "claude"
            ? "\(cliPath) --allowedTools \"WebSearch WebFetch Bash\" -p"
            : "\(cliPath) exec"
        return """
        You are a macOS launchd job generator. Output ONLY one JSON object, no prose, no code fences:
        {"name":"short name","command":"one shell command line","schedule":{"type":"interval|daily|weekly","minutes":60,"hour":9,"minute":0,"weekday":1}}
        The command runs via /bin/sh -c on a schedule under launchd (which has a minimal PATH).
        RULES:
        - Deterministic tasks (delete/backup/run a script/log something): emit a plain shell command with absolute paths or ~.
        - Tasks needing LIVE info, web lookup, judgment, or summarization (e.g. "check", "monitor", \
        "summarize", "find", "analyze", "notify me if ..."): do NOT emit a static reminder. Instead \
        invoke the local AI agent to actually do it. Use EXACTLY this invocation form so it has the \
        tool permissions to run headless: `\(invoke) "<clear instruction to fetch/check and, if \
        noteworthy, run osascript to show a macOS notification>"`.
        - Whenever the command uses any CLI, prefix the whole command with: PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
        weekday: 0=Sunday..6=Saturday. Output JSON only.
        Request: \(req)
        """
    }

    private static func parse(_ output: String) -> AIResult {
        guard let s = output.firstIndex(of: "{"), let e = output.lastIndex(of: "}") else {
            return .fail("AI 응답에서 JSON을 찾지 못함")
        }
        struct D: Codable {
            let name: String; let command: String; let schedule: S
            struct S: Codable {
                let type: String
                let minutes: Int?; let hour: Int?; let minute: Int?; let weekday: Int?
            }
        }
        guard let data = String(output[s...e]).data(using: .utf8),
              let d = try? JSONDecoder().decode(D.self, from: data) else {
            return .fail("AI 응답 JSON 파싱 실패")
        }
        let sched: JobSchedule
        switch d.schedule.type {
        case "daily":  sched = .daily(hour: d.schedule.hour ?? 9, minute: d.schedule.minute ?? 0)
        case "weekly": sched = .weekly(weekday: d.schedule.weekday ?? 1,
                                       hour: d.schedule.hour ?? 9, minute: d.schedule.minute ?? 0)
        default:       sched = .interval(minutes: d.schedule.minutes ?? 60)
        }
        return .ok(AIJobDraft(name: d.name, command: d.command, schedule: sched))
    }

    /// 기존 환경을 물려받고 PATH만 보강 (claude/codex가 자기 런타임·설정을 찾도록).
    private static func runProvider(_ launchPath: String, _ args: [String]) -> (String, Int32) {
        var env = ProcessInfo.processInfo.environment
        let binDir = (launchPath as NSString).deletingLastPathComponent
        env["PATH"] = "\(binDir):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        return shell(launchPath, args, env: env)
    }

    private static func shell(_ launchPath: String, _ args: [String], env: [String: String]?) -> (String, Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        if let env { p.environment = env }
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return ("실행 실패: \(error.localizedDescription)", -1) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "", p.terminationStatus)
    }
}
