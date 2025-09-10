import Foundation

public enum NoteType: String {
    case Markdown = "md"
    case RichText = "rtf"
    case PlainText = "txt"

    static func withExt(rawValue: String) -> NoteType {
        switch rawValue {
        case "markdown", "md", "mkd", "txt": return NoteType.Markdown
        case "rtf": return NoteType.RichText
        default: return NoteType.PlainText
        }
    }

    static func withTag(rawValue: Int) -> NoteType {
        switch rawValue {
        case 1: return .Markdown
        case 2: return .RichText
        case 3: return .PlainText
        default: return .Markdown
        }
    }

    static func withUTI(rawValue: String) -> NoteType {
        switch rawValue {
        case "net.daringfireball.markdown": return .Markdown
        case "public.rtf": return .RichText
        case "public.plain-text": return .PlainText
        default: return .Markdown
        }
    }

    public var tag: Int {
        switch self {
        case .Markdown: return 1
        case .RichText: return 2
        case .PlainText: return 3
        }
    }

    public var uti: String {
        switch self {
        case .Markdown: return "net.daringfireball.markdown"
        case .RichText: return "public.rtf"
        case .PlainText: return "public.plain-text"
        }
    }

    public func getExtension(for container: NoteContainer) -> String {
        switch self {
        case .Markdown:
            if container == .textBundle || container == .none {
                return "md"
            }
            return "markdown"
        case .RichText: return "rtf"
        case .PlainText: return "txt"
        }
    }
}
