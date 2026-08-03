import Foundation

/// 사용자가 잡에 직접 붙이는 메타데이터. launchd에는 없는 "사람용" 정보.
/// Observed 잡(남이 만든 것)도 여기에 별명·설명을 달 수 있어 세션이 끝나도 남는다.
struct JobAnnotation: Codable, Sendable, Hashable {
    var displayName: String = ""
    var note: String = ""
    var tags: [String] = []

    var isEmpty: Bool { displayName.isEmpty && note.isEmpty && tags.isEmpty }
}

/// annotations.json 읽기/쓰기. 파일이 작아 동기 I/O로 충분.
/// 위치: ~/Library/Application Support/JobWatch/annotations.json
enum AnnotationStore {
    static var directory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JobWatch", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static var fileURL: URL {
        directory.appendingPathComponent("annotations.json")
    }

    static func load() -> [String: JobAnnotation] {
        guard let data = try? Data(contentsOf: fileURL),
              let map = try? JSONDecoder().decode([String: JobAnnotation].self, from: data)
        else { return [:] }
        return map
    }

    static func save(_ map: [String: JobAnnotation]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(map) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
