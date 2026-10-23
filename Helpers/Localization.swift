import Foundation

@MainActor
enum I18n {
    #if DEBUG
        /// Lets tests render a language the language menu does not offer
        /// (Spanish follows the system language only).
        static var overrideBundle: Bundle?
    #endif

    private static var bundle: Bundle {
        #if DEBUG
            if let overrideBundle { return overrideBundle }
        #endif
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
