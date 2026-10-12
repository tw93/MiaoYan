import AppKit
import XCTest

@testable import MiaoYan

final class SidebarProjectViewTests: XCTestCase {
    private final class ReusingSidebar: SidebarProjectView {
        var reusedCell: SidebarCellView?

        override func makeView(withIdentifier identifier: NSUserInterfaceItemIdentifier, owner: Any?) -> NSView? {
            reusedCell
        }
    }

    @MainActor
    private func makeFolderCell() -> SidebarCellView {
        let cell = SidebarCellView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        let label = NSTextField(labelWithString: "Original")
        label.frame = NSRect(x: 30, y: 3, width: 160, height: 24)
        let icon = NSImageView(frame: .zero)
        cell.addSubview(label)
        cell.addSubview(icon)
        cell.label = label
        cell.textField = label
        cell.icon = icon
        label.cell?.sendsActionOnEndEditing = true
        label.target = cell
        label.action = #selector(SidebarCellView.projectName(_:))
        cell.awakeFromNib()
        return cell
    }

    @MainActor
    func testCompletingFolderRenameReturnsNameToReadOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanRename-\(UUID().uuidString)")
        let original = root.appendingPathComponent("Original", isDirectory: true)
        let renamed = root.appendingPathComponent("Renamed", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        let project = Project(url: original, label: "Original")
        let storage = AppEnvironment.current.storage
        _ = storage.add(project: project)
        defer {
            storage.removeBy(project: project)
            try? FileManager.default.removeItem(at: root)
        }

        let cell = makeFolderCell()
        cell.objectValue = SidebarItem(name: "Original", project: project, type: .Category)
        cell.label.isEditable = true
        cell.label.isSelectable = true
        XCTAssertTrue(cell.label.target === cell, "installing the label cell must preserve the storyboard action target")
        XCTAssertEqual(cell.label.action, #selector(SidebarCellView.projectName(_:)))
        let window = NSWindow(contentRect: cell.frame, styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = cell
        defer { window.close() }
        XCTAssertTrue(window.makeFirstResponder(cell.label))
        let editor = try XCTUnwrap(cell.label.currentEditor() as? NSTextView)
        editor.string = "Renamed"

        editor.insertNewline(nil)

        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(project.url.path, renamed.resolvingSymlinksInPath().path)
        XCTAssertFalse(cell.label.isEditable, "a completed rename must not leave the next click editing the folder name")
        XCTAssertFalse(cell.label.isSelectable, "the name must return to a label, not a selectable text field")
    }

    @MainActor
    func testCancellingFolderNameEditingReturnsNameToReadOnly() {
        let cell = makeFolderCell()
        cell.label.isEditable = true
        cell.label.isSelectable = true

        let handled =
            cell.label.delegate?.control?(
                cell.label,
                textView: NSTextView(),
                doCommandBy: #selector(NSResponder.cancelOperation(_:))
            ) ?? false

        XCTAssertTrue(handled)
        XCTAssertFalse(cell.label.isEditable)
        XCTAssertFalse(cell.label.isSelectable)
    }

    @MainActor
    func testReusingFolderRowResetsNameEditingState() throws {
        let cell = makeFolderCell()
        cell.label.isEditable = true
        cell.label.isSelectable = true
        let outlineView = ReusingSidebar(frame: NSRect(x: 0, y: 0, width: 200, height: 300))
        outlineView.reusedCell = cell
        let item = SidebarItem(name: "Another folder", type: .Category)

        let configuredCell = try XCTUnwrap(outlineView.outlineView(outlineView, viewFor: nil, item: item) as? SidebarCellView)

        XCTAssertTrue(configuredCell === cell)
        XCTAssertEqual(cell.label.stringValue, "Another folder")
        XCTAssertFalse(cell.label.isEditable)
        XCTAssertFalse(cell.label.isSelectable)
    }

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
