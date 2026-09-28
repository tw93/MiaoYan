import XCTest

import MiaoYanCore

final class FrontmatterTests: XCTestCase {
    private func body(_ text: String) -> String { String(Frontmatter.body(of: text)) }

    func testStripsFrontmatterWithOrWithoutTitleKey() {
        XCTAssertEqual(body("---\ntitle: Hello\ndate: 2026-07-13\n---\nBody text"), "Body text")
        XCTAssertEqual(body("---\ntags: [ai, notes]\ndraft: true\n---\nBody text"), "Body text")
    }

    func testKeepsTextThatDoesNotOpenWithAFence() {
        let text = "# Heading\n\n---\n\nafter a rule"
        XCTAssertEqual(body(text), text)
    }

    func testKeepsTextWhenTheFenceNeverClosesOnItsOwnLine() {
        XCTAssertEqual(body("---\nkey: value\nno closing fence"), "---\nkey: value\nno closing fence")
        XCTAssertEqual(body("---\nkey: value\n----\nstill inside"), "---\nkey: value\n----\nstill inside")
    }

    func testFrontmatterOnlyDocumentBecomesEmpty() {
        XCTAssertEqual(body("---\nkey: value\n---"), "")
    }

    func testCRLFDocuments() {
        XCTAssertEqual(body("---\r\nkey: value\r\n---\r\nBody"), "Body")
    }
}
