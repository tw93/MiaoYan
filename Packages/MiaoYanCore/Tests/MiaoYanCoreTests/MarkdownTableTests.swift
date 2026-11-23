import Foundation
import XCTest

@testable import MiaoYanCore

final class MarkdownTableTests: XCTestCase {
    /// Runs `command` on `source`, where `^` marks the caret (or the two
    /// ends of the selection), and returns the result marked the same way.
    private func run(_ command: TableEditing.Command, _ source: String, file: StaticString = #filePath, line: UInt = #line) -> String? {
        let marks = source.components(separatedBy: "^")
        XCTAssertTrue(marks.count == 2 || marks.count == 3, "one caret or one selection", file: file, line: line)
        let text = marks.joined() as NSString
        let start = (marks[0] as NSString).length
        let selection = NSRange(location: start, length: marks.count == 3 ? (marks[1] as NSString).length : 0)
        guard let edit = TableEditing.edit(command, in: text, selection: selection) else { return nil }
        let result = NSMutableString(string: text)
        result.replaceCharacters(in: edit.range, with: edit.replacement)
        if edit.selection.length > 0 { result.insert("^", at: NSMaxRange(edit.selection)) }
        result.insert("^", at: edit.selection.location)
        return result as String
    }

    private let tidy = """
        | Name  | Price |
        | ----- | ----- |
        | Apple | 3     |
        | Pear  | 12    |
        """

    func testTabGoesToTheNextCellAndSelectsItsWords() {
        XCTAssertEqual(
            run(.nextCell, tidy.replacingOccurrences(of: "Apple", with: "App^le")),
            tidy.replacingOccurrences(of: "| 3 ", with: "| ^3^ "))
        // From a row's last cell to the first cell of the next row.
        XCTAssertEqual(
            run(.nextCell, tidy.replacingOccurrences(of: "| 3 ", with: "| 3^ ")),
            tidy.replacingOccurrences(of: "Pear", with: "^Pear^"))
        // From the header's last cell over the dashes.
        XCTAssertEqual(
            run(.nextCell, tidy.replacingOccurrences(of: "Price", with: "Price^")),
            tidy.replacingOccurrences(of: "Apple", with: "^Apple^"))
    }

    func testTabInTheLastCellAddsARow() {
        XCTAssertEqual(
            run(.nextCell, tidy.replacingOccurrences(of: "| 12 ", with: "| 12^ ")),
            tidy + "\n| ^      |       |")
    }

    func testShiftTabGoesBackAndStopsAtTheFirstCell() {
        XCTAssertEqual(
            run(.previousCell, tidy.replacingOccurrences(of: "| 3 ", with: "| ^3^ ")),
            tidy.replacingOccurrences(of: "Apple", with: "^Apple^"))
        XCTAssertEqual(
            run(.previousCell, tidy.replacingOccurrences(of: "Apple", with: "^Apple")),
            tidy.replacingOccurrences(of: "Price", with: "^Price^"))
        XCTAssertEqual(
            run(.previousCell, tidy.replacingOccurrences(of: "Name", with: "Na^me")),
            tidy.replacingOccurrences(of: "Name", with: "^Name^"))
    }

    func testAMoveInATidyTableRewritesNothing() {
        let text = tidy as NSString
        let caret = text.range(of: "Apple").location + 2
        let edit = TableEditing.edit(.nextCell, in: text, selection: NSRange(location: caret, length: 0))
        XCTAssertEqual(edit?.range.length, 0)
        XCTAssertEqual(edit?.replacement, "")
        XCTAssertEqual(edit?.selection, text.range(of: "3"))
    }

    func testReturnGoesToTheNextRowAndAddsOneAfterTheLast() {
        XCTAssertEqual(
            run(.nextRow, tidy.replacingOccurrences(of: "| 3 ", with: "| 3^ ")),
            tidy.replacingOccurrences(of: "Pear", with: "^Pear^"))
        XCTAssertEqual(
            run(.nextRow, tidy.replacingOccurrences(of: "Price", with: "Pri^ce")),
            tidy.replacingOccurrences(of: "Apple", with: "^Apple^"))
        XCTAssertEqual(
            run(.nextRow, tidy.replacingOccurrences(of: "Pear", with: "Pear^")),
            tidy + "\n| ^      |       |")
    }

    func testReturnOnAnEmptyLastRowLeavesTheTable() {
        XCTAssertEqual(run(.nextRow, tidy + "\n| ^      |       |\n\nafter"), tidy + "\n^\n\nafter")
        // A row with words in it is a row like any other.
        XCTAssertEqual(
            run(.nextRow, tidy + "\n| ^      | 4     |"),
            tidy + "\n|       | 4     |\n| ^      |       |")
    }

    func testReturnBeforeARowsFirstPipeIsAPlainLineBreak() {
        XCTAssertNil(run(.nextRow, "^" + tidy), "the table is pushed down a line")
        XCTAssertNil(run(.nextRow, "^Name | Price\n--- | ---"), "a header without outer pipes too")
        XCTAssertNil(run(.nextRow, tidy.replacingOccurrences(of: "| Pear", with: "^| Pear")))
        XCTAssertNotNil(run(.nextRow, tidy.replacingOccurrences(of: "| Pear", with: "|^ Pear")))
        XCTAssertNotNil(run(.nextCell, "^" + tidy), "Tab still moves to the next cell")
    }

    func testAnUntidyTableIsTidiedByTheFirstKey() {
        let rough = """
            |Name|Price|
            |-|:-:|
            |App^le|3
            |Pear|12|extra|
            """
        XCTAssertEqual(
            run(.nextCell, rough),
            """
            | Name  | Price |       |
            | ----- | :---: | ----- |
            | Apple |   ^3^   |       |
            | Pear  |  12   | extra |
            """)
    }

    func testARowBeingTypedBecomesATable() {
        XCTAssertEqual(
            run(.nextRow, "| Name | Price |^"),
            """
            | Name | Price |
            | ---- | ----- |
            | ^     |       |
            """)
        XCTAssertEqual(
            run(.nextCell, "intro\n\n| Name^ | Price |"),
            """
            intro

            | Name | ^Price^ |
            | ---- | ----- |
            """)
    }

    /// A line that starts with a pipe is not yet a table: absolute values,
    /// a diagram drawn in pipes and a row still open keep the old keys.
    func testALineOfPipesThatIsNoRowIsLeftAlone() {
        XCTAssertNil(run(.nextRow, "|x| + |y| = 1^"))
        XCTAssertNil(run(.nextRow, "|x|^"), "one cell is no table")
        XCTAssertNil(run(.nextRow, "|^"))
        XCTAssertNil(run(.nextCell, "| Name | Price^"), "a row not closed yet")
        XCTAssertNil(run(.nextRow, "$$\n| a | b |^\n$$"), "a formula")
        XCTAssertNil(run(.nextRow, "$$\n| a | b |^\n| - | - |\n$$"))
        XCTAssertNotNil(run(.nextRow, "$$\nx\n$$\n\n| a | b |^"), "after the formula has closed")
        XCTAssertNotNil(run(.nextRow, "costs $$ 5\n\n$$ x $$\n\n| a | b |^"), "two `$$` on a line open nothing")
    }

    /// A line ending in `[[` trapped: the search for the closing brackets
    /// was given a range that ran backwards, and every Return and Tab on a
    /// line with a link being typed passed through it.
    func testALineEndingInOpenBracketsIsRead() {
        XCTAssertNil(run(.nextRow, "see [[^"))
        XCTAssertNil(run(.nextCell, "[[^"))
        XCTAssertEqual(run(.nextCell, "| a^ | b [[\n|-|-|"), "| a   | ^b [[^ |\n| --- | ---- |")
        XCTAssertEqual(run(.nextCell, "| a^ | [[]] |\n|-|-|"), "| a   | ^[[]]^ |\n| --- | ---- |")
        XCTAssertEqual(run(.nextCell, "| a^ | [ |\n|-|-|"), "| a   | ^[^   |\n| --- | --- |")
    }

    /// Only spaces and tabs are trimmed from a cell. Trimming every kind of
    /// white space deleted a no-break space, an ideographic space and a
    /// zero-width space the writer had put at a cell's edge.
    func testOtherSpacesAtACellsEdgeAreKept() {
        let table = "| a^ | \u{00A0} |\n|-|-|\n| \u{3000}\u{4E2D} | \u{200B} |\n| \tx\t | y |"
        let result = run(.nextCell, table)
        XCTAssertEqual(
            result,
            "| a    | ^\u{00A0}^   |\n| ---- | --- |\n| \u{3000}\u{4E2D} | \u{200B}   |\n| x    | y   |")
    }

    func testChineseAndEmojiCountTwoColumns() {
        XCTAssertEqual(TableEditing.displayWidth("abc"), 3)
        XCTAssertEqual(TableEditing.displayWidth("\u{540D}\u{79F0}"), 4)
        XCTAssertEqual(TableEditing.displayWidth("\u{30AB}\u{30BF}"), 4)
        XCTAssertEqual(TableEditing.displayWidth("\u{D55C}"), 2)
        XCTAssertEqual(TableEditing.displayWidth("\u{FF0C}"), 2, "a fullwidth comma")
        XCTAssertEqual(TableEditing.displayWidth("\u{1F600}"), 2)
        XCTAssertEqual(TableEditing.displayWidth("e\u{301}"), 1, "a combining accent takes no column")
        XCTAssertEqual(TableEditing.displayWidth("\u{201C}a\u{201D}"), 3, "curly quotes are narrow")
        XCTAssertEqual(TableEditing.displayWidth("1\u{FE0F}\u{20E3}"), 2, "a keycap")
        XCTAssertEqual(TableEditing.displayWidth("\u{2764}\u{FE0F}"), 2)
        XCTAssertEqual(TableEditing.displayWidth("a\u{200B}b"), 3, "Prettier counts a zero-width space as one")
        XCTAssertEqual(
            run(.nextCell, "| \u{540D}\u{79F0}^ | Price |\n|-|-|\n| \u{82F9}\u{679C}\u{6C41} | 3 |"),
            """
            | \u{540D}\u{79F0}   | ^Price^ |
            | ------ | ----- |
            | \u{82F9}\u{679C}\u{6C41} | 3     |
            """)
    }

    func testAnEscapedPipeStaysInItsCell() {
        XCTAssertEqual(
            run(.nextCell, "| a \\| b^ | c |\n|-|-|"),
            """
            | a \\| b | ^c^   |
            | ------ | --- |
            """)
    }

    func testALinkWithALabelIsNotCutAtItsPipe() {
        XCTAssertEqual(
            run(.nextCell, "| [[note|label]]^ | c |\n|-|-|"),
            """
            | [[note|label]] | ^c^   |
            | -------------- | --- |
            """)
        XCTAssertEqual(run(.nextCell, "| [[open^ | c |\n|-|-|"), "| [[open | ^c^   |\n| ------ | --- |", "brackets never closed are text")
    }

    func testProseCodeAndSpanningSelectionsAreLeftAlone() {
        XCTAssertNil(run(.nextCell, "a ^| b"), "a pipe in a sentence")
        XCTAssertNil(run(.nextCell, "plain ^text"))
        XCTAssertNil(run(.nextCell, "```\n| a^ | b |\n|-|-|\n```"), "a table in fenced code is code")
        XCTAssertNil(run(.nextCell, "~~~\n| a^ | b |\n|-|-|\n~~~"), "tildes fence too")
        XCTAssertNil(run(.nextCell, "- item\n  ```\n  | a^ | b |\n  |-|-|\n  ```"), "a fence indented under a list item")
        XCTAssertNil(run(.nextCell, "```\n| a^ | b |\n|-|-|"), "a fence never closed runs to the end")
        XCTAssertNil(run(.nextCell, "    | a^ | b |\n    |-|-|"), "four spaces in is a code block")
        XCTAssertNil(run(.nextCell, "\t| a^ | b |\n\t|-|-|"))
        XCTAssertNotNil(run(.nextCell, "```\ncode\n```\n\n| a^ | b |\n|-|-|"), "after the fence has closed")
        XCTAssertNotNil(run(.nextCell, "````\n```\n````\n\n| a^ | b |\n|-|-|"), "a shorter run does not close a longer fence")
        XCTAssertNil(run(.nextCell, "| a^ | b |\n|-|-|\n| c^ | d |"), "a selection over two rows indents as before")
        XCTAssertNil(run(.nextCell, "intro with a^ | pipe\n| a | b |\n|-|-|"), "the paragraph a table interrupts")
        XCTAssertFalse(TableEditing.isInTable(in: "text", selection: NSRange(location: 0, length: 0)))
        XCTAssertTrue(TableEditing.isInTable(in: "| a | b |\n|-|-|", selection: NSRange(location: 3, length: 0)))
    }

    func testHeaderAndDashesMustHaveTheSameNumberOfCells() {
        XCTAssertNil(run(.nextCell, "| a^ | b | c |\n|---|---|"), "three header cells over two dashes is no table")
        XCTAssertEqual(TableEditing.layouts(in: "| a | b | c |\n|---|---|" as NSString).count, 0)
        XCTAssertNotNil(run(.nextCell, "| a^ | b |\n|---|---|"))
    }

    func testFenceAndFormulaFollowCommonMark() {
        let table = "| a^ | b |\n|-|-|"
        XCTAssertNotNil(run(.nextCell, "```foo``` bar\n\n" + table), "a backtick in the info string is a code span, not a fence")
        XCTAssertNil(run(.nextCell, "``` foo\n\n" + table), "an info string without a backtick opens a fence")
        XCTAssertNil(run(.nextCell, "~~~ a`b\n\n" + table), "tildes allow a backtick in the info string")
        XCTAssertNil(run(.nextCell, "```\n    ```\n" + table), "four spaces in does not close a fence")
        XCTAssertNotNil(run(.nextCell, "```\n   ```\n" + table), "three spaces in closes it")
        XCTAssertNil(run(.nextCell, "- a\n    ```\n    x\n    ```\n    ```\n    | a^ | b |\n    |-|-|"), "a fence nested in an item closes at its own indent")
        XCTAssertNotNil(run(.nextCell, "price 5$$\n\n" + table), "a line ending in $$ opens no formula")
        XCTAssertNil(run(.nextCell, "$$\n" + table), "a line starting with $$ does")
        XCTAssertNotNil(run(.nextCell, "$$ x $$\n\n" + table), "$$ x $$ on one line opens nothing")
        XCTAssertNotNil(run(.nextCell, "$$\nx = 1 $$\n\n" + table), "a line ending in $$ closes an open formula")
        XCTAssertEqual(TableEditing.codeLineStarts(in: "```\n- a\n```\n- b" as NSString, covering: NSRange(location: 0, length: 16)), [4, 8], "a line begins inside the fence the line before it opened")
    }

    func testATableUnderAListItemIsNotAnIndentedCodeBlock() {
        XCTAssertNotNil(run(.nextCell, "- item\n\n    | a^ | b |\n    |-|-|"), "four spaces under a dash item is inside the item")
        XCTAssertNotNil(run(.nextCell, "- item\n  - nested\n\n      | a^ | b |\n      |-|-|"), "inside a nested item")
        XCTAssertNotNil(run(.nextCell, "1. item\n\n\t| a^ | b |\n\t|-|-|"), "a tab under a numbered item")
        XCTAssertNil(run(.nextCell, "- item\n\n          | a^ | b |\n          |-|-|"), "four columns past the item's content is code")
        XCTAssertNil(run(.nextCell, "- item\n\nplain\n\n    | a^ | b |\n    |-|-|"), "after the list ended")
        XCTAssertEqual(TableEditing.layouts(in: "- item\n\n    | a | b |\n    |-|-|" as NSString).count, 1)
    }

    func testATableWithoutOuterPipesIsReadAndGetsThem() {
        XCTAssertEqual(
            run(.nextCell, "Name^ | Price\n--- | ---\nApple | 3"),
            """
            | Name  | ^Price^ |
            | ----- | ----- |
            | Apple | 3     |
            """)
    }

    func testIndentedTablesKeepTheirIndent() {
        XCTAssertEqual(
            run(.nextCell, "  | a^ | b |\n  |-|-|"),
            "  | a   | ^b^   |\n  | --- | --- |")
    }

    func testRowsAreAddedAndRemoved() {
        XCTAssertEqual(
            run(.insertRowBelow, tidy.replacingOccurrences(of: "Apple", with: "App^le")),
            tidy.replacingOccurrences(of: "| Pear ", with: "| ^      |       |\n| Pear "))
        XCTAssertEqual(
            run(.insertRowAbove, tidy.replacingOccurrences(of: "| 3 ", with: "| 3^ ")),
            tidy.replacingOccurrences(of: "| Apple ", with: "|       | ^      |\n| Apple "))
        XCTAssertEqual(
            run(.insertRowBelow, tidy.replacingOccurrences(of: "Name", with: "Na^me")),
            tidy.replacingOccurrences(of: "| Apple ", with: "| ^      |       |\n| Apple "))
        XCTAssertEqual(
            run(.deleteRow, tidy.replacingOccurrences(of: "Apple", with: "App^le")),
            """
            | Name | Price |
            | ---- | ----- |
            | ^Pear^ | 12    |
            """)
        XCTAssertNil(run(.deleteRow, tidy.replacingOccurrences(of: "Name", with: "Na^me")), "the header is not a row to delete")
    }

    func testColumnsAreAddedRemovedAndAligned() {
        XCTAssertEqual(
            run(.insertColumnRight, tidy.replacingOccurrences(of: "Apple", with: "App^le")),
            """
            | Name  |     | Price |
            | ----- | --- | ----- |
            | Apple | ^    | 3     |
            | Pear  |     | 12    |
            """)
        XCTAssertEqual(
            run(.insertColumnLeft, tidy.replacingOccurrences(of: "Name", with: "Na^me")),
            """
            | ^    | Name  | Price |
            | --- | ----- | ----- |
            |     | Apple | 3     |
            |     | Pear  | 12    |
            """)
        XCTAssertEqual(
            run(.deleteColumn, tidy.replacingOccurrences(of: "Apple", with: "App^le")),
            """
            | Price |
            | ----- |
            | ^3^     |
            | 12    |
            """)
        XCTAssertNil(run(.deleteColumn, "| on^ly |\n|-|"), "a table keeps one column")
        XCTAssertEqual(
            run(.align(.right), tidy.replacingOccurrences(of: "| 3 ", with: "| 3^ ")),
            """
            | Name  | Price |
            | ----- | ----: |
            | Apple |     ^3^ |
            | Pear  |    12 |
            """)
        XCTAssertEqual(
            run(.align(.left), tidy.replacingOccurrences(of: "Name", with: "Na^me")),
            tidy.replacingOccurrences(of: "| ----- | ----- |", with: "| :---- | ----- |").replacingOccurrences(of: "Name", with: "^Name^"))
    }

    func testANoteWithWindowsLineEndingsKeepsThem() {
        XCTAssertEqual(
            run(.nextRow, "| a | b^ |\r\n|-|-|"),
            "| a   | b   |\r\n| --- | --- |\r\n| ^    |     |")
        // The table's own line ending, not the first one in the note.
        XCTAssertEqual(
            run(.nextRow, "intro\r\n\r\n| a | b^ |\n|-|-|"),
            "intro\r\n\r\n| a   | b   |\n| --- | --- |\n| ^    |     |")
        XCTAssertEqual(run(.nextRow, "old\r\r| a | b^ |\r|-|-|"), "old\r\r| a   | b   |\r| --- | --- |\r| ^    |     |")
    }

    func testEdgesOfTheTextAreRead() {
        XCTAssertNil(TableEditing.edit(.nextCell, in: "", selection: NSRange(location: 0, length: 0)))
        XCTAssertNil(TableEditing.edit(.nextCell, in: "| a | b |\n", selection: NSRange(location: 10, length: 0)), "the empty last line")
        XCTAssertNil(TableEditing.edit(.nextCell, in: "| a |", selection: NSRange(location: 9, length: 0)), "past the end")
        XCTAssertEqual(run(.nextCell, "| a | b |\n|-|-|\n| c | d^ |"), "| a   | b   |\n| --- | --- |\n| c   | d   |\n| ^    |     |")
        XCTAssertEqual(run(.previousCell, "| a | b |\n|-^|-|\n| c | d |"), "| a   | ^b^   |\n| --- | --- |\n| c   | d   |", "from the dashes")
    }

    /// The lines of the table were found by counting from the top of the
    /// note for every row, so one key in a table at the end of a long note
    /// took most of a second, and opening Format, which asks nine times,
    /// several. A table now costs its own lines.
    func testATableAtTheEndOfALongNoteIsFoundFromTheCaret() {
        let filler = String(repeating: "A line of an ordinary paragraph, no table in sight.\n", count: 20_000)
        let rows = (1...50).map { "| row \($0) | value |" }.joined(separator: "\n")
        let text = (filler + "\n| Name | Value |\n| --- | --- |\n" + rows) as NSString
        let caret = NSRange(location: text.length - 3, length: 0)
        let started = Date()
        for _ in 0..<9 { XCTAssertNotNil(TableEditing.edit(.nextCell, in: text, selection: caret)) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5, "nine edits in a megabyte of text")
    }

    /// Whatever the text and wherever the caret, a table key never traps,
    /// never points outside the text and never loses a character that is
    /// not table punctuation: 400 texts made from the characters that
    /// steer the parser, every command at every offset of each.
    func testNoCommandLosesTextOrLeavesTheTextOnAnyInput() {
        let punctuation = Set<Character>(["|", "-", ":", " ", "\t", "\n", "\r", "\r\n"])
        func words(_ text: String) -> String { String(text.filter { !punctuation.contains($0) }) }
        let keeping: [TableEditing.Command] = [
            .nextCell, .previousCell, .nextRow, .insertRowAbove, .insertRowBelow, .insertColumnLeft, .insertColumnRight, .align(.center),
        ]
        let texts = MadeUpTexts(seed: 0x2026_1120)
        var edits = 0
        for round in 0..<400 {
            let source = round % 2 == 0 ? texts.soup(4 + texts.random(36)) : texts.tableLike()
            let text = source as NSString
            for offset in 0...text.length {
                let selection = NSRange(location: offset, length: 0)
                for command in keeping + [.deleteRow, .deleteColumn] {
                    guard let edit = TableEditing.edit(command, in: text, selection: selection) else { continue }
                    edits += 1
                    guard edit.range.location >= 0, NSMaxRange(edit.range) <= text.length else {
                        return XCTFail("\(command) replaces outside \(source.debugDescription) at \(offset)")
                    }
                    let result = text.replacingCharacters(in: edit.range, with: edit.replacement)
                    guard NSMaxRange(edit.selection) <= (result as NSString).length else {
                        return XCTFail("\(command) selects outside \(source.debugDescription) at \(offset)")
                    }
                    if keeping.contains(command), words(result) != words(source) {
                        return XCTFail("\(command) at \(offset) turned \(source.debugDescription) into \(result.debugDescription)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(edits, 10_000, "the texts did hold tables")
    }

    // MARK: - Where the pipes stand

    func testTheLayoutNamesWhereEachCellStarts() {
        let source = "Intro\n\n| a | \u{4E2D} |\n| :-- | --: |\n| long cell | b |\nafter"
        let text = source as NSString
        let layouts = TableEditing.layouts(in: text)
        XCTAssertEqual(layouts.count, 1)
        let layout = layouts[0]
        XCTAssertEqual(text.substring(with: layout.range), "| a | \u{4E2D} |\n| :-- | --: |\n| long cell | b |")
        XCTAssertEqual(layout.alignments, [.left, .right])
        XCTAssertEqual(layout.rows.count, 3)
        for row in layout.rows {
            XCTAssertEqual(row.count, 3, "two cells and the closing pipe")
            XCTAssertTrue(row.allSatisfy { text.character(at: $0) == 0x7C })
        }
        XCTAssertEqual(layout.rows[0], [7, 11, 15])
    }

    func testARowWithoutALeadingPipeStartsAtItsFirstWord() {
        let text = "  a | b\n  --- | ---\n  c | d" as NSString
        let layout = TableEditing.layouts(in: text)[0]
        XCTAssertEqual(layout.rows[0], [2, 4], "the first cell starts after the indent, the second at its pipe")
        XCTAssertEqual(layout.alignments, [.none])
    }

    func testOnlyRealTablesHaveALayout() {
        func count(_ source: String) -> Int { TableEditing.layouts(in: source as NSString).count }
        XCTAssertEqual(count("a | b in a sentence\nand |x| + |y|"), 0)
        XCTAssertEqual(count("| a | b |\n| c | d |"), 0, "rows still being typed, no dashes yet")
        XCTAssertEqual(count("```\n| a | b |\n| - | - |\n```"), 0)
        XCTAssertEqual(count("~~~\n| a | b |\n| - | - |"), 0, "a fence never closed runs to the end")
        XCTAssertEqual(count("$$\n| a | b |\n| - | - |\n$$"), 0)
        XCTAssertEqual(count("    | a | b |\n    | - | - |"), 0, "four columns of indent is code")
        XCTAssertEqual(count("```\ncode\n```\n| a | b |\n| - | - |\n\n| c |\n| - |"), 2)
        XCTAssertEqual(count("prose | here\n| a | b |\n| - | - |"), 1, "the table starts at the line above the dashes")
    }

    /// The layouts are the tables the keys edit: read from the top, read
    /// for a few lines, and found from the caret, they name the same lines.
    func testTheLayoutsAreTheTablesTheKeysEdit() {
        let texts = MadeUpTexts(seed: 0x2026_1121)
        var tables = 0
        for round in 0..<600 {
            var source = round % 3 == 0 ? texts.soup(4 + texts.random(36)) : texts.tableLike()
            if round % 5 == 0 { source = ["```", "~~~", "$$", "``` \n```"][texts.random(4)] + "\n" + source }
            let text = source as NSString
            let fromTheTop = TableEditing.layouts(in: text)
            XCTAssertEqual(TableEditing.layouts(in: text, lines: NSRange(location: 0, length: text.length)), fromTheTop, source.debugDescription)
            tables += fromTheTop.count
            for offset in 0...text.length {
                // Between the two halves of a Windows line ending is no line.
                if offset > 0, offset < text.length, text.character(at: offset - 1) == 0x0D, text.character(at: offset) == 0x0A { continue }
                let located = TableEditing.locate(in: text, selection: NSRange(location: offset, length: 0))
                let expected = located.flatMap { $0.hasDelimiter ? $0.range : nil }
                let layout = fromTheTop.first { $0.range.location <= offset && offset <= NSMaxRange($0.range) }
                guard layout?.range == expected else {
                    return XCTFail("at \(offset) of \(source.debugDescription) the keys see \(String(describing: expected)), the layout \(String(describing: layout?.range))")
                }
            }
            for layout in fromTheTop {
                XCTAssertEqual(TableEditing.layouts(in: text, lines: layout.range), [layout], "read for its own lines alone")
                for row in layout.rows {
                    guard row == row.sorted(), row.allSatisfy({ layout.range.location <= $0 && $0 < NSMaxRange(layout.range) }) else {
                        return XCTFail("a cell starts outside its table in \(source.debugDescription)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(tables, 150, "the texts did hold tables")
    }

    func testTheTablesOfALongNoteAreReadInOnePass() {
        let table = "| a | b |\n| --- | --- |\n| c | d |\n\n"
        let prose = String(repeating: "A line of prose with a | pipe in it.\n", count: 40)
        let note = String(repeating: "```\ncode | here\n```\n" + prose + table, count: 600) as NSString
        XCTAssertGreaterThan(note.length, 900_000)
        let start = Date()
        XCTAssertEqual(TableEditing.layouts(in: note).count, 600)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2, "one pass, not one from the top for each table")
    }
}

/// Made-up texts for the tests that try every offset: anything at all, and
/// rows of cells between two stretches of anything.
private final class MadeUpTexts {
    private let alphabet: [String] = [
        "|", "|", "|", "-", "-", ":", " ", " ", "\n", "\n", "\r\n", "\r", "[", "]", "\\", "$", "`", "~", "\t", "a", "b",
        "\u{4E2D}", "\u{1F600}", "\u{00A0}", "\u{3000}", "e\u{301}",
    ]
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    func random(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(bound))
    }

    func soup(_ length: Int) -> String { (0..<length).map { _ in alphabet[random(alphabet.count)] }.joined() }

    /// Rows of cells, most with a line of dashes second, between two
    /// stretches of anything.
    func tableLike() -> String {
        let lineBreak = ["\n", "\r\n", "\r"][random(3)]
        let columns = 1 + random(4)
        // The header has as many cells as the dashes, or it is no table; the rows below may differ.
        var lines = (0..<(1 + random(4))).map { row -> String in
            let cells = (0..<(columns + (row == 0 ? 0 : random(2)))).map { _ in soup(random(4)).filter { $0 != "\n" && $0 != "\r" && $0 != "\r\n" } }
            return (random(4) == 0 ? "" : "|") + cells.joined(separator: "|") + (random(4) == 0 ? "" : "|")
        }
        if random(5) != 0 { lines.insert("|" + (0..<columns).map { _ in [":-", "-", "-:", ":-:", "---"][random(5)] }.joined(separator: "|") + "|", at: min(1, lines.count)) }
        return soup(random(6)) + lineBreak + lines.joined(separator: lineBreak) + lineBreak + soup(random(6))
    }
}
