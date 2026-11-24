import AppKit
import MiaoYanCore

// MARK: - Shortcut Template Structure
struct ShortcutTemplate {
    private static let cursorMarker = "{{cursor}}"
    private static let selectionStartMarker = "{{select}}"
    private static let selectionEndMarker = "{{/select}}"

    let content: String
    let cursorOffset: Int
    let cursorLength: Int

    init(content: String, cursorOffset: Int, cursorLength: Int = 0) {
        self.content = content
        self.cursorOffset = cursorOffset
        self.cursorLength = cursorLength
    }

    init(template: String) {
        let parsed = ShortcutTemplate.parse(template: template)
        self.content = parsed.content
        self.cursorOffset = parsed.cursorOffset
        self.cursorLength = parsed.cursorLength
    }

    private struct ParseResult {
        let content: String
        let cursorOffset: Int
        let cursorLength: Int
    }

    private static func parse(template: String) -> ParseResult {
        let mutable = NSMutableString(string: template)
        let nsTemplate = template as NSString

        let selectionStartRange = nsTemplate.range(of: selectionStartMarker)
        let selectionEndRange = nsTemplate.range(of: selectionEndMarker)
        let cursorMarkerRange = nsTemplate.range(of: cursorMarker)

        var cursorOffset = 0
        var cursorLength = 0

        if selectionStartRange.location != NSNotFound,
            selectionEndRange.location != NSNotFound,
            selectionEndRange.location >= selectionStartRange.location
        {
            let selectionContentStart = selectionStartRange.location + selectionStartRange.length
            cursorOffset = selectionStartRange.location
            cursorLength = max(0, selectionEndRange.location - selectionContentStart)

            mutable.deleteCharacters(in: NSRange(location: selectionEndRange.location, length: selectionEndRange.length))
            mutable.deleteCharacters(in: selectionStartRange)
        } else if cursorMarkerRange.location != NSNotFound {
            cursorOffset = cursorMarkerRange.location
            mutable.deleteCharacters(in: cursorMarkerRange)
        } else {
            cursorOffset = mutable.length
            cursorLength = 0
        }

        var result = mutable as String

        if result.hasPrefix("\n") {
            result.removeFirst()
            cursorOffset = max(0, cursorOffset - 1)
        }

        let finalNSString = result as NSString
        cursorOffset = min(cursorOffset, finalNSString.length)
        if cursorLength > 0 {
            cursorLength = min(cursorLength, max(0, finalNSString.length - cursorOffset))
        }

        return ParseResult(content: result, cursorOffset: cursorOffset, cursorLength: cursorLength)
    }
}

// MARK: - Shortcut Template Manager
@MainActor
class ShortcutTemplateManager {
    static let shared = ShortcutTemplateManager()

    private init() {}

    /// The placeholder words come in the interface's language (they were
    /// Chinese for every reader until 2026-11-21); the Chinese ones are the
    /// words the templates always had.
    private func template(for key: String) -> ShortcutTemplate? {
        func word(_ key: String) -> String { I18n.str(key) }
        switch key {
        case "table":
            return tableTemplate([word("Column 1"), word("Column 2"), word("Column 3")])
        case "img":
            return ShortcutTemplate(template: "<img src=\"{{cursor}}\" width=\"800\">")
        case "video":
            return ShortcutTemplate(
                template: "<video width=\"800px\" preload=\"metadata\" loop autoplay controls muted><source src=\"{{cursor}}\" type=\"video/mp4\"></video>"
            )
        case "markmap":
            return ShortcutTemplate(
                template: """
                    ```markmap
                    # {{select}}\(word("Topic")){{/select}}
                    ## \(word("Branch 1"))
                    - \(word("Item 1"))
                    - \(word("Item 2"))
                    ## \(word("Branch 2"))
                    - \(word("Item 3"))
                    ```
                    """
            )
        case "mermaid":
            return ShortcutTemplate(
                template: """
                    ```mermaid
                    graph LR
                    A[{{select}}\(word("Start")){{/select}}] --> B[\(word("Process"))]
                    B --> C[\(word("Finish"))]
                    ```
                    """
            )
        case "plantuml":
            return ShortcutTemplate(
                template: """
                    ```plantuml
                    @startuml
                    participant A
                    participant B
                    A -> B: {{select}}\(word("Message")){{/select}}
                    @enduml
                    ```
                    """
            )
        case "fold":
            return ShortcutTemplate(
                template: """
                    <details>
                    <summary>{{select}}\(word("Click to expand")){{/select}}</summary>

                    \(word("Content goes here"))

                    </details>
                    """
            )
        case "task":
            return ShortcutTemplate(
                template: """
                    - [ ] {{select}}\(word("Task 1")){{/select}}
                    - [ ] \(word("Task 2"))
                    - [x] \(word("Finished task"))
                    """
            )
        default:
            return nil
        }
    }

    /// A header, its line of dashes and two empty rows with the first header
    /// selected (`TableEditing.template`, which the iPhone and iPad write too).
    private func tableTemplate(_ headers: [String]) -> ShortcutTemplate {
        let table = TableEditing.template(headers: headers)
        return ShortcutTemplate(content: table.text, cursorOffset: table.selection.location, cursorLength: table.selection.length)
    }

    func getTemplate(for key: String) -> ShortcutTemplate? {
        if key == "time" {
            return getCurrentTimeTemplate()
        }
        return template(for: key)
    }

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private func getCurrentTimeTemplate() -> ShortcutTemplate {
        let timeString = timeFormatter.string(from: Date())
        return ShortcutTemplate(
            content: timeString,
            cursorOffset: timeString.utf16.count,
            cursorLength: 0
        )
    }

}

extension EditTextView {
    // MARK: - Shortcut Expansion
    func handleShortcutExpansion() -> Bool {
        guard let storage = textStorage else { return false }

        let range = selectedRange()
        let text = storage.string as NSString

        // Get the current line
        let lineRange = text.lineRange(for: range)
        let beforeCursor = text.substring(with: NSRange(location: lineRange.location, length: range.location - lineRange.location))

        // Extract shortcut if present
        guard let shortcut = extractShortcut(from: beforeCursor) else { return false }

        return expandShortcut(shortcut, at: range)
    }

    private func extractShortcut(from text: String) -> String? {
        // Simple suffix matching - more efficient than regex for this case
        guard text.hasSuffix("/") == false else { return nil }

        let components = text.components(separatedBy: "/")
        guard let lastComponent = components.last,
            !lastComponent.isEmpty,
            lastComponent.allSatisfy({ $0.isLetter || $0.isNumber })
        else {
            return nil
        }

        return lastComponent
    }

    private func expandShortcut(_ shortcut: String, at range: NSRange) -> Bool {
        guard let template = ShortcutTemplateManager.shared.getTemplate(for: shortcut),
            let textStorage = textStorage
        else {
            return false
        }

        // Calculate the range to replace (including the "/" + shortcut)
        let replaceStart = range.location - shortcut.count - 1  // -1 for "/"
        let replaceLength = shortcut.count + 1

        // Bounds checking
        guard replaceStart >= 0,
            replaceStart + replaceLength <= textStorage.length
        else {
            return false
        }

        let replaceRange = NSRange(location: replaceStart, length: replaceLength)

        // Perform text replacement
        replaceText(template.content, in: replaceRange)

        // Set cursor position based on template with bounds checking
        let newCursorPosition = replaceRange.location + template.cursorOffset
        let finalLength = textStorage.length
        let safeCursorPosition = min(newCursorPosition, finalLength)
        let safeCursorLength = min(template.cursorLength, max(0, finalLength - safeCursorPosition))

        let newRange = NSRange(location: safeCursorPosition, length: safeCursorLength)
        setSelectedRange(newRange)

        // Links in the lines the template now covers; the rest of the note did not change.
        let inserted = NSRange(location: replaceRange.location, length: min(template.content.utf16.count, finalLength - replaceRange.location))
        fillHighlightLinks(range: textStorage.mutableString.paragraphRange(for: inserted))

        return true
    }

    // MARK: - Text Replacement Helper
    private func replaceText(_ text: String, in range: NSRange) {
        // shouldChangeText registers the undo for this edit; without it the
        // typing undo kept the old range and Command-Z cut into the template.
        guard let textStorage = textStorage, shouldChangeText(in: range, replacementString: text) else { return }

        // Preserve text attributes when replacing
        let attributes = typingAttributes
        let attributedText = NSAttributedString(string: text, attributes: attributes)

        textStorage.replaceCharacters(in: range, with: attributedText)

        // Lays out the inserted text only; the whole container laid out every line below it again.
        layoutManager?.ensureLayout(forCharacterRange: NSRange(location: range.location, length: attributedText.length))
        didChangeText()
    }
}
