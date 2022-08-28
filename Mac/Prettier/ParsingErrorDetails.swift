import Foundation

/// Details supplied by PrettierFormatterError when parsing fails.
public struct ParsingErrorDetails: CustomDebugStringConvertible {
    public struct Location {
        let line: Int
        let column: Int
    }

    public let line: Int
    public let column: Int
    public let codeFrame: String
    public var debugDescription: String {
        return "Parsing error at line \(line), column \(column):\n\(codeFrame)"
    }

    init?(object: [String: Any]) {
        guard let codeFrame = object["codeFrame"] as? String else {
            return nil
        }
        guard let loc = object["loc"] as? [String: Any], let start = loc["start"] as? [String: Int] else {
            return nil
        }
        guard let line = start["column"] else {
            return nil
        }
        guard let column = start["column"] else {
            return nil
        }
        self.line = line
        self.column = column
        self.codeFrame = codeFrame
    }
}
