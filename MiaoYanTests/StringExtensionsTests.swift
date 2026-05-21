import XCTest

@testable import MiaoYan

final class StringExtensionsTests: XCTestCase {

    func testCondenseWhitespaceCollapsesMixedSeparators() {
        XCTAssertEqual("  foo\t\n bar   baz ".condenseWhitespace(), "foo bar baz")
    }

    func testTrimRemovesLeadingTrailingSpaces() {
        XCTAssertEqual("   hello   ".trim(), "hello")
    }

    func testRemoveLastNewLineOnlyDropsTrailingNewline() {
        XCTAssertEqual("abc\n".removeLastNewLine(), "abc")
        XCTAssertEqual("abc".removeLastNewLine(), "abc")
        XCTAssertEqual("abc\n\n".removeLastNewLine(), "abc\n")
    }

    func testIsNumberListMatchesOrderedListPrefix() {
        XCTAssertTrue("1. first".isNumberList())
        XCTAssertTrue("   42. spaced".isNumberList())
        XCTAssertFalse("- bullet".isNumberList())
        XCTAssertFalse("1.no-space".isNumberList())
    }

    func testIsValidUUID() {
        XCTAssertTrue("E621E1F8-C36C-495A-93FC-0C247A3E6E5F".isValidUUID)
        XCTAssertFalse("not-a-uuid".isValidUUID)
    }

    func testEscapePlusReplacesPlusWithEncodedSpace() {
        XCTAssertEqual("a+b+c".escapePlus(), "a%20b%20c")
    }

    func testGetPrefixMatchSequentiallyCollectsRepeatedChar() {
        XCTAssertEqual("###heading".getPrefixMatchSequentially(char: "#"), "###")
        XCTAssertNil("heading".getPrefixMatchSequentially(char: "#"))
    }

    func testLocalizedStandardContainsTermsArray() {
        XCTAssertTrue("Quick brown fox".localizedStandardContains(["brown", "missing"]))
        XCTAssertFalse("Quick brown fox".localizedStandardContains(["zebra", "lion"]))
    }
}
