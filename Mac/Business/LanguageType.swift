import Foundation

enum LanguageType: Int {
    case Chinese = 0x00
    case English = 0x01

    var description: String {
        switch self.rawValue {
        case 0x00: return "Chinese (Simplified)"
        case 0x01: return "English"
        default: return "Chinese (Simplified)"
        }
    }

    var code: String {
        switch self.rawValue {
        case 0x00: return "zh-Hans"
        case 0x01: return "en"
        default: return "zh-Hans"
        }
    }

    static func withName(rawValue: String) -> LanguageType {
        switch rawValue {
        case "English": return LanguageType.English
        case "Chinese (Simplified)": return LanguageType.Chinese
        default: return LanguageType.Chinese
        }
    }
}
