import Foundation

/// plist(라벨 + 실행 명령)에서 "사람이 읽는 이름 / 종류 / 태그"를 규칙 기반으로 추론.
/// AI가 아니라 결정적 규칙 — 사용자 주석의 "초깃값"을 만들어 주는 역할 (덮어쓰지 않음).
/// 나중에 Phase 3에서 claude/codex provider가 이 자리를 더 똑똑하게 대체할 수 있다.
enum Inference {

    static let interpreters: Set<String> =
        ["sh", "bash", "zsh", "fish", "env", "node", "deno", "bun",
         "python", "python3", "ruby", "perl", "osascript", "php"]

    // MARK: - 표시 이름

    static func displayName(for job: LaunchJob) -> String {
        if let script = scriptBase(job.programArguments) {
            return prettify(script)
        }
        return prettify(lastLabelComponent(job.label))
    }

    /// 실행 인자에서 "의미 있는" 스크립트/바이너리 이름을 뽑는다 (인터프리터·플래그 건너뜀).
    private static func scriptBase(_ args: [String]) -> String? {
        for arg in args {
            if arg.hasPrefix("-") { continue }
            let base = (arg as NSString).lastPathComponent
            let name = (base as NSString).deletingPathExtension
            if name.isEmpty || interpreters.contains(name.lowercased()) { continue }
            if arg.contains("/") || base.contains(".") { return name }  // 경로/스크립트로 보임
        }
        if let first = args.first {
            let name = ((first as NSString).lastPathComponent as NSString).deletingPathExtension
            if !name.isEmpty && !interpreters.contains(name.lowercased()) { return name }
        }
        return nil
    }

    private static func lastLabelComponent(_ label: String) -> String {
        label.split(separator: ".").last.map(String.init) ?? label
    }

    /// "turbo-cache-cleanup" → "Turbo Cache Cleanup", "sync_notion" → "Sync Notion"
    static func prettify(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        let words = cleaned.split(separator: " ").map { w -> String in
            let s = String(w)
            if s.count <= 3, s == s.uppercased() { return s }  // DB, API 같은 약어 보존
            return s.prefix(1).uppercased() + s.dropFirst()
        }
        let result = words.joined(separator: " ")
        return result.isEmpty ? raw : result
    }

    // MARK: - 종류 (아이콘 + 태그 후보)

    struct Category { let name: String; let icon: String }

    static func category(for job: LaunchJob) -> Category {
        let cmd = job.programArguments.joined(separator: " ").lowercased()
        func has(_ needles: String...) -> Bool { needles.contains { cmd.contains($0) } }

        // AI를 먼저 — claude가 /opt/homebrew/bin/claude 처럼 "homebrew" 경로에 있어 오분류되지 않게
        if has("claude", "codex", "ollama", "llm") { return Category(name: "AI", icon: "sparkles") }
        if has("rsync", "tmutil", "restic", "borg", "backup") { return Category(name: "Backup", icon: "externaldrive.fill") }
        if has("brew ", "/brew") { return Category(name: "Homebrew", icon: "cup.and.saucer.fill") }  // homebrew 경로 오탐 방지
        if has("docker", "colima", "podman") { return Category(name: "Docker", icon: "shippingbox.fill") }
        if has("git ", "/git") { return Category(name: "Git", icon: "arrow.triangle.branch") }
        if has("node", ".js", ".mjs", ".ts", "pnpm", "npm", "yarn") { return Category(name: "Node.js", icon: "hexagon.fill") }
        if has("python", ".py", "pip") { return Category(name: "Python", icon: "chevron.left.forwardslash.chevron.right") }
        if has("ruby", ".rb") { return Category(name: "Ruby", icon: "diamond.fill") }
        if has("osascript", ".scpt") { return Category(name: "AppleScript", icon: "applescript.fill") }
        if has("/sh", "/bash", "/zsh", ".sh", "/env") { return Category(name: "Shell", icon: "terminal.fill") }
        return Category(name: "Job", icon: "gearshape.fill")
    }

    /// 편집기 열 때 미리 채울 태그 후보 (종류 기반).
    static func suggestedTags(for job: LaunchJob) -> [String] {
        [category(for: job).name]
    }

    // MARK: - 대략적 설명 ("무슨 일을 하는가" — 규칙 기반. Phase 3에서 AI가 대체)

    // 동작(동사) — 우선순위 순. 토큰이 매칭되면 해당 지역화 동사 사용.
    private static let verbs: [(key: String, toks: [String])] = [
        ("verb.clean",   ["clean", "cleanup", "cleaner", "clear", "prune", "purge", "gc", "vacuum"]),
        ("verb.backup",  ["backup", "snapshot", "dump"]),
        ("verb.sync",    ["sync", "mirror"]),
        ("verb.deploy",  ["deploy", "release", "publish", "ship"]),
        ("verb.build",   ["build", "compile", "bundle"]),
        ("verb.update",  ["update", "upgrade", "refresh", "renew"]),
        ("verb.fetch",   ["fetch", "pull", "download", "crawl", "scrape", "import", "collect", "gather", "aggregate"]),
        ("verb.upload",  ["upload", "push", "export", "send"]),
        ("verb.notify",  ["notify", "alert", "report", "email", "mail", "digest", "summary", "summarize"]),
        ("verb.monitor", ["monitor", "watch", "healthcheck", "ping", "check", "status"]),
        ("verb.archive", ["archive", "compress", "zip", "rotate"]),
        ("verb.restart", ["restart", "reload", "reboot", "start", "launch"]),
        ("verb.test",    ["test", "lint"]),
        ("verb.index",   ["index", "reindex"]),
    ]

    // 대상(명사)
    private static let nouns: [(key: String, toks: [String])] = [
        ("noun.cache",  ["cache", "caches"]),
        ("noun.log",    ["log", "logs"]),
        ("noun.db",     ["db", "database", "sql", "postgres", "mysql", "mongo", "sqlite", "redis"]),
        ("noun.image",  ["image", "images", "img", "photo", "thumbnail", "thumb"]),
        ("noun.dep",    ["deps", "dependencies", "modules"]),
        ("noun.cert",   ["cert", "certs", "ssl", "tls", "certificate"]),
        ("noun.file",   ["file", "files", "temp", "tmp"]),
        ("noun.data",   ["data", "dataset"]),
        ("noun.report", ["report", "digest"]),
    ]

    // 고유명사 — 번역하지 않고 예쁘게만
    private static let propers: [String: String] = [
        "turbo": "Turborepo", "turborepo": "Turborepo", "notion": "Notion",
        "slack": "Slack", "github": "GitHub", "gitlab": "GitLab", "git": "Git",
        "s3": "S3", "aws": "AWS", "gcp": "GCP", "docker": "Docker",
        "vercel": "Vercel", "npm": "npm", "pnpm": "pnpm", "brew": "Homebrew",
    ]

    static func description(for job: LaunchJob) -> String {
        // 1순위: 스크립트 헤더 주석에서 읽은 실제 목적
        if let summary = job.scriptSummary, !summary.isEmpty { return summary }

        let tokens = tokenize(job)

        // 대상: 고유명사/명사를 등장 순으로 최대 2개
        var objectParts: [String] = []
        for tok in tokens {
            if let proper = propers[tok] {
                if !objectParts.contains(proper) { objectParts.append(proper) }
            } else if let key = nouns.first(where: { $0.toks.contains(tok) })?.key {
                let word = t(key)
                if !objectParts.contains(word) { objectParts.append(word) }
            }
            if objectParts.count >= 2 { break }
        }

        // 동작: 처음 매칭되는 동사
        let verbWord = tokens.compactMap { tok in
            verbs.first(where: { $0.toks.contains(tok) })?.key
        }.first.map { t($0) }

        let objectStr = objectParts.joined(separator: " ")

        switch (verbWord, objectStr.isEmpty) {
        case let (.some(v), false): return t("desc.compose", objectStr, v)  // 대상 + 동작
        case let (.some(v), true):  return v                                 // 동작만
        case (.none, false):        return t("desc.objectOnly", objectStr)   // 대상 관리
        case (.none, true):         return t("desc.generic", category(for: job).name)
        }
    }

    /// 라벨 마지막 요소 + 스크립트명 + 전체 명령을 소문자 토큰으로.
    private static func tokenize(_ job: LaunchJob) -> [String] {
        let raw = [lastLabelComponent(job.label),
                   scriptBase(job.programArguments) ?? "",
                   job.programArguments.joined(separator: " ")]
            .joined(separator: " ")
            .lowercased()
        return raw.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
