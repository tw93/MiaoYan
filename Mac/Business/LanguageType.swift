import Foundation

enum LanguageType: Int {
    case English = 0x00
    case Chinese = 0x06
    
    var description: String {
        switch self.rawValue {
        case 0x00: return "English"
        case 0x06: return "Chinese"
        default: return "Chinese"
        }
    }
    
    var code: String {
        switch self.rawValue {
        case 0x00: return "English"
        case 0x06: return "Chinese"
        default: return "Chinese"
        }
    }
    
    static func withName(rawValue: String) -> LanguageType {
        switch rawValue {
        case "English": return LanguageType.English
        case "Chinese": return LanguageType.Chinese
        default: return LanguageType.Chinese
        }
    }
}
