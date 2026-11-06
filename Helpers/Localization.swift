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

    /// "Words: 12", with the full-width colon Chinese and Japanese use
    /// (the "%@: %@" key is "%@：%@" there).
    static func labeled(_ key: String, _ value: String) -> String {
        String(format: str("%@: %@"), str(key), value)
    }

    /// A counted string. English and Spanish take their singular and plural
    /// from Localizable.stringsdict (`1 note`, `2 notes`); the other
    /// languages have one form and read the .strings value.
    static func count(_ key: String, _ n: Int) -> String {
        String.localizedStringWithFormat(str(key), n)
    }
}
