import Foundation

/// 정밀 추적(adopt)한 잡의 원래 ProgramArguments 백업. label → 원본 인자.
/// 되돌리기(revert) 때 이 값으로 plist를 복원한다.
enum AdoptStore {
    private static var fileURL: URL {
        AnnotationStore.directory.appendingPathComponent("adopted.json")
    }
    static func load() -> [String: [String]] {
        guard let d = try? Data(contentsOf: fileURL),
              let m = try? JSONDecoder().decode([String: [String]].self, from: d) else { return [:] }
        return m
    }
    static func save(_ m: [String: [String]]) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(m) { try? d.write(to: fileURL, options: .atomic) }
    }
}

/// plist를 편집해 잡 실행을 runner로 감싸거나(adopt) 원복(revert)한다. 편집 후 재로드.
enum LaunchdEdit {
    private static func readDict(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any] else { return nil }
        return dict
    }
    private static func writeDict(_ dict: [String: Any], _ path: String) -> Bool {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        else { return false }
        do { try data.write(to: URL(fileURLWithPath: path)); return true } catch { return false }
    }
    private static func reload(_ path: String) {
        let uid = getuid()
        Launchd.run("/bin/launchctl", ["bootout", "gui/\(uid)", path])
        Launchd.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", path])
    }

    /// 실행을 runner로 감쌈: ProgramArguments = [runner, run, label, --, 원본...]
    static func adopt(plistPath: String, label: String, runner: String, original: [String]) -> (Bool, String) {
        guard var dict = readDict(plistPath) else { return (false, "plist 읽기 실패") }
        dict["ProgramArguments"] = [runner, "run", label, "--"] + original
        dict["Program"] = nil   // Program 단일키가 있으면 충돌하므로 제거
        guard writeDict(dict, plistPath) else { return (false, "plist 쓰기 실패(권한?)") }
        reload(plistPath)
        return (true, "정밀 추적 켜짐")
    }

    /// 원본 인자로 복원.
    static func revert(plistPath: String, original: [String]) -> (Bool, String) {
        guard var dict = readDict(plistPath) else { return (false, "plist 읽기 실패") }
        dict["ProgramArguments"] = original
        guard writeDict(dict, plistPath) else { return (false, "plist 쓰기 실패") }
        reload(plistPath)
        return (true, "정밀 추적 꺼짐")
    }
}
