import Foundation

// MARK: - Note Types
public enum NoteType: String, CaseIterable {
    case markdown = "md"

    public var tag: Int { 1 }
    public var uti: String { "net.daringfireball.markdown" }
    public var fileExtension: String { rawValue }
}

public enum NoteContainer: Int, CaseIterable {
    case none = 0x01

    public var uti: String { "" }
    public var tag: Int { rawValue }
}

// MARK: - UI Types
enum SidebarItemType: Int {
    case All = 0x01
    case Trash = 0x02
    case Category = 0x03
}

public enum AppearanceType: Int {
    case System = 0x00
    case Light = 0x01
    case Dark = 0x02
    case Custom = 0x03
}

// MARK: - Sorting Types
public enum SortDirection: String {
    case asc
    case desc
}

public enum SortBy: String {
    case none
    case modificationDate
    case creationDate
    case title
}

// MARK: - Attribute Types
enum NoteAttribute {
    static let highlight = NSAttributedString.Key(rawValue: "com.tw93.search.highlight")

    static let all = Set<NSAttributedString.Key>([
        highlight
    ])
}

extension NSAttributedString.Key {
    public static var todo: NSAttributedString.Key {
        NSAttributedString.Key(rawValue: AppIdentifier.todoKey)
    }

    public static var codeBlock: NSAttributedString.Key {
        NSAttributedString.Key(rawValue: AppIdentifier.codeBlockKey)
    }

    public static var codeLanguage: NSAttributedString.Key {
        NSAttributedString.Key(rawValue: AppIdentifier.codeLanguageKey)
    }
}

// MARK: - Configuration Types
struct KeychainConfiguration {
    static let serviceName = "MiaoYanApp"
    static let accessGroup: String? = nil
}
