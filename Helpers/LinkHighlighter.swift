import Cocoa

@MainActor
enum LinkHighlighter {
    private static var cachedLinkRegex: NSRegularExpression?
    private static var cachedSearchRegex: [String: NSRegularExpression] = [:]

    private static func getLinkRegex() -> NSRegularExpression? {
        if let cached = cachedLinkRegex {
            return cached
        }

        let chars = "[a-zA-Z0-9\\.\\-~!@#$%^&*+?:_/=<>]*"
        let host = "[a-zA-Z0-9\\.\\-]+\\.([a-zA-Z]{2,7})(:\\d+)?"
        let pattern = [
            "((http[s]{0,1}|ftp)://\(host)(/\(chars))?)",
            "(www\\.\(host)(/\(chars))?)",
            "(miaoyan://[a-zA-Z0-9]+\\/[a-zA-Z0-9|%]*)",
            "(/(?:i|files)/[a-zA-Z0-9-]+\\.[a-zA-Z0-9]*)",
        ].joined(separator: "|")

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        cachedLinkRegex = regex
        return regex
    }

    private static func getSearchRegex(for search: String) -> NSRegularExpression? {
        if let cached = cachedSearchRegex[search] {
            return cached
        }

        let escapedSearch = NSRegularExpression.escapedPattern(for: search)
        let pattern = "(\(escapedSearch))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        cachedSearchRegex[search] = regex
        if cachedSearchRegex.count > 100 {
            cachedSearchRegex.removeAll(keepingCapacity: true)
        }

        return regex
    }

    static func highlightLinks(in storage: NSTextStorage, range: NSRange, note: Note?) {
        guard range.location >= 0,
            range.location <= storage.length,
            range.upperBound <= storage.length
        else {
            return
        }

        storage.enumerateAttribute(NoteAttribute.autoLink, in: range) { value, autoRange, _ in
            guard value != nil, autoRange.upperBound <= storage.length else { return }
            storage.removeAttribute(NoteAttribute.autoLink, range: autoRange)
            storage.removeAttribute(.link, range: autoRange)
        }

        guard let regex = getLinkRegex() else {
            return
        }

        regex.enumerateMatches(in: storage.string, options: [], range: range) { result, _, _ in
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

            guard linkRange.upperBound <= storage.length else {
                return
            }

            if storage.attribute(.link, at: linkRange.location, effectiveRange: nil) != nil {
                return
            }

            if str.starts(with: "/i/") || str.starts(with: "/files/"),
                let note,
                let path = note.project.url.appendingPathComponent(str).path.removingPercentEncoding
            {
                str = "file://" + path
                storage.addAttribute(.link, value: str, range: linkRange)
                storage.addAttribute(NoteAttribute.autoLink, value: true, range: linkRange)
                return
            }

            guard let url = URL(string: str) else { return }
            storage.addAttribute(.link, value: url, range: linkRange)
            storage.addAttribute(NoteAttribute.autoLink, value: true, range: linkRange)
        }
    }

    static func highlightKeyword(in storage: NSTextStorage, search: String, remove: Bool, titleColor: NSColor) {
        guard !search.isEmpty else { return }

        let range = NSRange(location: 0, length: storage.length)
        guard range.length > 0 else { return }

        guard let regex = getSearchRegex(for: search) else {
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
            return
        }

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
