import XCTest

@testable import MiaoYan

/// Version history's line counts and marks, and the ceiling on how much
/// history all notes keep together.
final class VersionChangesTests: XCTestCase {
    func testAVersionTellsTheLinesItAddedAndTheLinesItRewrote() throws {
        let changes = try XCTUnwrap(VersionChanges.between(older: "a\nb\nc", newer: "a\nB\nc\nd"))
        XCTAssertEqual(changes.added, 2)
        XCTAssertEqual(changes.removed, 1)
        XCTAssertEqual(changes.marks, [.init(line: 1, kind: .rewritten), .init(line: 3, kind: .added)])
    }

    func testALineRewrittenIntoTwoIsOneRewriteAndOneAddition() throws {
        let changes = try XCTUnwrap(VersionChanges.between(older: "a\nb\nc", newer: "a\nb one\nb two\nc"))
        XCTAssertEqual(changes.added, 2)
        XCTAssertEqual(changes.removed, 1)
        XCTAssertEqual(changes.marks, [.init(line: 1, kind: .rewritten), .init(line: 2, kind: .added)])
    }

    func testRemovedLinesCountButMarkNothingInTheNewerText() throws {
        let changes = try XCTUnwrap(VersionChanges.between(older: "a\nb\nc", newer: "a\nc"))
        XCTAssertEqual(changes.added, 0)
        XCTAssertEqual(changes.removed, 1)
        XCTAssertTrue(changes.marks.isEmpty)
    }

    func testLineEndingsAloneAreNoChange() throws {
        let changes = try XCTUnwrap(VersionChanges.between(older: "a\r\nb\r\n", newer: "a\nb\n"))
        XCTAssertEqual(changes.added + changes.removed, 0)
    }

    func testAVeryLongPairIsNotCompared() {
        let long = Array(repeating: "line", count: VersionChanges.longestDiffed).joined(separator: "\n")
        XCTAssertNil(VersionChanges.between(older: long, newer: long + "\nmore"))
    }

    func testMarksLandOnTheirOwnLines() throws {
        // A lone "\r" and U+2028 stay inside a line, and an emoji is two
        // UTF-16 units: the ranges must still start where each line starts.
        let newer = "one\r\u{2028}x\n\u{1F600} two\nthree\n"
        let changes = try XCTUnwrap(VersionChanges.between(older: "one\r\u{2028}x\nthree\n", newer: newer))
        let ranges = VersionChanges.ranges(of: changes.marks, in: newer)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual((newer as NSString).substring(with: ranges[0].range), "\u{1F600} two\n")
        XCTAssertEqual(ranges[0].kind, .added)

        let added = try XCTUnwrap(VersionChanges.between(older: "a", newer: "a\n"))
        let last = VersionChanges.ranges(of: added.marks, in: "a\n")
        XCTAssertEqual(last.map(\.range), [NSRange(location: 2, length: 0)])
    }

    /// The panel itself, in a window off screen: the list counts what the
    /// newest version changed and the preview tints its new lines. With
    /// `MIAOYAN_SHOTS` set to a folder it also writes a light and a dark
    /// capture there, which is how the panel is looked at without driving
    /// the running app.
    @MainActor
    func testThePanelCountsAndTintsWhatAVersionChanged() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanVersionPanel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Plan-\(UUID().uuidString).md")
        let note = Note(url: url, with: Project(url: dir, label: "test", isRoot: true))
        defer { NoteVersionManager.shared.removeVersions(for: note) }

        // Versions are named by the second, so each save waits for the next.
        let drafts = [
            "# Weekly plan\n\nShip the table editor.\nWrite the release notes.\n",
            "# Weekly plan\n\nShip the table editor.\nWrite the release note in two languages.\nReview the version panel.\n",
        ]
        for (index, draft) in drafts.enumerated() {
            if index > 0 { Thread.sleep(forTimeInterval: 1.1) }
            note.content = NSMutableAttributedString(string: draft)
            let saved = expectation(description: "saved \(index)")
            NoteVersionManager.shared.saveVersionIfNeeded(for: note, force: true) { saved.fulfill() }
            wait(for: [saved], timeout: 5)
        }
        note.content = NSMutableAttributedString(string: drafts[1] + "Book the venue.\n")

        let panel = VersionHistoryViewController(note: note)
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 700, height: 440), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = panel.view
        panel.viewDidAppear()
        let table = try XCTUnwrap(descendants(of: panel.view).compactMap { $0 as? NSTableView }.first)
        let preview = try XCTUnwrap(descendants(of: panel.view).compactMap { $0 as? VersionPreviewTextView }.first)
        let counted = NSPredicate { _, _ in
            self.descendants(of: table).contains { ($0 as? NSTextField)?.stringValue == "+1 \u{2212}0" }
        }
        wait(for: [XCTNSPredicateExpectation(predicate: counted, object: nil)], timeout: 5)

        // The current text added one line at the end.
        XCTAssertEqual(preview.marks.map { (preview.string as NSString).substring(with: $0.range) }, ["Book the venue.\n"])
        XCTAssertEqual(preview.marks.map(\.kind), [.added])

        // The newest saved version rewrote one line and added one, and the
        // preview shows that version's own text, not the current one.
        table.selectRowIndexes([1], byExtendingSelection: false)
        XCTAssertTrue(descendants(of: table).contains { ($0 as? NSTextField)?.stringValue == "+2 \u{2212}1" })
        XCTAssertEqual(preview.string, drafts[1])
        XCTAssertEqual(
            preview.marks.map { (preview.string as NSString).substring(with: $0.range) },
            ["Write the release note in two languages.\n", "Review the version panel.\n"])
        XCTAssertEqual(preview.marks.map(\.kind), [.rewritten, .added])

        guard let folder = ProcessInfo.processInfo.environment["MIAOYAN_SHOTS"] else { return }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            panel.view.layoutSubtreeIfNeeded()
            panel.view.display()
            let view = try XCTUnwrap(window.contentView)
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appendingPathComponent("version-panel-\(name).png"))
        }
    }

    @MainActor
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    func testTheHistoryDropsTheOldestVersionsButEachNotesNewest() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanBudget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let kilobyte = Data(repeating: 0x61, count: 1024)
        let files = [
            "a-1": ["2026-11-01T10-00-00Z", "2026-11-03T10-00-00Z", "2026-11-05T10-00-00Z"],
            "b-2": ["2026-11-02T10-00-00Z", "2026-11-04T10-00-00Z"],
            "c-3": ["2026-10-01T10-00-00Z"],
        ]
        for (folder, names) in files {
            let dir = root.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for name in names { try kilobyte.write(to: dir.appendingPathComponent(name + ".md")) }
        }

        // What is not a version is neither counted nor removed: a stray file
        // whose name sorts after every version, a .DS_Store, and a symlink to
        // a folder elsewhere whose file must survive.
        let a1 = root.appendingPathComponent("a-1")
        try kilobyte.write(to: a1.appendingPathComponent("zz-notes.txt"))
        try kilobyte.write(to: a1.appendingPathComponent(".DS_Store"))
        let outside = root.deletingLastPathComponent().appendingPathComponent("MiaoYanBudgetOutside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data(repeating: 0x62, count: 8192).write(to: outside.appendingPathComponent("2026-01-01T10-00-00Z.md"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: outside)

        // Six files of 1 KiB under a 3.5 KiB ceiling: the three oldest that
        // are not a note's newest go, oldest first, and c-3's only version,
        // older than all of them, stays.
        XCTAssertEqual(NoteVersionManager.keepWithinBudget(root: root, budget: 3584), 3072, "the size left, which later saves add to")
        func left(_ folder: String) -> [String] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(folder).path)) ?? []
            return names.sorted()
        }
        XCTAssertEqual(left("a-1"), [".DS_Store", "2026-11-05T10-00-00Z.md", "zz-notes.txt"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.appendingPathComponent("2026-01-01T10-00-00Z.md").path))
        XCTAssertEqual(left("b-2"), ["2026-11-04T10-00-00Z.md"])
        XCTAssertEqual(left("c-3"), ["2026-10-01T10-00-00Z.md"])

        // Under the ceiling nothing is touched.
        XCTAssertEqual(NoteVersionManager.keepWithinBudget(root: root, budget: 1 << 20), 3072)
        XCTAssertEqual(left("a-1").count + left("b-2").count + left("c-3").count, 5)
    }
}
