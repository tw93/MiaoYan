import Foundation

@MainActor
enum I18n {
    // 根据用户偏好动态选择 bundle
    private static var bundle: Bundle {
        let langIndex = UserDefaultsManagement.defaultLanguage
        if let lang = LanguageType(rawValue: langIndex),
           let path = Bundle.main.path(forResource: lang.code, ofType: "lproj"),
           let b = Bundle(path: path) {
            return b
        }
        return .main
    }

    // 使用自定义 bundle 取文案，没有就回退到 key
    static func str(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: bundle, value: key, comment: "")
    }
}
