import CommonCrypto
import CryptoKit
import Foundation

extension String {
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

    public func localizedCaseInsensitiveContainsTerms(_ terms: [Substring]) -> Bool {
        terms.allSatisfy { localizedLowercase.contains($0) }
    }

    public func startsWith(string: String) -> Bool {
        guard let range = range(of: string, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return false
        }
        return range.lowerBound == startIndex
    }

    public func removeLastNewLine() -> String {
        last == "\n" ? String(dropLast()) : self
    }

    public func isNumberList() -> Bool {
        let pattern = "^(( |\t)*[0-9]+\\. )"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: self, options: [], range: NSRange(location: 0, length: count)) != nil
    }

    public func regexReplace(regex: String, content: String) -> String {
        guard let regexExpression = try? NSRegularExpression(pattern: regex, options: .caseInsensitive) else {
            return self
        }
        return regexExpression.stringByReplacingMatches(
            in: self,
            options: .reportProgress,
            range: NSRange(location: 0, length: count),
            withTemplate: content
        )
    }

    public var isValidUUID: Bool {
        UUID(uuidString: self) != nil
    }

    public func escapePlus() -> String {
        replacingOccurrences(of: "+", with: "%20")
    }

    public func matchingStrings(regex: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: regex, options: [.dotMatchesLineSeparators]) else { return [] }

        let nsString = self as NSString
        let results = regex.matches(in: self, options: [], range: NSRange(0..<nsString.length))
        return results.map { result in
            (0..<result.numberOfRanges).map {
                result.range(at: $0).location != NSNotFound
                    ? nsString.substring(with: result.range(at: $0))
                    : ""
            }
        }
    }

    public var md5: String {
        let data = Data(self.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }

    public var isWhitespace: Bool {
        guard !isEmpty else { return true }
        return !unicodeScalars.contains { !CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    public var isNumber: Bool {
        !isEmpty && rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
    }
}

extension StringProtocol where Index == String.Index {
    public func nsRange(from range: Range<Index>) -> NSRange {
        NSRange(range, in: self)
    }
}

// MARK: - String Subscript Extensions
extension String {
    // Single character access by integer index
    public subscript(value: Int) -> Character {
        self[index(at: value)]
    }

    // Substring access by NSRange
    public subscript(value: NSRange) -> Substring {
        self[value.lowerBound..<value.upperBound]
    }

    // Substring access by closed range
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

