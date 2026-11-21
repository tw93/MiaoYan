import Foundation
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

    /// A header, its line of dashes and two empty rows, written the way
    /// the table keys and Format write a table, with the first header
    /// selected: a word wider than three columns needs wider rows under it.
    private func tableTemplate(_ headers: [String]) -> ShortcutTemplate {
        let empty = "|" + String(repeating: "  |", count: headers.count)
        let dashes = "|" + String(repeating: " --- |", count: headers.count)
        let rough = (["| " + headers.joined(separator: " | ") + " |", dashes, empty, empty].joined(separator: "\n")) as NSString
        guard let edit = TableEditing.edit(.align(.none), in: rough, selection: NSRange(location: 2, length: 0)) else {
            return ShortcutTemplate(content: rough as String, cursorOffset: 2, cursorLength: (headers.first ?? "").utf16.count)
        }
        return ShortcutTemplate(
            content: rough.replacingCharacters(in: edit.range, with: edit.replacement),
            cursorOffset: edit.selection.location, cursorLength: edit.selection.length)
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
