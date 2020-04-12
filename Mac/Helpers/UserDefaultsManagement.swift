//
//  Preferences.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 8/8/17.
//  Copyright © 2017 Oleksandr Glushchenko. All rights reserved.
//

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
    
    static var DefaultFont = ".AppleSystemUIFont"

#if os(OSX)
    static var DefaultFontSize = 14
#else
    static var DefaultFontSize = 17
#endif

    static var DefaultSnapshotsInterval = 1
    static var DefaultSnapshotsIntervalMinutes = 5
    
    static var DefaultFontColor = Color.black
    static var DefaultBgColor = Color.white

    private struct Constants {
        static let AppearanceTypeKey = "appearanceType"
        static let ArchiveDirectoryKey = "archiveDirectory"
        static let AutomaticSpellingCorrection = "automaticSpellingCorrection"
        static let AutomaticQuoteSubstitution = "automaticQuoteSubstitution"
        static let AutomaticDataDetection = "automaticDataDetection"
        static let AutomaticLinkDetection = "automaticLinkDetection"
        static let AutomaticTextReplacement = "automaticTextReplacement"
        static let AutomaticDashSubstitution = "automaticDashSubstitution"
        static let BackupManually = "backupManually"
        static let BgColorKey = "bgColorKeyed"
        static let CellFrameOriginY = "cellFrameOriginY"
        static let CodeFontNameKey = "codeFont"
        static let CodeFontSizeKey = "codeFontSize"
        static let codeBlockHighlight = "codeBlockHighlight"
        static let codeTheme = "codeTheme"
        static let ContinuousSpellChecking = "continuousSpellChecking"
        static let DefaultLanguageKey = "defaultLanguage"
        static let FontNameKey = "font"
        static let FontSizeKey = "fontsize"
        static let FontColorKey = "fontColorKeyed"
        static let FullScreen = "fullScreen"
        static let FirstLineAsTitle = "firstLineAsTitle"
        static let NoteType = "noteType"
        static let GrammarChecking = "grammarChecking"
        static let GitStorage = "gitStorage"
        static let HideDate = "hideDate"
        static let HideOnDeactivate = "hideOnDeactivate"
        static let HideSidebar = "hideSidebar"
        static let HidePreviewKey = "hidePreview"
        static let HidePreviewImages = "hidePreviewImages"
        static let ImagesWidthKey = "imagesWidthKey"
        static let ImportURLsKey = "ImportURLs"
        static let InlineTags = "inlineTags"
        static let LastSelectedPath = "lastSelectedPath"
        static let LastProject = "lastProject"
        static let LineSpacingEditorKey = "lineSpacingEditor"
        static let LineWidthKey = "lineWidth"
        static let LiveImagesPreview = "liveImagesPreview"
        static let MarginSizeKey = "marginSize"
        static let MarkdownPreviewCSS = "markdownPreviewCSS"
        static let NightModeType = "nightModeType"
        static let NightModeAuto = "nightModeAuto"
        static let NightModeBrightnessLevel = "nightModeBrightnessLevel"
        static let NoteContainer = "noteContainer"
        static let PinListKey = "pinList"
        static let Preview = "preview"
        static let PreviewFontSize = "previewFontSize"
        static let ProjectsKey = "projects"
        static let RestoreCursorPosition = "restoreCursorPosition"
        static let SaveInKeychain = "saveInKeychain"
        static let SharedContainerKey = "sharedContainer"
        static let ShowDockIcon = "showDockIcon"
        static let SmartInsertDelete = "smartInsertDelete"
        static let SnapshotsInterval = "snapshotsInterval"
        static let SnapshotsIntervalMinutes = "snapshotsIntervalMinutes"
        static let SortBy = "sortBy"
        static let SpacesInsteadTabs = "spacesInsteadTabs"
        static let StoragePathKey = "storageUrl"
        static let TableOrientation = "isUseHorizontalMode"
        static let TextMatchAutoSelection = "textMatchAutoSelection"
        static let TxtAsMarkdown = "txtAsMarkdown"
        static let AutocloseBrackets = "autocloseBrackets"
        static let Welcome = "welcome"
    }

    static var codeFontName: String {
        get {
            if let returnFontName = UserDefaults.standard.object(forKey: Constants.CodeFontNameKey) {
                return returnFontName as! String
            } else {
                return "Source Code Pro"
            }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.CodeFontNameKey)
        }
    }

    static var codeFontSize: Int {
        get {
            if let returnFontSize = UserDefaults.standard.object(forKey: Constants.CodeFontSizeKey) {
                return returnFontSize as! Int
            } else {
                return self.DefaultFontSize
            }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.CodeFontSizeKey)
        }
    }

    static var fontName: String {
        get {
            if let returnFontName = UserDefaults.standard.object(forKey: Constants.FontNameKey) {
                return returnFontName as! String
            } else {
                return "Avenir Next"
            }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.FontNameKey)
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

    static var codeFont: Font! {
        get {
            if let font = Font(name: self.codeFontName, size: CGFloat(self.codeFontSize)) {
                return font
            }

            return Font.systemFont(ofSize: CGFloat(self.codeFontSize))
        }
        set {
            guard let newValue = newValue else {return}

            self.codeFontName = newValue.fontName
            self.codeFontSize = Int(newValue.pointSize)
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
            guard let newValue = newValue else {return}
            
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
    
    static var externalEditor: String {
        get {
            let name = UserDefaults.standard.object(forKey: "externalEditorApp")
            if name != nil && (name as! String).count > 0 {
                return name as! String
            } else {
                return "TextEdit"
            }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "externalEditorApp")
        }
    }

    static var horizontalOrientation: Bool {
        get {
            if let returnMode = UserDefaults.standard.object(forKey: Constants.TableOrientation) {
                return returnMode as! Bool
            } else {
                return false
            }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.TableOrientation)
        }
    }
    
    static var iCloudDocumentsContainer: URL? {
        get {
            if let iCloudDocumentsURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents").resolvingSymlinksInPath() {
                if (!FileManager.default.fileExists(atPath: iCloudDocumentsURL.path, isDirectory: nil)) {
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
    }
    
    static var localDocumentsContainer: URL? {
        get {
            if let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
                return URL(fileURLWithPath: path)
            }
 
            return nil
        }
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
        get {
            if let path = storagePath {
                let expanded = NSString(string: path).expandingTildeInPath

                return URL.init(fileURLWithPath: expanded).resolvingSymlinksInPath()
            }
            
            return nil
        }
    }
            
    static var preview: Bool {
        get {
            if let preview = UserDefaults.standard.object(forKey: Constants.Preview) {
                return preview as! Bool
            } else {
                return false
            }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.Preview)
        }
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
    
    static var hideOnDeactivate: Bool {
        get {
            if let hideOnDeactivate = UserDefaults.standard.object(forKey: Constants.HideOnDeactivate) {
                return hideOnDeactivate as! Bool
            } else {
                return false
            }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.HideOnDeactivate)
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
    
    static var hidePreview: Bool {
        get {
            if let returnMode = UserDefaults.standard.object(forKey: Constants.HidePreviewKey) {
                return returnMode as! Bool
            } else {
                return false
            }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.HidePreviewKey)
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
    
    static var sortDirection: Bool {
        get {
            if let returnMode = UserDefaults.standard.object(forKey: "sortDirection") {
                return returnMode as! Bool
            } else {
                return true
            }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "sortDirection")
        }
    }
    
    static var hideSidebar: Bool {
        get {
            if let hide = UserDefaults.standard.object(forKey: "hideSidebar") {
                return hide as! Bool
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hideSidebar")
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
                return 250
            #endif
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "sidebarSize")
        }
    }
    
    static var hideRealSidebar: Bool {
        get {
            if let hide = UserDefaults.standard.object(forKey: "hideRealSidebar") {
                return hide as! Bool
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hideRealSidebar")
        }
    }
    
    static var realSidebarSize: Int {
        get {
            if let size = UserDefaults.standard.object(forKey: "realSidebarSize") {
                return size as! Int
            }
            return 100
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "realSidebarSize")
        }
    }
    
    static var codeBlockHighlight: Bool {
        get {
            if let highlight = UserDefaults.standard.object(forKey: Constants.codeBlockHighlight) {
                return highlight as! Bool
            }
            return true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.codeBlockHighlight)
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
    
    static var liveImagesPreview: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.LiveImagesPreview) {
                return result as! Bool
            }
            return true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.LiveImagesPreview)
        }
    }
    
    static var focusInEditorOnNoteSelect: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: "focusInEditorOnNoteSelect") {
                return result as! Bool
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "focusInEditorOnNoteSelect")
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
    
    static var restoreCursorPosition: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.RestoreCursorPosition) {
                return result as! Bool
            }
            return true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.RestoreCursorPosition)
        }
    }
    
    static var nightModeAuto: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.NightModeAuto) {
                return result as! Bool
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.NightModeAuto)
        }
    }
    
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
    
    static var maxNightModeBrightnessLevel: Float {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.NightModeBrightnessLevel) {
                return result as! Float
            }
            return 35
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.NightModeBrightnessLevel)
        }
    }
    
    static var autocloseBrackets: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.AutocloseBrackets) {
                return result as! Bool
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.AutocloseBrackets)
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
    
    static var showDockIcon: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.ShowDockIcon) {
                return result as! Bool
            }
            return true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.ShowDockIcon)
        }
    }
    
    static var archiveDirectory: URL? {
        get {
            #if os(OSX)
            if let path = UserDefaults.standard.object(forKey: Constants.ArchiveDirectoryKey) as? String,
                let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                let archiveURL = URL(string: "file://" + encodedPath + "/") {
                var isDirectory = ObjCBool(true)
                let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)

                if (exists && isDirectory.boolValue) {
                    return archiveURL
                } else {
                    self.archiveDirectory = nil
                    print("Archive path not accessible, settings resetted to default")
                }
            }
            #endif

            if let archive = storageUrl?.appendingPathComponent("Archive") {
                if !FileManager.default.fileExists(atPath: archive.path) {
                    do {
                        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: false, attributes: nil)
                        self.archiveDirectory = archive
                        return archive
                    } catch {
                        print(error)
                    }
                } else {
                    self.archiveDirectory = archive
                    return archive
                }
            }
            
            return nil
        }
        
        set {
            if let url = newValue {
                UserDefaults.standard.set(url.path, forKey: Constants.ArchiveDirectoryKey)
            } else {
                UserDefaults.standard.set(nil, forKey: Constants.ArchiveDirectoryKey)
            }
        }
    }
    
    static var editorLineSpacing: Float {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.LineSpacingEditorKey) {
                return result as! Float
            }
            return 0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.LineSpacingEditorKey)
        }
    }

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

    static var lineWidth: Float {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.LineWidthKey) {
                return result as! Float
            }
            return 1000
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.LineWidthKey)
        }
    }
    
    static var textMatchAutoSelection: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.TextMatchAutoSelection) {
                return result as! Bool
            }
            return true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.TextMatchAutoSelection)
        }
    }
    
    static var continuousSpellChecking: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.ContinuousSpellChecking) {
                return result as! Bool
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.ContinuousSpellChecking)
        }
    }
    
    static var grammarChecking: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.GrammarChecking) {
                return result as! Bool
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.GrammarChecking)
        }
    }
    
    static var smartInsertDelete: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.SmartInsertDelete) {
                return result as! Bool
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.SmartInsertDelete)
        }
    }
    
    static var automaticSpellingCorrection: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.AutomaticSpellingCorrection) {
                return result as! Bool
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.AutomaticSpellingCorrection)
        }
    }
    
    static var automaticQuoteSubstitution: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.AutomaticQuoteSubstitution) {
                return result as! Bool
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.AutomaticQuoteSubstitution)
        }
    }
    
    static var automaticDataDetection: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.AutomaticDataDetection) {
                return result as! Bool
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.AutomaticDataDetection)
        }
    }
    
    static var automaticLinkDetection: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.AutomaticLinkDetection) {
                return result as! Bool
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.AutomaticLinkDetection)
        }
    }
        
    static var automaticTextReplacement: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.AutomaticTextReplacement) {
                return result as! Bool
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.AutomaticTextReplacement)
        }
    }
    
    static var automaticDashSubstitution: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.AutomaticDashSubstitution) {
                return result as! Bool
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.AutomaticDashSubstitution)
        }
    }

    static var isHiddenSidebar: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.HideSidebar) {
                return result as! Bool
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.HideSidebar)
        }
    }

    static var txtAsMarkdown: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.TxtAsMarkdown) as? Bool {
                return result
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.TxtAsMarkdown)
        }
    }
    
    static var fileContainer: NoteContainer {
        get {
            #if SHARE_EXT
                let defaults = UserDefaults.init(suiteName: "group.fsnotes-manager")
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
            UserDefaults.init(suiteName: "group.fsnotes-manager")?.set(newValue.rawValue, forKey: Constants.SharedContainerKey)
            #endif

            UserDefaults.standard.set(newValue.rawValue, forKey: Constants.NoteContainer)
        }
    }

    static var projects: [URL] {
        get {
            guard let defaults = UserDefaults.init(suiteName: "group.fsnotes-manager") else { return [] }

            if let result = defaults.object(forKey: Constants.ProjectsKey) as? Data, let urls = NSKeyedUnarchiver.unarchiveObject(with: result) as? [URL] {
                return urls
            }

            return []
        }
        set {
            guard let defaults = UserDefaults.init(suiteName: "group.fsnotes-manager") else { return }

            let data = NSKeyedArchiver.archivedData(withRootObject: newValue)
            defaults.set(data, forKey: Constants.ProjectsKey)
        }
    }

    static var importURLs: [URL] {
        get {
            guard let defaults = UserDefaults.init(suiteName: "group.fsnotes-manager") else { return [] }

            if let result = defaults.object(forKey: Constants.ImportURLsKey) as? Data, let urls = NSKeyedUnarchiver.unarchiveObject(with: result) as? [URL] {
                return urls
            }

            return []
        }
        set {
            guard let defaults = UserDefaults.init(suiteName: "group.fsnotes-manager") else { return }

            let data = NSKeyedArchiver.archivedData(withRootObject: newValue)
            defaults.set(data, forKey: Constants.ImportURLsKey)
        }
    }

    static var fileFormat: NoteType {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.NoteType) as? Int {
                return NoteType.withTag(rawValue: result)
            }
            return .Markdown
        }
        set {
            UserDefaults.standard.set(newValue.tag, forKey: Constants.NoteType)
        }
    }

    static var previewFontSize: Int {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.PreviewFontSize) as? Int {
                return result
            }
            return 11
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.PreviewFontSize)
        }
    }

    static var hidePreviewImages: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.HidePreviewImages) as? Bool {
                return result
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.HidePreviewImages)
        }
    }

    static var hideDate: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.HideDate) as? Bool {
                return result
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.HideDate)
        }
    }

    static var spacesInsteadTabs: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.SpacesInsteadTabs) as? Bool {
                return result
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.SpacesInsteadTabs)
        }
    }

    static var firstLineAsTitle: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.FirstLineAsTitle) as? Bool {
                return result
            }

            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.FirstLineAsTitle)
        }
    }

    static var marginSize: Float {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.MarginSizeKey) {
                return result as! Float
            }
            return 20
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.MarginSizeKey)
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

    static var gitStorage: URL {
        get {
            if let repositories = UserDefaults.standard.url(forKey: Constants.GitStorage) {
                if !FileManager.default.fileExists(atPath: repositories.path) {
                    try? FileManager.default.createDirectory(at: repositories, withIntermediateDirectories: true, attributes: nil)
                }

                return repositories
            }

            let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let repositories = applicationSupport.appendingPathComponent("Repositories")

            if !FileManager.default.fileExists(atPath: repositories.path) {
                try? FileManager.default.createDirectory(at: repositories, withIntermediateDirectories: true, attributes: nil)
            }

            return repositories
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.GitStorage)
        }
    }

    static var snapshotsInterval: Int {
        get {
            if let interval = UserDefaults.standard.object(forKey: Constants.SnapshotsInterval) as? Int {
                return interval
            }

            return self.DefaultSnapshotsInterval
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.SnapshotsInterval)
        }
    }

    static var snapshotsIntervalMinutes: Int {
        get {
            if let interval = UserDefaults.standard.object(forKey: Constants.SnapshotsIntervalMinutes) as? Int {
                return interval
            }

            return self.DefaultSnapshotsIntervalMinutes
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.SnapshotsIntervalMinutes)
        }
    }

    static var backupManually: Bool {
        get {
            if let returnMode = UserDefaults.standard.object(forKey: Constants.BackupManually) as? Bool {
                return returnMode
            } else {
                return true
            }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.BackupManually)
        }
    }

    static var fullScreen: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.FullScreen) as? Bool {
                return result
            }
            return false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.FullScreen)
        }
    }

    static var inlineTags: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.InlineTags) as? Bool {
                return result
            }
            return true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.InlineTags)
        }
    }

    static var copyWelcome: Bool {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.Welcome) as? Bool {
                return result
            }
            return true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.Welcome)
        }
    }
}
