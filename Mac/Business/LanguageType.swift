import Foundation

enum LanguageType: Int {
    case English = 0x00
    case Chinese = 0x06
    
    var description: String {
        switch self.rawValue {
        case 0x00: return "English"
        case 0x06: return "Chinese (Simplified)"
        default: return ""
        }
    }
    
    var code: String {
        switch self.rawValue {
        case 0x00: return "en"
        case 0x06: return "zh-Hans"
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
