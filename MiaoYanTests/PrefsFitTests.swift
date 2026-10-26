import XCTest

@testable import MiaoYan

/// Every settings row keeps its title and description on one line at the
/// window's fixed width, in every interface language, Spanish included
/// although only the system language reaches it.
final class PrefsFitTests: XCTestCase {
    @MainActor
    func testEveryRowFitsInEveryLanguage() throws {
        let previousLanguage = UserDefaults.standard.object(forKey: "defaultLanguage")
        defer {
            I18n.overrideBundle = nil
            if let previousLanguage {
                UserDefaults.standard.set(previousLanguage, forKey: "defaultLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "defaultLanguage")
            }
        }
        let spanish = try XCTUnwrap(Bundle.main.path(forResource: "es", ofType: "lproj").flatMap(Bundle.init(path:)))
        for language in ["zh-Hans", "en", "ja", "zh-Hant", "es"] {
            if let type = [LanguageType.Chinese, .English, .Japanese, .ChineseTC].first(where: { $0.code == language }) {
                UserDefaultsManagement.defaultLanguage = type.rawValue
                I18n.overrideBundle = nil
            } else {
                I18n.overrideBundle = spanish
            }
            let pages: [NSViewController] = [
                GeneralPrefsViewController(), EditorPrefsViewController(), TypographyPrefsViewController(),
            ]
            for page in pages {
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: PrefsMetrics.windowWidth, height: 600),
                    styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentViewController = page
                window.setContentSize(NSSize(width: PrefsMetrics.windowWidth, height: 600))
                page.view.layoutSubtreeIfNeeded()
                let rows = Self.rows(in: page.view)
                XCTAssertFalse(rows.isEmpty, "\(language) \(type(of: page))")
                for row in rows {
                    // A middle-truncated detail is the user's own path, not copy:
                    // it is meant to shorten, and its length depends on the Mac.
                    for label in [row.titleLabel, row.detailLabel]
                    where !label.isHidden && !label.stringValue.isEmpty && label.lineBreakMode != .byTruncatingMiddle {
                        XCTAssertGreaterThanOrEqual(
                            label.frame.width + 0.5, label.intrinsicContentSize.width,
                            "\(language) \(type(of: page)): \(label.stringValue)")
                    }
                }
                window.orderOut(nil)
            }
        }
    }

    @MainActor
    private static func rows(in view: NSView) -> [PrefsRowView] {
        view.subviews.flatMap { subview -> [PrefsRowView] in
            if let row = subview as? PrefsRowView { return [row] }
            return rows(in: subview)
        }
    }
}
