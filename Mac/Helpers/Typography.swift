//
//  Typography.swift
//  MiaoYan
//
//  Created by Tw93 on 2022/6/16.
//

import Foundation

private enum PanguRegex {
    private static let CJK = "([\\p{InHiragana}\\p{InKatakana}\\p{InBopomofo}\\p{InCJKCompatibilityIdeographs}\\p{InCJKUnifiedIdeographs}])"

    private static func regex(with patten: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: patten, options: .caseInsensitive)
    }

    static let cjk_ans = regex(with: "\(CJK)([a-z0-9`~@\\$%\\^&\\-_\\+=\\|\\\\/])")
    static let ans_cjk = regex(with: "([a-z0-9`~!\\$%\\^&\\-_\\+=\\|\\\\;:,\\./\\?])\(CJK)")
    static let cjk_quote = regex(with: "([\"'])\(CJK)")
    static let quote_cjk = regex(with: "\(CJK)([\"'])")
    static let fix_quote = regex(with: "([\"'])(\\s*)(.+?)(\\s*)([\"'])")
    static let cjk_bracket_cjk = regex(with: "\(CJK)([\\({\\[]+(.*?)[\\)}\\]]+)\(CJK)")
    static let cjk_bracket = regex(with: "\(CJK)([\\(\\){}\\[\\]<>])")
    static let bracket_cjk = regex(with: "\(CJK)([\\(\\){}\\[\\]<>])")
    static let fix_bracket = regex(with: "([(\\({\\[)]+)(\\s*)(.+?)(\\s*)([\\)}\\]]+)")
    static let cjk_hash = regex(with: "\(CJK)(#(\\S+))")
    static let hash_cjk = regex(with: "((\\S+)#)\(CJK)")
}

public extension String {
    private func passWithRule(_ rule: (NSRegularExpression, String)) -> String {
        rule.0.stringByReplacingMatches(
            in: self, options: [],
            range: NSMakeRange(0, self.count), withTemplate: rule.1)
    }

    /// text with paranoid text spacing
    var spaced: String {
        var result = self
        result = result.passWithRule((PanguRegex.cjk_quote, "$1 $2"))
        result = result.passWithRule((PanguRegex.quote_cjk, "$1 $2"))
        result = result.passWithRule((PanguRegex.fix_quote, "$1$3$5"))

        let old = result
        result = result.passWithRule((PanguRegex.cjk_bracket_cjk, "$1 $2 $4"))

        if result == old {
            result = result.passWithRule((PanguRegex.cjk_bracket, "$1 $2"))
            result = result.passWithRule((PanguRegex.bracket_cjk, "$1 $2"))
        }

        result = result.passWithRule((PanguRegex.fix_bracket, "$1$3$5"))
        result = result.passWithRule((PanguRegex.cjk_hash, "$1 $2"))
        result = result.passWithRule((PanguRegex.hash_cjk, "$1 $3"))
        result = result.passWithRule((PanguRegex.cjk_ans, "$1 $2"))
        result = result.passWithRule((PanguRegex.ans_cjk, "$1 $2"))
        return result
    }
}
