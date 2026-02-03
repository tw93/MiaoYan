import Cocoa
import Foundation

extension Notification.Name {
    static let editorModeChanged = Notification.Name("editorModeChanged")
    static let preferencesChanged = Notification.Name("PreferencesChanged")
    static let splitViewModeChanged = Notification.Name("SplitViewModeChanged")
    static let alwaysOnTopChanged = Notification.Name("alwaysOnTopChanged")
}
@MainActor
public enum UserDefaultsManagement {
    typealias Color = NSColor
    typealias Image = NSImage
    typealias Font = NSFont
    static var DefaultFont = "TsangerJinKai02-W04"
    static var DefaultFontSize = 16
    static var DefaultPreviewFontSize = 16
    static var DefaultPresentationFontSize = 24
    static let FullWidthValue = "Full Width"
    static var DefaultFontColor = Color(red: 0.38, green: 0.38, blue: 0.38, alpha: 1.00)
    static var DefaultBgColor = Color.white
    static var lineWidth = 1000
    static var linkColor = Color(red: 0.23, green: 0.23, blue: 0.23, alpha: 1.00)
    static var fullScreen = false
    static var isWillFullScreen = false
    static var editorLineSpacing = 3.0
    static var editorLineHeight = 1.3
    static var editorLetterSpacing = 0.5
    static var windowLetterSpacing = 0.6
    static var titleFontSize = 20
    static var emptyEditTitleFontSize = 36
    static var nameFontSize = 14
    static var searchFontSize = 14
    static var dateFontSize = 11
    static var marginSize = 24
    static var realSidebarSize = 138
    static var sidebarSize = 280
    static var isOnExport = false
    static var isOnExportPPT = false
    static var isOnExportHtml = false
    private enum Constants {
        static let AppearanceTypeKey = "appearanceType"
        static let BgColorKey = "bgColorKeyed"

        static let CodeFontNameKey = "codeFont"
        static let FontNameKey = "font"
        static let FontSizeKey = "fontsize"
        static let FontColorKey = "fontColorKeyed"
        static let FullScreen = "fullScreen"
        static let NoteType = "noteType"
        static let ImagesWidthKey = "imagesWidthKey"
        static let DefaultLanguageKey = "defaultLanguage"
        static let DefaultPicUpload = "defaultPicUpload"
        static let ImportURLsKey = "ImportURLs"
        static let LastSelectedPath = "lastSelectedPath"
        static let LastProject = "lastProject"
        static let LineSpacingEditorKey = "lineSpacingEditor"
        static let LineWidthKey = "lineWidth"
        static let MarginSizeKey = "marginSize"
        static let MarkdownPreviewCSS = "markdownPreviewCSS"
        static let PreviewFontSize = "previewFontSize"
        static let PresentationFontSize = "presentationFontSize"
        static let ProjectsKey = "projects"
        static let RestoreCursorPosition = "restoreCursorPosition"
        static let SaveInKeychain = "saveInKeychain"
        static let SortBy = "sortBy"
        static let StoragePathKey = "storageUrl"
        static let FontName = "fontName"
        static let WindowFontName = "windowFontName"
        static let PreviewFontName = "previewFontName"
        static let IsFirstLaunch = "isFirstLaunch"
        static let SortDirection = "sortDirection"
        static let IsSingleMode = "isSingleMode"
        static let SingleModePath = "singleModePath"
        static let PreviewWidth = "previewWidth"
        static let PreviewLocation = "previewLocation"
        static let EditorLineBreak = "editorLineBreak"
        static let ButtonShow = "buttonShow"
        static let NotesTableScrollPosition = "notesTableScrollPosition"
        static let AlwaysOnTop = "alwaysOnTop"
        static let HasShownImagePreviewTip = "hasShownImagePreviewTip"
        static let SplitViewMode = "splitViewMode"
        static let EditorContentSplitPosition = "editorContentSplitPosition"
        static let EditorModeKey = "editorMode"
    }

    private static func resolvedFontName(forKey key: String) -> String {
        if let stored = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !stored.isEmpty,
            NSFont(name: stored, size: 12) != nil
        {
            return stored
        }

        // Use Menlo as default for code font, otherwise use app default font
        let defaultFont = (key == Constants.CodeFontNameKey) ? "Menlo" : DefaultFont
        UserDefaults.standard.set(defaultFont, forKey: key)
        return defaultFont
    }
    static var appearanceType: AppearanceType {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.AppearanceTypeKey) as? Int {
                return AppearanceType(rawValue: result)!
            }
            return AppearanceType.System
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Constants.AppearanceTypeKey)
        }
    }
    static var lastProject: Int {
        get {
            if let lastProject = UserDefaults.standard.object(forKey: Constants.LastProject) {
                return lastProject as! Int
            } else {
                return 0
            }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.LastProject)
        }
    }
    static var defaultLanguage: Int {
        get {
            if let dl = UserDefaults.standard.object(forKey: Constants.DefaultLanguageKey) as? Int {
                return dl
            }
            guard let lang = Locale.preferredLanguages.first else { return 1 }
            if lang.hasPrefix("zh-Hans") { return 0 }
            if lang.hasPrefix("zh-Hant") { return 3 }
            if lang.hasPrefix("ja") { return 2 }
            return 1
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.DefaultLanguageKey)
        }
    }
    static var defaultPicUpload: String {
        get {
            if let dl = UserDefaults.standard.object(forKey: Constants.DefaultPicUpload) as? String {
                return dl
            }
            return "None"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.DefaultPicUpload)
        }
    }
    static var editorLineBreak: String {
        get {
            if let dl = UserDefaults.standard.object(forKey: Constants.EditorLineBreak) as? String {
                return dl
            }
            return "MiaoYan"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.EditorLineBreak)
        }
    }
    static var buttonShow: String {
        get {
            if let dl = UserDefaults.standard.object(forKey: Constants.ButtonShow) as? String {
                return dl
            }
            return "Always"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.ButtonShow)
        }
    }

    static var alwaysOnTop: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.AlwaysOnTop) as? Bool {
                return result
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.AlwaysOnTop)
        }
    }

    static var imagePreviewTipShowCount: Int {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.HasShownImagePreviewTip) as? Int {
                return result
            }
            return 0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.HasShownImagePreviewTip)
        }
    }

    static var isFirstLaunch: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.IsFirstLaunch) as? Bool {
                return result
            }
            return true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.IsFirstLaunch)
        }
    }

    static var hasFixedInitialization: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "hasFixedInitialization")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hasFixedInitialization")
        }
    }

    static var hasShownTOCTip: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "hasShownTOCTip")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hasShownTOCTip")
        }
    }

    static var isSingleMode: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.IsSingleMode) as? Bool {
                return result
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.IsSingleMode)
        }
    }
    static var singleModePath: String {
        get {
            if let dl = UserDefaults.standard.object(forKey: Constants.SingleModePath) as? String {
                return dl
            }
            return ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.SingleModePath)
        }
    }
    static var sortDirection: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.SortDirection) as? Bool {
                return result
            }
            return true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.SortDirection)
        }
    }
    static var fontSize: Int {
        get {
            if let returnFontSize = UserDefaults.standard.object(forKey: Constants.FontSizeKey) {
                return returnFontSize as! Int
            } else {
                return DefaultFontSize
            }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.FontSizeKey)
        }
    }
    static var previewWidth: String {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.PreviewWidth) as? String {
                return result
            }
            return "1000px"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.PreviewWidth)
        }
    }
    static var previewLocation: String {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.PreviewLocation) as? String {
                return result
            }
            return "Begin"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.PreviewLocation)
        }
    }
    static var previewFontSize: Int {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.PreviewFontSize) as? Int {
                return result
            }
            return DefaultPreviewFontSize
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.PreviewFontSize)
        }
    }
    static var presentationFontSize: Int {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.PresentationFontSize) as? Int {
                return result
            }
            return DefaultPresentationFontSize
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.PresentationFontSize)
        }
    }
    static var fontName: String {
        get { resolvedFontName(forKey: Constants.FontName) }
        set { UserDefaults.standard.set(newValue, forKey: Constants.FontName) }
    }
    static var windowFontName: String {
        get { resolvedFontName(forKey: Constants.WindowFontName) }
        set { UserDefaults.standard.set(newValue, forKey: Constants.WindowFontName) }
    }
    static var previewFontName: String {
        get { resolvedFontName(forKey: Constants.PreviewFontName) }
        set { UserDefaults.standard.set(newValue, forKey: Constants.PreviewFontName) }
    }
    static var codeFontName: String {
        get { resolvedFontName(forKey: Constants.CodeFontNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: Constants.CodeFontNameKey) }
    }
    static var codeFont: Font! {
        get {
            if let font = Font(name: codeFontName, size: CGFloat(fontSize)) {
                return font
            }
            return Font.systemFont(ofSize: CGFloat(fontSize))
        }
        set {
            guard let newValue = newValue else {
                return
            }
            codeFontName = newValue.fontName
            fontSize = Int(newValue.pointSize)
        }
    }
    static var noteFont: Font! {
        get {
            if let font = Font(name: fontName, size: CGFloat(fontSize)) {
                return font
            }
            return Font.systemFont(ofSize: CGFloat(fontSize))
        }
        set {
            guard let newValue = newValue else {
                return
            }
            fontName = newValue.fontName
            fontSize = Int(newValue.pointSize)
        }
    }
    static var titleFont: Font! {
        if let font = Font(name: windowFontName, size: CGFloat(titleFontSize)) {
            if windowFontName == "SF Pro Text" {
                return Font(name: "Helvetica Neue", size: CGFloat(titleFontSize))
            }
            return font
        }
        return Font.systemFont(ofSize: CGFloat(titleFontSize))
    }
    static var emptyEditTitleFont: Font! {
        if let font = Font(name: windowFontName, size: CGFloat(emptyEditTitleFontSize)) {
            return font
        }
        return Font.systemFont(ofSize: CGFloat(emptyEditTitleFontSize))
    }
    static var nameFont: Font! {
        if let font = Font(name: windowFontName, size: CGFloat(nameFontSize)) {
            return font
        }
        return Font.systemFont(ofSize: CGFloat(nameFontSize))
    }
    static var searchFont: Font! {
        if let font = Font(name: windowFontName, size: CGFloat(searchFontSize)) {
            return font
        }
        return Font.systemFont(ofSize: CGFloat(searchFontSize))
    }
    static var dateFont: Font! {
        if let font = Font(name: windowFontName, size: CGFloat(dateFontSize)) {
            return font
        }
        return Font.systemFont(ofSize: CGFloat(dateFontSize))
    }
    static var fontColor: Color {
        get {
            if let returnFontColor = UserDefaults.standard.data(forKey: Constants.FontColorKey),
                let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: Color.self, from: returnFontColor)
            {
                return color
            } else {
                return DefaultFontColor
            }
        }
        set {
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: false) {
                UserDefaults.standard.set(data, forKey: Constants.FontColorKey)
            }
        }
    }
    static var bgColor: Color {
        get {
            if let returnBgColor = UserDefaults.standard.data(forKey: Constants.BgColorKey),
                let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: Color.self, from: returnBgColor)
            {
                return color
            } else {
                return DefaultBgColor
            }
        }
        set {
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: false) {
                UserDefaults.standard.set(data, forKey: Constants.BgColorKey)
            }
        }
    }

    // Cache to avoid multiple permission dialogs
    private static var _cachedICloudURL: URL?
    private static var _iCloudURLChecked = false

    static var iCloudDocumentsContainer: URL? {
        if _iCloudURLChecked {
            return _cachedICloudURL
        }
        _iCloudURLChecked = true

        if let iCloudDocumentsURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents").resolvingSymlinksInPath() {
            if !FileManager.default.fileExists(atPath: iCloudDocumentsURL.path, isDirectory: nil) {
                do {
                    try FileManager.default.createDirectory(at: iCloudDocumentsURL, withIntermediateDirectories: true, attributes: nil)
                    _cachedICloudURL = iCloudDocumentsURL.resolvingSymlinksInPath()
                    return _cachedICloudURL
                } catch {
                    AppDelegate.trackError(error, context: "UserDefaultsManagement.iCloudDocumentsContainer creation failed")
                }
            } else {
                _cachedICloudURL = iCloudDocumentsURL.resolvingSymlinksInPath()
                return _cachedICloudURL
            }
        }
        return nil
    }

    // Cache for local Documents
    private static var _cachedLocalDocumentsURL: URL?
    private static var _localDocumentsChecked = false

    static var localDocumentsContainer: URL? {
        if _localDocumentsChecked {
            return _cachedLocalDocumentsURL
        }
        _localDocumentsChecked = true

        if let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
            let miaoyanPath: String = path + "/MiaoYan"
            try? FileManager.default.createDirectory(
                atPath: miaoyanPath,
                withIntermediateDirectories: true, attributes: nil)
            _cachedLocalDocumentsURL = URL(fileURLWithPath: miaoyanPath)
            return _cachedLocalDocumentsURL
        }
        return nil
    }
    static var storagePath: String? {
        get {
            if let storagePath = UserDefaults.standard.object(forKey: Constants.StoragePathKey) as? String {
                if FileManager.default.isWritableFile(atPath: storagePath) {
                    return storagePath
                } else {
                    let error = NSError(domain: "StorageError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Storage path not accessible, resetting to default"])
                    AppDelegate.trackError(error, context: "UserDefaultsManagement.storagePath")
                }
            }
            if let iCloudDocumentsURL = iCloudDocumentsContainer {
                return iCloudDocumentsURL.path
            }
            return localDocumentsContainer?.path
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.StoragePathKey)
        }
    }
    static var storageBookmark: Data? {
        get {
            return UserDefaults.standard.data(forKey: "StorageBookmark")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "StorageBookmark")
        }
    }

    static var storageUrl: URL? {
        if let bookmarkData = storageBookmark {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale)
                return url
            } catch {
                AppDelegate.trackError(error, context: "UserDefaultsManagement.storageUrl.resolveBookmark")
            }
        }

        if let path = storagePath {
            let expanded = NSString(string: path).expandingTildeInPath
            return URL(fileURLWithPath: expanded).resolvingSymlinksInPath()
        }

        return nil
    }
    // MARK: - Editor Mode Management
    /// Editor mode enumeration
    enum EditorMode: String, CaseIterable {
        case normal  // Normal editing mode
        case preview  // Preview mode
        case presentation  // Presentation mode
        case ppt  // PPT mode
    }
    /// Editor state manager - internal implementation
    private class EditorStateManager {
        @MainActor static let shared = EditorStateManager()
        private var _currentMode: EditorMode = .normal
        private init() {
            // Read from UserDefaults
            if let storedMode = UserDefaults.standard.string(forKey: Constants.EditorModeKey),
                let mode = EditorMode(rawValue: storedMode)
            {
                _currentMode = mode
            } else {
                _currentMode = .normal
            }
        }
        var currentMode: EditorMode {
            get { return _currentMode }
            set {
                let oldMode = _currentMode
                _currentMode = newValue

                // Save to UserDefaults
                UserDefaults.standard.set(newValue.rawValue, forKey: Constants.EditorModeKey)

                // Send mode change notification
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .editorModeChanged,
                        object: newValue,
                        userInfo: ["previousMode": oldMode]
                    )
                }
            }
        }
        var isPreviewMode: Bool { return _currentMode == .preview || _currentMode == .ppt }
        var isPresentationMode: Bool { return _currentMode == .presentation || _currentMode == .ppt }
        var isPPTMode: Bool { return _currentMode == .ppt }
        var isInSpecialMode: Bool { return _currentMode != .normal }
        var canUseMenu: Bool { return _currentMode != .presentation && _currentMode != .ppt }
        func setMode(_ mode: EditorMode) {
            currentMode = mode
        }
        func reset() {
            currentMode = .normal
        }
    }
    // Public interface - non-persistent state, reset on each startup
    static var preview: Bool {
        get {
            return EditorStateManager.shared.isPreviewMode
        }
        set {
            if newValue && !EditorStateManager.shared.isPPTMode {
                EditorStateManager.shared.setMode(.preview)
            } else if !newValue && EditorStateManager.shared.currentMode == .preview {
                EditorStateManager.shared.setMode(.normal)
            }
        }
    }
    static var presentation: Bool {
        get {
            return EditorStateManager.shared.isPresentationMode
        }
        set {
            if newValue && !EditorStateManager.shared.isPPTMode {
                EditorStateManager.shared.setMode(.presentation)
            } else if !newValue && EditorStateManager.shared.currentMode == .presentation {
                EditorStateManager.shared.setMode(.normal)
            }
        }
    }

    static var magicPPT: Bool {
        get {
            return EditorStateManager.shared.isPPTMode
        }
        set {
            EditorStateManager.shared.setMode(newValue ? .ppt : .normal)
        }
    }

    static var splitViewMode: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.SplitViewMode) as? Bool {
                return result
            }
            return false
        }
        set {
            let oldValue = splitViewMode
            guard oldValue != newValue else { return }
            UserDefaults.standard.set(newValue, forKey: Constants.SplitViewMode)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .splitViewModeChanged, object: nil)
            }
        }
    }
    static var editorContentSplitPosition: Double {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.EditorContentSplitPosition) {
                if let ratio = result as? Double {
                    return ratio
                }
                if let legacyWidth = result as? Int, legacyWidth > 0 {
                    // Old absolute width value - reset to default 50/50
                    UserDefaults.standard.removeObject(forKey: Constants.EditorContentSplitPosition)
                    return 0
                }
            }
            return 0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.EditorContentSplitPosition)
        }
    }
    // Convenience properties
    static var isInSpecialMode: Bool {
        return EditorStateManager.shared.isInSpecialMode
    }
    static var canUseMenu: Bool {
        return EditorStateManager.shared.canUseMenu
    }
    // Reset editor state
    static func resetEditorState() {
        EditorStateManager.shared.reset()
    }
    // Get current editor mode
    static var currentEditorMode: EditorMode {
        return EditorStateManager.shared.currentMode
    }
    static var lastSync: Date? {
        get {
            if let sync = UserDefaults.standard.object(forKey: "lastSync") {
                return sync as? Date
            } else {
                return nil
            }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "lastSync")
        }
    }

    static var sort: SortBy {
        get {
            if let result = UserDefaults.standard.object(forKey: "sortBy"), let sortBy = SortBy(rawValue: result as! String) {
                return sortBy
            } else {
                return .creationDate
            }
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "sortBy")
        }
    }
    static var lastSelectedURL: URL? {
        get {
            guard let path = UserDefaults.standard.object(forKey: Constants.LastSelectedPath) as? String else {
                return nil
            }
            if path.hasPrefix("file://") {
                return URL(string: path)
            }
            return URL(fileURLWithPath: path)
        }
        set {
            if let url = newValue {
                UserDefaults.standard.set(url.path, forKey: Constants.LastSelectedPath)
            } else {
                UserDefaults.standard.set(nil, forKey: Constants.LastSelectedPath)
            }
        }
    }
    static var restoreCursorPosition = true
    static var imagesWidth: Float {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.ImagesWidthKey) {
                return result as! Float
            }
            return 300
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.ImagesWidthKey)
        }
    }

    static var projects: [URL] {
        get {
            guard let defaults = UserDefaults(suiteName: "group.miaoyan-manager") else {
                return []
            }
            if let result = defaults.object(forKey: Constants.ProjectsKey) as? Data, let urls = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSURL.self], from: result) as? [URL] {
                return urls
            }
            return []
        }
        set {
            guard let defaults = UserDefaults(suiteName: "group.miaoyan-manager") else {
                return
            }
            let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: false)
            defaults.set(data, forKey: Constants.ProjectsKey)
        }
    }
    static var importURLs: [URL] {
        get {
            guard let defaults = UserDefaults(suiteName: "group.miaoyan-manager") else {
                return []
            }
            if let result = defaults.object(forKey: Constants.ImportURLsKey) as? Data,
                let urls = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSURL.self], from: result) as? [URL]
            {
                return urls
            }
            return []
        }
        set {
            guard let defaults = UserDefaults(suiteName: "group.miaoyan-manager") else {
                return
            }
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: false) {
                defaults.set(data, forKey: Constants.ImportURLsKey)
            }
        }
    }
    static var markdownPreviewCSS: URL? {
        get {
            if let path = UserDefaults.standard.object(forKey: Constants.MarkdownPreviewCSS) as? String,
                let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            {
                if FileManager.default.fileExists(atPath: path) {
                    return URL(string: "file://" + encodedPath)
                }
            }
            return nil
        }
        set {
            if let url = newValue {
                UserDefaults.standard.set(url.path, forKey: Constants.MarkdownPreviewCSS)
            } else {
                UserDefaults.standard.set(nil, forKey: Constants.MarkdownPreviewCSS)
            }
        }
    }
    private static func scrollPositionKey(for projectURL: URL?) -> String {
        projectURL?.path ?? "__all__"
    }

    static func notesTableScrollPosition(for projectURL: URL?) -> CGFloat {
        guard let stored = UserDefaults.standard.dictionary(forKey: Constants.NotesTableScrollPosition) as? [String: Double] else {
            return 0.0
        }
        let key = scrollPositionKey(for: projectURL)
        if let value = stored[key] {
            return CGFloat(value)
        }
        return 0.0
    }

    static func setNotesTableScrollPosition(_ value: CGFloat, for projectURL: URL?) {
        var stored = UserDefaults.standard.dictionary(forKey: Constants.NotesTableScrollPosition) as? [String: Double] ?? [:]
        let key = scrollPositionKey(for: projectURL)
        if value == 0 {
            stored.removeValue(forKey: key)
        } else {
            stored[key] = Double(value)
        }
        UserDefaults.standard.set(stored, forKey: Constants.NotesTableScrollPosition)
    }
}
