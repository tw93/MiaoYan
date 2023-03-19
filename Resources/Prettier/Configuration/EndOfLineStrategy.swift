import Foundation

/// Line endings to be used in formatted code.
public enum EndOfLineStrategy: String, Codable {
    /// Line Feed only (\n). Common on Linux and macOS as well as inside git repositories.
    case lf
    /// Carriage Return + Line Feed characters (\r\n). Cmmon on Windows.
    case crlf
    /// Carriage Return character only (\r). Used very rarely.
    case cr
    /// Maintain existing line endings. Mixed values within one file are normalised by looking at what’s used after the first line.
    case auto
}
