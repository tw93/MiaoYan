import Foundation

/// A parser that can be used with Prettier to format code.
///
/// Parsers reside in a plugin and a plugin may contain one or more parsers.
public protocol Parser {
    var name: String { get }
}
