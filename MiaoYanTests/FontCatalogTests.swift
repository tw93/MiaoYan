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
    func testBoldStackKeepsTheFallbackTail() throws {
        // Naming the heavier face alone leaves a glyph it lacks with nowhere to
        // go, so the bold stack carries the same tail as the body stack.
        let retired = "TsangerJinKai02-W04"
        guard let bold = FontCatalog.boldFontStack(forStored: retired) else {
            throw XCTSkip("No face on this machine needs a bold override")
        }
        XCTAssertTrue(bold.hasPrefix("\"TsangerJinKai02-W05\""), bold)
        XCTAssertTrue(bold.hasSuffix("sans-serif"), bold)
        XCTAssertTrue(bold.contains("\"PingFang SC\""), bold)
        // A family that resolves its own bold gets no override at all.
        XCTAssertNil(FontCatalog.boldFontStack(forStored: "Songti SC"))
    }

    @MainActor
    func testTheShippedDefaultYieldsLatinToTheSystemStack() {
        // Nobody chose PingFang for the English; it is what the app starts with,
        // and its Latin is drawn for interface labels. So the default, and only
        // the default, lets the system take Latin while staying on as the CJK
        // fallback.
        let stack = FontCatalog.fontStack(forStored: FontConfiguration.defaultPreviewFont)
        let systemAt = stack.range(of: "ui-sans-serif")
        let chosenAt = stack.range(of: "\"\(FontConfiguration.defaultPreviewFont)\"")
        XCTAssertNotNil(systemAt)
        XCTAssertNotNil(chosenAt)
        if let s = systemAt, let c = chosenAt { XCTAssertTrue(s.lowerBound < c.lowerBound, stack) }
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

    @MainActor
    func testPreviewStyleCarriesTheBoldFaceOnlyWhenThereIsOne() throws {
        let defaults = UserDefaults.standard
        let key = "previewFontName"
        let original = defaults.string(forKey: key)
        defer { defaults.set(original, forKey: key) }

        // A family that resolves its own bold must not get the override, or the
        // stylesheet would pin a face the system was already choosing correctly.
        defaults.set("PingFang SC", forKey: key)
        let resolved = HtmlManager.previewStyle()
        XCTAssertFalse(resolved.contains("--text-font-bold"))
        XCTAssertFalse(resolved.contains("--text-font-synthesis"))

        // A family that does not gets both variables, because naming a face
        // without disabling synthesis would smear that face in turn.
        let retired = "TsangerJinKai02-W04"
        guard FontCatalog.boldFace(forStored: retired) != nil else {
            throw XCTSkip("No family on this machine needs the override")
        }
        defaults.set(retired, forKey: key)
        let overridden = HtmlManager.previewStyle()
        XCTAssertTrue(overridden.contains("--text-font-bold: \"TsangerJinKai02-W05\""), overridden)
        XCTAssertTrue(overridden.contains("--text-font-synthesis: style"))
    }

    func testBoldFaceStaysOutOfTheWayWhenTheSystemCanResolveBold() {
        // These ship with macOS and declare real bold faces, so naming one here
        // would override the system for no reason.
        for family in ["PingFang SC", "Songti SC", "Hiragino Sans GB", "Helvetica Neue"] {
            guard NSFontManager.shared.availableFontFamilies.contains(family) else { continue }
            XCTAssertNil(FontCatalog.boldFace(forStored: family), "\(family) already resolves its own bold")
        }
        XCTAssertNil(FontCatalog.boldFace(forStored: "No Such Font"))
    }

    func testAnyBoldFaceNamedIsAnotherMemberOfTheSameFamily() {
        // Whatever the naming heuristic picks has to be a real face of the same
        // family and not the one already in use, on any machine's font library.
        let manager = NSFontManager.shared
        for family in manager.availableFontFamilies {
            guard let bold = FontCatalog.boldFace(forStored: family) else { continue }
            XCTAssertNotNil(NSFont(name: bold, size: 16), "\(bold) is not a loadable face")
            XCTAssertEqual(NSFont(name: bold, size: 16)?.familyName, family)
            XCTAssertNotEqual(bold, NSFont(name: family, size: 16)?.fontName)
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
    func testRealBoldOverridePreservesRenderedItalics() async throws {
        let family = "TsangerJinKai02-W04"
        guard FontCatalog.boldFace(forStored: family) != nil else {
            throw XCTSkip("The optional numbered-weight font is not installed")
        }
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "previewFontName")
        defaults.set(family, forKey: "previewFontName")
        defer { defaults.set(original, forKey: "previewFontName") }

        let bundle = try XCTUnwrap(Bundle.main.url(forResource: "DownView", withExtension: "bundle"))
        let css = try ["typography.css", "base.css"].map {
            try String(contentsOf: bundle.appendingPathComponent("css/\($0)"), encoding: .utf8)
        }.joined(separator: "\n")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 140))
        let window = NSWindow(contentRect: web.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = web
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        web.loadHTMLString(
            """
            <html><head><style>\(css) \(HtmlManager.previewStyle())
            body { margin: 0; padding: 20px; background: white; }
            .heti { font-size: 32px; color: black; }
            </style></head><body><div class="heti"><em id="sample">Italic English abcdef</em></div></body></html>
            """, baseURL: nil)
        var loaded = false
        for _ in 0..<250 {
            if (try? await web.evaluateJavaScript("document.readyState === 'complete' && !!document.getElementById('sample')")) as? Bool == true {
                loaded = true
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(loaded, "The font rendering fixture must load")
        guard loaded else { return }

        let italic = try await fontSnapshotPixels(web)
        _ = try await web.evaluateJavaScript("document.getElementById('sample').style.fontStyle = 'normal'")
        let upright = try await fontSnapshotPixels(web)
        XCTAssertNotEqual(italic, upright, "Italic markup must visibly differ from upright text when a real bold face is selected")
        let weight = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('sample')).fontSynthesis")
        XCTAssertEqual(weight as? String, "style", "Keep italic synthesis without adding fake bold")
    }

    @MainActor
    private func fontSnapshotPixels(_ web: WKWebView) async throws -> Data {
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        let image = try await web.takeSnapshot(configuration: configuration)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        return Data(bytes: pixels, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

}
