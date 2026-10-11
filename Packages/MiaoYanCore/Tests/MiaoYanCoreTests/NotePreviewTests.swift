import XCTest

import MiaoYanCore

final class NotePreviewTests: XCTestCase {
    func testCardTextDropsMarkupAndKeepsTwoLines() {
        let text = "---\ntitle: x\n---\n# Heading\n\n![cover](i/a.png)\nSee [the docs](https://example.com) and `code`.\n\n```swift\nlet a = 1\n```\n- **third** line\n"
        XCTAssertEqual(NotePreview.cardText(from: text), "Heading See the docs and code.")
    }

    func testCardTextOfImageOnlyNoteIsEmpty() {
        XCTAssertEqual(NotePreview.cardText(from: "![](i/a.png)\n"), "")
    }

    func testTextReadsOnlyTheHeadAndSurvivesASplitCharacter() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        // 899 ASCII bytes then a 3-byte character, so the 900-byte read ends inside it.
        let head = String(repeating: "a", count: NotePreview.byteLimit - 1)
        try (head + "中\nsecond").write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(NotePreview.text(at: url), head)
    }

    func testTextOfLongFrontmatterReadsPastTheHead() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        let keys = (0..<200).map { "key\($0): value" }.joined(separator: "\n")
        try "---\n\(keys)\n---\nBody line".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(NotePreview.text(at: url), "Body line")
    }
    func testTextSkipsAnOpeningHeadingThatRepeatsTheTitle() throws {
        // Cards print the title above the preview, so a note that opens with
        // its own name as an H1 showed it twice ("发布流程 发布流程 打包").
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let same = dir.appendingPathComponent("发布流程.md")
        try "# 发布流程\n\n打包签名\n公证".write(to: same, atomically: true, encoding: .utf8)
        XCTAssertEqual(NotePreview.text(at: same), "打包签名 公证")

        // A heading that differs from the file name is content, not a repeat.
        let other = dir.appendingPathComponent("notes.md")
        try "# Meeting\n\nAgenda".write(to: other, atomically: true, encoding: .utf8)
        XCTAssertEqual(NotePreview.text(at: other), "Meeting Agenda")
    }
}
