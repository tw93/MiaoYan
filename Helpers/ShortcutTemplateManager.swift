import Foundation

// MARK: - Shortcut Template Structure
struct ShortcutTemplate {
    // Place {{cursor}} or {{select}}...{{/select}} markers in templates
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

    private static func parse(template: String) -> (content: String, cursorOffset: Int, cursorLength: Int) {
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

        return (result, cursorOffset, cursorLength)
    }
}

// MARK: - Shortcut Template Manager
class ShortcutTemplateManager {
    nonisolated(unsafe) static let shared = ShortcutTemplateManager()

    private init() {}

    private let templates: [String: ShortcutTemplate] = [
        "table": ShortcutTemplate(
            template: """
                | {{select}}列1{{/select}} | 列2 | 列3 |
                |-----|-----|-----|
                |     |     |     |
                |     |     |     |
                """
        ),

        "img": ShortcutTemplate(
            template: "<img src=\"{{cursor}}\" width=\"800\">"
        ),

        "video": ShortcutTemplate(
            template: """
                <video width="800px" preload loop autoplay controls muted>
                  <source src="{{cursor}}" type="video/mp4">
                </video>
                """
        ),

        "markmap": ShortcutTemplate(
            template: """
                ```markmap
                # {{select}}主题{{/select}}
                ## 分支1
                - 内容1
                - 内容2
                ## 分支2
                - 内容3
                ```
                """
        ),

        "mermaid": ShortcutTemplate(
            template: """
                ```mermaid
                graph LR
                A[{{select}}开始{{/select}}] --> B[处理]
                B --> C[结束]
                ```
                """
        ),

        "plantuml": ShortcutTemplate(
            template: """
                ```plantuml
                @startuml
                participant A
                participant B
                A -> B: {{select}}消息{{/select}}
                @enduml
                ```
                """
        ),

        "fold": ShortcutTemplate(
            template: """
                <details>
                <summary>{{select}}点击展开{{/select}}</summary>

                内容区域

                </details>
                """
        ),

        "task": ShortcutTemplate(
            template: """
                - [ ] {{select}}待完成任务1{{/select}}
                - [ ] 待完成任务2
                - [x] 已完成任务
                """
        ),
    ]

    func getTemplate(for key: String) -> ShortcutTemplate? {
        if key == "time" {
            return getCurrentTimeTemplate()
        }
        return templates[key]
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

    func getAllShortcuts() -> [String] {
        var shortcuts = Array(templates.keys)
        shortcuts.append("time")
        return shortcuts.sorted()
    }
}
