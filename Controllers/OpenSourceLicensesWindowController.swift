import AppKit

/// MiaoYan > Open Source Licenses: the bundled `THIRD-PARTY-NOTICES.md`, read
/// only and selectable, so the notices the licenses ask for ship inside the app.
@MainActor
final class OpenSourceLicensesWindowController: NSWindowController, NSWindowDelegate {
    static let noticesResource = "THIRD-PARTY-NOTICES"

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = I18n.str("Open Source Licenses")
        window.minSize = NSSize(width: 460, height: 320)
        window.isReleasedWhenClosed = false
        window.backgroundColor = Theme.panelBackgroundColor
        self.init(window: window)
        window.delegate = self
        window.contentView = Self.makeScrollView()
        window.center()
    }

    private static func makeScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 28, height: 24)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.linkTextAttributes = [
            .foregroundColor: Theme.brand,
            .cursor: NSCursor.pointingHand,
        ]
        textView.textStorage?.setAttributedString(noticesText())

        scrollView.documentView = textView
        return scrollView
    }

    private static func noticesText() -> NSAttributedString {
        guard let url = Bundle.main.url(forResource: noticesResource, withExtension: "md"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else { return NSAttributedString() }
        return OpenSourceNoticeRenderer.attributedString(from: source)
    }
}

/// Turns the notices file into styled text. It reads only the Markdown the
/// file uses: `##` and `###` headings, `-` list items, fenced license texts,
/// `**bold**`, `` `code` `` and `<https://…>` links. The `#` title is dropped
/// because the window title already says it.
enum OpenSourceNoticeRenderer {
    static func attributedString(from source: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        var paragraph: [String] = []
        var listItem: [String] = []
        var code: [String] = []
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            output.append(inline(paragraph.joined(separator: " "), style: .body))
            paragraph.removeAll()
        }
        func flushListItem() {
            guard !listItem.isEmpty else { return }
            output.append(inline(listItem.joined(separator: " "), style: .listItem))
            listItem.removeAll()
        }

        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    output.append(plain(code.joined(separator: "\n"), style: .code))
                    code.removeAll()
                } else {
                    flushParagraph()
                    flushListItem()
                }
                inCode.toggle()
                continue
            }
            if inCode {
                code.append(line)
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                flushListItem()
                continue
            }
            if trimmed.hasPrefix("# ") {
                flushParagraph()
                flushListItem()
                continue
            }
            if trimmed.hasPrefix("### ") || trimmed.hasPrefix("## ") {
                flushParagraph()
                flushListItem()
                let isSection = trimmed.hasPrefix("## ")
                let title = String(trimmed.drop(while: { $0 == "#" }).dropFirst())
                output.append(inline(title, style: isSection ? .section : .subsection))
                continue
            }
            if trimmed.hasPrefix("- ") {
                flushParagraph()
                flushListItem()
                listItem.append(String(trimmed.dropFirst(2)))
                continue
            }
            if !listItem.isEmpty {
                listItem.append(trimmed)
            } else {
                paragraph.append(trimmed)
            }
        }
        flushParagraph()
        flushListItem()
        return output
    }

    enum Style {
        case section, subsection, body, listItem, code

        var font: NSFont {
            switch self {
            case .section: return .systemFont(ofSize: 16, weight: .semibold)
            case .subsection: return .systemFont(ofSize: 13, weight: .semibold)
            case .body, .listItem: return .systemFont(ofSize: 13)
            case .code: return .monospacedSystemFont(ofSize: 11, weight: .regular)
            }
        }

        var color: NSColor {
            self == .code ? Theme.Ink.secondary : Theme.Ink.primary
        }

        var paragraphStyle: NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = self == .code ? 1 : 3
            switch self {
            case .section:
                style.paragraphSpacingBefore = 22
                style.paragraphSpacing = 8
            case .subsection:
                style.paragraphSpacingBefore = 14
                style.paragraphSpacing = 6
            case .body:
                style.paragraphSpacing = 10
            case .code:
                // Every line of a license text is its own paragraph, so the
                // gap after the block is added to its last line only.
                style.paragraphSpacing = 0
            case .listItem:
                style.paragraphSpacing = 4
                style.headIndent = 14
                style.tabStops = [NSTextTab(textAlignment: .left, location: 14)]
            }
            return style
        }
    }

    private static func attributes(_ style: Style) -> [NSAttributedString.Key: Any] {
        [.font: style.font, .foregroundColor: style.color, .paragraphStyle: style.paragraphStyle]
    }

    private static func plain(_ text: String, style: Style) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text + "\n", attributes: attributes(style))
        let lastLine = (result.string as NSString).paragraphRange(for: NSRange(location: result.length - 1, length: 0))
        let closing = NSMutableParagraphStyle()
        closing.setParagraphStyle(style.paragraphStyle)
        closing.paragraphSpacing = 14
        result.addAttribute(.paragraphStyle, value: closing, range: lastLine)
        return result
    }

    /// `**bold**`, `` `code` `` and `<https://…>` inside one paragraph.
    static func inline(_ text: String, style: Style) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let base = attributes(style)
        if style == .listItem {
            result.append(NSAttributedString(string: "•\t", attributes: base))
        }
        let bold = NSFontManager.shared.convert(style.font, toHaveTrait: .boldFontMask)
        let mono = NSFont.monospacedSystemFont(ofSize: style.font.pointSize - 1, weight: .regular)
        var rest = Substring(text)
        var isBold = false
        while !rest.isEmpty {
            if rest.hasPrefix("**") {
                isBold.toggle()
                rest = rest.dropFirst(2)
                continue
            }
            var attrs = base
            if isBold { attrs[.font] = bold }
            if rest.hasPrefix("`"), let end = rest.dropFirst().firstIndex(of: "`") {
                attrs[.font] = mono
                result.append(NSAttributedString(string: String(rest[rest.index(after: rest.startIndex)..<end]), attributes: attrs))
                rest = rest[rest.index(after: end)...]
                continue
            }
            if rest.hasPrefix("<"), let end = rest.firstIndex(of: ">") {
                let inner = String(rest[rest.index(after: rest.startIndex)..<end])
                let address = inner.hasPrefix("www.") ? "https://\(inner)" : inner
                if address.hasPrefix("http"), let url = URL(string: address) {
                    attrs[.link] = url
                    result.append(NSAttributedString(string: inner, attributes: attrs))
                    rest = rest[rest.index(after: end)...]
                    continue
                }
            }
            let stop = rest.dropFirst().firstIndex(where: { $0 == "*" || $0 == "`" || $0 == "<" }) ?? rest.endIndex
            result.append(NSAttributedString(string: String(rest[..<stop]), attributes: attrs))
            rest = rest[stop...]
        }
        result.append(NSAttributedString(string: "\n", attributes: base))
        return result
    }
}
