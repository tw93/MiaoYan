import Foundation

/// What one saved version changed against the version before it, line by
/// line: how many lines it added and removed, for the version list, and
/// which of its own lines are new or rewritten, for the preview. Where a
/// run of new lines replaced old ones, as many as were replaced are
/// rewrites and the rest additions. Removed lines leave no mark in the
/// newer text: the older version shows them.
public struct VersionChanges: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case added, rewritten
    }

    public struct Mark: Equatable, Sendable {
        /// Zero-based line in the newer text.
        public let line: Int
        public let kind: Kind

        public init(line: Int, kind: Kind) {
            self.line = line
            self.kind = kind
        }
    }

    public let added: Int
    public let removed: Int
    public let marks: [Mark]

    /// Past this many lines on both sides together the diff is skipped:
    /// `CollectionDifference` grows with lines times changes, and a note
    /// that long is not read line by line in this panel anyway.
    public static let longestDiffed = 20000

    public static func between(older: String, newer: String) -> VersionChanges? {
        let old = lines(of: older)
        let new = lines(of: newer)
        guard old.count + new.count <= longestDiffed else { return nil }

        var removedLines = Set<Int>()
        var insertedLines = Set<Int>()
        for change in new.difference(from: old) {
            switch change {
            case .remove(let offset, _, _): removedLines.insert(offset)
            case .insert(let offset, _, _): insertedLines.insert(offset)
            }
        }

        // Walk both texts together; every stretch where the old side drops
        // lines or the new side gains them is one hunk.
        var marks: [Mark] = []
        var i = 0
        var j = 0
        while i < old.count || j < new.count {
            guard removedLines.contains(i) || insertedLines.contains(j) else {
                i += 1
                j += 1
                continue
            }
            var dropped = 0
            while removedLines.contains(i) {
                i += 1
                dropped += 1
            }
            var gained: [Int] = []
            while insertedLines.contains(j) {
                gained.append(j)
                j += 1
            }
            // As many new lines as the hunk dropped stand in for them; the
            // rest are new.
            marks += gained.enumerated().map { Mark(line: $1, kind: $0 < dropped ? .rewritten : .added) }
        }
        return VersionChanges(added: insertedLines.count, removed: removedLines.count, marks: marks)
    }

    /// Lines without their ending, so a file saved with CRLF compares equal
    /// to the same text with LF. "\r\n" is one Character in Swift, so it is
    /// a separator of its own: splitting on "\n" alone never sees it.
    public static func lines(of text: String) -> [Substring] {
        text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" }
    }

    /// The UTF-16 range of each marked line in `text`, its line break
    /// included, for drawing.
    public static func ranges(of marks: [Mark], in text: String) -> [(range: NSRange, kind: Kind)] {
        guard !marks.isEmpty else { return [] }
        let ns = text as NSString
        // Only "\n" ends a line, as in `lines(of:)`: NSString's own line
        // ranges also break at a lone "\r" and U+2028, and the marks would
        // land on the wrong lines.
        var starts: [Int] = [0]
        for index in 0..<ns.length where ns.character(at: index) == 0x0A {
            starts.append(index + 1)
        }
        return marks.compactMap { mark in
            guard mark.line < starts.count else { return nil }
            let start = starts[mark.line]
            let end = mark.line + 1 < starts.count ? starts[mark.line + 1] : ns.length
            return (NSRange(location: start, length: max(0, end - start)), mark.kind)
        }
    }
}
