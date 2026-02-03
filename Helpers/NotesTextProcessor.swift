import Cocoa
import Highlightr

@MainActor
public class NotesTextProcessor {
    typealias Color = NSColor
    typealias Image = NSImage
    typealias Font = NSFont

    public static var fontColor: NSColor { Theme.textColor }

    public static var highlightColor: NSColor { Theme.linkColor }

    public static var listColor: NSColor { Theme.listColor }

    public static var htmlColor: NSColor { Theme.htmlColor }

    public static var titleColor: NSColor { Theme.titleColor }

    public static var linkColor: NSColor { Theme.linkColor }

    // MARK: Syntax highlight customisation
    @MainActor public static var syntaxColor = fontColor

    public static var font: NSFont {
        UserDefaultsManagement.noteFont
    }

    open var highlightColor: NSColor { Theme.linkColor }
    open var titleColor: NSColor { Theme.titleColor }
    open var linkColor: NSColor { Theme.linkColor }

    public static var underlineColor: NSColor { Theme.underlineColor }
    open var quoteIndentation: CGFloat = 20

    @MainActor public static var codeFont = NSFont(name: UserDefaultsManagement.codeFontName, size: CGFloat(UserDefaultsManagement.fontSize))
    @MainActor public static var georgiaFont = NSFont(name: "Georgia", size: CGFloat(UserDefaultsManagement.fontSize))
    @MainActor public static var publicFont = NSFont(name: "Helvetica Neue", size: CGFloat(UserDefaultsManagement.fontSize))
    @MainActor public static var monacoFont = NSFont(name: "Monaco", size: CGFloat(UserDefaultsManagement.fontSize))
    @MainActor public static var titleFont = NSFont(name: UserDefaultsManagement.windowFontName, size: CGFloat(UserDefaultsManagement.titleFontSize))

    @MainActor public static var hideSyntax = false

    // Performance optimization flags
    @MainActor public static var shouldSkipCodeHighlighting = false
    @MainActor public static var shouldUseSimplifiedHighlighting = false

    private var note: Note?
    private var storage: NSTextStorage?
    private var range: NSRange?
    private var width: CGFloat?

    init(note: Note? = nil, storage: NSTextStorage? = nil, range: NSRange? = nil) {
        self.note = note
        self.storage = storage
        self.range = range
    }

    public static func getFencedCodeBlockRange(paragraphRange: NSRange, string: NSMutableAttributedString) -> NSRange? {
        guard let regex = getCodeBlockRegex() else {
            return nil
        }

        var foundRange: NSRange?
        regex.enumerateMatches(
            in: string.string,
            options: NSRegularExpression.MatchingOptions(),
            range: NSRange(0..<string.length),
            using: { result, _, stop in
                guard let r = result else {
                    return
                }

                if r.range.intersection(paragraphRange) != nil {
                    if r.range.upperBound < string.length {
                        foundRange = NSRange(location: r.range.location, length: r.range.length)
                    } else {
                        foundRange = r.range
                    }

                    stop.pointee = true
                }
            }
        )

        return foundRange
    }

    @MainActor public static func getSpanCodeBlockRange(content: NSMutableAttributedString, range: NSRange) -> NSRange? {
        var codeSpan: NSRange?
        let paragraphRange = content.mutableString.paragraphRange(for: range)
        let paragraph = content.attributedSubstring(from: paragraphRange).string

        if paragraph.contains("`") {
            NotesTextProcessor.codeSpanRegex.matches(content.string, range: paragraphRange) { result in
                if let spanRange = result?.range, spanRange.intersection(range) != nil {
                    codeSpan = spanRange
                }
            }
        }

        return codeSpan
    }

    @MainActor public static var hl: Highlightr?
    @MainActor private static var cachedTheme: String?
    @MainActor private static var cachedCodeBlockRegex: NSRegularExpression?

    @MainActor public static func getHighlighter() -> Highlightr? {
        let codeTheme = UserDataService.instance.isDark ? "tomorrow-night-blue" : "atom-one-light"

        if let instance = hl, cachedTheme == codeTheme {
            return instance
        }

        if let instance = hl {
            instance.setTheme(to: codeTheme)
            cachedTheme = codeTheme
            return instance
        }

        guard let highlightr = Highlightr() else { return nil }
        highlightr.setTheme(to: codeTheme)
        highlightr.ignoreIllegals = true

        hl = highlightr
        cachedTheme = codeTheme
        return highlightr
    }

    @MainActor public static func getCodeBlockRegex() -> NSRegularExpression? {
        if let cached = cachedCodeBlockRegex {
            return cached
        }

        guard
            let regex = try? NSRegularExpression(
                pattern: _codeQuoteBlockPattern,
                options: [.allowCommentsAndWhitespace, .anchorsMatchLines]
            )
        else {
            return nil
        }

        cachedCodeBlockRegex = regex
        return regex
    }

    public static func highlightCode(attributedString: NSMutableAttributedString, range: NSRange, language: String? = nil) {
        guard range.upperBound <= attributedString.length else {
            return
        }

        if shouldSkipCodeHighlighting {
            applyBasicCodeStyle(attributedString: attributedString, range: range)
            return
        }

        let maxCodeBlockSize = shouldUseSimplifiedHighlighting ? 500 : 3000

        if range.length > maxCodeBlockSize {
            applyBasicCodeStyle(attributedString: attributedString, range: range)
            return
        }

        guard let highlighter = NotesTextProcessor.getHighlighter() else {
            applyBasicCodeStyle(attributedString: attributedString, range: range)
            return
        }

        let codeString = attributedString.mutableString.substring(with: range)
        let preDefinedLanguage = language ?? getLanguage(codeString)

        guard let code = highlighter.highlight(codeString, as: preDefinedLanguage),
            code.string == attributedString.mutableString.substring(with: range)
        else {
            applyBasicCodeStyle(attributedString: attributedString, range: range)
            return
        }

        code.enumerateAttributes(in: NSRange(location: 0, length: code.length)) { attrs, locRange, _ in
            let fixedRange = NSRange(
                location: range.location + locRange.location,
                length: min(locRange.length, attributedString.length - (range.location + locRange.location))
            )

            guard fixedRange.length > 0, fixedRange.upperBound <= attributedString.length else {
                return
            }

            attributedString.addAttributes(attrs, range: fixedRange)

            if let font = NotesTextProcessor.codeFont {
                attributedString.addAttribute(.font, value: font, range: fixedRange)
            }
        }

        attributedString.addAttribute(.codeBlock, value: true, range: range)
        if let language = preDefinedLanguage {
            attributedString.addAttribute(.codeLanguage, value: language, range: range)
        } else {
            attributedString.removeAttribute(.codeLanguage, range: range)
        }

        attributedString.fixAttributes(in: range)
    }

    private static func applyBasicCodeStyle(attributedString: NSMutableAttributedString, range: NSRange) {
        guard range.upperBound <= attributedString.length,
            let codeFont = NotesTextProcessor.codeFont
        else {
            return
        }

        let codeColor =
            UserDataService.instance.isDark
            ? NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
            : NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)

        attributedString.addAttribute(.font, value: codeFont, range: range)
        attributedString.addAttribute(.foregroundColor, value: codeColor, range: range)
        attributedString.addAttribute(.codeBlock, value: true, range: range)
        attributedString.removeAttribute(.codeLanguage, range: range)
        attributedString.fixAttributes(in: range)
    }

    @MainActor public static var languages: [String]?

    @MainActor public static func getLanguage(_ code: String) -> String? {
        guard code.starts(with: "```") else { return nil }

        let range = code.startIndex..<code.index(code.startIndex, offsetBy: 3)
        let paragraphRange = code.paragraphRange(for: range)
        let detectedLang = code[paragraphRange]
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        languages = getHighlighter()?.supportedLanguages()

        guard let supportedLanguages = languages,
            supportedLanguages.contains(detectedLang),
            detectedLang != "go"
        else {
            return nil
        }

        return detectedLang
    }

    public static func convertAppLinks(in content: NSMutableAttributedString) -> NSMutableAttributedString {
        let attributedString = content.mutableCopy() as! NSMutableAttributedString
        let fullRange = NSRange(location: 0, length: attributedString.length)
        let tagQuery = "miaoyan://goto/"

        // Process app link patterns
        appUrlRegex.matches(content.string, range: fullRange) { result in
            guard let innerRange = result?.range else { return }

            let substring = attributedString.mutableString.substring(with: innerRange)
                .replacingOccurrences(of: "[[", with: "")
                .replacingOccurrences(of: "]]", with: "")
                .trim()

            guard let tag = substring.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }
            attributedString.addAttribute(.link, value: "\(tagQuery)\(tag)", range: innerRange)
        }

        var replacements: [(range: NSRange, text: String)] = []

        var index = 0
        while index < attributedString.length {
            var effectiveRange = NSRange(location: index, length: 0)
            let value = attributedString.attribute(.link, at: index, effectiveRange: &effectiveRange)

            if let linkValue = value as? String,
                linkValue.starts(with: tagQuery),
                let tag = linkValue.replacingOccurrences(of: tagQuery, with: "").removingPercentEncoding,
                effectiveRange.length > 0
            {
                if getSpanCodeBlockRange(content: attributedString, range: effectiveRange) == nil,
                    getFencedCodeBlockRange(paragraphRange: effectiveRange, string: attributedString) == nil
                {
                    let markdownLink = "[\(tag)](\(linkValue))"
                    replacements.append((effectiveRange, markdownLink))
                }
            }

            let nextIndex = effectiveRange.length > 0 ? NSMaxRange(effectiveRange) : index + 1
            index = nextIndex
        }

        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            attributedString.replaceCharacters(in: replacement.range, with: replacement.text)
        }

        return attributedString
    }

    @MainActor public static func highlight(note: Note) {
        // Tiered performance optimization based on file size
        checkPerformanceLevel(attributedString: note.content)

        // For very large files, skip all complex highlighting
        if shouldUseSimplifiedHighlighting {
            highlightBasicMarkdown(attributedString: note.content, note: note)
        } else {
            highlightMarkdown(attributedString: note.content, note: note)
            highlightFencedAndIndentCodeBlocks(attributedString: note.content)
        }
    }

    @MainActor public static func checkPerformanceLevel(attributedString: NSMutableAttributedString) {
        let lineCount = attributedString.string.components(separatedBy: .newlines).count
        if lineCount > 5000 {
            shouldUseSimplifiedHighlighting = true
            shouldSkipCodeHighlighting = true
            return
        }

        if lineCount > 2000 {
            shouldUseSimplifiedHighlighting = true
            shouldSkipCodeHighlighting = false
            return
        }

        shouldUseSimplifiedHighlighting = false

        let range = NSRange(0..<attributedString.length)
        guard range.length > 0 else {
            shouldSkipCodeHighlighting = false
            return
        }

        guard let regex = getCodeBlockRegex() else {
            shouldSkipCodeHighlighting = false
            return
        }

        var matchCount = 0
        regex.enumerateMatches(in: attributedString.string, options: [], range: range) { _, _, stop in
            matchCount += 1
            if matchCount > 20 {
                stop.pointee = true
            }
        }
        shouldSkipCodeHighlighting = matchCount > 20
    }

    // Simplified highlighting for large files - only basic styles, no regex-heavy operations
    public static func highlightBasicMarkdown(attributedString: NSMutableAttributedString, range: NSRange? = nil, note: Note) {
        let range = range ?? NSRange(0..<attributedString.length)
        let string = attributedString.string

        // Ensure range is valid
        guard range.upperBound <= attributedString.length else { return }

        // Apply basic font and color
        attributedString.removeAttribute(.codeBlock, range: range)
        attributedString.removeAttribute(.codeLanguage, range: range)
        attributedString.addAttribute(.font, value: font, range: range)
        attributedString.addAttribute(.foregroundColor, value: fontColor, range: range)

        // 1. Headers (Fast & Critical for structure) - Support H1 to H6
        NotesTextProcessor.headersAtxRegex.matches(string, range: range) { result in
            guard let range = result?.range, range.upperBound <= attributedString.length else { return }
            attributedString.addAttribute(.foregroundColor, value: titleColor, range: range)
        }

        // 2. Lists (Fast & Visual)
        NotesTextProcessor.listRegex.matches(string, range: range) { result in
            guard let range = result?.range, range.upperBound <= attributedString.length else { return }

            // Only highlight the marker to keep it fast
            NotesTextProcessor.listOpeningRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range, innerRange.upperBound <= attributedString.length else { return }
                attributedString.addAttribute(.foregroundColor, value: listColor, range: innerRange)
            }
        }

        // 3. Blockquotes (Fast)
        NotesTextProcessor.blockQuoteRegex.matches(string, range: range) { result in
            guard let range = result?.range, range.upperBound <= attributedString.length else { return }
            attributedString.addAttribute(.foregroundColor, value: listColor, range: range)
        }

        // 4. Basic Fenced Code Blocks (No syntax highlighting, just color)
        // Note: We use getCodeBlockRegex() which is cached, but we only iterate lightly
        if let regex = getCodeBlockRegex() {
            // Use enumerateMatches with a simpler block to avoid overhead
            regex.enumerateMatches(in: string, options: [], range: range) { result, _, _ in
                guard let codeRange = result?.range, codeRange.upperBound <= attributedString.length else { return }

                // Use a single color for the whole block instead of parsing language
                let codeColor =
                    UserDataService.instance.isDark
                    ? NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
                    : NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)

                if let codeFont = NotesTextProcessor.codeFont {
                    attributedString.addAttribute(.font, value: codeFont, range: codeRange)
                }
                attributedString.addAttribute(.foregroundColor, value: codeColor, range: codeRange)
                attributedString.addAttribute(.codeBlock, value: true, range: codeRange)
                attributedString.removeAttribute(.codeLanguage, range: codeRange)
            }
        }

        // 5. Images (Fast & Visual) - Critical for "default.md" which has many images
        NotesTextProcessor.imageRegex.matches(string, range: range) { result in
            guard let range = result?.range, range.upperBound <= attributedString.length else { return }
            // Highlight the entire image markdown syntax
            attributedString.addAttribute(.foregroundColor, value: linkColor, range: range)
        }

        attributedString.fixAttributes(in: range)
    }

    public static func highlightFencedAndIndentCodeBlocks(attributedString: NSMutableAttributedString) {
        let range = NSRange(0..<attributedString.length)
        guard range.length > 0 else { return }

        guard let regex = getCodeBlockRegex() else {
            return
        }

        regex.enumerateMatches(in: attributedString.string, range: range) { result, _, _ in
            guard let codeRange = result?.range,
                codeRange.upperBound <= attributedString.length
            else {
                return
            }
            NotesTextProcessor.highlightCode(attributedString: attributedString, range: codeRange)
        }
    }

    public static func isIntersect(fencedRanges: [NSRange], indentRange: NSRange) -> Bool {
        for fencedRange in fencedRanges where fencedRange.intersection(indentRange) != nil {
            return true
        }
        return false
    }

    // swiftlint:disable:next cyclomatic_complexity
    public static func highlightMarkdown(attributedString: NSMutableAttributedString, paragraphRange: NSRange? = nil, note: Note) {
        let paragraphRange = paragraphRange ?? NSRange(0..<attributedString.length)
        let isFullScan = attributedString.length == paragraphRange.upperBound && paragraphRange.lowerBound == 0
        let string = attributedString.string

        let quoteFont = NotesTextProcessor.quoteFont(CGFloat(UserDefaultsManagement.fontSize))

        let hiddenFont = NSFont.systemFont(ofSize: 0.1)

        let hiddenColor = Color.clear
        let hiddenAttributes: [NSAttributedString.Key: Any] = [
            .font: hiddenFont,
            .foregroundColor: hiddenColor,
        ]

        func hideSyntaxIfNecessary(range: @autoclosure () -> NSRange) {
            guard NotesTextProcessor.hideSyntax else { return }
            attributedString.addAttributes(hiddenAttributes, range: range())
        }

        attributedString.enumerateAttribute(.link, in: paragraphRange) { value, range, _ in
            guard value != nil,
                range.upperBound <= attributedString.length,
                attributedString.attribute(.attachment, at: range.location, effectiveRange: nil) == nil
            else {
                return
            }
            attributedString.removeAttribute(.link, range: range)
        }

        attributedString.enumerateAttribute(.strikethroughStyle, in: paragraphRange) { value, range, _ in
            guard value != nil, range.upperBound <= attributedString.length else {
                return
            }
            attributedString.removeAttribute(.strikethroughStyle, range: range)
        }

        attributedString.addAttribute(.font, value: font, range: paragraphRange)
        attributedString.fixAttributes(in: paragraphRange)

        attributedString.addAttribute(.foregroundColor, value: fontColor, range: paragraphRange)
        attributedString.enumerateAttribute(.foregroundColor, in: paragraphRange) { value, range, _ in
            guard value is NSColor,
                range.upperBound <= attributedString.length
            else {
                return
            }
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.fontColor, range: range)
        }

        NotesTextProcessor.italicRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                range.upperBound <= attributedString.length
            else {
                return
            }
            attributedString.fixAttributes(in: range)
            attributedString.addAttribute(.foregroundColor, value: titleColor, range: range)
        }

        NotesTextProcessor.boldRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                range.upperBound <= attributedString.length
            else {
                return
            }
            attributedString.fixAttributes(in: range)
            attributedString.addAttribute(.foregroundColor, value: htmlColor, range: range)
        }

        NotesTextProcessor.strikeRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                range.upperBound <= attributedString.length
            else {
                return
            }
            attributedString.fixAttributes(in: range)
            attributedString.addAttribute(.foregroundColor, value: htmlColor, range: range)
        }

        NotesTextProcessor.codeLineRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                range.upperBound <= attributedString.length
            else {
                return
            }
            attributedString.fixAttributes(in: range)
            attributedString.addAttribute(.foregroundColor, value: htmlColor, range: range)
        }

        // We detect and process underlined headers
        NotesTextProcessor.headersSetextRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                range.upperBound <= attributedString.length
            else {
                return
            }
            attributedString.fixAttributes(in: range)

            NotesTextProcessor.headersSetextUnderlineRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range,
                    innerRange.upperBound <= attributedString.length
                else {
                    return
                }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                hideSyntaxIfNecessary(range: NSRange(location: innerRange.location, length: innerRange.length))
            }
        }

        // We detect and process dashed headers
        NotesTextProcessor.headersAtxRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                range.upperBound <= attributedString.length
            else {
                return
            }
            attributedString.addAttribute(.foregroundColor, value: titleColor, range: range)
            attributedString.fixAttributes(in: range)

            NotesTextProcessor.headersAtxOpeningRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range,
                    innerRange.upperBound <= attributedString.length
                else {
                    return
                }
                attributedString.addAttribute(.foregroundColor, value: titleColor, range: innerRange)
                let syntaxRange = NSRange(location: innerRange.location, length: innerRange.length + 1)
                guard syntaxRange.upperBound <= attributedString.length else { return }
                hideSyntaxIfNecessary(range: syntaxRange)
            }

            NotesTextProcessor.headersAtxClosingRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range,
                    innerRange.upperBound <= attributedString.length
                else {
                    return
                }
                attributedString.addAttribute(.foregroundColor, value: titleColor, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }
        }

        // We detect and process reference links
        NotesTextProcessor.referenceLinkRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                range.upperBound <= attributedString.length
            else {
                return
            }
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: range)
        }

        // We detect and process lists
        NotesTextProcessor.listRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                range.upperBound <= attributedString.length
            else {
                return
            }

            NotesTextProcessor.listOpeningRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range,
                    innerRange.upperBound <= attributedString.length
                else {
                    return
                }
                attributedString.addAttribute(.foregroundColor, value: listColor, range: innerRange)
            }
        }

        // We detect and process anchors (links)
        NotesTextProcessor.anchorRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }
            attributedString.fixAttributes(in: range)
            NotesTextProcessor.openingSquareRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
            NotesTextProcessor.closingSquareRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
            NotesTextProcessor.parenRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                let initialSyntaxRange = NSRange(location: innerRange.location, length: 1)
                let finalSyntaxRange = NSRange(location: innerRange.location + innerRange.length - 1, length: 1)
                hideSyntaxIfNecessary(range: initialSyntaxRange)
                hideSyntaxIfNecessary(range: finalSyntaxRange)
            }
        }

        // We detect and process inline anchors (links)
        NotesTextProcessor.anchorInlineRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }
            attributedString.fixAttributes(in: range)

            var destinationLink: String?

            NotesTextProcessor.coupleRoundRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)

                guard let linkRange = result?.range(at: 3), linkRange.length > 0 else { return }

                var substring = attributedString.mutableString.substring(with: linkRange)

                guard !substring.isEmpty else { return }
                guard let note = EditTextView.note else { return }

                if substring.starts(with: "/i/") || substring.starts(with: "/files/"), let path = note.project.url.appendingPathComponent(substring).path.removingPercentEncoding {
                    substring = "file://" + path
                }

                destinationLink = substring

                attributedString.addAttribute(.link, value: substring, range: linkRange)
                hideSyntaxIfNecessary(range: innerRange)
            }

            NotesTextProcessor.openingSquareRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }

            NotesTextProcessor.closingSquareRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }

            guard destinationLink != nil else { return }

            NotesTextProcessor.coupleSquareRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                var _range = innerRange
                _range.location += 1
                _range.length -= 2

                let substring = attributedString.mutableString.substring(with: _range)
                guard substring.lengthOfBytes(using: .utf8) > 0 else { return }

                attributedString.addAttribute(.foregroundColor, value: linkColor, range: _range)
            }
        }

        NotesTextProcessor.imageRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }
            attributedString.fixAttributes(in: range)

            // TODO: add image attachment
            if NotesTextProcessor.hideSyntax {
                attributedString.addAttribute(.font, value: hiddenFont, range: range)
            }
            NotesTextProcessor.imageOpeningSquareRegex.matches(string, range: paragraphRange) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: linkColor, range: innerRange)
            }
            NotesTextProcessor.imageClosingSquareRegex.matches(string, range: paragraphRange) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
        }

        // We detect and process app urls [[link]]
        NotesTextProcessor.appUrlRegex.matches(string, range: paragraphRange) { result in

            guard let innerRange = result?.range else { return }
            var _range = innerRange
            _range.location += 2
            _range.length -= 4

            let appLink = attributedString.mutableString.substring(with: _range)

            attributedString.addAttribute(.link, value: "miaoyan://goto/" + appLink, range: _range)
            attributedString.addAttribute(.foregroundColor, value: linkColor, range: _range)
            if let range = result?.range(at: 0) {
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: range)
            }

            if let range = result?.range(at: 2) {
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: range)
            }
        }

        // We detect and process quotes
        NotesTextProcessor.blockQuoteRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }
            attributedString.addAttribute(.font, value: quoteFont, range: range)
            attributedString.fixAttributes(in: range)
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.listColor, range: range)
            NotesTextProcessor.blockQuoteOpeningRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.listColor, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }
        }

        NotesTextProcessor.imageInlineRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }

            if let linkRange = result?.range(at: 3) {
                let link = attributedString.mutableString.substring(with: linkRange).removingPercentEncoding

                if let link = link, let url = note.getImageUrl(imageName: link) {
                    attributedString.addAttribute(.link, value: url, range: linkRange)
                    attributedString.addAttribute(.foregroundColor, value: linkColor, range: linkRange)
                }
            }

            NotesTextProcessor.imageOpeningSquareRegex.matches(string, range: paragraphRange) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
            NotesTextProcessor.imageClosingSquareRegex.matches(string, range: paragraphRange) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
            NotesTextProcessor.parenRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
        }

        NotesTextProcessor.htmlRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }
            attributedString.fixAttributes(in: range)
            NotesTextProcessor.highlightCode(attributedString: attributedString, range: range)
        }

        NotesTextProcessor.imageHtmlRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }
            attributedString.fixAttributes(in: range)
            NotesTextProcessor.highlightCode(attributedString: attributedString, range: range)
        }

        NotesTextProcessor.emojiRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                getSpanCodeBlockRange(content: attributedString, range: range) == nil,
                getFencedCodeBlockRange(paragraphRange: range, string: attributedString) == nil
            else { return }

            let substring = attributedString.mutableString.substring(with: range)
            if !substring.isNumber {
                attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: CGFloat(UserDefaultsManagement.fontSize - 2)), range: range)
                attributedString.fixAttributes(in: range)
            }
        }

        if UserDefaultsManagement.fontName == "SF Mono" {
            NotesTextProcessor.blankRegex.matches(string, range: paragraphRange) { result in
                guard let range = result?.range else { return }
                attributedString.addAttribute(.font, value: publicFont!, range: range)
            }
        }

        if UserDefaultsManagement.fontName == "Times New Roman", georgiaFont != nil {
            NotesTextProcessor.englishAndSymbolRegex.matches(string, range: paragraphRange) { result in
                guard let range = result?.range else { return }
                attributedString.addAttribute(.font, value: georgiaFont!, range: range)
            }
        }

        if monacoFont != nil {
            NotesTextProcessor.allTodoInlineRegex.matches(string, range: paragraphRange) { result in
                guard let range = result?.range else { return }
                let middleRange = NSRange(location: range.location + 3, length: 1)

                attributedString.addAttribute(.font, value: monacoFont!, range: middleRange)
            }
        }

        attributedString.enumerateAttribute(.attachment, in: paragraphRange) { value, range, _ in
            guard value != nil,
                range.upperBound <= attributedString.length,
                let todo = attributedString.attribute(.todo, at: range.location, effectiveRange: nil)
            else {
                return
            }
            let strikeRange = attributedString.mutableString.paragraphRange(for: range)
            guard strikeRange.upperBound <= attributedString.length else { return }
            attributedString.addAttribute(.strikethroughStyle, value: todo, range: strikeRange)
        }

        if isFullScan {
            checkBackTick(styleApplier: attributedString)
        }
    }

    public static func checkBackTick(styleApplier: NSMutableAttributedString, paragraphRange: NSRange? = nil) {
        let range = paragraphRange ?? NSRange(0..<styleApplier.length)
        guard range.upperBound <= styleApplier.length else { return }

        styleApplier.enumerateAttribute(.backgroundColor, in: range) { value, innerRange, _ in
            guard value != nil,
                innerRange.upperBound <= styleApplier.length,
                let font = UserDefaultsManagement.noteFont
            else {
                return
            }
            styleApplier.removeAttribute(.backgroundColor, range: innerRange)
            styleApplier.addAttribute(.font, value: font, range: innerRange)
            styleApplier.fixAttributes(in: innerRange)
        }

        NotesTextProcessor.codeSpanRegex.matches(styleApplier.string, range: range) { result in
            guard let matchRange = result?.range,
                matchRange.upperBound <= styleApplier.length
            else {
                return
            }
            styleApplier.addAttribute(.foregroundColor, value: NotesTextProcessor.htmlColor, range: matchRange)
        }

        if UserDefaultsManagement.fontName == "Times New Roman" {
            NotesTextProcessor.englishAndSymbolRegex.matches(styleApplier.string, range: range) { result in
                guard let matchRange = result?.range,
                    matchRange.upperBound <= styleApplier.length
                else {
                    return
                }
                styleApplier.addAttribute(.font, value: georgiaFont!, range: matchRange)
            }

            if monacoFont != nil {
                NotesTextProcessor.allTodoInlineRegex.matches(styleApplier.string, range: range) { result in
                    guard let matchRange = result?.range,
                        matchRange.upperBound <= styleApplier.length
                    else {
                        return
                    }
                    let middleRange = NSRange(location: matchRange.location + 3, length: 1)
                    guard middleRange.upperBound <= styleApplier.length else { return }
                    styleApplier.addAttribute(.font, value: monacoFont!, range: middleRange)
                }
            }
        }
    }

    public static func getAttachPrefix(url: URL? = nil) -> String {
        if let url = url, !url.isImage {
            return "/files/"
        }

        return "/i/"
    }

    /// Tabs are automatically converted to spaces as part of the transform
    /// this constant determines how "wide" those tabs become in spaces
    public static let _tabWidth = 4

    // MARK: Headers
    /*
     Head
     ======
    
     Subhead
     -------
     */

    fileprivate static let headerSetextPattern = [
        "^(.+?)",
        "\\p{Z}*",
        "\\n",
        "(==+|--+)",  // $1 = string of ='s or -'s
        "\\p{Z}*",
        "\\n|\\Z",
    ].joined(separator: "\n")

    @MainActor public static let headersSetextRegex = MarklightRegex(pattern: headerSetextPattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])

    fileprivate static let setextUnderlinePattern = [
        "(==+|--+)     # $1 = string of ='s or -'s",
        "\\p{Z}*$",
    ].joined(separator: "\n")

    @MainActor public static let headersSetextUnderlineRegex = MarklightRegex(pattern: setextUnderlinePattern, options: [.allowCommentsAndWhitespace])

    /*
     # Head
    
     ## Subhead ##
     */

    fileprivate static let headerAtxPattern = [
        "^(\\#{1,6}\\  )  # $1 = string of #'s",
        "\\p{Z}*",
        "(.+?)        # $2 = Header text",
        "\\p{Z}*",
        "\\#*         # optional closing #'s (not counted)",
        "(?:\\n|\\Z)",
    ].joined(separator: "\n")

    @MainActor public static let headersAtxRegex = MarklightRegex(pattern: headerAtxPattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])

    fileprivate static let headersAtxOpeningPattern = [
        "^(\\#{1,6}\\ )"
    ].joined(separator: "\n")

    @MainActor public static let headersAtxOpeningRegex = MarklightRegex(pattern: headersAtxOpeningPattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])

    fileprivate static let headersAtxClosingPattern = [
        "\\#{1,6}\\ \\n+"
    ].joined(separator: "\n")

    @MainActor public static let headersAtxClosingRegex = MarklightRegex(pattern: headersAtxClosingPattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])

    // MARK: Reference links
    /*
     TODO: we don't know how reference links are formed
     */

    fileprivate static let referenceLinkPattern = [
        "^\\p{Z}{0,\(_tabWidth - 1)}\\[([^\\[\\]]+)\\]:  # id = $1",
        "  \\p{Z}*",
        "  \\n?                   # maybe *one* newline",
        "  \\p{Z}*",
        "<?(\\S+?)>?              # url = $2",
        "  \\p{Z}*",
        "  \\n?                   # maybe one newline",
        "  \\p{Z}*",
        "(?:",
        "    (?<=\\s)             # lookbehind for whitespace",
        "    [\"(]",
        "    (.+?)                # title = $3",
        "    [\")]",
        "    \\p{Z}*",
        ")?                       # title is optional",
        "(?:\\n|\\Z)",
    ].joined(separator: "")

    @MainActor public static let referenceLinkRegex = MarklightRegex(pattern: referenceLinkPattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])

    // MARK: Lists
    /*
     * First element
     * Second element
     */

    fileprivate static let _markerUL = "[*+-]"
    fileprivate static let _markerOL = "[0-9-]+[.]"

    fileprivate static let _listMarker = "(?:\\p{Z}|\\t)*(?:\(_markerUL)|\(_markerOL))"
    fileprivate static let _listSingleLinePattern = "^(?:\\p{Z}|\\t)*((?:[*+-]|\\d+[.]))\\p{Z}+"

    @MainActor public static let listRegex = MarklightRegex(pattern: _listSingleLinePattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])
    @MainActor public static let listOpeningRegex = MarklightRegex(pattern: _listMarker, options: [.allowCommentsAndWhitespace])

    // MARK: Anchors
    /*
     [Title](http://example.com)
     */

    fileprivate static let anchorPattern = [
        "(                                  # wrap whole match in $1",
        "    \\[",
        "        (\(NotesTextProcessor.getNestedBracketsPattern()))  # link text = $2",
        "    \\]",
        "",
        "    \\p{Z}?                        # one optional space",
        "    (?:\\n\\p{Z}*)?                # one optional newline followed by spaces",
        "",
        "    \\[",
        "        (.*?)                      # id = $3",
        "    \\]",
        ")",
    ].joined(separator: "\n")

    @MainActor public static let anchorRegex = MarklightRegex(pattern: anchorPattern, options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators])

    fileprivate static let openingSquarePattern = [
        "(\\[)"
    ].joined(separator: "\n")

    @MainActor public static let openingSquareRegex = MarklightRegex(pattern: openingSquarePattern, options: [.allowCommentsAndWhitespace])

    fileprivate static let closingSquarePattern = [
        "\\]"
    ].joined(separator: "\n")

    @MainActor public static let closingSquareRegex = MarklightRegex(pattern: closingSquarePattern, options: [.allowCommentsAndWhitespace])

    fileprivate static let coupleSquarePattern = [
        "\\[(.*?)\\]"
    ].joined(separator: "\n")

    @MainActor public static let coupleSquareRegex = MarklightRegex(pattern: coupleSquarePattern, options: [])

    fileprivate static let coupleRoundPattern = [
        ".*(?:\\])\\((.+)\\)"
    ].joined(separator: "\n")

    @MainActor public static let coupleRoundRegex = MarklightRegex(pattern: coupleRoundPattern, options: [])

    fileprivate static let parenPattern = [
        "(",
        "\\(                 # literal paren",
        "      \\p{Z}*",
        "      (\(NotesTextProcessor.getNestedParensPattern()))    # href = $3",
        "      \\p{Z}*",
        "      (               # $4",
        "      (['\"])         # quote char = $5",
        "      (.*?)           # title = $6",
        "      \\5             # matching quote",
        "      \\p{Z}*",
        "      )?              # title is optional",
        "  \\)",
        ")",
    ].joined(separator: "\n")

    @MainActor public static let parenRegex = MarklightRegex(pattern: parenPattern, options: [.allowCommentsAndWhitespace])

    fileprivate static let anchorInlinePattern = [
        "(                           # wrap whole match in $1",
        "    \\[",
        "        (\(NotesTextProcessor.getNestedBracketsPattern()))   # link text = $2",
        "    \\]",
        "    \\(                     # literal paren",
        "        \\p{Z}*",
        "        (\(NotesTextProcessor.getNestedParensPattern()))   # href = $3",
        "        \\p{Z}*",
        "        (                   # $4",
        "        (['\"])           # quote char = $5",
        "        (.*?)               # title = $6",
        "        \\5                 # matching quote",
        "        \\p{Z}*                # ignore any spaces between closing quote and )",
        "        )?                  # title is optional",
        "    \\)",
        ")",
    ].joined(separator: "\n")

    @MainActor public static let anchorInlineRegex = MarklightRegex(pattern: anchorInlinePattern, options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators])

    // MARK: Images
    /*
     ![Title](http://example.com/image.png)
     */

    fileprivate static let imagePattern = [
        "(               # wrap whole match in $1",
        "!\\[",
        "    (.*?)       # alt text = $2",
        "\\]",
        "",
        "\\p{Z}?            # one optional space",
        "(?:\\n\\p{Z}*)?    # one optional newline followed by spaces",
        "",
        "\\[",
        "    (.*?)       # id = $3",
        "\\]",
        "",
        ")",
    ].joined(separator: "\n")

    @MainActor public static let imageRegex = MarklightRegex(pattern: imagePattern, options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators])

    fileprivate static let imageOpeningSquarePattern = [
        "(!\\[)"
    ].joined(separator: "\n")

    @MainActor public static let imageOpeningSquareRegex = MarklightRegex(pattern: imageOpeningSquarePattern, options: [.allowCommentsAndWhitespace])

    fileprivate static let imageClosingSquarePattern = [
        "(\\])"
    ].joined(separator: "\n")

    @MainActor public static let imageClosingSquareRegex = MarklightRegex(pattern: imageClosingSquarePattern, options: [.allowCommentsAndWhitespace])

    fileprivate static let imageInlinePattern = [
        "(                     # wrap whole match in $1",
        "  !\\[",
        "      ([^\\[\\]]*?)           # alt text = $2",
        "  \\]",
        "  \\s?                # one optional whitespace character",
        "  \\(                 # literal paren",
        "      \\p{Z}*",
        "      (\(NotesTextProcessor.getNestedParensPattern()))    # href = $3",
        "      \\p{Z}*",
        "      (               # $4",
        "      (['\"])         # quote char = $5",
        "      (.*?)           # title = $6",
        "      \\5             # matching quote",
        "      \\p{Z}*",
        "      )?              # title is optional",
        "  \\)",
        ")",
    ].joined(separator: "\n")

    @MainActor public static let imageInlineRegex = MarklightRegex(pattern: imageInlinePattern, options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators])

    fileprivate static let todoInlinePattern = "(^(-\\ \\[(?:\\ |x)\\])\\ )"

    @MainActor public static let todoInlineRegex = MarklightRegex(pattern: todoInlinePattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])

    fileprivate static let allTodoInlinePattern = "((-\\ \\[(?:\\ |x)\\])\\ )"

    @MainActor public static let allTodoInlineRegex = MarklightRegex(pattern: allTodoInlinePattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])

    // MARK: Code
    /*
     ```
     Code
     ```
    
     Code
     */
    public static let _codeQuoteBlockPattern = [
        "(?<=\\n|\\A)",
        "(^```[\\S\\ \\(\\)]*\\n[\\s\\S]*?\\n```(?:\\n|\\Z))",
    ].joined(separator: "\n")

    fileprivate static let codeSpanPattern = [
        "(?<![\\\\`])   # Character before opening ` can't be a backslash or backtick",
        "(`+)           # $1 = Opening run of `",
        "(?!`)          # and no more backticks -- match the full run",
        "(.+?)          # $2 = The code block",
        "(?<!`)",
        "\\1",
        "(?!`)",
    ].joined(separator: "\n")

    @MainActor public static let codeSpanRegex = MarklightRegex(pattern: codeSpanPattern, options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators])

    fileprivate static let codeSpanOpeningPattern = [
        "(?<![\\\\`])   # Character before opening ` can't be a backslash or backtick",
        "(`+)           # $1 = Opening run of `",
    ].joined(separator: "\n")

    @MainActor public static let codeSpanOpeningRegex = MarklightRegex(pattern: codeSpanOpeningPattern, options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators])

    fileprivate static let codeSpanClosingPattern = [
        "(?<![\\\\`])   # Character before opening ` can't be a backslash or backtick",
        "(`+)           # $1 = Opening run of `",
    ].joined(separator: "\n")

    @MainActor public static let codeSpanClosingRegex = MarklightRegex(pattern: codeSpanClosingPattern, options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators])

    // MARK: Block quotes
    /*
     > Quoted text
     */

    fileprivate static let blockQuotePattern = [
        "(                           # Wrap whole match in $1",
        "    (",
        "    ^\\p{Z}*>\\p{Z}?              # '>' at the start of a line",
        "        .+(?:\\n|\\Z)               # rest of the first line",
        "    (.+(?:\\n|\\Z))*                # subsequent consecutive lines",
        "    (?:\\n|\\Z)*                    # blanks",
        "    )+",
        ")",
    ].joined(separator: "\n")

    @MainActor public static let blockQuoteRegex = MarklightRegex(pattern: blockQuotePattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])

    fileprivate static let blockQuoteOpeningPattern = [
        "(^\\p{Z}*>\\p{Z})"
    ].joined(separator: "\n")

    @MainActor public static let blockQuoteOpeningRegex = MarklightRegex(pattern: blockQuoteOpeningPattern, options: [.anchorsMatchLines])

    // MARK: App url
    fileprivate static let appUrlPattern = "(\\[\\[)(.+?[\\[\\]]*)\\]\\]"
    @MainActor public static let appUrlRegex = MarklightRegex(pattern: appUrlPattern, options: [.anchorsMatchLines])

    // MARK: Bold
    fileprivate static let strictBoldPattern = "(^|[\\W_])(?:(?!\\1)|(?=^))(\\*|_)\\2(?=\\S)(.*?\\S)\\2\\2(?!\\2)(?=[\\W_]|$)"
    @MainActor public static let strictBoldRegex = MarklightRegex(pattern: strictBoldPattern, options: [.anchorsMatchLines])

    fileprivate static let boldPattern = "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1"
    @MainActor public static let boldRegex = MarklightRegex(pattern: boldPattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])

    // MARK: Strike
    fileprivate static let strikePattern = "(\\~\\~) (?=\\S) (.+?[~]*) (?<=\\S) \\1"
    @MainActor public static let strikeRegex = MarklightRegex(pattern: strikePattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])

    fileprivate static let codeLinePattern = "(\\`\\`\\`) (?=\\S) (.+?[`]*) (?<=\\S) \\1"
    @MainActor public static let codeLineRegex = MarklightRegex(pattern: codeLinePattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])

    // MARK: HTML
    fileprivate static let htmlPattern = "<(\\S*)[^>]*>[^<]*<\\/(\\1)>"
    @MainActor public static let htmlRegex = MarklightRegex(pattern: htmlPattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])

    fileprivate static let imageHtmlPattern = "<(img|br|hr|input)[^>]*>"
    @MainActor public static let imageHtmlRegex = MarklightRegex(pattern: imageHtmlPattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])

    @MainActor public static let emojiRegex = MarklightRegex(pattern: EmojiPattern, options: [.allowCommentsAndWhitespace])

    public static let englishAndSymbolPattern = "([a-zA-Z]+|[\\x21-\\x2f\\x3a-\\x40\\x5b-\\x60\\x7B-\\x7F])"
    @MainActor public static let englishAndSymbolRegex = MarklightRegex(pattern: englishAndSymbolPattern, options: [.allowCommentsAndWhitespace])

    @MainActor public static let blankRegex = MarklightRegex(pattern: "\\s+", options: [.allowCommentsAndWhitespace])

    // MARK: Italic
    fileprivate static let strictItalicPattern = "(^|[\\s_])(?:(?!\\1)|(?=^))(\\*|_)(?=\\S)((?:(?!\\2).)*?\\S)\\2(?!\\2)(?=[\\s]|(?:[.,!?]\\s)|$)"

    @MainActor public static let strictItalicRegex = MarklightRegex(pattern: strictItalicPattern, options: [.anchorsMatchLines])

    fileprivate static let italicPattern = "(?<!\\*|_)(?<!\\*\\*)(\\*|_)(?!\\s)(.+?)(?<!\\s)\\1(?!\\*|_)(?!\\*\\*)"
    @MainActor public static let italicRegex = MarklightRegex(pattern: italicPattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])

    fileprivate static let autolinkPrefixPattern = "((https?|ftp)://)"

    @MainActor public static let autolinkPrefixRegex = MarklightRegex(pattern: autolinkPrefixPattern, options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators])

    /// maximum nested depth of [] and () supported by the transform;
    /// implementation detail
    fileprivate static let _nestDepth = 6

    @MainActor fileprivate static var _nestedBracketsPattern = ""
    @MainActor fileprivate static var _nestedParensPattern = ""

    /// Reusable pattern to match balanced [brackets]. See Friedl's
    /// "Mastering Regular Expressions", 2nd Ed., pp. 328-331.
    fileprivate static func getNestedBracketsPattern() -> String {
        // in other words [this] and [this[also]] and [this[also[too]]]
        // up to _nestDepth
        if _nestedBracketsPattern.isEmpty {
            _nestedBracketsPattern =
                repeatString(
                    [
                        "(?>             # Atomic matching",
                        "[^\\[\\]]+      # Anything other than brackets",
                        "|",
                        "\\[",
                    ].joined(separator: "\n"), _nestDepth) + repeatString(" \\])*", _nestDepth)
        }
        return _nestedBracketsPattern
    }

    /// Reusable pattern to match balanced (parens). See Friedl's
    /// "Mastering Regular Expressions", 2nd Ed., pp. 328-331.
    fileprivate static func getNestedParensPattern() -> String {
        // in other words (this) and (this(also)) and (this(also(too)))
        // up to _nestDepth
        if _nestedParensPattern.isEmpty {
            _nestedParensPattern =
                repeatString(
                    [
                        "(?>            # Atomic matching",
                        "[^()\\s]+      # Anything other than parens or whitespace",
                        "|",
                        "\\(",
                    ].joined(separator: "\n"), _nestDepth) + repeatString(" \\))*", _nestDepth)
        }
        return _nestedParensPattern
    }

    /// this is to emulate what's available in PHP
    fileprivate static func repeatString(_ text: String, _ count: Int) -> String {
        Array(repeating: text, count: count).reduce("", +)
    }

    // We transform the user provided `fontName` `String` to a `NSFont`

    fileprivate static func codeFont(_ size: CGFloat) -> Font {
        if let font = UserDefaultsManagement.noteFont {
            return font
        } else {
            return NSFont.systemFont(ofSize: size)
        }
    }

    // We transform the user provided `quoteFontName` `String` to a `NSFont`

    fileprivate static func quoteFont(_ size: CGFloat) -> Font {
        if let font = UserDefaultsManagement.noteFont {
            return font
        } else {
            return NSFont.systemFont(ofSize: size)
        }
    }

    public func highlightLinks() {
        guard let storage = storage, let range = range else {
            return
        }

        // Safe range validation
        guard range.location >= 0,
            range.location <= storage.length,
            range.upperBound <= storage.length
        else {
            return
        }

        // Safe attribute removal
        storage.removeAttribute(.link, range: range)

        let chars = "[a-zA-Z0-9\\.\\-~!@#$%^&*+?:_/=<>]*"
        let host = "[a-zA-Z0-9\\.\\-]+\\.([a-zA-Z]{2,7})(:\\d+)?"
        let pattern = [
            "((http[s]{0,1}|ftp)://\(host)(/\(chars))?)",
            "(www.\(host)(/\(chars))?)",
            "(miaoyan://[a-zA-Z0-9]+\\/[a-zA-Z0-9|%]*)",
            "(/[i|files]/[a-zA-Z0-9-]+\\.[a-zA-Z0-9]*)",
        ].joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return
        }

        regex.enumerateMatches(
            in: storage.string,
            options: [],
            range: range,
            using: { result, _, _ in
                guard let matchRange = result?.range,
                    matchRange.upperBound <= storage.length
                else {
                    return
                }

                var str = storage.mutableString.substring(with: matchRange)
                var linkRange = matchRange

                if str.hasSuffix(">") {
                    str = String(str.dropLast())
                    linkRange = NSRange(location: matchRange.location, length: matchRange.length - 1)
                }

                // Validate adjusted range
                guard linkRange.upperBound <= storage.length else {
                    return
                }

                guard let note = EditTextView.note else { return }

                if str.starts(with: "/i/") || str.starts(with: "/files/"),
                    let path = note.project.url.appendingPathComponent(str).path.removingPercentEncoding
                {
                    str = "file://" + path
                    storage.addAttribute(.link, value: str, range: linkRange)
                    return
                }

                guard let url = URL(string: str) else { return }
                storage.addAttribute(.link, value: url, range: linkRange)
            }
        )

        // Process app urls [[link]] with safe range checking
        NotesTextProcessor.appUrlRegex.matches(storage.string, range: range) { result in
            guard let innerRange = result?.range,
                innerRange.upperBound <= storage.length,
                innerRange.length >= 4
            else {
                return
            }

            let from = String.Index(utf16Offset: innerRange.lowerBound + 2, in: storage.string)
            let to = String.Index(utf16Offset: innerRange.upperBound - 2, in: storage.string)
            guard from < to else { return }

            let appLink = storage.string[from..<to]

            storage.addAttribute(.link, value: "miaoyan://goto/" + appLink, range: innerRange)
            if let range = result?.range(at: 0), range.upperBound <= storage.length {
                storage.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: range)
            }

            if let range = result?.range(at: 2), range.upperBound <= storage.length {
                storage.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: range)
            }
        }
    }

    func highlightKeyword(search: String = "", remove: Bool = false) {
        guard let storage = storage, !search.isEmpty else { return }

        let range = NSRange(location: 0, length: storage.length)
        guard range.length > 0 else { return }

        let searchTerm = NSRegularExpression.escapedPattern(for: search)
        let pattern = "(\(searchTerm))"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return
        }

        if remove {
            regex.enumerateMatches(in: storage.string, options: [], range: range) { result, _, _ in
                guard let subRange = result?.range,
                    subRange.upperBound <= storage.length
                else {
                    return
                }

                let hasHighlight = storage.attribute(NoteAttribute.highlight, at: subRange.location, effectiveRange: nil) != nil
                storage.removeAttribute(hasHighlight ? NoteAttribute.highlight : .backgroundColor, range: subRange)
            }
        } else {
            let attributedString = NSMutableAttributedString(attributedString: storage)

            regex.enumerateMatches(in: storage.string, options: [], range: range) { result, _, _ in
                guard let subRange = result?.range,
                    subRange.upperBound <= storage.length,
                    subRange.location < attributedString.length
                else {
                    return
                }

                let hasBackground = attributedString.attribute(.backgroundColor, at: subRange.location, effectiveRange: nil) != nil
                if hasBackground {
                    attributedString.addAttribute(NoteAttribute.highlight, value: true, range: subRange)
                }
                attributedString.addAttribute(.backgroundColor, value: titleColor, range: subRange)
                attributedString.addAttribute(.foregroundColor, value: Theme.selectionTextColor, range: subRange)
            }

            storage.setAttributedString(attributedString)
        }
    }
}

public struct MarklightRegex {
    public let regularExpression: NSRegularExpression!

    public init(pattern: String, options: NSRegularExpression.Options = NSRegularExpression.Options(rawValue: 0)) {
        var error: NSError?
        let re: NSRegularExpression?
        do {
            re = try NSRegularExpression(
                pattern: pattern,
                options: options)
        } catch let error1 as NSError {
            error = error1
            re = nil
        }

        // If re is nil, it means NSRegularExpression didn't like
        // the pattern we gave it.  All regex patterns used by Markdown
        // should be valid, so this probably means that a pattern
        // valid for .NET Regex is not valid for NSRegularExpression.
        if re == nil {
            if let error = error {
                Task { @MainActor in
                    AppDelegate.trackError(error, context: "NotesTextProcessor.MarklightRegex")
                }
            }
            assert(re != nil)
        }
        regularExpression = re
    }

    public func matches(
        _ input: String, range: NSRange,
        completion: @escaping (_ result: NSTextCheckingResult?) -> Void
    ) {
        let s = input as NSString
        regularExpression.enumerateMatches(in: s as String, options: [], range: range) { result, _, _ in
            completion(result)
        }
    }
}
