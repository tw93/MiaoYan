import Carbon.HIToolbox
import MiaoYanCore
import XCTest

@testable import MiaoYan

/// Random runs of the keys and commands that rewrite the text for the writer
/// (Return, Tab and their Shift forms, the Format menu, the Table menu,
/// typing and Backspace) over made-up notes. Each run must leave the
/// selection inside the text, undo back to the note it started from and redo
/// forward to where it ended; a run of structural keys alone must also keep
/// every letter the note had, in order. The table commands have their own
/// fuzz in MiaoYanCore; this one goes through the editor, where the keys
/// meet the list, quote, indent and table paths together.
final class EditorKeyFuzzTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanKeyFuzz-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Seeded, so a failure names the run that reproduces it.
    private struct SplitMix64 {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func below(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
        mutating func pick<T>(_ items: [T]) -> T { items[below(items.count)] }
        mutating func chance(_ percent: Int) -> Bool { below(100) < percent }
    }

    private static let lines = [
        "- item", "  - nested item", "* star", "+ plus", "1. one", "2. two", "10. ten", "  1. nested one",
        "- [ ] open task", "- [x] done task", "1. [ ] numbered task", "> quote", "> ", ">", "> - quoted item",
        "| Name | Price |", "| ---- | ----: |", "| Apple | 3 |", "| Pear | 12 |", "|  |  |", "| a | b",
        "```", "```swift", "~~~", "$$", "x = y", "\u{2013} en dash", "\u{2022} bullet", "| piped words",
        "plain words here", "\u{4E2D}\u{6587}\u{6BB5}\u{843D}", "emoji \u{1F600} line", "", "", "    indented code",
        "\t- tab item", "\twith tab", "# Heading", "## Sub heading", "**bold** and *em*", "a | b | c",
        "[[Note|label]] | x", "- ", "1. ", "- [ ] ",
    ]

    private static let typed = ["a", "\u{4E2D}", "-", " ", "|", "`", "1", ".", ">", "x", "\u{1F600}", "[", "]"]

    private enum Step: CustomStringConvertible {
        case key(Int, shift: Bool)
        case type(String)
        case backspace
        case format(String)
        case table(TableEditing.Command)
        case select(Int, Int)

        var description: String {
            switch self {
            case .key(let code, let shift): return (shift ? "shift-" : "") + (code == kVK_Return ? "return" : "tab")
            case .type(let s): return "type \(s.debugDescription)"
            case .backspace: return "backspace"
            case .format(let name): return name
            case .table(let command): return "table \(command)"
            case .select(let location, let length): return "select \(location)+\(length)"
            }
        }
    }

    @MainActor
    private final class UndoHost: NSObject, NSTextViewDelegate {
        let manager: UndoManager = {
            let manager = UndoManager()
            manager.groupsByEvent = false
            manager.levelsOfUndo = 0
            return manager
        }()
        func undoManager(for view: NSTextView) -> UndoManager? { manager }
    }

    private func makeText(_ rng: inout SplitMix64) -> String {
        let count = 1 + rng.below(9)
        let text = (0..<count).map { _ in rng.pick(Self.lines) }.joined(separator: "\n")
        return rng.chance(8) ? text.replacingOccurrences(of: "\n", with: "\r\n") : text
    }

    private func makeSteps(_ rng: inout SplitMix64, structural: Bool) -> [Step] {
        let formats = structural ? ["bold", "italic", "todo", "quote", "codeBlock", "backTick"] : ["bold", "italic", "todo", "quote", "codeBlock", "backTick", "link"]
        let commands: [TableEditing.Command] = [.insertRowAbove, .insertRowBelow, .insertColumnLeft, .insertColumnRight, .align(.center), .align(.right)]
        let destructive: [TableEditing.Command] = [.deleteRow, .deleteColumn]
        return (0..<(4 + rng.below(10))).map { _ in
            switch rng.below(structural ? 8 : 11) {
            case 0, 1: return .key(kVK_Return, shift: rng.chance(20))
            case 2, 3: return .key(kVK_Tab, shift: rng.chance(35))
            case 4: return .format(rng.pick(formats))
            case 5: return .table(rng.pick(commands))
            case 6, 7: return .select(rng.below(1000), rng.chance(70) ? 0 : rng.below(40))
            case 8: return .backspace
            case 9: return .table(rng.pick(destructive))
            default: return .type(rng.pick(Self.typed))
            }
        }
    }

    @MainActor
    private func makeEditor(_ body: String, host: UndoHost) throws -> EditTextView {
        let url = tempDir.appendingPathComponent("fuzz-\(UUID().uuidString).md")
        try body.write(to: url, atomically: true, encoding: .utf8)
        let note = Note(url: url, with: Project(url: tempDir, label: "test", isRoot: true))
        note.content = NSMutableAttributedString(string: body)
        EditTextView.note = note
        let editor = EditTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        editor.isShellHosted = true
        editor.allowsUndo = true
        editor.delegate = host
        editor.publishStorage(NSAttributedString(string: body), owner: note)
        return editor
    }

    @MainActor
    private func press(_ key: Int, shift: Bool, in editor: EditTextView) throws {
        let characters = key == kVK_Return ? "\r" : "\t"
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [], timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(key)))
        editor.keyDown(with: event)
    }

    @MainActor
    private func run(_ step: Step, in editor: EditTextView, structural: Bool) throws {
        let length = (editor.string as NSString).length
        guard let note = EditTextView.note else { return XCTFail("no note") }
        switch step {
        case .key(let code, let shift):
            // A structural run keeps the writer's letters, so a line break
            // never types over a selection there. Return in a table moves to
            // the next row and keeps the cell it selected; Shift-Return is a
            // plain line break even there. Tab may still act on a selection.
            if structural, code == kVK_Return, editor.selectedRange().length > 0, shift || !inTable(editor) {
                editor.setSelectedRange(NSRange(location: NSMaxRange(editor.selectedRange()), length: 0))
            }
            try press(code, shift: shift, in: editor)
        case .type(let s):
            editor.insertText(s, replacementRange: editor.selectedRange())
        case .backspace:
            editor.deleteBackward(nil)
        case .format(let name):
            let formatter = TextFormatter(textView: editor, note: note)
            switch name {
            case "bold": formatter.bold()
            case "italic": formatter.italic()
            case "todo": formatter.toggleTodo()
            case "quote": formatter.quote()
            case "codeBlock": formatter.codeBlock()
            case "backTick": formatter.backTick()
            default: formatter.link()
            }
        case .table(let command):
            TextFormatter(textView: editor, note: note).tableEdit(command)
        case .select(let location, let size):
            let start = min(location, length)
            var range = NSRange(location: start, length: min(size, length - start))
            // Never split a surrogate pair or a CRLF: AppKit would not either.
            range = (editor.string as NSString).rangeOfComposedCharacterSequences(for: range)
            editor.setSelectedRange(range)
        }
    }

    @MainActor
    private func inTable(_ editor: EditTextView) -> Bool {
        TableEditing.edit(.nextRow, in: editor.string as NSString, selection: editor.selectedRange()) != nil
    }

    /// The letters of a text, with a task's box left out: Return on an empty
    /// task item ends the list and takes its `[x]` with it, as it should.
    private func letters(_ text: String) -> [Character] {
        let unboxed = text.replacingOccurrences(of: "\\[[ xX]\\]", with: "", options: .regularExpression)
        return unboxed.filter { $0.isLetter }
    }

    private func isSubsequence(_ small: [Character], of big: [Character]) -> Bool {
        var index = big.startIndex
        for character in small {
            guard let found = big[index...].firstIndex(of: character) else { return false }
            index = big.index(after: found)
        }
        return true
    }

    @MainActor
    func testRandomKeysUndoRedoAndKeepTheWritersLetters() throws {
        let runs = Int(ProcessInfo.processInfo.environment["MIAOYAN_FUZZ_RUNS"] ?? "") ?? 1000
        let firstSeed = UInt64(ProcessInfo.processInfo.environment["MIAOYAN_FUZZ_SEED"] ?? "") ?? 1
        var failures = 0
        for seed in firstSeed..<(firstSeed + UInt64(runs)) {
            var rng = SplitMix64(state: seed)
            let original = makeText(&rng)
            let structural = seed % 2 == 0
            let steps = makeSteps(&rng, structural: structural)
            let host = UndoHost()
            let editor = try makeEditor(original, host: host)
            editor.setSelectedRange(NSRange(location: rng.below((original as NSString).length + 1), length: 0))
            editor.setSelectedRange((editor.string as NSString).rangeOfComposedCharacterSequences(for: editor.selectedRange()))

            var done: [String] = []
            func fail(_ what: String) {
                failures += 1
                XCTFail("seed \(seed) \(what)\noriginal: \(original.debugDescription)\nsteps: \(done.joined(separator: ", "))\nnow: \(editor.string.debugDescription)")
            }

            for step in steps {
                done.append(step.description)
                host.manager.beginUndoGrouping()
                try run(step, in: editor, structural: structural)
                host.manager.endUndoGrouping()
                let selection = editor.selectedRange()
                if NSMaxRange(selection) > (editor.string as NSString).length {
                    fail("selection \(selection) past the text")
                    break
                }
            }
            let final = editor.string

            if structural, !isSubsequence(letters(original), of: letters(final)) {
                fail("lost a letter of the note")
            }
            while host.manager.canUndo { host.manager.undo() }
            if editor.string != original { fail("undo to the end gave \(editor.string.debugDescription)") }
            while host.manager.canRedo { host.manager.redo() }
            if editor.string != final { fail("redo to the end gave \(editor.string.debugDescription), not \(final.debugDescription)") }

            if failures >= 5 { break }
        }
    }
}
