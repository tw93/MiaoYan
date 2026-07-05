import UIKit

/// Font/colour palette for the markdown editor, derived from one body font.
struct MarkdownEditorTheme {
    let bodyFont: UIFont

    var ink: UIColor { MobileTheme.inkUIColor }
    var muted: UIColor { MobileTheme.secondaryInkUIColor }
    var accent: UIColor { MobileTheme.accentUIColor }
    var codeBackground: UIColor { MobileTheme.codeBackgroundUIColor }

    var boldFont: UIFont { bodyFont.withTraits(.traitBold) }
    var italicFont: UIFont { bodyFont.withTraits(.traitItalic) }
    var headingFont: UIFont { bodyFont.withTraits(.traitBold) }
    var codeFont: UIFont {
        UIFont.monospacedSystemFont(ofSize: (bodyFont.pointSize * 0.88).rounded(), weight: .regular)
    }

    /// Shared paragraph style. `lineBreakStrategy = []` disables the system
    /// push-out strategy that wraps CJK lines one word early to avoid an
    /// orphan on the last line — the "line breaks too early" complaint in
    /// mixed Chinese/English notes.
    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 6
        style.lineBreakStrategy = []
        return style
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: ink,
            .paragraphStyle: paragraphStyle,
        ]
    }
}

extension UIFont {
    fileprivate func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        let combined = fontDescriptor.symbolicTraits.union(traits)
        guard let descriptor = fontDescriptor.withSymbolicTraits(combined) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

/// Lightweight regex-based markdown syntax highlighting for the mobile
/// editor. Applies attributes directly to the UITextView's textStorage.
/// Deliberately plain-text: markers stay visible, nothing is hidden or
/// resized, so text layout never shifts while typing.
enum MarkdownHighlighter {
    // MARK: - Patterns (compiled once)

    private static let headingRegex = regex("^(#{1,6})[ \\t][^\\n]*$", [.anchorsMatchLines])
    private static let blockquoteRegex = regex("^[ \\t]*>[^\\n]*$", [.anchorsMatchLines])
    private static let listMarkerRegex = regex("^[ \\t]*(?:[-*+]|\\d+[.)])[ \\t]", [.anchorsMatchLines])
    private static let taskMarkerRegex = regex("^[ \\t]*[-*+][ \\t]\\[[ xX]\\]", [.anchorsMatchLines])
    private static let boldRegex = regex("(\\*\\*|__)(?=\\S)(?:.+?)(?<=\\S)\\1", [])
    private static let italicRegex = regex(
        "(?<![*_\\w])([*_])(?=[^*_\\s])(?:[^*_\\n]+?)(?<=\\S)\\1(?![*_\\w])", [])
    private static let strikethroughRegex = regex("~~(?=\\S)(?:.+?)(?<=\\S)~~", [])
    private static let inlineCodeRegex = regex("`[^`\\n]+`", [])
    private static let linkRegex = regex("\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)", [])
    private static let wikilinkRegex = regex("\\[\\[[^\\]\\n]+\\]\\]", [])
    /// Whole fenced block, opening fence line through closing fence line.
    /// `[\s\S]` instead of dot-matches-all keeps the `^` anchors line-based.
    private static let fenceRegex = regex("^```[^\\n]*\\n[\\s\\S]*?\\n```[ \\t]*$", [.anchorsMatchLines])

    private static func regex(
        _ pattern: String, _ options: NSRegularExpression.Options
    ) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: options)
    }

    // MARK: - Passes

    /// Re-apply base attributes and inline/line markdown styling to `range`.
    /// Callers pass a paragraph-aligned range (attributes are line-scoped,
    /// so cutting a paragraph in half would strand stale styling).
    static func highlight(_ storage: NSMutableAttributedString, in range: NSRange, theme: MarkdownEditorTheme) {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        storage.setAttributes(theme.baseAttributes, range: range)
        let text = storage.string as NSString

        apply(headingRegex, to: text, in: range) { match in
            storage.addAttribute(.font, value: theme.headingFont, range: match.range)
            storage.addAttribute(.foregroundColor, value: theme.accent, range: match.range(at: 1))
        }
        apply(blockquoteRegex, to: text, in: range) { match in
            storage.addAttribute(.foregroundColor, value: theme.muted, range: match.range)
        }
        apply(listMarkerRegex, to: text, in: range) { match in
            storage.addAttribute(.foregroundColor, value: theme.accent, range: match.range)
        }
        apply(taskMarkerRegex, to: text, in: range) { match in
            storage.addAttribute(.foregroundColor, value: theme.accent, range: match.range)
        }
        apply(boldRegex, to: text, in: range) { match in
            storage.addAttribute(.font, value: theme.boldFont, range: match.range)
        }
        apply(italicRegex, to: text, in: range) { match in
            storage.addAttribute(.font, value: theme.italicFont, range: match.range)
        }
        apply(strikethroughRegex, to: text, in: range) { match in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
            storage.addAttribute(.foregroundColor, value: theme.muted, range: match.range)
        }
        apply(linkRegex, to: text, in: range) { match in
            storage.addAttribute(.foregroundColor, value: theme.accent, range: match.range(at: 1))
            storage.addAttribute(.foregroundColor, value: theme.muted, range: match.range(at: 2))
        }
        apply(wikilinkRegex, to: text, in: range) { match in
            storage.addAttribute(.foregroundColor, value: theme.accent, range: match.range)
        }
        apply(inlineCodeRegex, to: text, in: range) { match in
            storage.addAttribute(.font, value: theme.codeFont, range: match.range)
            storage.addAttribute(.backgroundColor, value: theme.codeBackground, range: match.range)
        }
    }

    /// Full-document pass for fenced code blocks. Fences span paragraphs,
    /// so paragraph-scoped re-highlighting cannot see them; this is a single
    /// cheap regex sweep the editor runs only when the text contains "```".
    static func highlightCodeFences(_ storage: NSMutableAttributedString, theme: MarkdownEditorTheme) {
        let full = NSRange(location: 0, length: storage.length)
        apply(fenceRegex, to: storage.string as NSString, in: full) { match in
            storage.addAttribute(.font, value: theme.codeFont, range: match.range)
            storage.addAttribute(.foregroundColor, value: theme.ink, range: match.range)
        }
    }

    private static func apply(
        _ regex: NSRegularExpression?,
        to text: NSString,
        in range: NSRange,
        _ body: (NSTextCheckingResult) -> Void
    ) {
        guard let regex else { return }
        regex.enumerateMatches(in: text as String, options: [], range: range) { match, _, _ in
            if let match { body(match) }
        }
    }
}
