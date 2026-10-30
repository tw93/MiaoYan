import XCTest

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
}
