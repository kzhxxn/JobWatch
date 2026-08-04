import Foundation

/// jobwatch-runner를 앱 번들에서 안정 경로로 설치.
/// plist가 이 안정 경로를 참조하므로, 앱을 옮겨도 등록된 잡이 깨지지 않는다.
enum RunnerInstall {
    static var installedPath: String {
        AnnotationStore.directory.appendingPathComponent("bin/jobwatch-runner").path
    }

    private static var bundledPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/jobwatch-runner").path
    }

    @discardableResult
    static func installIfNeeded() -> Bool {
        let fm = FileManager.default
        let src = bundledPath, dest = installedPath
        guard fm.fileExists(atPath: src) else { return false }
        try? fm.createDirectory(atPath: (dest as NSString).deletingLastPathComponent,
                                withIntermediateDirectories: true)
        let srcDate = (try? fm.attributesOfItem(atPath: src))?[.modificationDate] as? Date
        let destDate = (try? fm.attributesOfItem(atPath: dest))?[.modificationDate] as? Date
        let needsCopy = !fm.fileExists(atPath: dest)
            || (srcDate != nil && destDate != nil && srcDate! > destDate!)
        if needsCopy {
            try? fm.removeItem(atPath: dest)
            do {
                try fm.copyItem(atPath: src, toPath: dest)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest)
            } catch { return false }
        }
        return fm.fileExists(atPath: dest)
    }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: installedPath) }
}
