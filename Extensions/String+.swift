//
//  String+.swift
//  FSNotes
//
//  Created by Jeff Hanbury on 29/08/17.
//  Copyright © 2017 Oleksandr Glushchenko. All rights reserved.
//

import CommonCrypto
import CryptoKit
import Foundation

extension String {
    public func condenseWhitespace() -> String {
        let components = components(separatedBy: NSCharacterSet.whitespacesAndNewlines)
        return components.filter { !$0.isEmpty }.joined(separator: " ")
    }

    // Search the string for the existence of any of the terms in the provided array of terms.

    // Inspired by magic from https://stackoverflow.com/a/41902740/2778502
    public func localizedStandardContains<S: StringProtocol>(_ terms: [S]) -> Bool {
        terms.contains { self.localizedStandardContains($0) }
    }

    public func trim() -> String {
        trimmingCharacters(in: NSCharacterSet.whitespaces)
    }

    public func getPrefixMatchSequentially(char: String) -> String? {
        var result = String()

        for current in self {
            if current.description == char {
                result += char
                continue
            }
            break
        }

        if !result.isEmpty {
            return result
        }

        return nil
    }

    public func localizedCaseInsensitiveContainsTerms(_ terms: [Substring]) -> Bool {
        // Use magic from https://stackoverflow.com/a/41902740/2778502
        terms.allSatisfy { localizedLowercase.contains($0) }
    }

    public func startsWith(string: String) -> Bool {
        guard let range = range(of: string, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return false
        }
        return range.lowerBound == startIndex
    }

    public func removeLastNewLine() -> String {
        if last == "\n" {
            return String(self.dropLast())
        }

        return self
    }

    public func isNumberList() -> Bool {
        let pattern = "^(( |\t)*[0-9]+\\. )"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            return regex.firstMatch(in: self, options: [], range: NSRange(location: 0, length: count)) != nil
        }

        return false
    }

    public func regexReplace(regex: String, content: String) -> String {
        do {
            let regexExpression = try NSRegularExpression(pattern: regex, options: .caseInsensitive)
            let modified = regexExpression.stringByReplacingMatches(in: self, options: .reportProgress, range: NSRange(location: 0, length: count), withTemplate: content)
            return modified
        } catch {
            return self
        }
    }

    public var isValidUUID: Bool {
        UUID(uuidString: self) != nil
    }

    public func escapePlus() -> String {
        self.replacingOccurrences(of: "+", with: "%20")
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

        let whitespaceChars = NSCharacterSet.whitespacesAndNewlines

        return !unicodeScalars.contains { (unicodeScalar: UnicodeScalar) -> Bool in !whitespaceChars.contains(unicodeScalar) }
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

extension String {
    public subscript(value: Int) -> Character {
        self[index(at: value)]
    }
}

extension String {
    public subscript(value: NSRange) -> Substring {
        self[value.lowerBound..<value.upperBound]
    }
}

extension String {
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
}

extension String {
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
