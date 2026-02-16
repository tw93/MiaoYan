import Cocoa

/// Centralized font configuration for the app
/// All default fonts are defined here for easy maintenance
@MainActor
enum FontConfiguration {
    /// Default editor font name
    /// Current: TsangerJinKai (elegant Chinese font)
    /// Fallback: PingFang SC (system Chinese font)
    static let defaultEditorFont = "TsangerJinKai02-W04"
    static let fallbackFont = "PingFangSC-Regular"

    /// Default interface font name
    static let defaultInterfaceFont = "TsangerJinKai02-W04"

    /// Default preview font name
    static let defaultPreviewFont = "TsangerJinKai02-W04"

    /// Default code font name
    static let defaultCodeFont = "Menlo"

    /// All bundled custom fonts
    static let bundledFonts = ["TsangerJinKai02-W04"]

    /// Returns the actual NSFont for editor use
    static func editorFont(size: CGFloat) -> NSFont {
        let fontName = UserDefaultsManagement.fontName
        return NSFont(name: fontName, size: size)
            ?? NSFont(name: fallbackFont, size: size)
            ?? NSFont.systemFont(ofSize: size)
    }

    /// Returns the actual NSFont for interface use
    static func interfaceFont(size: CGFloat) -> NSFont {
        let fontName = UserDefaultsManagement.windowFontName
        return NSFont(name: fontName, size: size)
            ?? NSFont(name: fallbackFont, size: size)
            ?? NSFont.systemFont(ofSize: size)
    }

    /// Returns the actual NSFont for code
    static func codeFont(size: CGFloat) -> NSFont {
        let fontName = UserDefaultsManagement.codeFontName
        return NSFont(name: fontName, size: size)
            ?? NSFont.userFixedPitchFont(ofSize: size)
            ?? NSFont.systemFont(ofSize: size)
    }
}
