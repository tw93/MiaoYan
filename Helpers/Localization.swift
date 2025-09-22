import Foundation

@MainActor
enum I18n {
    private static var bundle: Bundle {
        let langIndex = UserDefaultsManagement.defaultLanguage
        if let lang = LanguageType(rawValue: langIndex),
            let path = Bundle.main.path(forResource: lang.code, ofType: "lproj"),
            let b = Bundle(path: path)
        {
            return b
        }
        return .main
    }

    static func str(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: bundle, value: key, comment: "")
    }
}
