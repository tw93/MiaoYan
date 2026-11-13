import Cocoa

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
    /// The MiaoYan lockup at the top of the sidebar, a mark rather than a
    /// place: it cannot be selected, and All Notes sits under it.
    case Brand = 0x04
    /// Files opened from Finder that live outside the library, listed while
    /// the app runs so opening one no longer swaps the library away. The row
    /// shows only when such a file is open, just above the Trash.
    case Opened = 0x05
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
    static let autoLink = NSAttributedString.Key(rawValue: "com.tw93.link.autodetected")

    static let all = Set<NSAttributedString.Key>([
        highlight,
        autoLink,
    ])
}

extension NSAttributedString.Key {
    public static var codeBlock: NSAttributedString.Key {
        NSAttributedString.Key(rawValue: AppIdentifier.codeBlockKey)
    }

    public static var codeLanguage: NSAttributedString.Key {
        NSAttributedString.Key(rawValue: AppIdentifier.codeLanguageKey)
    }
}

// MARK: - Utility Types

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
}

@MainActor
final class EditorSessionState {
    var preview: Bool {
        get { UserDefaultsManagement.preview }
        set { UserDefaultsManagement.preview = newValue }
    }

    var presentation: Bool {
        get { UserDefaultsManagement.presentation }
        set { UserDefaultsManagement.presentation = newValue }
    }

    var magicPPT: Bool {
        get { UserDefaultsManagement.magicPPT }
        set { UserDefaultsManagement.magicPPT = newValue }
    }

    var splitViewMode: Bool {
        get { UserDefaultsManagement.splitViewMode }
        set { UserDefaultsManagement.splitViewMode = newValue }
    }

    var isOnExport: Bool {
        get { UserDefaultsManagement.isOnExport }
        set { UserDefaultsManagement.isOnExport = newValue }
    }

    var isOnExportPPT: Bool {
        get { UserDefaultsManagement.isOnExportPPT }
        set { UserDefaultsManagement.isOnExportPPT = newValue }
    }

    var isOnExportHtml: Bool {
        get { UserDefaultsManagement.isOnExportHtml }
        set { UserDefaultsManagement.isOnExportHtml = newValue }
    }

    var fullScreen: Bool {
        get { UserDefaultsManagement.fullScreen }
        set { UserDefaultsManagement.fullScreen = newValue }
    }

    var isWillFullScreen: Bool {
        get { UserDefaultsManagement.isWillFullScreen }
        set { UserDefaultsManagement.isWillFullScreen = newValue }
    }

    var shouldShowPreview: Bool {
        preview || magicPPT || presentation || splitViewMode
    }
}

@MainActor
final class AppContext {
    static let shared = AppContext()

    let storage: Storage
    let sessionState: EditorSessionState
    weak var viewController: ViewController?

    private init() {
        storage = Storage.sharedInstance()
        sessionState = EditorSessionState()
    }

    func bind(viewController: ViewController?) {
        self.viewController = viewController
    }
}
