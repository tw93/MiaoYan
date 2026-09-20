import AppKit
import XCTest

@testable import MiaoYan

final class FontCatalogTests: XCTestCase {
    func testTextListDropsFacesThatCannotRenderChinese() {
        let text = FontCatalog.families(for: .text)
        XCTAssertFalse(text.isEmpty)

        // These sit in the first screenful of the raw alphabetical list and are
        // the reason the popup read as noise: a braille face, an emoji face and
        // a Hebrew face cannot set a line of Chinese prose.
        for family in ["Apple Braille", "Apple Color Emoji", "Arial Hebrew"] {
            guard NSFontManager.shared.availableFontFamilies.contains(family) else { continue }
            XCTAssertFalse(text.contains(family), "\(family) should not be offered as a text font")
        }

        // Every family that survives must actually cover the probe.
        for family in text {
            let font = try? XCTUnwrap(NSFont(name: family, size: 12))
            guard let covered = font?.coveredCharacterSet else { continue }
            XCTAssertTrue(covered.contains("永"), "\(family) was kept but cannot draw 永")
        }
    }

    func testCodeListIsMonospacedOnly() {
        let code = FontCatalog.families(for: .code)
        XCTAssertFalse(code.isEmpty)
        XCTAssertLessThan(code.count, FontCatalog.families(for: .text).count)
        for family in code {
            XCTAssertTrue(NSFont(name: family, size: 12)?.isFixedPitch ?? false, "\(family) is not monospaced")
        }
    }

    func testStoredPostScriptNameResolvesToItsFamily() {
        // The shipped defaults are PostScript names while the popup lists family
        // names, so without this mapping the default matched no row and was
        // appended below the alphabetical list as its own entry.
        // PingFang SC is the only face safe to assert on: it ships with macOS, so
        // this holds on a CI runner too. A third-party face would make the test
        // report the machine's font library rather than this mapping.
        XCTAssertEqual(FontCatalog.familyName(forStored: "PingFangSC-Regular"), "PingFang SC")

        // A value that already is a family name, or that names nothing at all,
        // has to survive untouched.
        XCTAssertEqual(FontCatalog.familyName(forStored: "Menlo"), "Menlo")
        XCTAssertEqual(FontCatalog.familyName(forStored: "No Such Font"), "No Such Font")
        XCTAssertEqual(FontCatalog.familyName(forStored: ""), "")
    }

    func testRecommendationsAreOfferedOnlyWhenInstalled() {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        for kind in [FontListKind.text, .code] {
            let recommended = FontCatalog.installedRecommendations(for: kind)
            for family in recommended {
                XCTAssertTrue(installed.contains(family), "\(family) is recommended but not installed")
            }
        }
        // PingFang SC is the app's default text font and ships with macOS, so it
        // has to be there; if it ever is not, the popup loses its default row.
        XCTAssertTrue(FontCatalog.installedRecommendations(for: .text).contains("PingFang SC"))
        XCTAssertTrue(FontCatalog.installedRecommendations(for: .code).contains("Menlo"))
    }
}
