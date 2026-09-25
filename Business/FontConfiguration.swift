import Cocoa

/// Centralized font configuration for the app
/// All default fonts are defined here for easy maintenance
@MainActor
enum FontConfiguration {
    /// TsangerJinKai02 is the face MiaoYan is designed around. It is not
    /// bundled (redistribution needs a licence), so the default names it and
    /// everything renders in `fallbackFont` until the user installs it; the
    /// stored choice is never rewritten while the face is missing.
    static let defaultEditorFont = "TsangerJinKai02-W04"
    static let fallbackFont = "PingFangSC-Regular"

    /// Default interface font name
    static let defaultInterfaceFont = "TsangerJinKai02-W04"

    /// Default preview font name
    static let defaultPreviewFont = "TsangerJinKai02-W04"

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
