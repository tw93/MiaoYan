import XCTest

import MiaoYanCore

final class NoteSearchReaderTests: XCTestCase {
    func testReadsMatchBeyondFormerSearchLimitAndAcrossUTF8ChunkBoundary() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = String(repeating: "a", count: 65_535) + "中文 café" + String(repeating: "b", count: 65_536)
        try text.write(to: url, atomically: true, encoding: .utf8)
        let result = try NoteSearchReader.read(url)
        XCTAssertEqual(result, text)
        XCTAssertNotNil(result.range(of: "中文 CAFE", options: [.caseInsensitive, .diacriticInsensitive]))
    }

    func testEmptyFileRemainsReadableForTitleSearch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data().write(to: url)
        XCTAssertEqual(try NoteSearchReader.read(url), "")
    }

    func testCancellationStopsBeforeOpeningFile() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try NoteSearchReader.read(URL(fileURLWithPath: "/nonexistent-miaoyan-search-test"))
                XCTFail("Cancelled reads must stop before opening a file")
            } catch is CancellationError {
                // Expected, rather than a file-not-found error.
            } catch {
                XCTFail("Expected cancellation, got \(error)")
            }
        }
        await task.value
    }
}

final class NoteContentMatcherTests: XCTestCase {
    private func candidate(_ index: Int, title: String, url: URL = URL(fileURLWithPath: "/nonexistent"), loaded: String? = nil) -> NoteSearchCandidate {
        NoteSearchCandidate(index: index, title: title, url: url, loadedText: loaded)
    }

    func testPriorityFollowsWhereTheTermsWereFound() {
        XCTAssertEqual(NoteContentMatcher.priority(title: "潮流周刊", body: { "" }, terms: ["潮流"]), 4)
        XCTAssertEqual(NoteContentMatcher.priority(title: "潮流周刊", body: { "Rust 工具" }, terms: ["潮流", "rust"]), 2)
        XCTAssertEqual(NoteContentMatcher.priority(title: "周刊", body: { "Rust 工具" }, terms: ["rust"]), 1)
        XCTAssertNil(NoteContentMatcher.priority(title: "周刊", body: { "Rust" }, terms: ["go"]))
    }

    func testBodyIsNotReadWhenTheTitleSettlesTheMatch() {
        var reads = 0
        _ = NoteContentMatcher.priority(
            title: "潮流周刊",
            body: {
                reads += 1; return ""
            }, terms: ["周刊"])
        XCTAssertEqual(reads, 0)
    }

    func testADotMatchesTextNotTheFileExtension() {
        // Titles carry no extension, so "." only matches a note that has one.
        let matches = NoteContentMatcher.match(
            [candidate(0, title: "潮流周刊", loaded: "没有句点"), candidate(1, title: "周刊", loaded: "v1.2")],
            terms: ["."], limit: .max, isCancelled: { false })
        XCTAssertEqual(matches.map(\.index), [1])
    }

    func testLoadedTextWinsOverTheFileAndUnloadedNotesAreRead() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try "saved on disk".write(to: url, atomically: true, encoding: .utf8)

        let fromDisk = NoteContentMatcher.match([candidate(0, title: "a", url: url)], terms: ["disk"], limit: .max, isCancelled: { false })
        XCTAssertEqual(fromDisk.map(\.index), [0])

        // An open note's unsaved text is what the user sees, so it decides.
        let edited = NoteContentMatcher.match([candidate(0, title: "a", url: url, loaded: "typed just now")], terms: ["disk"], limit: .max, isCancelled: { false })
        XCTAssertTrue(edited.isEmpty)
    }

    func testLimitCapsBodyMatchesAndCancellationReturnsNothing() {
        let all = (0..<5).map { candidate($0, title: "entry \($0)", loaded: "a note") }
        XCTAssertEqual(NoteContentMatcher.match(all, terms: ["note"], limit: 2, isCancelled: { false }).map(\.index), [0, 1])
        XCTAssertTrue(NoteContentMatcher.match(all, terms: ["note"], limit: .max, isCancelled: { true }).isEmpty)
    }

    func testATitleMatchIsNeverCutByEarlierBodyMatches() {
        let bodies = (0..<150).map { candidate($0, title: "entry \($0)", loaded: "mentions plan") }
        let exact = candidate(150, title: "plan")
        let found = NoteContentMatcher.match(bodies + [exact], terms: ["plan"], limit: 100, isCancelled: { false })
        XCTAssertTrue(found.contains { $0.index == 150 && $0.priority == 4 }, "the note titled exactly as the query is kept")
        XCTAssertEqual(found.count, 100)
    }

    func testUnopenedGBKNotesMatchOnTheirBody() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        try XCTUnwrap("旧笔记里的周报".data(using: gb18030)).write(to: url)
        let found = NoteContentMatcher.match([candidate(0, title: "legacy", url: url)], terms: ["周报"], limit: 100, isCancelled: { false })
        XCTAssertEqual(found.map(\.index), [0])
    }
}
