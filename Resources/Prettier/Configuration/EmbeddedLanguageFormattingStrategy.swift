import Foundation

/// Controls whether to format quoted code embedded in the file.
public enum EmbeddedLanguageFormattingStrategy: String, Codable {
    /// Format embedded code if Prettier can automatically identify it.
    case auto
    /// Never automatically format embedded code.
    case off
}
