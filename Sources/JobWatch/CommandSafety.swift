import Foundation

/// 잡 명령의 위험 신호를 규칙 기반으로 감지. AI/수동 생성 명령을 등록 전 검사한다.
/// "차단"이 아니라 "경고" — 사용자가 인지하고 진행하도록 (human-in-the-loop).
enum CommandSafety {
    struct Warning: Identifiable, Sendable {
        let id = UUID()
        let reason: String
    }

    /// 위험 패턴 → 사유. 소문자 명령 문자열에서 검사.
    private static let rules: [(needles: [String], reasonKey: String)] = [
        (["sudo "],                              "danger.sudo"),
        (["rm -rf", "rm -fr", "rm  -rf"],        "danger.rmrf"),
        (["mkfs", "diskutil erase", "dd if=", " of=/dev/"], "danger.disk"),
        (["curl", "wget"],                       "danger.remoteFetch"),   // 원격 다운로드
        ([":(){", "fork bomb"],                  "danger.forkbomb"),
        (["--dangerously-skip-permissions", "--dangerously-bypass"], "danger.bypass"),
        (["/dev/tcp/", "nc -e", "ncat -e", "bash -i"], "danger.reverseShell"),
        (["keychain", "security dump", "security find-generic"], "danger.keychain"),
        (["> /etc/", ">/etc/", "chmod 777", "chown "], "danger.systemWrite"),
    ]

    /// 원격 다운로드를 바로 실행하는 파이프(curl … | sh) — 특히 위험.
    private static func pipesRemoteToShell(_ c: String) -> Bool {
        let fetched = c.contains("curl") || c.contains("wget")
        let piped = c.contains("| sh") || c.contains("|sh") || c.contains("| bash") || c.contains("|bash")
        return fetched && piped
    }

    static func warnings(for command: String) -> [Warning] {
        let c = command.lowercased()
        var out: [Warning] = []
        for rule in rules where rule.needles.contains(where: { c.contains($0) }) {
            out.append(Warning(reason: rule.reasonKey))
        }
        if pipesRemoteToShell(c) {
            out.append(Warning(reason: "danger.pipeToShell"))
        }
        // 중복 사유 제거
        var seen = Set<String>()
        return out.filter { seen.insert($0.reason).inserted }
    }

    static func isRisky(_ command: String) -> Bool { !warnings(for: command).isEmpty }
}
