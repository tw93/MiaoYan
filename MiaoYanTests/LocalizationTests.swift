import XCTest

@testable import MiaoYan

final class LocalizationTests: XCTestCase {

    @MainActor
    private func withLanguage<T>(_ code: String, _ body: () throws -> T) throws -> T {
        let bundle = try XCTUnwrap(Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)))
        I18n.overrideBundle = bundle
        defer { I18n.overrideBundle = nil }
        return try body()
    }

    /// English and Spanish used to show "1 note(s)"; their stringsdict
    /// picks the singular or the plural.
    @MainActor
    func testCountedStringsTakeSingularAndPlural() throws {
        let key = "Move %d note(s) to the system Trash?"
        try withLanguage("en") {
            XCTAssertEqual(I18n.count(key, 1), "Move 1 note to the system Trash?")
            XCTAssertEqual(I18n.count(key, 3), "Move 3 notes to the system Trash?")
            XCTAssertEqual(I18n.count("Moved %d unused attachment(s) to Trash", 1), "Moved 1 unused attachment to the Trash")
        }
        try withLanguage("es") {
            XCTAssertEqual(I18n.count(key, 1), "¿Mover 1 nota a la Papelera del sistema?")
            XCTAssertEqual(I18n.count(key, 2), "¿Mover 2 notas a la Papelera del sistema?")
        }
        try withLanguage("zh-Hans") {
            XCTAssertEqual(I18n.count(key, 3), "将 3 篇笔记移到系统废纸篓？")
        }
    }

    /// The info panel's labels joined with an ASCII colon in every language.
    @MainActor
    func testLabelsUseTheLanguagesColon() throws {
        try withLanguage("en") { XCTAssertEqual(I18n.labeled("Words", "5"), "Words: 5") }
        for code in ["zh-Hans", "zh-Hant", "ja"] {
            try withLanguage(code) {
                let label = I18n.labeled("Words", "5")
                XCTAssertTrue(label.hasSuffix("\u{FF1A}5"), "\(code): \(label)")
            }
        }
    }
}
