import Foundation

enum LanguageType: Int {
    case Chinese = 0x00
    case English = 0x01
    case Japanese = 0x02
    case ChineseTC = 0x03

    @MainActor
    var description: String {
        switch self.rawValue {
        case 0x00: return "简体中文"
        case 0x01: return "English"
        case 0x02: return "日本語"
        case 0x03: return "繁體中文"
        default: return "简体中文"
        }
    }

    var code: String {
        switch self.rawValue {
        case 0x00: return "zh-Hans"
        case 0x01: return "en"
        case 0x02: return "ja"
        case 0x03: return "zh-Hant"
        default: return "zh-Hans"
        }
    }

    @MainActor
    static func withName(rawValue: String) -> LanguageType {
        switch rawValue {
        case "English": return LanguageType.English
        case "简体中文", "Chinese (Simplified)": return LanguageType.Chinese
        case "日本語", "日语", "Japanese": return LanguageType.Japanese
        case "繁體中文", "繁体中文", "Chinese (Traditional)": return LanguageType.ChineseTC
        default: return LanguageType.Chinese
        }
    }
}
