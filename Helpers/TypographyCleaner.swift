import Foundation

/// Pure-string typography cleanup for CJK/Latin mixed markdown, aimed at text
/// pasted from AI tools: pangu spacing, punctuation width normalization, stray
/// em dashes, ASCII ellipsis, and blank-line runs. Markdown structure that must
/// not change (fenced and indented code, inline code, math, link targets,
/// wikilinks, URLs, frontmatter, hard line breaks) is detected and left untouched.
enum TypographyCleaner {

    static func clean(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var output: [String] = []
        output.reserveCapacity(lines.count)

        var inFence = false
        var fenceMarker: Character = "`"
        var fenceLength = 0
        var inFrontmatter = false
        var inBlockMath = false
        var blankRun = 0
        var previousWasIndentedCode = false

        if lines.first == "---" || lines.first == "---\r" {
            inFrontmatter = true
        }

        for (index, line) in lines.enumerated() {
            // .whitespacesAndNewlines so CRLF documents (trailing \r) close
            // frontmatter and fences correctly.
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if inFrontmatter {
                output.append(line)
                if index > 0, trimmed == "---" || trimmed == "..." {
                    inFrontmatter = false
                }
                continue
            }

            if inFence {
                output.append(line)
                if isFenceLine(unquoted(trimmed), marker: fenceMarker, minLength: fenceLength, closing: true) {
                    inFence = false
                }
                blankRun = 0
                continue
            }

            // $$ display math: delimiter lines and everything between them are
            // formulas, where punctuation/em-dash rewrites would corrupt TeX.
            // An odd number of $$ on a line toggles the block; even counts are
            // single-line $$x$$, which the inline scanner already protects.
            if inBlockMath {
                output.append(line)
                if doubleDollarCount(unquoted(trimmed)) % 2 == 1 {
                    inBlockMath = false
                }
                blankRun = 0
                continue
            }
            if unquoted(trimmed).hasPrefix("$$"), doubleDollarCount(unquoted(trimmed)) % 2 == 1 {
                inBlockMath = true
                output.append(line)
                blankRun = 0
                previousWasIndentedCode = false
                continue
            }

            // Fences may live inside blockquotes ("> ```"); strip quote markers
            // before matching.
            if let fence = openingFence(unquoted(trimmed)) {
                inFence = true
                fenceMarker = fence.marker
                fenceLength = fence.length
                output.append(line)
                blankRun = 0
                previousWasIndentedCode = false
                continue
            }

            // Indented code blocks are code too. Over-matching (deeply indented
            // list text) only skips cleaning, never corrupts.
            if line.hasPrefix("    ") || line.hasPrefix("\t") {
                output.append(line)
                blankRun = 0
                previousWasIndentedCode = true
                continue
            }

            if trimmed.isEmpty {
                if previousWasIndentedCode {
                    // Blank lines may separate parts of one indented code block.
                    output.append(line)
                } else {
                    blankRun += 1
                    if blankRun == 1 {
                        output.append(line)
                    }
                }
                continue
            }

            // Reference-style link and footnote definitions ("[ref]: target",
            // "[^1]: note") are link plumbing: pangu spacing or punctuation
            // width changes in the target break the link.
            if isReferenceDefinition(unquoted(trimmed)) {
                output.append(line)
                blankRun = 0
                previousWasIndentedCode = false
                continue
            }

            blankRun = 0
            previousWasIndentedCode = false
            output.append(cleanLine(line))
        }

        // components(separatedBy:) preserved a trailing newline as a final empty
        // element; the blank-run collapse above may have dropped it.
        if markdown.hasSuffix("\n"), output.last?.isEmpty != true {
            output.append("")
        }

        return output.joined(separator: "\n")
    }

    // MARK: - Fences

    private struct Fence {
        let marker: Character
        let length: Int
    }

    /// Strips leading blockquote markers ("> > ") so quoted fences are seen.
    private static func unquoted(_ trimmed: String) -> String {
        var s = Substring(trimmed)
        while s.first == ">" {
            s = s.dropFirst()
            while s.first == " " { s = s.dropFirst() }
        }
        return String(s)
    }

    private static func openingFence(_ trimmed: String) -> Fence? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let run = trimmed.prefix(while: { $0 == first })
        guard run.count >= 3 else { return nil }
        return Fence(marker: first, length: run.count)
    }

    /// Non-overlapping count of "$$" occurrences in a line.
    private static func doubleDollarCount(_ s: String) -> Int {
        var count = 0
        var previousWasDollar = false
        for ch in s {
            if ch == "$" {
                if previousWasDollar {
                    count += 1
                    previousWasDollar = false
                } else {
                    previousWasDollar = true
                }
            } else {
                previousWasDollar = false
            }
        }
        return count
    }

    /// "[label]: ..." at line start (after any blockquote markers): a
    /// reference-style link or footnote definition line.
    private static func isReferenceDefinition(_ trimmed: String) -> Bool {
        guard trimmed.first == "[" else { return false }
        guard let close = trimmed.firstIndex(of: "]") else { return false }
        let after = trimmed.index(after: close)
        guard after < trimmed.endIndex else { return false }
        return trimmed[after] == ":"
    }

    private static func isFenceLine(_ trimmed: String, marker: Character, minLength: Int, closing: Bool) -> Bool {
        guard trimmed.first == marker else { return false }
        let run = trimmed.prefix(while: { $0 == marker })
        guard run.count >= minLength else { return false }
        // A closing fence has nothing after the marker run.
        return !closing || trimmed.dropFirst(run.count).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Line segmentation

    private struct Segment {
        var text: String
        let isProtected: Bool
        let isInlineCode: Bool
    }

    static func cleanLine(_ line: String) -> String {
        // Two or more trailing spaces are a markdown hard line break; keep them.
        var trailingSpaces = 0
        for c in line.reversed() {
            if c == " " { trailingSpaces += 1 } else { break }
        }
        let core = trailingSpaces > 0 ? String(line.dropLast(trailingSpaces)) : line
        let cleaned = cleanLineCore(core)
        if trailingSpaces >= 2 {
            return cleaned + String(repeating: " ", count: trailingSpaces)
        }
        return cleaned
    }

    private static func cleanLineCore(_ line: String) -> String {
        let segments = parseSegments(line)
        var result = ""
        // Last content character before the current segment. Inline code is
        // transparent so `执行`git status`,` still sees CJK context for the comma.
        var context: Character?

        for (index, segment) in segments.enumerated() {
            if segment.isProtected {
                if segment.isInlineCode {
                    // Pangu spacing across an inline-code boundary: `代码`中文 → `代码` 中文.
                    if let last = result.last, isCJK(last) || isLatinOrDigit(last) {
                        result.append(" ")
                    }
                    result += segment.text
                    if index + 1 < segments.count,
                        let next = firstCharacter(of: segments[(index + 1)...]), isCJK(next) || isLatinOrDigit(next)
                    {
                        result.append(" ")
                    }
                } else {
                    result += segment.text
                    context = segment.text.last
                }
            } else {
                let cleaned = cleanPlainText(segment.text, leadingContext: context)
                result += cleaned
                if let last = cleaned.last {
                    context = last
                }
            }
        }
        return result
    }

    private static func firstCharacter(of segments: ArraySlice<Segment>) -> Character? {
        for segment in segments {
            if let c = segment.text.first { return c }
        }
        return nil
    }

    private static func parseSegments(_ line: String) -> [Segment] {
        var segments: [Segment] = []
        let chars = Array(line)
        var plainStart = 0
        var i = 0
        // Once a "]]" scan fails, every later scan fails too; remember it so a
        // pathological run of "[" stays O(n).
        var noWikilinkClose = false

        func flushPlain(upTo end: Int) {
            if end > plainStart {
                segments.append(Segment(text: String(chars[plainStart..<end]), isProtected: false, isInlineCode: false))
            }
        }

        while i < chars.count {
            let c = chars[i]

            // Inline code span: matching backtick runs of equal length.
            if c == "`" {
                var runEnd = i
                while runEnd < chars.count, chars[runEnd] == "`" { runEnd += 1 }
                let runLength = runEnd - i
                if let close = findBacktickRun(chars, from: runEnd, length: runLength) {
                    flushPlain(upTo: i)
                    segments.append(Segment(text: String(chars[i..<close]), isProtected: true, isInlineCode: true))
                    plainStart = close
                    i = close
                    continue
                }
            }

            // Inline math: $...$, but only when it plausibly is math. Dollar
            // amounts ("$100和$200") and spans that would steal a backtick are
            // rejected and treated as plain text.
            if c == "$" {
                if let close = indexOf(chars, "$", from: i + 1), isValidMathSpan(chars, open: i, close: close) {
                    flushPlain(upTo: i)
                    segments.append(Segment(text: String(chars[i...close]), isProtected: true, isInlineCode: false))
                    plainStart = close + 1
                    i = close + 1
                    continue
                }
            }

            // Wikilink [[target]]: the target is a filename, never reflow it.
            if c == "[", i + 1 < chars.count, chars[i + 1] == "[", !noWikilinkClose {
                if let close = findDoubleClose(chars, from: i + 2) {
                    flushPlain(upTo: i)
                    segments.append(Segment(text: String(chars[i..<(close + 2)]), isProtected: true, isInlineCode: false))
                    plainStart = close + 2
                    i = close + 2
                    continue
                } else {
                    noWikilinkClose = true
                }
            }

            // Link / image target: "](" up to the matching ")".
            if c == "]", i + 1 < chars.count, chars[i + 1] == "(" {
                var depth = 1
                var j = i + 2
                while j < chars.count, depth > 0 {
                    if chars[j] == "(" { depth += 1 }
                    if chars[j] == ")" { depth -= 1 }
                    j += 1
                }
                if depth == 0 {
                    flushPlain(upTo: i)
                    segments.append(Segment(text: String(chars[i..<j]), isProtected: true, isInlineCode: false))
                    plainStart = j
                    i = j
                    continue
                }
            }

            // Bare or autolinked URL.
            if c == "h", matchesURLPrefix(chars, at: i) {
                var j = i
                while j < chars.count, !isURLBoundary(chars, at: j) { j += 1 }
                flushPlain(upTo: i)
                segments.append(Segment(text: String(chars[i..<j]), isProtected: true, isInlineCode: false))
                plainStart = j
                i = j
                continue
            }

            i += 1
        }
        flushPlain(upTo: chars.count)
        return segments
    }

    private static func findBacktickRun(_ chars: [Character], from: Int, length: Int) -> Int? {
        var i = from
        while i < chars.count {
            if chars[i] == "`" {
                var runEnd = i
                while runEnd < chars.count, chars[runEnd] == "`" { runEnd += 1 }
                if runEnd - i == length {
                    return runEnd
                }
                i = runEnd
            } else {
                i += 1
            }
        }
        return nil
    }

    private static func indexOf(_ chars: [Character], _ target: Character, from: Int) -> Int? {
        var i = from
        while i < chars.count {
            if chars[i] == target { return i }
            i += 1
        }
        return nil
    }

    private static func findDoubleClose(_ chars: [Character], from: Int) -> Int? {
        var i = from
        while i + 1 < chars.count {
            if chars[i] == "]", chars[i + 1] == "]" { return i }
            i += 1
        }
        return nil
    }

    private static func isValidMathSpan(_ chars: [Character], open: Int, close: Int) -> Bool {
        guard close > open + 1 else { return false }
        let inner = chars[(open + 1)..<close]
        // Math spans containing backticks would steal an inline-code delimiter;
        // spans containing CJK are almost always prose with dollar amounts.
        if inner.contains("`") { return false }
        if inner.contains(where: isCJK) { return false }
        if chars[open + 1] == " " { return false }
        if chars[close - 1] == " " { return false }
        if close + 1 < chars.count, chars[close + 1].isNumber { return false }
        return true
    }

    private static func matchesURLPrefix(_ chars: [Character], at index: Int) -> Bool {
        for prefix in ["https://", "http://"] {
            let p = Array(prefix)
            if index + p.count <= chars.count, Array(chars[index..<(index + p.count)]) == p {
                return true
            }
        }
        return false
    }

    private static func isURLBoundary(_ chars: [Character], at index: Int) -> Bool {
        let c = chars[index]
        if c.isWhitespace || c == ")" || c == ">" || c == "]" || c == "\"" || c == "'" { return true }
        // Fullwidth punctuation never belongs to a URL; a halfwidth comma or
        // semicolon glued to a CJK char ends the URL in Chinese prose.
        if fullwidthPunctuation.contains(c) || fullwidthOpeners.contains(c) || fullwidthClosers.contains(c) { return true }
        if c == "," || c == ";", index + 1 < chars.count, isCJK(chars[index + 1]) { return true }
        return false
    }

    // MARK: - Plain text transforms

    static func cleanPlainText(_ text: String, leadingContext: Character? = nil) -> String {
        var chars = Array(text)
        chars = normalizeFullwidthAlphanumerics(chars)
        chars = normalizeEllipsis(chars)
        chars = normalizeEmDash(chars)
        chars = normalizePunctuationWidth(chars, leadingContext: leadingContext)
        chars = insertPanguSpacing(chars)
        chars = trimSpacesAroundFullwidthPunctuation(chars)
        return String(chars)
    }

    private static func normalizeFullwidthAlphanumerics(_ chars: [Character]) -> [Character] {
        return chars.map { c in
            guard let scalar = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return c }
            switch scalar.value {
            case 0xFF10...0xFF19, 0xFF21...0xFF3A, 0xFF41...0xFF5A:
                return Character(UnicodeScalar(scalar.value - 0xFEE0)!)
            default:
                return c
            }
        }
    }

    /// `中文...` → `中文……` (three or more ASCII dots after a CJK char).
    private static func normalizeEllipsis(_ chars: [Character]) -> [Character] {
        var result: [Character] = []
        var i = 0
        while i < chars.count {
            if chars[i] == ".", let prev = result.last, isCJK(prev) {
                var j = i
                while j < chars.count, chars[j] == "." { j += 1 }
                if j - i >= 3 {
                    result.append(contentsOf: "……")
                    i = j
                    continue
                }
            }
            result.append(chars[i])
            i += 1
        }
        return result
    }

    /// A single em dash between CJK text is an AI-English tic; a doubled `——`
    /// is the legitimate Chinese break dash and stays.
    private static func normalizeEmDash(_ chars: [Character]) -> [Character] {
        var result: [Character] = []
        var i = 0
        while i < chars.count {
            if chars[i] == "—" {
                var j = i
                while j < chars.count, chars[j] == "—" { j += 1 }
                if j - i == 1 {
                    let prev = lastNonSpace(result)
                    let next = firstNonSpace(chars, from: j)
                    if let prev, let next, isCJK(prev), isCJK(next) {
                        while result.last == " " { result.removeLast() }
                        result.append("\u{FF0C}")
                        i = j
                        while i < chars.count, chars[i] == " " { i += 1 }
                        continue
                    }
                }
                result.append(contentsOf: chars[i..<j])
                i = j
                continue
            }
            result.append(chars[i])
            i += 1
        }
        return result
    }

    private static func lastNonSpace(_ chars: [Character]) -> Character? {
        for c in chars.reversed() where c != " " { return c }
        return nil
    }

    private static func firstNonSpace(_ chars: [Character], from: Int) -> Character? {
        var i = from
        while i < chars.count {
            if chars[i] != " " { return chars[i] }
            i += 1
        }
        return nil
    }

    /// Halfwidth `,;:!?.` after a CJK char becomes fullwidth when it ends a
    /// clause (followed by space, CJK, or end of line). Digits/Latin right after
    /// (e.g. `3.5`, `10:00`) never match because the preceding char is not CJK.
    /// Fullwidth forms are written as escapes; literals are too easy to confuse
    /// with their halfwidth twins in review.
    private static func normalizePunctuationWidth(_ chars: [Character], leadingContext: Character?) -> [Character] {
        let mapping: [Character: Character] = [
            ",": "\u{FF0C}", ";": "\u{FF1B}", ":": "\u{FF1A}",
            "!": "\u{FF01}", "?": "\u{FF1F}", ".": "\u{3002}",
        ]
        var result = chars
        for i in 0..<result.count {
            guard let fullwidth = mapping[result[i]] else { continue }
            let prev: Character? = i > 0 ? result[i - 1] : leadingContext
            guard let prev, isCJK(prev) else { continue }
            let next: Character? = i + 1 < result.count ? result[i + 1] : nil
            if next == nil || next == " " || (next.map(isCJK) ?? false) {
                result[i] = fullwidth
            }
        }
        return result
    }

    private static func insertPanguSpacing(_ chars: [Character]) -> [Character] {
        var result: [Character] = []
        result.reserveCapacity(chars.count + 8)
        for c in chars {
            if let prev = result.last {
                if (isCJK(prev) && isLatinOrDigit(c)) || (isLatinOrDigit(prev) && isCJK(c)) {
                    result.append(" ")
                }
            }
            result.append(c)
        }
        return result
    }

    private static let fullwidthPunctuation = Set<Character>("\u{FF0C}\u{3002}\u{FF01}\u{FF1F}\u{FF1B}\u{FF1A}\u{3001}")
    private static let fullwidthOpeners = Set<Character>("\u{300C}\u{300E}\u{3010}\u{300A}\u{FF08}\u{201C}")
    private static let fullwidthClosers = Set<Character>("\u{300D}\u{300F}\u{3011}\u{300B}\u{FF09}\u{201D}")

    private static func trimSpacesAroundFullwidthPunctuation(_ chars: [Character]) -> [Character] {
        var result: [Character] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == " " {
                // Drop spaces that precede fullwidth punctuation or closers.
                var j = i
                while j < chars.count, chars[j] == " " { j += 1 }
                if j < chars.count, fullwidthPunctuation.contains(chars[j]) || fullwidthClosers.contains(chars[j]) {
                    i = j
                    continue
                }
                // Drop spaces that follow fullwidth punctuation or openers.
                if let prev = result.last, fullwidthPunctuation.contains(prev) || fullwidthOpeners.contains(prev) {
                    i = j
                    continue
                }
            }
            result.append(c)
            i += 1
        }
        return result
    }

    // MARK: - Character classes

    private static func isCJK(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF, 0x3040...0x30FF, 0x31F0...0x31FF:
            return true
        default:
            return false
        }
    }

    private static func isLatinOrDigit(_ c: Character) -> Bool {
        return ("A"..."Z").contains(c) || ("a"..."z").contains(c) || ("0"..."9").contains(c)
    }
}
