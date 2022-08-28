import Foundation

/// Strategy used when surrounding properties with quotes.
public enum QuotePropertyStrategy: String, Codable {
    /// Only add quotes around object properties where required.
    case asNeeded = "as-needed"
    /// If at least one property in an object requires quotes, quote all properties.
    case consistent
    /// Respect the input use of quotes in object properties.
    case preserve
}
