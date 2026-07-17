import XCTest

@testable import MiaoYan

final class GitHubAlertsTests: XCTestCase {

    // MARK: - Full render pipeline

    func testRenderConvertsNoteAlert() {
        let markdown = "> [!NOTE]\n> Useful information."
        let html = renderMarkdownHTML(markdown: markdown, useGithubLineBreak: false)!

        XCTAssertTrue(html.contains("markdown-alert markdown-alert-note"))
        XCTAssertTrue(html.contains("markdown-alert-title"))
        XCTAssertTrue(html.contains(">Note</p>"))
        XCTAssertTrue(html.contains("Useful information."))
        XCTAssertFalse(html.contains("[!NOTE]"))
        XCTAssertFalse(html.contains("<blockquote"))
    }

    func testRenderConvertsAlertWithGithubLineBreak() {
        let markdown = "> [!WARNING]\n> Careful here."
        let html = renderMarkdownHTML(markdown: markdown, useGithubLineBreak: true)!

        XCTAssertTrue(html.contains("markdown-alert-warning"))
        XCTAssertTrue(html.contains("Careful here."))
        XCTAssertFalse(html.contains("[!WARNING]"))
    }

    func testRenderAllFiveKinds() {
        for (marker, className) in [
            ("NOTE", "note"), ("TIP", "tip"), ("IMPORTANT", "important"),
            ("WARNING", "warning"), ("CAUTION", "caution"),
        ] {
            let html = renderMarkdownHTML(markdown: "> [!\(marker)]\n> body", useGithubLineBreak: false)!
            XCTAssertTrue(html.contains("markdown-alert-\(className)"), "missing class for \(marker)")
        }
    }

    // MARK: - Transform edge cases

    func testMarkerOnlyBlockquote() {
        let html = renderMarkdownHTML(markdown: "> [!TIP]", useGithubLineBreak: false)!

        XCTAssertTrue(html.contains("markdown-alert-tip"))
        XCTAssertFalse(html.contains("[!TIP]"))
        XCTAssertFalse(html.contains("<p></p>"))
    }

    func testMarkerIsCaseInsensitive() {
        let html = renderMarkdownHTML(markdown: "> [!note]\n> lower", useGithubLineBreak: false)!
        XCTAssertTrue(html.contains("markdown-alert-note"))
    }

    func testUnknownMarkerStaysBlockquote() {
        let html = renderMarkdownHTML(markdown: "> [!DANGER]\n> not a github kind", useGithubLineBreak: false)!

        XCTAssertTrue(html.contains("<blockquote"))
        XCTAssertFalse(html.contains("markdown-alert"))
    }

    func testMarkerGluedToTextStaysBlockquote() {
        let html = transformGitHubAlerts(in: "<blockquote>\n<p>[!NOTE]: glued</p>\n</blockquote>")

        XCTAssertTrue(html.contains("<blockquote"))
        XCTAssertFalse(html.contains("markdown-alert"))
    }

    func testPlainBlockquoteUntouched() {
        let input = "<blockquote>\n<p>ordinary quote</p>\n</blockquote>"
        XCTAssertEqual(transformGitHubAlerts(in: input), input)
    }

    func testMarkerInsideCodeBlockUntouched() {
        let html = renderMarkdownHTML(markdown: "```\n> [!NOTE]\n```", useGithubLineBreak: false)!

        XCTAssertTrue(html.contains("[!NOTE]"))
        XCTAssertFalse(html.contains("markdown-alert"))
    }

    func testNestedBlockquoteInsideAlertKeepsBalance() {
        let markdown = "> [!NOTE]\n> outer\n> > inner quote"
        let html = renderMarkdownHTML(markdown: markdown, useGithubLineBreak: false)!

        XCTAssertTrue(html.contains("markdown-alert-note"))
        XCTAssertTrue(html.contains("inner quote"))
        // Inner plain blockquote survives, and tags stay balanced.
        XCTAssertEqual(html.components(separatedBy: "<blockquote").count - 1, 1)
        XCTAssertEqual(html.components(separatedBy: "</blockquote>").count - 1, 1)
        XCTAssertEqual(html.components(separatedBy: "</div>").count - 1, 1)
    }

    func testTwoSiblingAlerts() {
        let markdown = "> [!NOTE]\n> first\n\n> [!CAUTION]\n> second"
        let html = renderMarkdownHTML(markdown: markdown, useGithubLineBreak: false)!

        XCTAssertTrue(html.contains("markdown-alert-note"))
        XCTAssertTrue(html.contains("markdown-alert-caution"))
        XCTAssertFalse(html.contains("<blockquote"))
    }

    func testMultiParagraphAlertBody() {
        let markdown = "> [!IMPORTANT]\n> first paragraph\n>\n> second paragraph"
        let html = renderMarkdownHTML(markdown: markdown, useGithubLineBreak: false)!

        XCTAssertTrue(html.contains("markdown-alert-important"))
        XCTAssertTrue(html.contains("first paragraph"))
        XCTAssertTrue(html.contains("second paragraph"))
        XCTAssertFalse(html.contains("<blockquote"))
    }

    func testSourcePosAttributePreserved() {
        let markdown = "> [!NOTE]\n> body"
        let html = renderMarkdownHTML(markdown: markdown, useGithubLineBreak: false)!

        // cmark renders with SOURCEPOS; the wrapper div keeps the blockquote's attrs.
        XCTAssertTrue(html.contains("<div class=\"markdown-alert markdown-alert-note\" data-sourcepos="))
    }
}
