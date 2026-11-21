import AppKit

/// Wraps a long list item under its own words rather than under the dash:
/// the paragraph's `headIndent` becomes the drawn width of its marker, the
/// leading spaces, the `-`, `*`, `+` or `1.`, a task box and the space after
/// them, so the lines after the first start where the text does (maintainer
/// 2026-11-21, reader feedback 2026-11-17). Only the paragraph style
/// changes, never a character, and a paragraph that stops being a list item
/// gets the plain style back.
@MainActor
enum ListHangingIndent {
    /// Indent, marker, the space after it, and a task box with its space.
    private static let marker = try? NSRegularExpression(pattern: #"^[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+(?:\[[ xX]\][ \t]+)?"#)

    /// The two passes that draw a note's structure without touching its
    /// text, after a pass over the whole note: tables lined up, then list
    /// items indented. `editing` as in `TableColumnAligner.alignAll`.
    static func drawStructure(of storage: NSTextStorage, editing: Bool = false) {
        TableColumnAligner.alignAll(in: storage, editing: editing)
        applyAll(in: storage)
    }

    /// Every paragraph of the note, after a pass that wrote the plain style
    /// over the whole note (`updateParagraphStyle`) or changed its spacing.
    static func applyAll(in storage: NSTextStorage) {
        apply(in: NSRange(location: 0, length: storage.length), of: storage)
    }

    /// The paragraphs that `range` touches, from inside the storage's own
    /// editing pass: a list item's indent depends only on its own line.
    static func apply(in range: NSRange, of storage: NSTextStorage) {
        let text = storage.mutableString
        guard text.length > 0, let marker else { return }
        let location = min(max(range.location, 0), text.length)
        let paragraphs = text.paragraphRange(for: NSRange(location: location, length: min(range.length, text.length - location)))
        text.enumerateSubstrings(in: paragraphs, options: [.byParagraphs, .substringNotRequired]) { _, line, enclosing, _ in
            var indent: CGFloat = 0
            if line.length > 1, storage.attribute(.codeBlock, at: line.location, effectiveRange: nil) == nil,
                let match = marker.firstMatch(in: text as String, range: line), match.range.length < line.length
            {
                indent = width(of: storage.attributedSubstring(from: match.range))
            }
            set(indent, on: enclosing, of: storage)
        }
    }

    private static func set(_ indent: CGFloat, on paragraph: NSRange, of storage: NSTextStorage) {
        guard paragraph.length > 0 else { return }
        let current = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
        guard abs((current?.headIndent ?? 0) - indent) > 0.25 else { return }
        let style = (current?.mutableCopy() as? NSMutableParagraphStyle) ?? NSTextStorage.getParagraphStyle()
        style.headIndent = indent
        storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
    }

    /// Markers repeat down a note, so each is measured once per face.
    private static let widths = NSCache<NSAttributedString, NSNumber>()

    private static func width(of marker: NSAttributedString) -> CGFloat {
        if let known = widths.object(forKey: marker) { return CGFloat(known.doubleValue) }
        let measured = ceil(marker.size().width * 2) / 2
        widths.setObject(NSNumber(value: Double(measured)), forKey: marker)
        return measured
    }
}
