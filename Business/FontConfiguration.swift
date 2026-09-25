import Cocoa

/// Centralized font configuration for the app
/// All default fonts are defined here for easy maintenance
@MainActor
enum FontConfiguration {
    /// Use installed system fonts without redistributing font files.
    static let defaultEditorFont = "PingFangSC-Regular"
    static let fallbackFont = "PingFangSC-Regular"

    /// Default interface font name
    static let defaultInterfaceFont = "PingFangSC-Regular"

    /// Default preview font name
    static let defaultPreviewFont = "PingFangSC-Regular"

    /// Stored as the code font when code blocks use the text font, the editor
    /// font in the editor and the preview font in the preview. It names no
    /// installed face, so it is checked before any font lookup.
    static let followTextFont = "FollowText"

    /// Default code font name
    static let defaultCodeFont = followTextFont

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
