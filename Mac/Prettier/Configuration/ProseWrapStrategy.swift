import Foundation

/// Strategy used when wrapping markdown text.
public enum ProseWrapStrategy: String, Codable {
    /// Wrap prose if it exceeds the print width.
    case always
    /// Do not wrap prose.
    case never
    /// Wrap prose as-is.
    case preserve
}
