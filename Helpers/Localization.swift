import Foundation

enum I18n {
    // Dynamically resolve localization bundle based on user preference
    private static var bundle: Bundle {
        let langIndex = UserDefaultsManagement.defaultLanguage
        if let lang = LanguageType(rawValue: langIndex) {
            if let path = Bundle.main.path(forResource: lang.code, ofType: "lproj"),
                let b = Bundle(path: path)
            {
                return b
            }
        }
        return Bundle.main
    }

    // Localize string using custom bundle, with key as fallback if translation missing
    static func str(_ key: String) -> String {
        return NSLocalizedString(key, tableName: "Localizable", bundle: bundle, value: key, comment: "")
    }
}
