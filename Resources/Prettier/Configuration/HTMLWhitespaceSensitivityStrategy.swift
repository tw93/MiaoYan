import Foundation

/// The whitespace sensitivity for HTML, Vue, Angular, and Handlebars.
public enum HTMLWhitespaceSensitivityStrategy: String, Codable {
    /// Respect the default value of CSS display property. For Handlebars treated same as `strict`.
    case css
    /// Whitespace (or the lack of it) around all tags is considered significant.
    case strict
    /// Whitespace (or the lack of it) around all tags is considered insignificant.
    case ignore
}
