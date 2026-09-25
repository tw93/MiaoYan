import AppKit
import WebKit
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

    @MainActor
    func testTheDefaultFamilyYieldsLatinHoweverItWasStored() {
        // The shipped value is a PostScript name and the popup writes family
        // names, so both spellings have to be recognised as the default. Picking
        // 苹方-简 from the list, which is the row already shown as selected, used
        // to store "PingFang SC" and silently hand Latin back to PingFang with no
        // way to undo it from the UI.
        for stored in ["PingFangSC-Regular", "PingFang SC"] {
            let stack = FontCatalog.fontStack(forStored: stored)
            XCTAssertTrue(stack.hasPrefix("ui-sans-serif"), "\(stored) -> \(stack)")
            XCTAssertTrue(stack.contains("\"\(stored)\""), "\(stored) -> \(stack)")
        }
    }

    @MainActor
    func testTheFallbackYieldsLatinToTheSystemStack() {
        // Nobody chose PingFang for the English; it is the fallback, and its
        // Latin is drawn for interface labels. So PingFang, and only PingFang,
        // lets the system take Latin while staying on as the CJK fallback.
        let stack = FontCatalog.fontStack(forStored: FontConfiguration.fallbackFont)
        let systemAt = stack.range(of: "ui-sans-serif")
        let chosenAt = stack.range(of: "\"\(FontConfiguration.fallbackFont)\"")
        XCTAssertNotNil(systemAt)
        XCTAssertNotNil(chosenAt)
        if let s = systemAt, let c = chosenAt { XCTAssertTrue(s.lowerBound < c.lowerBound, stack) }
    }

    @MainActor
    func testTheDefaultFaceLeadsItsOwnStack() {
        // TsangerJinKai02 draws Latin to match its 楷书, so as the default it
        // leads the stack rather than yielding English to the system.
        let stack = FontCatalog.fontStack(forStored: FontConfiguration.defaultPreviewFont)
        XCTAssertTrue(stack.hasPrefix("\"\(FontConfiguration.defaultPreviewFont)\""), stack)
    }

    @MainActor
    func testAChosenFaceLeadsTheStackWhateverScriptItIs() {
        // Picking a face means picking it for the whole line. TsangerJinKai02
        // draws its Latin to match its Chinese, and handing those words to the
        // system face splits the line into two typefaces.
        for family in ["TsangerJinKai02-W04", "Georgia", "Songti SC", "Menlo"] {
            let stack = FontCatalog.fontStack(forStored: family)
            XCTAssertTrue(stack.hasPrefix("\"\(family)\""), stack)
            XCTAssertTrue(stack.contains("PingFang SC"), stack)
        }
    }

    @MainActor
    func testEveryStackEndsInAGenericFamily() {
        // Without the generic tail a face missing a glyph falls through to the
        // renderer's last resort rather than to a sans-serif.
        for name in ["PingFang SC", "Georgia", "Menlo", "No Such Font", "TsangerJinKai02-W04"] {
            XCTAssertTrue(FontCatalog.fontStack(forStored: name).hasSuffix("sans-serif"), name)
        }
    }

    func testTextPopupSeparatesChineseFromLatin() {
        let sections = FontCatalog.sections(for: .text)
        XCTAssertEqual(sections.map(\.title), ["zh", "latin"])

        let chinese = Set(sections[0].families)
        let latin = Set(sections[1].families)
        XCTAssertFalse(chinese.isEmpty)
        XCTAssertFalse(latin.isEmpty)
        // A family belongs to one section or the other, never both.
        XCTAssertTrue(chinese.isDisjoint(with: latin))

        // The Latin section exists so someone writing English can find the
        // obvious faces; a rule that drops these is too aggressive no matter how
        // clean it looks, since they are the ones people go looking for.
        for family in ["Georgia", "Helvetica Neue", "Arial", "Times New Roman", "Verdana"] {
            guard NSFontManager.shared.availableFontFamilies.contains(family) else { continue }
            XCTAssertTrue(latin.contains(family), "\(family) is missing from the Latin section")
        }
        for family in latin {
            XCTAssertFalse(NSFont(name: family, size: 12)?.coveredCharacterSet.contains("永") ?? false)
        }
    }

    func testCodePopupHasASingleSection() {
        let sections = FontCatalog.sections(for: .code)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].families, FontCatalog.families(for: .code))
    }

    func testDisplayNameNeverReplacesTheStoredFamily() {
        // The popup label is the localized name while the stored value stays the
        // family, so these two must not be conflated. On an English runner they
        // are equal for most faces; what has to hold everywhere is that a
        // display name is never empty and never leaks back as a stored value.
        for family in FontCatalog.families(for: .text).prefix(40) {
            let shown = FontCatalog.displayName(for: family)
            XCTAssertFalse(shown.isEmpty, "\(family) has no display name")
            XCTAssertEqual(FontCatalog.familyName(forStored: family), family)
        }
        // Menlo carries no localized name in any language, so it is the stable
        // case: label and family stay the same string.
        XCTAssertEqual(FontCatalog.displayName(for: "Menlo"), "Menlo")
    }

    func testListsAreOrderedByWhatTheUserReads() {
        // Sorting by family name would scatter a localized list, because the user
        // never sees the name it was sorted by.
        for kind in [FontListKind.text, .code] {
            let shown = FontCatalog.families(for: kind).map { FontCatalog.displayName(for: $0) }
            let ordered = shown.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            XCTAssertEqual(shown, ordered, "\(kind) is not ordered by its labels")
        }
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

    @MainActor
    func testPreviewNamesNoSeparateBoldFace() {
        // TsangerJinKai02 keeps W04 for its bold, the way it rendered before the
        // font batch, and no family gets a heavier face swapped in.
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "previewFontName")
        defer { defaults.set(original, forKey: "previewFontName") }
        for family in ["TsangerJinKai02-W04", "PingFang SC"] {
            defaults.set(family, forKey: "previewFontName")
            XCTAssertFalse(HtmlManager.previewStyle().contains("--text-font-bold"), family)
        }
    }

    @MainActor
    func testCodeFontFollowsTheTextStackUntilOneIsChosen() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "codeFont")
        defer { defaults.set(original, forKey: "codeFont") }

        defaults.set(FontConfiguration.followTextFont, forKey: "codeFont")
        let textStack = FontCatalog.fontStack(forStored: UserDefaultsManagement.previewFontName)
        XCTAssertTrue(HtmlManager.previewStyle().contains("--code-text-font: \(textStack);"))
        XCTAssertEqual(UserDefaultsManagement.codeFont.fontName, UserDefaultsManagement.noteFont.fontName)

        defaults.set("Menlo", forKey: "codeFont")
        XCTAssertTrue(HtmlManager.previewStyle().contains("--code-text-font: \"Menlo\","))
        XCTAssertEqual(UserDefaultsManagement.codeFont.familyName, "Menlo")
    }

    @MainActor
    func testCodeFontReachesOnlyTopLevelCodeBlocks() async throws {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "codeFont")
        defaults.set("Menlo", forKey: "codeFont")
        defer { defaults.set(original, forKey: "codeFont") }

        let bundle = try XCTUnwrap(Bundle.main.url(forResource: "DownView", withExtension: "bundle"))
        let css = try ["typography.css", "base.css"].map {
            try String(contentsOf: bundle.appendingPathComponent("css/\($0)"), encoding: .utf8)
        }.joined(separator: "\n")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        web.loadHTMLString(
            """
            <html><head><style>\(css) \(HtmlManager.previewStyle())</style></head><body><div class="heti">
            <p id="text">text <code id="inline">inline</code></p>
            <blockquote id="quote"><p><code id="quoteInline">q</code></p><pre><code id="quoteBlock">q</code></pre></blockquote>
            <pre><code id="block">block</code></pre>
            </div></body></html>
            """, baseURL: nil)
        var loaded = false
        for _ in 0..<250 {
            if (try? await web.evaluateJavaScript("document.readyState === 'complete' && !!document.getElementById('block')")) as? Bool == true {
                loaded = true
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(loaded, "The font fixture must load")
        guard loaded else { return }

        let ids = ["text", "inline", "quote", "quoteInline", "quoteBlock", "block"]
        let script = "JSON.stringify([\(ids.map { "'\($0)'" }.joined(separator: ","))].map(id => getComputedStyle(document.getElementById(id)).fontFamily))"
        let result = try await web.evaluateJavaScript(script)
        let json = try XCTUnwrap(result as? String)
        let families = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String])
        let family = Dictionary(uniqueKeysWithValues: zip(ids, families))
        XCTAssertTrue(family["block"]?.hasPrefix("Menlo") == true, family.description)
        XCTAssertEqual(family["inline"], family["text"])
        XCTAssertEqual(family["quoteInline"], family["quote"])
        XCTAssertEqual(family["quoteBlock"], family["quote"])
    }

}
