import CommonCrypto
import CoreServices
import CryptoKit
import Foundation

extension String {
    // Shared regex cache to avoid recompilation overhead
    nonisolated(unsafe) private static let regexCache = NSCache<NSString, NSRegularExpression>()

    private func getCachedRegex(pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        let key = "\(pattern)-\(options.rawValue)" as NSString
        if let cached = String.regexCache.object(forKey: key) {
            return cached
        }

        if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
            String.regexCache.setObject(regex, forKey: key)
            return regex
        }
        return nil
    }

    public func condenseWhitespace() -> String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public func localizedStandardContains<S: StringProtocol>(_ terms: [S]) -> Bool {
        terms.contains { localizedStandardContains($0) }
    }

    public func trim() -> String {
        trimmingCharacters(in: .whitespaces)
    }

    public func getPrefixMatchSequentially(char: String) -> String? {
        var result = String()

        for current in self {
            guard current.description == char else { break }
            result += char
        }

        return result.isEmpty ? nil : result
    }

    public func removeLastNewLine() -> String {
        last == "\n" ? String(dropLast()) : self
    }

    public func isNumberList() -> Bool {
        let pattern = "^(( |\t)*[0-9]+\\. )"
        guard let regex = getCachedRegex(pattern: pattern) else { return false }
        return regex.firstMatch(in: self, options: [], range: NSRange(location: 0, length: count)) != nil
    }

    public var isValidUUID: Bool {
        UUID(uuidString: self) != nil
    }

    public func escapePlus() -> String {
        replacingOccurrences(of: "+", with: "%20")
    }

    public func tag(withClass: CFString) -> String? {
        UTTypeCopyPreferredTagWithClass(self as CFString, withClass)?.takeRetainedValue() as String?
    }

    public func uti(withClass: CFString) -> String? {
        UTTypeCreatePreferredIdentifierForTag(withClass, self as CFString, nil)?.takeRetainedValue() as String?
    }

    public var utiFileExtension: String? {
        tag(withClass: kUTTagClassFilenameExtension)
    }

    public var md5: String {
        let data = Data(self.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }

    public var isNumber: Bool {
        !isEmpty && rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
    }
}

extension StringProtocol where Index == String.Index {
}

// MARK: - String Subscript Extensions
extension String {
    // Single character access by integer index
    // PERF: O(n) complexity. Use valid String.Index for performance critical code.
    public subscript(value: Int) -> Character {
        self[index(at: value)]
    }

    // Substring access by NSRange
    public subscript(value: NSRange) -> Substring {
        self[value.lowerBound..<value.upperBound]
    }

    // Substring access by closed range
    // PERF: O(n) complexity for index calculation.
    public subscript(value: CountableClosedRange<Int>) -> Substring {
        self[index(at: value.lowerBound)...index(at: value.upperBound)]
    }

    public subscript(value: CountableRange<Int>) -> Substring {
        self[index(at: value.lowerBound)..<index(at: value.upperBound)]
    }

    public subscript(value: PartialRangeUpTo<Int>) -> Substring {
        self[..<index(at: value.upperBound)]
    }

    public subscript(value: PartialRangeThrough<Int>) -> Substring {
        self[...index(at: value.upperBound)]
    }

    public subscript(value: PartialRangeFrom<Int>) -> Substring {
        self[index(at: value.lowerBound)...]
    }

    // Helper method to convert integer offset to String.Index
    fileprivate func index(at offset: Int) -> String.Index {
        self.index(startIndex, offsetBy: offset)
    }
}

extension String {
    /// The info panel's word count: each Chinese, Japanese or Korean
    /// character is one, and a run of other letters or digits is one word,
    /// so English and Spanish count words rather than characters and mixed
    /// text counts both. Markdown markers and punctuation are not counted.
    var noteWordCount: Int {
        var count = 0
        var inWord = false
        for scalar in unicodeScalars {
            if scalar.isCJKWordCharacter {
                count += 1
                inWord = false
            } else if CharacterSet.alphanumerics.contains(scalar) || (inWord && (scalar == "'" || scalar == "\u{2019}")) {
                if !inWord { count += 1 }
                inWord = true
            } else {
                inWord = false
            }
        }
        return count
    }
}

extension Unicode.Scalar {
    fileprivate var isCJKWordCharacter: Bool {
        switch value {
        case 0x3040...0x30FF,  // Hiragana, Katakana
            0x3400...0x4DBF,  // CJK Extension A
            0x4E00...0x9FFF,  // CJK Unified Ideographs
            0xAC00...0xD7AF,  // Hangul syllables
            0xF900...0xFAFF,  // CJK Compatibility Ideographs
            0x20000...0x2FA1F:  // CJK Extensions B and later
            return true
        default:
            return false
        }
    }
}

extension NSString {
    public func getLineRangeBefore(_ lineRange: NSRange) -> NSRange? {
        var lineStart = 0
        getLineStart(&lineStart, end: nil, contentsEnd: nil, for: lineRange)
        if lineStart == 0 {
            return nil
        }
        return self.lineRange(for: NSRange(location: lineStart - 1, length: 0))
    }
}
