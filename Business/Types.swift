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

// MARK: - Utility Types
class UndoData: NSObject {
    let string: NSAttributedString
    let range: NSRange

    init(string: NSAttributedString, range: NSRange) {
        self.string = string
        self.range = range
    }
}

struct RuntimeError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    public var localizedDescription: String {
        message
    }
}

class IndexSetWrapper: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool {
        true
    }

    let indexSet: IndexSet

    init(indexSet: IndexSet) {
        self.indexSet = indexSet
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
        guard let intArray = aDecoder.decodeObject(of: NSArray.self, forKey: "indexSet") as? [Int] else {
            return nil
        }
        self.indexSet = IndexSet(intArray)
        super.init()
    }

    func encode(with aCoder: NSCoder) {
        let intArray = indexSet.map { $0 }
        aCoder.encode(intArray, forKey: "indexSet")
    }
}

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

class Commit {
    private var date: String?
    private var hash: String

    init(hash: String) {
        self.hash = hash
    }

    public func setDate(date: String) {
        self.date = date
    }

    public func getDate() -> String? {
        date
    }

    public func getHash() -> String {
        hash
    }
}

@MainActor
final class EditorSessionState {
    private var _preview = false
    private var _presentation = false
    private var _magicPPT = false
    private var _splitViewMode = false
    private var _isOnExport = false
    private var _isOnExportPPT = false
    private var _isOnExportHtml = false
    private var _fullScreen = false
    private var _isWillFullScreen = false

    init() {
        syncFromUserDefaults()
    }

    var preview: Bool {
        get { _preview }
        set {
            _preview = newValue
            UserDefaultsManagement.preview = newValue
        }
    }

    var presentation: Bool {
        get { _presentation }
        set {
            _presentation = newValue
            UserDefaultsManagement.presentation = newValue
        }
    }

    var magicPPT: Bool {
        get { _magicPPT }
        set {
            _magicPPT = newValue
            UserDefaultsManagement.magicPPT = newValue
        }
    }

    var splitViewMode: Bool {
        get { _splitViewMode }
        set {
            _splitViewMode = newValue
            UserDefaultsManagement.splitViewMode = newValue
        }
    }

    var isOnExport: Bool {
        get { _isOnExport }
        set {
            _isOnExport = newValue
            UserDefaultsManagement.isOnExport = newValue
        }
    }

    var isOnExportPPT: Bool {
        get { _isOnExportPPT }
        set {
            _isOnExportPPT = newValue
            UserDefaultsManagement.isOnExportPPT = newValue
        }
    }

    var isOnExportHtml: Bool {
        get { _isOnExportHtml }
        set {
            _isOnExportHtml = newValue
            UserDefaultsManagement.isOnExportHtml = newValue
        }
    }

    var fullScreen: Bool {
        get { _fullScreen }
        set {
            _fullScreen = newValue
            UserDefaultsManagement.fullScreen = newValue
        }
    }

    var isWillFullScreen: Bool {
        get { _isWillFullScreen }
        set {
            _isWillFullScreen = newValue
            UserDefaultsManagement.isWillFullScreen = newValue
        }
    }

    var shouldShowPreview: Bool {
        preview || magicPPT || presentation || splitViewMode
    }

    func syncFromUserDefaults() {
        _preview = UserDefaultsManagement.preview
        _presentation = UserDefaultsManagement.presentation
        _magicPPT = UserDefaultsManagement.magicPPT
        _splitViewMode = UserDefaultsManagement.splitViewMode
        _isOnExport = UserDefaultsManagement.isOnExport
        _isOnExportPPT = UserDefaultsManagement.isOnExportPPT
        _isOnExportHtml = UserDefaultsManagement.isOnExportHtml
        _fullScreen = UserDefaultsManagement.fullScreen
        _isWillFullScreen = UserDefaultsManagement.isWillFullScreen
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
