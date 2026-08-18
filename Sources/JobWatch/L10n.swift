import Foundation

private final class BundleFinder {}

/// 리소스 번들을 방어적으로 탐색. SPM의 Bundle.module은 못 찾으면 fatalError로 죽지만
/// (.app 패키징이 조금만 어긋나도 크래시), 이건 못 찾으면 nil을 반환해 앱이 죽지 않는다.
private let resourceBundle: Bundle? = {
    let name = "JobWatch_JobWatch.bundle"
    var candidates: [URL] = []
    if let r = Bundle.main.resourceURL { candidates.append(r) }
    candidates.append(Bundle.main.bundleURL)
    candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS"))
    candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"))
    if let r = Bundle(for: BundleFinder.self).resourceURL { candidates.append(r) }
    candidates.append(Bundle(for: BundleFinder.self).bundleURL.deletingLastPathComponent())
    for base in candidates {
        if let b = Bundle(url: base.appendingPathComponent(name)) { return b }
    }
    return nil
}()

/// 다국어 문자열 조회. 지원 언어: en, ko, ja, zh-Hans (없으면 en 폴백).
/// 리소스 번들을 못 찾아도 크래시하지 않고 키 문자열을 그대로 반환한다.
func t(_ key: String, _ args: CVarArg...) -> String {
    let format = (resourceBundle ?? .main).localizedString(forKey: key, value: key, table: nil)
    return args.isEmpty ? format : String(format: format, arguments: args)
}
