import XCTest

@testable import MiaoYanCore

final class MarkdownEditingTests: XCTestCase {
    // MARK: Source lines

    func testLineRangesEndOnlyAtCmarkLineEndings() {
        let text = "a\u{2028}b\r\nsecond\rthird\nlast" as NSString
        XCTAssertEqual(SourceLines.range(ofLine: 0, in: text).map(text.substring(with:)), "a\u{2028}b")
        XCTAssertEqual(SourceLines.range(ofLine: 1, in: text).map(text.substring(with:)), "second")
        XCTAssertEqual(SourceLines.range(ofLine: 2, in: text).map(text.substring(with:)), "third")
        XCTAssertEqual(SourceLines.range(ofLine: 3, in: text).map(text.substring(with:)), "last")
        XCTAssertNil(SourceLines.range(ofLine: 4, in: text))
    }

    func testLineAtOffsetMatchesLineRanges() {
        let text = "one\r\ntwo\n\nfour" as NSString
        for index in 0..<4 {
            let range = SourceLines.range(ofLine: index, in: text)!
            XCTAssertEqual(SourceLines.line(atOffset: range.location, in: text), index)
            XCTAssertEqual(SourceLines.line(atOffset: NSMaxRange(range), in: text), index)
        }
        XCTAssertEqual(SourceLines.line(atOffset: 999, in: text), 3)
    }

    // MARK: Task marker

    func testToggleCountsBodyLinesAfterFrontmatter() {
        let text = "---\ntitle: a\n---\nintro\n- [ ] first\n- [x] second\n"
        XCTAssertEqual(TaskMarker.toggled(text, bodyLine: 2), "---\ntitle: a\n---\nintro\n- [x] first\n- [x] second\n")
        XCTAssertEqual(TaskMarker.toggled(text, bodyLine: 3), "---\ntitle: a\n---\nintro\n- [ ] first\n- [ ] second\n")
        XCTAssertNil(TaskMarker.toggled(text, bodyLine: 1))
        XCTAssertNil(TaskMarker.toggled(text, bodyLine: 9))
    }

    func testToggleReachesNestedAndQuotedItems() {
        XCTAssertEqual(TaskMarker.toggled("- a\n  1. [ ] b", bodyLine: 2), "- a\n  1. [x] b")
        XCTAssertEqual(TaskMarker.toggled("> - [X] q", bodyLine: 1), "> - [ ] q")
    }

    // MARK: List continuation

    private func pressReturn(_ text: String, at caret: Int? = nil) -> (String, Int)? {
        let ns = text as NSString
        guard let edit = ListContinuation.edit(in: ns, caret: caret ?? ns.length) else { return nil }
        return (ns.replacingCharacters(in: edit.range, with: edit.replacement), edit.caret)
    }

    func testReturnContinuesBulletsNumbersAndTasks() {
        XCTAssertEqual(pressReturn("- one")?.0, "- one\n- ")
        XCTAssertEqual(pressReturn("* one")?.0, "* one\n* ")
        XCTAssertEqual(pressReturn("9. nine")?.0, "9. nine\n10. ")
        XCTAssertEqual(pressReturn("1) one")?.0, "1) one\n2) ")
        XCTAssertEqual(pressReturn("- [x] done")?.0, "- [x] done\n- [ ] ")
        XCTAssertEqual(pressReturn("  - nested")?.0, "  - nested\n  - ")
        XCTAssertEqual(pressReturn("> - quoted")?.0, "> - quoted\n> - ")
        XCTAssertEqual(pressReturn("- 中文条目")?.1, ("- 中文条目\n- " as NSString).length)
    }

    func testReturnOnAnEmptyItemEndsTheList() {
        XCTAssertEqual(pressReturn("- one\n- ")?.0, "- one\n")
        XCTAssertEqual(pressReturn("- one\n- ")?.1, 6)
        XCTAssertEqual(pressReturn("- [ ] ")?.0, "")
        XCTAssertEqual(pressReturn("- [ ]")?.0, "")
        XCTAssertEqual(pressReturn("2. ")?.0, "")
    }

    func testReturnElsewhereIsAPlainNewline() {
        XCTAssertNil(pressReturn("plain text"))
        XCTAssertNil(pressReturn("- one", at: 3))
        XCTAssertNil(pressReturn("-not a list"))
        XCTAssertNil(pressReturn("**bold** line"))
        XCTAssertNil(pressReturn("---"))
        XCTAssertNil(pressReturn("- one\nplain"))
    }

    func testReturnOnAMiddleLineContinuesThatLine() {
        let text = "- one\n- two\nend"
        let caret = ("- one" as NSString).length
        XCTAssertEqual(pressReturn(text, at: caret)?.0, "- one\n- \n- two\nend")
    }

    func testReturnWorksOnCRLFNotes() {
        XCTAssertEqual(pressReturn("- one\r\n- two", at: 5)?.0, "- one\r\n- \r\n- two")
        XCTAssertEqual(pressReturn("intro\r\n- last")?.0, "intro\r\n- last\r\n- ")
    }

    /// U+2028 and U+2029 do not end a line for cmark, so `- ` after one is
    /// text inside the line, not an empty item to delete.
    func testReturnTreatsUnicodeSeparatorsAsTextInTheLine() {
        for separator in ["\u{2028}", "\u{2029}"] {
            XCTAssertNil(pressReturn("pasted\(separator)- "), separator.debugDescription)
            XCTAssertNil(pressReturn("pasted\(separator)- [ ] "), separator.debugDescription)
            XCTAssertEqual(pressReturn("- a\(separator)b")?.0, "- a\(separator)b\n- ", separator.debugDescription)
            XCTAssertEqual(pressReturn("- a\(separator)")?.0, "- a\(separator)\n- ", separator.debugDescription)
        }
    }

    func testAThematicBreakIsNotAListItem() {
        XCTAssertNil(pressReturn("* * *"))
        XCTAssertNil(pressReturn("- - -"))
        XCTAssertNil(pressReturn("  * * * *"))
        XCTAssertEqual(pressReturn("- - nested dash")?.0, "- - nested dash\n- ")
    }

    /// The Mac editor continued `> ` quote lines and the iPhone did not;
    /// both run this rule now, so a quote continues at its depth and an
    /// empty quote line ends it, as an empty item ends its list.
    func testReturnContinuesQuotesAtTheirDepth() {
        XCTAssertEqual(pressReturn("> quoted")?.0, "> quoted\n> ")
        XCTAssertEqual(pressReturn("> quoted")?.1, ("> quoted\n> " as NSString).length)
        XCTAssertEqual(pressReturn("> > deeper")?.0, "> > deeper\n> > ")
        XCTAssertEqual(pressReturn("  > indented")?.0, "  > indented\n  > ")
        XCTAssertEqual(pressReturn(">  two spaces")?.0, ">  two spaces\n>  ")
        XCTAssertEqual(pressReturn("> > - quoted item")?.0, "> > - quoted item\n> > - ")
        XCTAssertEqual(pressReturn("> 1) quoted")?.0, "> 1) quoted\n> 2) ")
        XCTAssertEqual(pressReturn("> a\r\nend", at: 3)?.0, "> a\r\n> \r\nend")
    }

    func testReturnOnAnEmptyQuoteLineEndsTheQuote() {
        XCTAssertEqual(pressReturn("> a\n> ")?.0, "> a\n")
        XCTAssertEqual(pressReturn("> a\n> ")?.1, 4)
        XCTAssertEqual(pressReturn("> > ")?.0, "")
        XCTAssertEqual(pressReturn("> a\n>  \nend", at: 7)?.0, "> a\n\nend")
        XCTAssertNil(pressReturn(">"))
        XCTAssertNil(pressReturn(">no space"))
    }

    /// `- name:` in a YAML block is code: the Mac editor wrote a `- ` after
    /// it, the iPhone checked fences itself; the rule skips fences now.
    func testReturnInsideAFencedCodeBlockIsAPlainNewline() {
        let yaml = "```yaml\n- name: a\n> not a quote\n1) step\n```\n- after"
        let ns = yaml as NSString
        for line in ["- name: a", "> not a quote", "1) step"] {
            let caret = NSMaxRange(ns.range(of: line))
            XCTAssertNil(pressReturn(yaml, at: caret), line)
            XCTAssertTrue(ListContinuation.isInFencedCode(at: caret, in: ns), line)
        }
        XCTAssertEqual(pressReturn(yaml)?.0, yaml + "\n- ")
        XCTAssertFalse(ListContinuation.isInFencedCode(at: ns.length, in: ns))
        XCTAssertNil(pressReturn("intro\r\n```\r\n- a\r\n```\r\n", at: 15))
        XCTAssertNotNil(pressReturn("intro\r\n```\r\n- a\r\n", at: 15))
        XCTAssertNil(pressReturn("```\n- a\n```  \n", at: 7))
        // A fence never closed is drawn as text and stays a list.
        XCTAssertEqual(pressReturn("```\n- a")?.0, "```\n- a\n- ")
        XCTAssertEqual(pressReturn("```\nx\n```\n- a")?.0, "```\nx\n```\n- a\n- ")
        // An indented fence is no fence for the editors' highlighting.
        XCTAssertEqual(pressReturn("  ```\n- a\n  ```", at: 9)?.0, "  ```\n- a\n- \n  ```")
    }

    func testLineBreakFollowsTheNote() {
        XCTAssertEqual(ListContinuation.lineBreak(in: "a\nb"), "\n")
        XCTAssertEqual(ListContinuation.lineBreak(in: "a\r\nb"), "\r\n")
        XCTAssertEqual(ListContinuation.lineBreak(in: ""), "\n")
    }

    // MARK: Line edits

    private func apply(_ edit: LineEdits.Edit?, to text: String) -> (String, NSRange)? {
        guard let edit else { return nil }
        return ((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), edit.selection)
    }

    func testIndentAndOutdentCoverEveryLineOfTheSelection() {
        let text = "- a\n- b\n\n- c"
        let all = NSRange(location: 0, length: (text as NSString).length)
        let indented = apply(LineEdits.indent(in: text as NSString, selection: all), to: text)
        XCTAssertEqual(indented?.0, "  - a\n  - b\n\n  - c")
        XCTAssertEqual(indented?.1, NSRange(location: 0, length: 18))
        let back = apply(LineEdits.outdent(in: indented!.0 as NSString, selection: indented!.1), to: indented!.0)
        XCTAssertEqual(back?.0, text)
        XCTAssertNil(LineEdits.outdent(in: text as NSString, selection: all))
        XCTAssertEqual(apply(LineEdits.outdent(in: "\tx" as NSString, selection: NSRange(location: 1, length: 0)), to: "\tx")?.0, "x")
        XCTAssertEqual(apply(LineEdits.outdent(in: " x" as NSString, selection: NSRange(location: 1, length: 0)), to: " x")?.0, "x")
    }

    /// Indent then outdent on the last line, or on `selection` when given.
    private func indentRoundTrip(_ text: String, selection: NSRange? = nil) -> (String?, String?) {
        let ns = text as NSString
        let range = selection ?? NSRange(location: ns.length, length: 0)
        guard let indented = apply(LineEdits.indent(in: ns, selection: range), to: text) else { return (nil, nil) }
        let back = apply(LineEdits.outdent(in: indented.0 as NSString, selection: indented.1), to: indented.0)
        return (indented.0, back?.0)
    }

    func testIndentUnderAnOrderedItemNestsAtItsContentColumn() {
        XCTAssertEqual(indentRoundTrip("1. a\n- b").0, "1. a\n   - b")
        XCTAssertEqual(indentRoundTrip("1. a\n- b").1, "1. a\n- b")
        XCTAssertEqual(indentRoundTrip("10. a\n- b").0, "10. a\n    - b")
        XCTAssertEqual(indentRoundTrip("10. a\n- b").1, "10. a\n- b")
        XCTAssertEqual(indentRoundTrip("1) a\n- b").0, "1) a\n   - b")
        XCTAssertEqual(indentRoundTrip("1.  a\n- b").0, "1.  a\n    - b")
        // An ordered item that is itself nested.
        XCTAssertEqual(indentRoundTrip("- x\n  1. a\n  - b").0, "- x\n  1. a\n     - b")
        XCTAssertEqual(indentRoundTrip("- x\n  1. a\n  - b").1, "- x\n  1. a\n  - b")
        // Every selected line moves by the same amount.
        let text = "1. a\n- b\n- c"
        let lines = NSRange(location: 5, length: 7)
        XCTAssertEqual(indentRoundTrip(text, selection: lines).0, "1. a\n   - b\n   - c")
        XCTAssertEqual(indentRoundTrip(text, selection: lines).1, text)
    }

    func testIndentOutsideOrderedItemsStaysTwoSpaces() {
        XCTAssertEqual(indentRoundTrip("- a\n- b").0, "- a\n  - b")
        XCTAssertEqual(indentRoundTrip("- a\n- b").1, "- a\n- b")
        XCTAssertEqual(indentRoundTrip("plain\n- b").0, "plain\n  - b")
        XCTAssertEqual(indentRoundTrip("1.5 kg\n- b").0, "1.5 kg\n  - b")
        // Already at or past the item's content: plain two spaces.
        XCTAssertEqual(indentRoundTrip("1. a\n   - b").0, "1. a\n     - b")
        XCTAssertEqual(indentRoundTrip("1. a\n   - b").1, "1. a\n   - b")
    }

    func testACaretKeepsItsPlaceInTheLine() {
        let text = "one\n- two\nthree"
        let caret = NSRange(location: 7, length: 0)  // "- t|wo"
        let edit = apply(LineEdits.indent(in: text as NSString, selection: caret), to: text)
        XCTAssertEqual(edit?.0, "one\n  - two\nthree")
        XCTAssertEqual(edit?.1, NSRange(location: 9, length: 0))
    }

    func testToggleTaskTicksClearsAndCreates() {
        func toggle(_ text: String) -> String? {
            apply(LineEdits.toggleTask(in: text as NSString, selection: NSRange(location: 0, length: 0)), to: text)?.0
        }
        XCTAssertEqual(toggle("- [ ] a"), "- [x] a")
        XCTAssertEqual(toggle("  - [x] a"), "  - [ ] a")
        XCTAssertEqual(toggle("- a"), "- [ ] a")
        XCTAssertEqual(toggle("2. a"), "2. [ ] a")
        XCTAssertEqual(toggle("plain"), "- [ ] plain")
        XCTAssertEqual(toggle("  plain"), "  - [ ] plain")
        XCTAssertNil(toggle(""))
        XCTAssertEqual(toggle("- [ ] a\r\nnext"), "- [x] a\r\nnext")
    }

    func testToggleTaskKeepsTheQuote() {
        func toggle(_ text: String) -> String? {
            apply(LineEdits.toggleTask(in: text as NSString, selection: NSRange(location: 0, length: 0)), to: text)?.0
        }
        XCTAssertEqual(toggle("> quote"), "> - [ ] quote")
        XCTAssertEqual(toggle("> - [ ] quote"), "> - [x] quote")
        XCTAssertEqual(toggle("> - [x] a"), "> - [ ] a")
        XCTAssertEqual(toggle("> > quote"), "> > - [ ] quote")
        XCTAssertEqual(toggle(">quote"), ">- [ ] quote")
        XCTAssertEqual(toggle("  > quote"), "  > - [ ] quote")
        XCTAssertEqual(toggle("> - a"), "> - [ ] a")
        XCTAssertEqual(toggle("> 1. a"), "> 1. [ ] a")
    }

    // MARK: Insert panel

    /// The text and selection after `edit`, with the caret written as `|`
    /// and a selection as `[...]`.
    private func shown(_ edit: LineEdits.Edit?, on text: String) -> String? {
        guard let edit else { return nil }
        let new = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement) as NSString
        let end = NSMaxRange(edit.selection)
        if edit.selection.length == 0 { return new.replacingCharacters(in: edit.selection, with: "|") }
        return new.substring(to: edit.selection.location) + "[" + new.substring(with: edit.selection) + "]" + new.substring(from: end)
    }

    /// `kind` toggled at the `|` in `marked`, or over the `[...]` selection.
    private func toggled(_ kind: LineEdits.LineKind, _ marked: String) -> String? {
        let (text, selection) = unmark(marked)
        return shown(LineEdits.toggle(kind, in: text as NSString, selection: selection), on: text)
    }

    private func unmark(_ marked: String) -> (String, NSRange) {
        let ns = marked as NSString
        let open = ns.range(of: "[")
        let caret = ns.range(of: "|")
        if caret.location != NSNotFound {
            return (ns.replacingCharacters(in: caret, with: ""), NSRange(location: caret.location, length: 0))
        }
        let close = ns.range(of: "]", options: .backwards)
        let inner = ns.substring(with: NSRange(location: open.location + 1, length: close.location - open.location - 1))
        let text = ns.substring(to: open.location) + inner + ns.substring(from: close.location + 1)
        return (text, NSRange(location: open.location, length: (inner as NSString).length))
    }

    func testAHeadingTakesTheLineSwapsALevelAndComesOffOnTheSameLevel() {
        XCTAssertEqual(toggled(.heading(2), "|"), "## |")
        XCTAssertEqual(toggled(.heading(2), "abc|"), "## abc|")
        XCTAssertEqual(toggled(.heading(2), "a|bc"), "## a|bc")
        XCTAssertEqual(toggled(.heading(2), "# abc|"), "## abc|")
        XCTAssertEqual(toggled(.heading(2), "## abc|"), "abc|")
        XCTAssertEqual(toggled(.heading(1), "- [ ] abc|"), "# abc|")
        XCTAssertEqual(toggled(.heading(3), "> abc|"), "> ### abc|")
        XCTAssertEqual(toggled(.heading(1), "x\n|\ny"), "x\n# |\ny")
    }

    func testAListTakesTheLineSwitchesKindAndComesOffOnTheSameKind() {
        XCTAssertEqual(toggled(.bullet, "abc|"), "- abc|")
        XCTAssertEqual(toggled(.bullet, "- abc|"), "abc|")
        XCTAssertEqual(toggled(.bullet, "1. abc|"), "- abc|")
        XCTAssertEqual(toggled(.bullet, "- [x] abc|"), "- abc|")
        XCTAssertEqual(toggled(.bullet, "## abc|"), "- abc|")
        XCTAssertEqual(toggled(.bullet, "  abc|"), "  - abc|")
        XCTAssertEqual(toggled(.task, "abc|"), "- [ ] abc|")
        XCTAssertEqual(toggled(.task, "- [x] abc|"), "abc|")
        XCTAssertEqual(toggled(.task, "* abc|"), "- [ ] abc|")
        XCTAssertEqual(toggled(.numbered, "|"), "1. |")
        XCTAssertEqual(toggled(.numbered, "- abc|"), "1. abc|")
        XCTAssertEqual(toggled(.numbered, "3) abc|"), "abc|")
    }

    func testSeveralLinesFollowTheFirstWithWordsAndSkipEmptyOnes() {
        XCTAssertEqual(toggled(.numbered, "[a\n\nb\nc]"), "[1. a\n\n2. b\n3. c]")
        XCTAssertEqual(toggled(.bullet, "[- a\nb]"), "[a\nb]")
        XCTAssertEqual(toggled(.bullet, "[\n- a\nb]"), "[\na\nb]")
        XCTAssertEqual(toggled(.quote, "[a\n\nb]"), "[> a\n\n> b]")
    }

    func testAQuoteStaysInFrontOfTheLinesKind() {
        XCTAssertEqual(toggled(.quote, "abc|"), "> abc|")
        XCTAssertEqual(toggled(.quote, "> abc|"), "abc|")
        XCTAssertEqual(toggled(.quote, ">abc|"), "abc|")
        XCTAssertEqual(toggled(.quote, "- abc|"), "> - abc|")
        XCTAssertEqual(toggled(.bullet, "> - abc|"), "> abc|")
        XCTAssertEqual(toggled(.task, "> abc|"), "> - [ ] abc|")
    }

    func testLineKindsKeepAWindowsLineEnding() {
        XCTAssertEqual(toggled(.bullet, "a\r\nb|\r\nc"), "a\r\n- b|\r\nc")
    }

    func testADividerStandsOnItsOwnLineApartFromTheWordsAboveIt() {
        let divide: (String) -> String? = { marked in
            let (text, selection) = self.unmark(marked)
            return self.shown(BlockInsert.divider(in: text as NSString, selection: selection), on: text)
        }
        XCTAssertEqual(divide("|"), "---\n|")
        // Right under a line of words, `---` would make that line a heading.
        XCTAssertEqual(divide("abc|"), "abc\n\n---\n|")
        XCTAssertEqual(divide("a|bc\ndef"), "abc\n\n---\n|\ndef")
        XCTAssertEqual(divide("abc\n|\ndef"), "abc\n\n---\n|\ndef")
        XCTAssertEqual(divide("abc\n\n|"), "abc\n\n---\n|")
    }

    func testACodeBlockOpensOnAnEmptyLineOrWrapsTheSelectedLines() {
        let code: (String) -> String? = { marked in
            let (text, selection) = self.unmark(marked)
            return self.shown(BlockInsert.codeBlock(in: text as NSString, selection: selection), on: text)
        }
        XCTAssertEqual(code("|"), "```\n|\n```")
        XCTAssertEqual(code("abc|\ndef"), "abc\n\n```\n|\n```\n\ndef")
        XCTAssertEqual(code("x\n[a\nb]\ny"), "x\n\n```|\na\nb\n```\n\ny")
        XCTAssertEqual(code("abc\r\n|"), "abc\r\n\r\n```\r\n|\r\n```")
    }

    func testATableIsTheTemplateWithItsFirstHeaderSelected() {
        let (text, selection) = unmark("Notes|")
        let result = shown(BlockInsert.table(headers: ["A", "B"], in: text as NSString, selection: selection), on: text)
        XCTAssertEqual(result, "Notes\n\n| [A]   | B   |\n| --- | --- |\n|     |     |\n|     |     |")
        let template = TableEditing.template(headers: ["Column 1", "Column 2"])
        XCTAssertEqual((template.text as NSString).substring(with: template.selection), "Column 1")
    }
}
