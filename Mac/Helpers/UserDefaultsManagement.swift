import Foundation

#if os(OSX)
    import Cocoa
#else
    import UIKit
#endif

public class UserDefaultsManagement {
    #if os(OSX)
        typealias Color = NSColor
        typealias Image = NSImage
        typealias Font = NSFont
    #else
        typealias Color = UIColor
        typealias Image = UIImage
        typealias Font = UIFont
    #endif

    static var DefaultFont = "LXGW WenKai Lite"

    static var DefaultFontSize = 15
    static var editorLineSpacing = 6

    static var DefaultFontColor = Color(red: 0.38, green: 0.38, blue: 0.38, alpha: 1.00)
    static var DefaultBgColor = Color.white

    static var codeFontName = DefaultFont
    static var lineWidth = 1000
    static var linkColor = Color(red: 0.23, green: 0.23, blue: 0.23, alpha: 1.00)
    static var fullScreen = false

    static var titleFontSize = 20
    static var emptyEditTitleFontSize = 36
    static var nameFontSize = 14
    static var dateFontSize = 11
    static var maxNightModeBrightnessLevel = 35

    static var sortDirection = true
    static var marginSize = 26
    static var realSidebarSize = 120

    private enum Constants {
        static let AppearanceTypeKey = "appearanceType"
        static let BgColorKey = "bgColorKeyed"
        static let CellFrameOriginY = "cellFrameOriginY"
        static let CodeFontNameKey = "codeFont"
        static let codeTheme = "codeTheme"
        static let FontNameKey = "font"
        static let FontSizeKey = "fontsize"
        static let FontColorKey = "fontColorKeyed"
        static let FullScreen = "fullScreen"
        static let NoteType = "noteType"
        static let ImagesWidthKey = "imagesWidthKey"
        static let DefaultLanguageKey = "defaultLanguage"
        static let ImportURLsKey = "ImportURLs"
        static let LastSelectedPath = "lastSelectedPath"
        static let LastProject = "lastProject"
        static let LineSpacingEditorKey = "lineSpacingEditor"
        static let LineWidthKey = "lineWidth"
        static let MarginSizeKey = "marginSize"
        static let MarkdownPreviewCSS = "markdownPreviewCSS"
        static let NightModeType = "nightModeType"
        static let NightModeAuto = "nightModeAuto"
        static let NightModeBrightnessLevel = "nightModeBrightnessLevel"
        static let NoteContainer = "noteContainer"
        static let LiveImagesPreview = "liveImagesPreview"
        static let PinListKey = "pinList"
        static let Preview = "preview"
        static let PreviewFontSize = "previewFontSize"
        static let ProjectsKey = "projects"
        static let RestoreCursorPosition = "restoreCursorPosition"
        static let SaveInKeychain = "saveInKeychain"
        static let SharedContainerKey = "sharedContainer"
        static let SortBy = "sortBy"
        static let StoragePathKey = "storageUrl"
        static let TextMatchAutoSelection = "textMatchAutoSelection"
        static let FontName = "fontName"
        static let WindowFontName = "windowFontName"
        static let PreviewFontName = "previewFontName"
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
            return 0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.DefaultLanguageKey)
        }
    }
    
    static var liveImagesPreview: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.LiveImagesPreview) {
                return result as! Bool
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.LiveImagesPreview)
        }
    }

    static var fontSize: Int {
        get {
            #if os(iOS)
                if UserDefaultsManagement.dynamicTypeFont {
                    return self.DefaultFontSize
                }
            #endif

            if let returnFontSize = UserDefaults.standard.object(forKey: Constants.FontSizeKey) {
                return returnFontSize as! Int
            } else {
                return self.DefaultFontSize
            }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.FontSizeKey)
        }
    }
    
    static var previewFontSize: Int {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.PreviewFontSize) as? Int {
                return result
            }
            return DefaultFontSize
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.PreviewFontSize)
        }
    }

    static var fontName: String {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.FontName) as? String {
                return result
            }
            return DefaultFont
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.FontName)
        }
    }
    
    static var windowFontName: String {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.WindowFontName) as? String {
                return result
            }
            return DefaultFont
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.WindowFontName)
        }
    }
    
    static var previewFontName: String {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.PreviewFontName) as? String {
                return result
            }
            return DefaultFont
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.PreviewFontName)
        }
    }
    
    static var codeFont: Font! {
        get {
            if let font = Font(name: self.codeFontName, size: CGFloat(self.fontSize)) {
                return font
            }

            return Font.systemFont(ofSize: CGFloat(self.fontSize))
        }
        set {
            guard let newValue = newValue else { return }

            self.codeFontName = newValue.fontName
            self.fontSize = Int(newValue.pointSize)
        }
    }

    static var noteFont: Font! {
        get {
            if let font = Font(name: self.fontName, size: CGFloat(self.fontSize)) {
                return font
            }

            return Font.systemFont(ofSize: CGFloat(self.fontSize))
        }
        set {
            guard let newValue = newValue else { return }

            self.fontName = newValue.fontName
            self.fontSize = Int(newValue.pointSize)
        }
    }
    
    static var titleFont: Font! {
        get {
            if let font = Font(name: self.windowFontName, size: CGFloat(self.titleFontSize)) {
                return font
            }

            return Font.systemFont(ofSize: CGFloat(self.titleFontSize))
        }
        set {
            guard let newValue = newValue else { return }

            self.fontName = newValue.fontName
            self.fontSize = Int(newValue.pointSize)
        }
    }
    
    static var emptyEditTitleFont: Font! {
        get {
            if let font = Font(name: self.windowFontName, size: CGFloat(self.emptyEditTitleFontSize)) {
                return font
            }

            return Font.systemFont(ofSize: CGFloat(self.emptyEditTitleFontSize))
        }
        set {
            guard let newValue = newValue else { return }

            self.fontName = newValue.fontName
            self.fontSize = Int(newValue.pointSize)
        }
    }
    
    static var nameFont: Font! {
        get {
            if let font = Font(name: self.windowFontName, size: CGFloat(self.nameFontSize)) {
                return font
            }

            return Font.systemFont(ofSize: CGFloat(self.nameFontSize))
        }
        set {
            guard let newValue = newValue else { return }

            self.fontName = newValue.fontName
            self.fontSize = Int(newValue.pointSize)
        }
    }
    
    static var dateFont: Font! {
        get {
            if let font = Font(name: self.windowFontName, size: CGFloat(self.dateFontSize)) {
                return font
            }

            return Font.systemFont(ofSize: CGFloat(self.dateFontSize))
        }
        set {
            guard let newValue = newValue else { return }

            self.fontName = newValue.fontName
            self.fontSize = Int(newValue.pointSize)
        }
    }


    static var fontColor: Color {
        get {
            if let returnFontColor = UserDefaults.standard.object(forKey: Constants.FontColorKey), let color = NSKeyedUnarchiver.unarchiveObject(with: returnFontColor as! Data) as? Color {
                return color
            } else {
                return self.DefaultFontColor
            }
        }
        set {
            let data = NSKeyedArchiver.archivedData(withRootObject: newValue)
            UserDefaults.standard.set(data, forKey: Constants.FontColorKey)
        }
    }

    static var bgColor: Color {
        get {
            if let returnBgColor = UserDefaults.standard.object(forKey: Constants.BgColorKey), let color = NSKeyedUnarchiver.unarchiveObject(with: returnBgColor as! Data) as? Color {
                return color
            } else {
                return self.DefaultBgColor
            }
        }
        set {
            let data = NSKeyedArchiver.archivedData(withRootObject: newValue)
            UserDefaults.standard.set(data, forKey: Constants.BgColorKey)
        }
    }

    static var iCloudDocumentsContainer: URL? {
        if let iCloudDocumentsURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents").resolvingSymlinksInPath() {
            if !FileManager.default.fileExists(atPath: iCloudDocumentsURL.path, isDirectory: nil) {
                do {
                    try FileManager.default.createDirectory(at: iCloudDocumentsURL, withIntermediateDirectories: true, attributes: nil)

                    return iCloudDocumentsURL.resolvingSymlinksInPath()
                } catch {
                    print("Home directory creation: \(error)")
                }
            } else {
                return iCloudDocumentsURL.resolvingSymlinksInPath()
            }
        }

        return nil
    }

    static var localDocumentsContainer: URL? {
        if let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
            return URL(fileURLWithPath: path)
        }

        return nil
    }

    static var storagePath: String? {
        get {
            if let storagePath = UserDefaults.standard.object(forKey: Constants.StoragePathKey) {
                if FileManager.default.isWritableFile(atPath: storagePath as! String) {
                    return storagePath as? String
                } else {
                    print("Storage path not accessible, settings resetted to default")
                }
            }

            if let iCloudDocumentsURL = self.iCloudDocumentsContainer {
                return iCloudDocumentsURL.path
            }

            #if os(iOS)
                return self.localDocumentsContainer?.path
            #elseif CLOUDKIT && os(macOS)
                return nil
            #else
                return self.localDocumentsContainer?.path
            #endif
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.StoragePathKey)
        }
    }

    static var storageUrl: URL? {
        if let path = storagePath {
            let expanded = NSString(string: path).expandingTildeInPath

            return URL(fileURLWithPath: expanded).resolvingSymlinksInPath()
        }

        return nil
    }

    static var preview = false

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

    static var cellViewFrameOriginY: CGFloat? {
        get {
            if let value = UserDefaults.standard.object(forKey: Constants.CellFrameOriginY) {
                return value as? CGFloat
            }
            return nil
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.CellFrameOriginY)
        }
    }

    static var sort: SortBy {
        get {
            if let result = UserDefaults.standard.object(forKey: "sortBy"), let sortBy = SortBy(rawValue: result as! String) {
                return sortBy
            } else {
                return .modificationDate
            }
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "sortBy")
        }
    }

    static var sidebarSize: CGFloat {
        get {
            if let size = UserDefaults.standard.object(forKey: "sidebarSize"), let width = size as? CGFloat {
                return width
            }

            #if os(iOS)
                return 0
            #else
                return 280
            #endif
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "sidebarSize")
        }
    }

    static var lastSelectedURL: URL? {
        get {
            if let path = UserDefaults.standard.object(forKey: Constants.LastSelectedPath) as? String, let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                return URL(string: "file://" + encodedPath)
            }
            return nil
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

    #if os(iOS)
        static var nightModeType: NightMode {
            get {
                if let result = UserDefaults.standard.object(forKey: Constants.NightModeType) {
                    return NightMode(rawValue: result as! Int) ?? .disabled
                }
                return NightMode(rawValue: 0x00) ?? .disabled
            }
            set {
                UserDefaults.standard.set(newValue.rawValue, forKey: Constants.NightModeType)
            }
        }
    #endif

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

    static var fileContainer: NoteContainer {
        get {
            #if SHARE_EXT
                let defaults = UserDefaults(suiteName: "group.miaoyan-manager")
                if let result = defaults?.object(forKey: Constants.SharedContainerKey) as? Int, let container = NoteContainer(rawValue: result) {
                    return container
                }
            #endif

            if let result = UserDefaults.standard.object(forKey: Constants.NoteContainer) as? Int, let container = NoteContainer(rawValue: result) {
                return container
            }
            return .none
        }
        set {
            #if os(iOS)
                UserDefaults(suiteName: "group.miaoyan-manager")?.set(newValue.rawValue, forKey: Constants.SharedContainerKey)
            #endif

            UserDefaults.standard.set(newValue.rawValue, forKey: Constants.NoteContainer)
        }
    }

    static var projects: [URL] {
        get {
            guard let defaults = UserDefaults(suiteName: "group.miaoyan-manager") else { return [] }

            if let result = defaults.object(forKey: Constants.ProjectsKey) as? Data, let urls = NSKeyedUnarchiver.unarchiveObject(with: result) as? [URL] {
                return urls
            }

            return []
        }
        set {
            guard let defaults = UserDefaults(suiteName: "group.miaoyan-manager") else { return }

            let data = NSKeyedArchiver.archivedData(withRootObject: newValue)
            defaults.set(data, forKey: Constants.ProjectsKey)
        }
    }

    static var importURLs: [URL] {
        get {
            guard let defaults = UserDefaults(suiteName: "group.miaoyan-manager") else { return [] }

            if let result = defaults.object(forKey: Constants.ImportURLsKey) as? Data, let urls = NSKeyedUnarchiver.unarchiveObject(with: result) as? [URL] {
                return urls
            }

            return []
        }
        set {
            guard let defaults = UserDefaults(suiteName: "group.miaoyan-manager") else { return }

            let data = NSKeyedArchiver.archivedData(withRootObject: newValue)
            defaults.set(data, forKey: Constants.ImportURLsKey)
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
}
