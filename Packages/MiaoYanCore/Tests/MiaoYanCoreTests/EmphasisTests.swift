import XCTest

@testable import MiaoYanCore

final class EmphasisTests: XCTestCase {
    func testChineseEmphasisTakesItsLanguage() {
        XCTAssertEqual(
            Emphasis.markCJK(in: "<p>有一段 <em>需要强调的中文</em>，和 <em>English</em></p>"),
            "<p>有一段 <em lang=\"zh\">需要强调的中文</em>，和 <em>English</em></p>")
    }

    func testEmphasisHoldingOtherTagsIsStillMarked() {
        let html = "<em>看 <code>Note</code> 和 <a href=\"x\">链接</a></em>"
        XCTAssertEqual(
            Emphasis.markCJK(in: html), "<em lang=\"zh\">看 <code>Note</code> 和 <a href=\"x\">链接</a></em>")
    }

    func testKanaAndHangulPickTheirLanguage() {
        XCTAssertEqual(Emphasis.markCJK(in: "<em>大切なこと</em>"), "<em lang=\"ja\">大切なこと</em>")
        XCTAssertEqual(Emphasis.markCJK(in: "<em>중요한 말</em>"), "<em lang=\"ko\">중요한 말</em>")
    }

    func testLatinOnlyHtmlIsUntouched() {
        let html = "<p><em>emphasis</em> and <strong>strong</strong></p>"
        XCTAssertEqual(Emphasis.markCJK(in: html), html)
        XCTAssertEqual(Emphasis.markCJK(in: "<p>没有强调</p>"), "<p>没有强调</p>")
    }

    /// Han alone follows the document's language, so emphasised kanji in a
    /// Japanese page are not set in Chinese forms; kana and Hangul still
    /// name their own language.
    func testHanAloneTakesTheDocumentLanguage() {
        XCTAssertEqual(Emphasis.markCJK(in: "<em>漢字</em>", hanLanguage: "ja"), "<em lang=\"ja\">漢字</em>")
        XCTAssertEqual(Emphasis.markCJK(in: "<em>重要</em>", hanLanguage: "zh-Hant"), "<em lang=\"zh-Hant\">重要</em>")
        XCTAssertEqual(Emphasis.markCJK(in: "<em>대切한</em>", hanLanguage: "ja"), "<em lang=\"ko\">대切한</em>")
        XCTAssertEqual(Emphasis.markCJK(in: "<em>English</em>", hanLanguage: "ja"), "<em>English</em>")
    }
}
