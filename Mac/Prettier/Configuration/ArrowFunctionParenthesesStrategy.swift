import Foundation

/// Strategy used when determining to include parentheses around a sole arrow function parameter.
public enum ArrowFunctionParenthesesStrategy: String, Codable {
    /// Always include parens. Example: `(x) => x`
    case always
    /// Omit parens when possible. Example: `x => x`
    case avoid
}
