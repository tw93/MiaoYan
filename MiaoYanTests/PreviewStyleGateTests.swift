import XCTest

/// The preview follows the family's visual standard: quotes and alerts carry
/// no left stripe, nothing glows, and motion eases out at 0.12s for feedback
/// on the control under the pointer and 0.25s for what the page shows.
final class PreviewStyleGateTests: XCTestCase {
    private let sheets = ["typography.css", "base.css", "theme-light.css", "theme-dark.css", "tocbot.css"]

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func css(_ name: String) throws -> String {
        try source("Resources/DownView.bundle/css/\(name)")
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
