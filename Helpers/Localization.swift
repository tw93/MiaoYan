import Foundation

@MainActor
enum I18n {
    // Resolve bundle based on the user's language preference
    private static var bundle: Bundle {
        let langIndex = UserDefaultsManagement.defaultLanguage
        if let lang = LanguageType(rawValue: langIndex),
           let path = Bundle.main.path(forResource: lang.code, ofType: "lproj"),
           let b = Bundle(path: path) {
            return b
        }
        return .main
    }

    // Fetch localized string from custom bundle with key fallback
    static func str(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: bundle, value: key, comment: "")
    }
}
