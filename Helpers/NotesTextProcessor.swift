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

    @MainActor private struct HighlightPerformanceState {
        let simplified: Bool
        let skipCode: Bool
    }

    @MainActor private static var performanceStateByNotePath: [String: HighlightPerformanceState] = [:]

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
        CodeBlockHighlighter.getCodeBlockRegex(pattern: _codeQuoteBlockPattern)
    }

    public static func highlightCode(attributedString: NSMutableAttributedString, range: NSRange, language: String? = nil) {
        CodeBlockHighlighter.highlightCode(attributedString: attributedString, range: range, language: language)
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
        checkPerformanceLevel(attributedString: note.content, note: note)

        // For very large files, skip all complex highlighting
        if shouldUseSimplifiedHighlighting {
            highlightBasicMarkdown(attributedString: note.content, note: note)
        } else {
            highlightMarkdown(attributedString: note.content, note: note)
            highlightFencedAndIndentCodeBlocks(attributedString: note.content)
        }
    }

    @MainActor public static func checkPerformanceLevel(attributedString: NSMutableAttributedString, note: Note? = nil) {
        let state = calculatePerformanceState(attributedString: attributedString)
        applyPerformanceState(state, note: note ?? EditTextView.note)
    }

    @MainActor private static func calculatePerformanceState(attributedString: NSMutableAttributedString) -> HighlightPerformanceState {
        let lineCount = attributedString.string.components(separatedBy: .newlines).count
        if lineCount > 5000 {
            return HighlightPerformanceState(simplified: true, skipCode: true)
        }

        if lineCount > 2000 {
            return HighlightPerformanceState(simplified: true, skipCode: false)
        }

        let range = NSRange(0..<attributedString.length)
        guard range.length > 0 else {
            return HighlightPerformanceState(simplified: false, skipCode: false)
        }

        guard let regex = getCodeBlockRegex() else {
            return HighlightPerformanceState(simplified: false, skipCode: false)
        }

        var matchCount = 0
        regex.enumerateMatches(in: attributedString.string, options: [], range: range) { _, _, stop in
            matchCount += 1
            if matchCount > 20 {
                stop.pointee = true
            }
        }
        return HighlightPerformanceState(simplified: false, skipCode: matchCount > 20)
    }

    @MainActor public static func applyPerformanceState(for note: Note? = nil) {
        let currentNote = note ?? EditTextView.note
        guard let currentNote else {
            shouldUseSimplifiedHighlighting = false
            shouldSkipCodeHighlighting = false
            return
        }

        let key = currentNote.url.path
        let state = performanceStateByNotePath[key] ?? HighlightPerformanceState(simplified: false, skipCode: false)
        shouldUseSimplifiedHighlighting = state.simplified
        shouldSkipCodeHighlighting = state.skipCode
    }

    @MainActor private static func applyPerformanceState(_ state: HighlightPerformanceState, note: Note?) {
        if let note {
            performanceStateByNotePath[note.url.path] = state
        }

        shouldUseSimplifiedHighlighting = state.simplified
        shouldSkipCodeHighlighting = state.skipCode
    }

    // Simplified highlighting for large files - only basic styles, no regex-heavy operations
    public static func highlightBasicMarkdown(attributedString: NSMutableAttributedString, range: NSRange? = nil, note: Note) {
        MarkdownRuleHighlighter.highlightBasicMarkdown(attributedString: attributedString, range: range, note: note)
    }

    public static func highlightMarkdown(attributedString: NSMutableAttributedString, paragraphRange: NSRange? = nil, note: Note) {
        MarkdownRuleHighlighter.highlightMarkdown(attributedString: attributedString, paragraphRange: paragraphRange, note: note)
    }

    public static func highlightFencedAndIndentCodeBlocks(attributedString: NSMutableAttributedString) {
        CodeBlockHighlighter.highlightFencedAndIndentCodeBlocks(attributedString: attributedString, pattern: _codeQuoteBlockPattern)
    }

    public static func isIntersect(fencedRanges: [NSRange], indentRange: NSRange) -> Bool {
        for fencedRange in fencedRanges where fencedRange.intersection(indentRange) != nil {
            return true
        }
        return false
    }

    public static func checkBackTick(styleApplier: NSMutableAttributedString, paragraphRange: NSRange? = nil) {
        BacktickAndFontNormalizer.normalize(styleApplier: styleApplier, paragraphRange: paragraphRange)
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

    static func quoteFont(_ size: CGFloat) -> Font {
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

        LinkHighlighter.highlightLinks(in: storage, range: range, note: EditTextView.note)
    }

    func highlightKeyword(search: String = "", remove: Bool = false) {
        guard let storage = storage, !search.isEmpty else { return }

        LinkHighlighter.highlightKeyword(in: storage, search: search, remove: remove, titleColor: titleColor)
    }
}

class CodeTextProcessor {
    private var textStorage: NSMutableAttributedString

    init(textStorage: NSMutableAttributedString) {
        self.textStorage = textStorage
    }

    public func getCodeBlockRanges() -> [NSRange]? {
        var paragraphRanges = [NSRange]()
        var paragraphList = [String]()

        let string = textStorage.string as NSString
        string.enumerateSubstrings(in: NSRange(0..<string.length), options: .byParagraphs) { value, range, _, _ in
            paragraphRanges.append(range)
            paragraphList.append(value!)
        }

        return getBlockRanges(ranges: paragraphRanges, pars: paragraphList)
    }

    public func getCodeBlockRanges(parRange: NSRange) -> [NSRange]? {
        let min = scanCodeBlockUp(location: parRange.location - 1)
        let max = scanCodeBlockDown(location: parRange.upperBound)

        let attributedParagraph = textStorage.attributedSubstring(from: parRange)
        let paragraph = attributedParagraph.string
        let isCodeParagraph = isCodeBlock(attributedParagraph)

        if let min = min, let max = max {
            if isCodeParagraph || paragraph.trim() == "\n" {
                return [NSRange(min.location..<max.upperBound)]
            } else {
                return [min, max]
            }
        } else if let min = min {
            if isCodeParagraph {
                return [NSRange(min.location..<parRange.upperBound - 1)]
            } else {
                return [min]
            }
        } else if let max = max {
            if isCodeParagraph {
                return [NSRange(parRange.location..<max.upperBound)]
            } else {
                return [max]
            }
        } else if isCodeParagraph {
            return [parRange]
        }

        return nil
    }

    private func scanCodeBlockUp(location: Int, min: Int? = nil, firstFound: Int? = nil) -> NSRange? {
        var firstFound = firstFound

        if location < 0 {
            if let min = min, let firstFound = firstFound {
                return NSRange(min..<firstFound)
            }
            return nil
        }

        let prevRange = textStorage.mutableString.paragraphRange(for: NSRange(location: location, length: 0))
        let prevAttributed = textStorage.attributedSubstring(from: prevRange)
        let prev = prevAttributed.string

        if isCodeBlock(prevAttributed) {
            if firstFound == nil {
                firstFound = prevRange.upperBound - 1
            }

            return scanCodeBlockUp(location: prevRange.location - 1, min: prevRange.location, firstFound: firstFound)
        } else if prev.trim() == "\n" {
            return scanCodeBlockUp(location: prevRange.location - 1, min: min, firstFound: firstFound)
        } else {
            if let firstFound = firstFound, let min = min {
                return NSRange(min..<firstFound)
            }

            return nil
        }
    }

    private func scanCodeBlockDown(location: Int, max: Int? = nil, firstFound: Int? = nil) -> NSRange? {
        var firstFound = firstFound

        if location > textStorage.length {
            if let max = max, let firstFound = firstFound {
                return NSRange(firstFound..<max)
            }
            return nil
        }

        let nextRange = textStorage.mutableString.paragraphRange(for: NSRange(location: location, length: 0))
        let nextAttributed = textStorage.attributedSubstring(from: nextRange)
        let next = nextAttributed.string

        if isCodeBlock(nextAttributed) {
            if textStorage.length == nextRange.upperBound {
                if let firstFound = firstFound {
                    return NSRange(firstFound..<nextRange.upperBound)
                }
            }

            if firstFound == nil {
                firstFound = nextRange.location
            }

            return scanCodeBlockDown(location: nextRange.upperBound, max: nextRange.upperBound - 1, firstFound: firstFound)
        } else if next.trim() == "\n" {
            if textStorage.length == nextRange.upperBound {
                if let max = max, let firstFound = firstFound {
                    return NSRange(firstFound..<max)
                }
            }

            return scanCodeBlockDown(location: nextRange.upperBound, max: max, firstFound: firstFound)
        } else {
            if let max = max, let firstFound = firstFound {
                return NSRange(firstFound..<max)
            }
            return nil
        }
    }

    private func isCodeBlock(_ attributedString: NSAttributedString) -> Bool {
        if attributedString.string.starts(with: "\t") || attributedString.string.starts(with: "  ") {
            return true
        }

        return false
    }

    public func getBlockRanges(
        ranges: [NSRange],
        pars: [String]
    ) -> [NSRange]? {
        let digitSet = CharacterSet.decimalDigits
        var codeBlocks = [NSRange]()
        var index = 0
        var start: Int?
        var finish: Int?
        var prevParagraph = ""
        var skipFlag = false

        for paragraph in pars {
            if isCodeBlockParagraph(paragraph) {
                if skipFlag {
                    index += 1
                    continue
                }

                if let char = prevParagraph.unicodeScalars.first,
                    (digitSet.contains(char) && prevParagraph.starts(with: "\(char). ")) || prevParagraph.starts(with: "- ") || prevParagraph.starts(with: " - ") || prevParagraph.starts(with: "*")
                {
                    skipFlag = true
                    index += 1
                    continue
                }

                if start != nil {
                    finish = ranges[index].upperBound
                } else {
                    start = ranges[index].location
                    finish = ranges[index].upperBound
                }

                index += 1
                prevParagraph = paragraph

                continue
            } else if paragraph.trim() == "" {
                index += 1
                continue
            } else if let startPos = start, let finishPos = finish {
                codeBlocks.append(NSRange(startPos..<finishPos))
                start = nil
                finish = nil
            }

            skipFlag = false
            index += 1
            prevParagraph = paragraph
        }

        if let startPos = start, let finishPos = finish {
            codeBlocks.append(NSRange(startPos..<finishPos))
            start = nil
            finish = nil
        }

        return codeBlocks
    }

    public func isCodeBlockParagraph(_ paragraph: String) -> Bool {
        if paragraph.starts(with: "\t") || paragraph.starts(with: "  ") {
            return true
        }

        return false
    }

    public func getIntersectedRange(range: NSRange, ranges: [NSRange]) -> NSRange? {
        for rangeItem in ranges where range.intersection(rangeItem) != nil {
            return rangeItem
        }

        return nil
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
