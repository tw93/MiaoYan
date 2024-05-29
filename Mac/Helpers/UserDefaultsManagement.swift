import Foundation

#if os(OSX)
import Cocoa
#else
import UIKit
#endif

public enum UserDefaultsManagement {
    #if os(OSX)
    typealias Color = NSColor
    typealias Image = NSImage
    typealias Font = NSFont
    #else
    typealias Color = UIColor
    typealias Image = UIImage
    typealias Font = UIFont
    #endif

    static var DefaultFont = "LXGW WenKai Screen"

    static var DefaultFontSize = 16
    static var DefaultPreviewFontSize = 16
    static var DefaultPresentationFontSize = 24

    static var DefaultFontColor = Color(red: 0.38, green: 0.38, blue: 0.38, alpha: 1.00)
    static var DefaultBgColor = Color.white

    static var lineWidth = 1000
    static var linkColor = Color(red: 0.23, green: 0.23, blue: 0.23, alpha: 1.00)
    static var fullScreen = false
    static var isWillFullScreen = false

    static var editorLineSpacing = 3.0
    static var editorLineHeight = 1.3
    static var editorLetterSpacing = 0.6
    static var windowLetterSpacing = 0.6

    static var titleFontSize = 20
    static var emptyEditTitleFontSize = 36
    static var nameFontSize = 14
    static var searchFontSize = 13
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
        static let CellFrameOriginY = "cellFrameOriginY"
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
        static let NightModeAuto = "nightModeAuto"
        static let NoteContainer = "noteContainer"
        static let PinListKey = "pinList"
        static let Preview = "preview"
        static let Presentation = "presentation"
        static let PreviewFontSize = "previewFontSize"
        static let PresentationFontSize = "presentationFontSize"
        static let ProjectsKey = "projects"
        static let RestoreCursorPosition = "restoreCursorPosition"
        static let SaveInKeychain = "saveInKeychain"
        static let SharedContainerKey = "sharedContainer"
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
        static let CodeBackground = "CodeBackground"
    }

    static var appearanceType: AppearanceType {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.AppearanceTypeKey) as? Int {
                return AppearanceType(rawValue: result)!
            }

            if #available(OSX 10.14, *) {
                return AppearanceType.System
            } else {
                return AppearanceType.Custom
            }
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
            return 0
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

    static var codeBackground: String {
        get {
            if let dl = UserDefaults.standard.object(forKey: Constants.CodeBackground) as? String {
                return dl
            }
            return "No"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.CodeBackground)
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
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.FontName) as? String {
                if result == "LXGW WenKai Lite" {
                    return DefaultFont
                }
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
                if result == "LXGW WenKai Lite" {
                    return DefaultFont
                }
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
                if result == "LXGW WenKai Lite" {
                    return DefaultFont
                }
                return result
            }
            return DefaultFont
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.PreviewFontName)
        }
    }

    static var codeFontName: String {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.CodeFontNameKey) as? String {
                if result == "LXGW WenKai Lite" {
                    return DefaultFont
                }
                return result
            }
            return DefaultFont
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.CodeFontNameKey)
        }
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
        get {
            if let font = Font(name: windowFontName, size: CGFloat(titleFontSize)) {
                if windowFontName == "SF Pro Text" {
                    return Font(name: "Helvetica Neue", size: CGFloat(titleFontSize))
                }
                return font
            }

            return Font.systemFont(ofSize: CGFloat(titleFontSize))
        }
        set {
            guard let newValue = newValue else {
                return
            }

            fontName = newValue.fontName
            fontSize = Int(newValue.pointSize)
        }
    }

    static var emptyEditTitleFont: Font! {
        get {
            if let font = Font(name: windowFontName, size: CGFloat(emptyEditTitleFontSize)) {
                return font
            }

            return Font.systemFont(ofSize: CGFloat(emptyEditTitleFontSize))
        }
        set {
            guard let newValue = newValue else {
                return
            }

            fontName = newValue.fontName
            fontSize = Int(newValue.pointSize)
        }
    }

    static var nameFont: Font! {
        get {
            if let font = Font(name: windowFontName, size: CGFloat(nameFontSize)) {
                return font
            }

            return Font.systemFont(ofSize: CGFloat(nameFontSize))
        }
        set {
            guard let newValue = newValue else {
                return
            }

            fontName = newValue.fontName
            fontSize = Int(newValue.pointSize)
        }
    }

    static var searchFont: Font! {
        get {
            if let font = Font(name: windowFontName, size: CGFloat(searchFontSize)) {
                return font
            }

            return Font.systemFont(ofSize: CGFloat(searchFontSize))
        }
        set {
            guard let newValue = newValue else {
                return
            }

            fontName = newValue.fontName
            fontSize = Int(newValue.pointSize)
        }
    }

    static var dateFont: Font! {
        get {
            if let font = Font(name: windowFontName, size: CGFloat(dateFontSize)) {
                return font
            }

            return Font.systemFont(ofSize: CGFloat(dateFontSize))
        }
        set {
            guard let newValue = newValue else {
                return
            }

            fontName = newValue.fontName
            fontSize = Int(newValue.pointSize)
        }
    }

    static var fontColor: Color {
        get {
            if let returnFontColor = UserDefaults.standard.data(forKey: Constants.FontColorKey),
               let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: Color.self, from: returnFontColor) {
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
               let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: Color.self, from: returnBgColor) {
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
            let miaoyanPath: String = path + "/MiaoYan"
            try! FileManager.default.createDirectory(atPath: miaoyanPath,
                    withIntermediateDirectories: true, attributes: nil)
            return URL(fileURLWithPath: miaoyanPath)
        }
        return nil
    }

    static var storagePath: String? {
        get {
            if let storagePath = UserDefaults.standard.object(forKey: Constants.StoragePathKey) {
                if FileManager.default.isWritableFile(atPath: storagePath as! String) {
                    return storagePath as? String
                } else {
                    print("Storage path not accessible, settings resettled to default")
                }
            }

            if let iCloudDocumentsURL = iCloudDocumentsContainer {
                return iCloudDocumentsURL.path
            }

            #if os(iOS)
            return localDocumentsContainer?.path
            #elseif CLOUDKIT && os(macOS)
            return nil
            #else
            return localDocumentsContainer?.path
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

    static var preview: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.Preview) as? Bool {
                return result
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.Preview)
        }
    }

    static var presentation = false

    static var magicPPT = false

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
                return .creationDate
            }
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "sortBy")
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
               let urls = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSURL.self], from: result) as? [URL] {
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
               let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
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
