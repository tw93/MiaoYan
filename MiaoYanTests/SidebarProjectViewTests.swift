import AppKit
import XCTest

@testable import MiaoYan

final class SidebarProjectViewTests: XCTestCase {
    @MainActor
    func testTileRestoresNonScrollableWidthAfterSidebarReload() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 127, height: 300))
        scrollView.hasHorizontalScroller = false

        let outlineView = SidebarProjectView(frame: NSRect(x: 0, y: 0, width: 127, height: 300))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        scrollView.documentView = outlineView
        scrollView.layoutSubtreeIfNeeded()

        let clipView = scrollView.contentView
        let clipWidth = clipView.bounds.width

        // Reproduce the AppKit geometry observed after a deletion refresh:
        // reloadData leaves the outline wider than its clip view, making the
        // otherwise hidden horizontal range scrollable during the next switch.
        outlineView.setFrameSize(NSSize(width: clipWidth + 32, height: outlineView.frame.height))
        column.width = clipWidth
        clipView.scroll(to: NSPoint(x: 32, y: clipView.bounds.origin.y))

        XCTAssertGreaterThan(outlineView.frame.width, clipWidth)
        XCTAssertGreaterThan(clipView.bounds.origin.x, 0)

        outlineView.reloadData()

        XCTAssertEqual(outlineView.frame.width, clipWidth, accuracy: 0.5)
        XCTAssertEqual(column.width, clipWidth, accuracy: 0.5)
        XCTAssertEqual(clipView.bounds.origin.x, 0, accuracy: 0.5)
    }

    /// The selected folder used to come back by row number, which pointed at
    /// another folder once anything above it changed, and a subfolder never
    /// came back. It is now found by path, with its parents expanded.
    @MainActor
    func testAFolderIsFoundByPathWithItsParentsExpanded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanSidebar-\(UUID().uuidString)")
        let work = root.appendingPathComponent("Work", isDirectory: true)
        let year = work.appendingPathComponent("2024", isDirectory: true)
        try FileManager.default.createDirectory(at: year, withIntermediateDirectories: true)
        try "x".write(to: year.appendingPathComponent("plan.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let outlineView = SidebarProjectView(frame: NSRect(x: 0, y: 0, width: 200, height: 300))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.dataSource = outlineView
        outlineView.sidebarItems = [
            SidebarItem(name: "Notes", type: .All),
            SidebarItem(name: "Work", project: Project(url: work, label: "Work"), type: .Category),
        ]
        outlineView.reloadData()

        let yearPath = Project(url: year, label: "2024").url.path
        let row = try XCTUnwrap(outlineView.revealRow(forProjectPath: yearPath))
        let item = try XCTUnwrap(outlineView.item(atRow: row) as? SidebarItem)
        XCTAssertEqual(item.project?.url.path, yearPath)
        XCTAssertNil(outlineView.revealRow(forProjectPath: root.appendingPathComponent("Gone").path))
    }
}
