import XCTest

@testable import MiaoYan

final class TypographyCleanerTests: XCTestCase {

    // MARK: - Pangu spacing

    func testInsertsSpaceBetweenCJKAndLatin() {
        XCTAssertEqual(TypographyCleaner.clean("使用Swift开发"), "使用 Swift 开发")
    }

    func testInsertsSpaceBetweenCJKAndDigits() {
        XCTAssertEqual(TypographyCleaner.clean("第3章共10节"), "第 3 章共 10 节")
    }

    func testExistingSpacingUntouched() {
        XCTAssertEqual(TypographyCleaner.clean("使用 Swift 开发"), "使用 Swift 开发")
    }

    func testPureEnglishUntouched() {
        let text = "Plain English sentence, nothing to do."
        XCTAssertEqual(TypographyCleaner.clean(text), text)
    }

    // MARK: - Punctuation width

    func testHalfwidthCommaAfterCJKBecomesFullwidth() {
        XCTAssertEqual(TypographyCleaner.clean("你好,世界"), "你好\u{FF0C}世界")
    }

    func testHalfwidthPeriodAtClauseEndBecomesFullwidth() {
        XCTAssertEqual(TypographyCleaner.clean("结束了. 下一句"), "结束了。下一句")
    }

    func testVersionNumberDotUntouched() {
        XCTAssertEqual(TypographyCleaner.clean("版本 3.5 发布"), "版本 3.5 发布")
    }

    func testTimeColonUntouched() {
        XCTAssertEqual(TypographyCleaner.clean("时间 10:00 开始"), "时间 10:00 开始")
    }

    func testColonAfterCJKBecomesFullwidth() {
        XCTAssertEqual(TypographyCleaner.clean("注意:这是重点"), "注意\u{FF1A}这是重点")
    }

    func testFullwidthAlphanumericsBecomeHalfwidth() {
        XCTAssertEqual(TypographyCleaner.clean("\u{FF21}\u{FF22}\u{FF23}\u{FF11}\u{FF12}\u{FF13}"), "ABC123")
    }

    func testImageSyntaxBangUntouched() {
        XCTAssertEqual(TypographyCleaner.clean("如图![](i/a.png)"), "如图![](i/a.png)")
    }

    // MARK: - Em dash and ellipsis

    func testSingleEmDashBetweenCJKBecomesComma() {
        XCTAssertEqual(TypographyCleaner.clean("这个功能—很有用"), "这个功能\u{FF0C}很有用")
    }

    func testSingleEmDashWithSpacesBetweenCJKBecomesComma() {
        XCTAssertEqual(TypographyCleaner.clean("这个功能 — 很有用"), "这个功能\u{FF0C}很有用")
    }

    func testDoubleEmDashKept() {
        XCTAssertEqual(TypographyCleaner.clean("真正的破折号——保留"), "真正的破折号——保留")
    }

    func testEmDashInEnglishKept() {
        let text = "an em dash — in English stays"
        XCTAssertEqual(TypographyCleaner.clean(text), text)
    }

    func testAsciiEllipsisAfterCJKBecomesChinese() {
        XCTAssertEqual(TypographyCleaner.clean("等等..."), "等等……")
    }

    // MARK: - Fullwidth punctuation spacing

    func testSpacesAroundFullwidthPunctuationRemoved() {
        XCTAssertEqual(TypographyCleaner.clean("你好, 世界 。好"), "你好\u{FF0C}世界。好")
    }

    // MARK: - Protected regions

    func testFencedCodeBlockUntouched() {
        let text = "前面3行\n```\nlet a=中文123\n```\n后面3行"
        XCTAssertEqual(TypographyCleaner.clean(text), "前面 3 行\n```\nlet a=中文123\n```\n后面 3 行")
    }

    func testInlineCodeContentUntouchedButSpacedAtBoundary() {
        XCTAssertEqual(TypographyCleaner.clean("使用`git status`命令"), "使用 `git status` 命令")
    }

    func testLinkTargetUntouched() {
        XCTAssertEqual(TypographyCleaner.clean("看[文档3](path/图3.png)吧"), "看[文档 3](path/图3.png)吧")
    }

    func testWikilinkUntouched() {
        XCTAssertEqual(TypographyCleaner.clean("参考[[笔记A1]]内容"), "参考[[笔记A1]]内容")
    }

    func testBareURLUntouched() {
        let text = "访问 https://example.com/中文path?q=1 查看"
        XCTAssertEqual(TypographyCleaner.clean(text), text)
    }

    func testInlineMathUntouched() {
        XCTAssertEqual(TypographyCleaner.clean("公式$a_1+b$成立"), "公式$a_1+b$成立")
    }

    func testDollarAmountsNotTreatedAsMath() {
        // "$100和$200" must not become a protected math span; the CJK inside
        // rejects the pairing and the text still gets pangu spacing.
        XCTAssertEqual(TypographyCleaner.clean("我有$100和$200的钱"), "我有$100 和$200 的钱")
    }

    func testMathMustNotStealInlineCodeBacktick() {
        let text = "单价$5 `inline $x$ 中文,好` 结束"
        XCTAssertEqual(TypographyCleaner.clean(text), text)
    }

    func testIndentedCodeBlockUntouched() {
        let text = "段落\n\n    print(\"中文,好\")\n\n结束"
        XCTAssertEqual(TypographyCleaner.clean(text), text)
    }

    func testFenceInsideBlockquoteProtected() {
        let text = "> ```\n> let a = 中文,好\n> ```"
        XCTAssertEqual(TypographyCleaner.clean(text), text)
    }

    func testCRLFDocumentStillCleaned() {
        let text = "---\r\ntitle: x\r\n---\r\n正文,好abc"
        XCTAssertEqual(TypographyCleaner.clean(text), "---\r\ntitle: x\r\n---\r\n正文\u{FF0C}好 abc")
    }

    func testHardLineBreakPreserved() {
        XCTAssertEqual(TypographyCleaner.clean("第一行,  \n第二行"), "第一行\u{FF0C}  \n第二行")
    }

    func testURLFollowedByCommaThenTextStillCleaned() {
        // The halfwidth comma glued to CJK ends the URL; text after it is cleaned.
        XCTAssertEqual(
            TypographyCleaner.clean("详见https://a.com,这段中文abc继续"),
            "详见https://a.com,这段中文 abc 继续")
    }

    func testPunctuationAfterInlineCodeConverted() {
        XCTAssertEqual(TypographyCleaner.clean("执行`git status`,然后继续"), "执行 `git status`\u{FF0C}然后继续")
    }

    func testFrontmatterUntouched() {
        let text = "---\ntitle: 标题123\n---\n正文123"
        XCTAssertEqual(TypographyCleaner.clean(text), "---\ntitle: 标题123\n---\n正文 123")
    }

    // MARK: - Blank lines

    func testBlankLineRunsCollapse() {
        XCTAssertEqual(TypographyCleaner.clean("一\n\n\n\n二"), "一\n\n二")
    }

    func testBlankLinesInsideFenceKept() {
        let text = "```\na\n\n\n\nb\n```"
        XCTAssertEqual(TypographyCleaner.clean(text), text)
    }

    func testTrailingNewlinePreserved() {
        XCTAssertEqual(TypographyCleaner.clean("正文abc\n"), "正文 abc\n")
    }

    // MARK: - Reference definitions

    func testReferenceLinkDefinitionUntouched() {
        let input = "[ref]: ./说明doc.md"
        XCTAssertEqual(TypographyCleaner.clean(input), input)
    }

    func testReferenceDefinitionCommaTargetUntouched() {
        let input = "[ref]: /a/中,文.md"
        XCTAssertEqual(TypographyCleaner.clean(input), input)
    }

    func testFootnoteDefinitionUntouched() {
        let input = "[^1]: 脚注target1说明"
        XCTAssertEqual(TypographyCleaner.clean(input), input)
    }

    func testReferenceUsageInProseStillCleaned() {
        XCTAssertEqual(TypographyCleaner.clean("见[说明][ref]和正文abc"), "见[说明][ref]和正文 abc")
    }

    // MARK: - Display math

    func testBlockMathUntouched() {
        let input = "$$\n\\text{中,文}\u{2014}x\n$$"
        XCTAssertEqual(TypographyCleaner.clean(input), input)
    }

    func testBlockMathClosingOnContentLine() {
        let input = "$$\na + b = c$$"
        XCTAssertEqual(TypographyCleaner.clean(input), input)
    }

    func testTextAfterBlockMathStillCleaned() {
        let input = "$$\nx=1\n$$\n正文abc"
        XCTAssertEqual(TypographyCleaner.clean(input), "$$\nx=1\n$$\n正文 abc")
    }

    func testSingleLineDollarDollarStillInlineProtected() {
        XCTAssertEqual(TypographyCleaner.clean("$$x,y$$后面正文abc"), "$$x,y$$后面正文 abc")
    }

    // MARK: - Idempotency

    func testCleaningTwiceIsStable() {
        let messy = "用AI写的文档,标点—很乱...使用`code`时看https://a.b/c第2次"
        let once = TypographyCleaner.clean(messy)
        XCTAssertEqual(TypographyCleaner.clean(once), once)
    }
}
