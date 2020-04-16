public enum NoteContainer: Int {
    case none = 0x01
    case textBundle = 0x02
    case textBundleV2 = 0x03
    case encryptedTextPack = 0x04

    static func withExt(rawValue: String) -> NoteContainer {
        switch rawValue {
        case "textbundle": return .textBundleV2
        case "etp": return .encryptedTextPack
        default: return .none
        }
    }

    public var uti: String {
        switch self {
        case .textBundle: return "com.apple.package"
        case .textBundleV2: return "com.apple.package"
        case .encryptedTextPack: return "es.fsnot.etp.package"
        case .none: return ""
        }
    }

    public var tag: Int {
        switch self {
        case .textBundle: return 0x02
        case .textBundleV2: return 0x03
        case .encryptedTextPack: return 0x04
        case .none: return 0x01
        }
    }
}
