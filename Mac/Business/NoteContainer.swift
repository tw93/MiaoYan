public enum NoteContainer: Int {
    case none = 0x01
    case textBundle = 0x02
    case textBundleV2 = 0x03

    static func withExt(rawValue: String) -> NoteContainer {
        switch rawValue {
        case "textbundle": return .textBundleV2
        default: return .none
        }
    }

    public var uti: String {
        switch self {
        case .textBundle: return "com.apple.package"
        case .textBundleV2: return "com.apple.package"
        case .none: return ""
        }
    }

    public var tag: Int {
        switch self {
        case .textBundle: return 0x02
        case .textBundleV2: return 0x03
        case .none: return 0x01
        }
    }
}
