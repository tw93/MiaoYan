import JavaScriptCore
import XCTest

@testable import MiaoYan

/// The app follows the family's visual standard (Kata `sumi`): alerts carry
/// no left stripe and a quote only its thin warm bar, nothing glows, and motion eases out at 0.12s
/// for feedback on the control under the pointer and 0.25s for what the
/// window shows, in the preview CSS and through `Theme.Motion` in Swift.
final class VisualRulesGateTests: XCTestCase {
    private let sheets = ["typography.css", "base.css", "theme-light.css", "theme-dark.css", "tocbot.css"]

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func css(_ name: String) throws -> String {
        try source("Resources/DownView.bundle/css/\(name)")
    }

    /// The quote bar is a 3px rounded pill drawn by `::before` in a warm grey
    /// that starts and stops with the text, not the 4px full-height border it
    /// replaced (maintainer's pick, 2026-10-25).
    func testQuoteBarIsTheThinRoundedPill() throws {
        let text = try css("typography.css")
        let rule = try XCTUnwrap(text.range(of: #"\.heti blockquote::before\s*\{[^}]*\}"#, options: .regularExpression))
        let body = String(text[rule])
        XCTAssertNotNil(body.range(of: #"width:\s*3px"#, options: .regularExpression), body)
        XCTAssertNotNil(body.range(of: #"border-radius:\s*1\.5px"#, options: .regularExpression), body)
        XCTAssertNotNil(body.range(of: #"background:\s*var\(--quote-bar\)"#, options: .regularExpression), body)
        for name in ["theme-light.css", "theme-dark.css"] {
            XCTAssertNotNil(try css(name).range(of: #"--quote-bar:\s*#"#, options: .regularExpression), name)
        }
    }

    /// The preview shares one reading rhythm with the iPhone reader, tw93.fun
    /// and Weekly (maintainer 2026-11-04): 1.64 line height, the 30/24/20
    /// heading ladder as em of the body, a heading's next block pulled up to
    /// it, monospace code blocks a step down, and MiaoYan green links.
    func testPreviewSharesTheFamilyReadingRhythm() throws {
        let typography = try css("typography.css")
        let base = try css("base.css")
        let core = try XCTUnwrap(typography.range(of: #"\n\.heti \{[^}]*\}"#, options: .regularExpression))
        XCTAssertNotNil(typography[core].range(of: "line-height: 1.64;"), String(typography[core]))
        for (heading, size) in [("h1", "1.76em"), ("h2", "1.41em"), ("h3", "1.18em")] {
            let rule = try XCTUnwrap(typography.range(of: #"\.heti \#(heading) \{[^}]*\}"#, options: .regularExpression), heading)
            XCTAssertNotNil(typography[rule].range(of: "font-size: \(size);"), String(typography[rule]))
        }
        let pull = try XCTUnwrap(
            typography.range(
                of: #"#write :is\(h1, h2, h3, h4, h5, h6\) \+ :not\(h1, h2, h3, h4, h5, h6\) \{[^}]*\}"#,
                options: .regularExpression))
        XCTAssertNotNil(typography[pull].range(of: "margin-block-start: 0;"), String(typography[pull]))
        // CJK emphasis is marked with its lang and never slanted (Emphasis.markCJK).
        XCTAssertNotNil(typography.range(of: ".heti em:not([lang]) {"))
        XCTAssertNil(typography.range(of: ".heti em:not(:lang(zh))"))
        // Links are told apart by the green alone; an underline at rest read ugly
        // (maintainer 2026-11-04).
        let link = try XCTUnwrap(typography.range(of: #"\n\.heti a,\n\.heti a:hover \{[^}]*\}"#, options: .regularExpression))
        XCTAssertNotNil(typography[link].range(of: "text-decoration: none;"), String(typography[link]))
        for css in [typography, base] { XCTAssertNil(css.range(of: "text-decoration: underline")) }
        let code = try XCTUnwrap(typography.range(of: #"\.heti pre code \{[^}]*\}"#, options: .regularExpression))
        XCTAssertNotNil(typography[code].range(of: "font-size: 0.86em;"), String(typography[code]))
        for name in sheets {
            XCTAssertNil(try css(name).range(of: "line-height: 1.74"), name)
        }
        XCTAssertNotNil(try css("theme-light.css").range(of: "--link-color: #1C5D33;"))
        XCTAssertNotNil(try css("theme-dark.css").range(of: "--link-color: #54C59F;"))
    }

    /// A SwiftUI chevron takes a named size (`Theme.Metrics.rowChevron`), not a literal (sumi principle 5).
    func testChevronsNameTheirSize() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Shell")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 4)
        // A chevron glyph whose next line sets a literal point size.
        let literal = try NSRegularExpression(pattern: #""chevron\.[a-z.]+"\)\s*\n\s*\.font\(\.system\(size: *[0-9]"#)
        var found: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in literal.matches(in: text, range: range) {
                found.append("\(file.lastPathComponent): \((text as NSString).substring(with: match.range))")
            }
        }
        XCTAssertEqual(found, [])
    }

    func testQuotesAndAlertsHaveNoLeftStripe() throws {
        let stripe = #"border-left\s*:\s*[1-9]"#
        for name in sheets {
            XCTAssertNil(try css(name).range(of: stripe, options: .regularExpression), name)
        }
        // PDF export restyles quotes on top of the preview.
        XCTAssertNil(try source("Business/HtmlManager.swift").range(of: stripe, options: .regularExpression))
    }

    /// No interface text is below 12pt: the note list's dates were 11pt in
    /// both windows until 2026-11-06, while AGENTS.md already named the floor.
    @MainActor
    func testListDatesMeetTheTwelvePointFloor() {
        XCTAssertGreaterThanOrEqual(UserDefaultsManagement.dateFontSize, 12)
    }

    /// Floating layers share one radius, and none of them uses a translucent
    /// `.hudWindow` material any more.
    func testFloatingLayersShareOneRadiusAndNoFrost() throws {
        XCTAssertTrue(try source("Views/Toast.swift").contains("cornerRadius: CGFloat = Theme.Metrics.floatingCornerRadius"))
        for path in ["Views/Toast.swift", "Views/ImagePreviewWindow.swift"] {
            XCTAssertFalse(try source(path).contains("material = .hudWindow"), path)
        }
    }

    /// Exports take the preview's green; an orange `--primary-color` from an
    /// older theme sat in the export CSS until 2026-11-06.
    func testExportCSSHasNoOrangeAccent() throws {
        XCTAssertFalse(try source("Business/HtmlManager.swift").lowercased().contains("#fd8258"))
    }

    func testNothingGlows() throws {
        for name in sheets {
            let text = try css(name)
            XCTAssertNil(text.range(of: "linear-gradient", options: .caseInsensitive), name)
            // A zero-offset blur is a glow; a floating layer's shadow drops.
            for line in text.components(separatedBy: .newlines) where line.contains("box-shadow") {
                XCTAssertNil(line.range(of: #"(:|,)\s*0\s+0\s+[1-9]"#, options: .regularExpression), "\(name): \(line)")
            }
        }
    }

    func testSwiftAnimationsUseThemeMotion() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let patterns = [
            #"context\.duration\s*=\s*[0-9]"#, #"easeOut\(duration:\s*[0-9]"#, #"easeInOut|\.easeIn\b|name:\s*\.easeIn\b"#,
        ]
        for folder in ["Controllers", "Views", "Shell", "Helpers"] {
            let files = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            while let url = files?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
                for (index, line) in lines.enumerated() {
                    for pattern in patterns where line.range(of: pattern, options: .regularExpression) != nil {
                        XCTFail("\(folder)/\(url.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }
    }

    func testMotionEasesOutAtTwoDurations() throws {
        for name in sheets {
            for line in try css(name).components(separatedBy: .newlines) where line.contains("transition:") {
                let parts = line.split(separator: ":", maxSplits: 1)[1].split(separator: ",")
                for part in parts {
                    let words = part.split(whereSeparator: \.isWhitespace).map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ";")) }
                    XCTAssertTrue(words.contains("ease-out"), "\(name): \(line)")
                    XCTAssertTrue(words.contains("0.12s") || words.contains("0.25s"), "\(name): \(line)")
                }
            }
        }
    }

    /// Mermaid, PlantUML and Markmap take their colours from theme-config.js,
    /// which kept the cool greys from before the warm paper palette, so a
    /// PlantUML diagram painted a bluish box inside the warm --diagram-bg.
    /// Its backgrounds now are the sheets' own values; diagram text in dark
    /// stays #E7E9EA (maintainer 2026-11-05).
    func testDiagramPaletteIsTheWarmPaper() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("var window = this;")
        context.evaluateScript(try source("Resources/DownView.bundle/js/theme-config.js"))
        func variable(_ sheet: String, _ name: String) throws -> String {
            let text = try css(sheet)
            let range = try XCTUnwrap(text.range(of: name + #":\s*#[0-9A-Fa-f]{6}"#, options: .regularExpression), "\(sheet) \(name)")
            return String(text[range].suffix(7)).lowercased()
        }
        for (dark, sheet) in [(false, "theme-light.css"), (true, "theme-dark.css")] {
            let colors = try XCTUnwrap(context.evaluateScript("ThemeColors.getThemeColors(\(dark))").toDictionary() as? [String: String])
            XCTAssertEqual(colors["diagramBg"]?.lowercased(), try variable(sheet, "--diagram-bg"), sheet)
            XCTAssertEqual(colors["codeBg"]?.lowercased(), try variable(sheet, "--code-bg"), sheet)
            XCTAssertEqual(colors["background"]?.lowercased(), try variable(sheet, "--bg-color"), sheet)
            XCTAssertEqual(colors["primaryColor"]?.lowercased(), try variable(sheet, "--mermaid-node-bg"), sheet)
            let skin = try XCTUnwrap(context.evaluateScript("ThemeColors.getPlantUMLSkinparams(\(dark))").toString())
            XCTAssertTrue(skin.contains("skinparam backgroundColor \(colors["diagramBg"] ?? "")"), "PlantUML paints no box of its own")
        }
        XCTAssertEqual(context.evaluateScript("ThemeColors.getThemeColors(true).textColor").toString(), "#E7E9EA")
        let cool = ["#2f353d", "#323a42", "#23282d", "#282e33", "#f7f7f7", "#d0d7e2", "#f0f3f6", "#49515a", "#252b31", "#2c3238", "#30363d", "#1f2933", "#f6f8fa", "#e8e8e8"]
        for file in ["Resources/DownView.bundle/js/theme-config.js", "Resources/DownView.bundle/css/diagrams.css"] {
            let text = try source(file).lowercased()
            for grey in cool { XCTAssertFalse(text.contains(grey), "\(file): \(grey)") }
        }
    }
}
