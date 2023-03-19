import Foundation

/// A plugin that can be passed to PrettierFormatter to format code.
///
/// One plugin may contain one or more parsers.
public protocol Plugin {
    var fileURL: URL { get }
}
