import Foundation

@MainActor
public class UserDataService {
    public static let instance = UserDataService()

    private var _searchTrigger = false
    private var _lastRenamed: URL?
    private var _fsUpdates = false
    private var _isNotesTableEscape = false
    private var _isDark = false

    private var _lastType: Int?
    private var _lastProject: URL?
    private var _lastName: String?

    private var _importProgress = false

    public var searchTrigger: Bool {
        get {
            _searchTrigger
        }
        set {
            _searchTrigger = newValue
        }
    }

    public var focusOnImport: URL? {
        get {
            _lastRenamed
        }
        set {
            _lastRenamed = newValue
        }
    }

    public var fsUpdatesDisabled: Bool {
        get {
            _fsUpdates
        }
        set {
            _fsUpdates = newValue
        }
    }

    public var isNotesTableEscape: Bool {
        get {
            _isNotesTableEscape
        }
        set {
            _isNotesTableEscape = newValue
        }
    }

    public var isDark: Bool {
        get {
            _isDark
        }
        set {
            _isDark = newValue
        }
    }

    public var lastType: Int? {
        get {
            _lastType
        }
        set {
            _lastType = newValue
        }
    }

    public var lastName: String? {
        get {
            _lastName
        }
        set {
            _lastName = newValue
        }
    }

    public var lastProject: URL? {
        get {
            _lastProject
        }
        set {
            _lastProject = newValue
        }
    }

    public func resetLastSidebar() {
        _lastProject = nil
        _lastType = nil
        _lastName = nil
    }

    public var skipSidebarSelection: Bool {
        get {
            _importProgress
        }
        set {
            _importProgress = newValue
        }
    }
}
