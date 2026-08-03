import Foundation

/// 다국어 문자열 조회 헬퍼. SPM 리소스 번들(Bundle.module)에서 현재 시스템 언어에 맞는
/// 문자열을 찾는다. 지원 언어: en, ko, ja, zh-Hans. 없으면 en 폴백.
func t(_ key: String, _ args: CVarArg...) -> String {
    let format = Bundle.module.localizedString(forKey: key, value: key, table: nil)
    return args.isEmpty ? format : String(format: format, arguments: args)
}
