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

    /// The MiaoYan lockup is a mark, not a place: All Notes is its own row
    /// under it, and a row number that lands on the lockup (one saved before
    /// it existed, or a removal falling back to row 0) selects All Notes.
    @MainActor
    func testTheBrandRowCannotBeSelectedAndFallsBackToAllNotes() throws {
        let list = Sidebar().getList().compactMap { $0 as? SidebarItem }
        XCTAssertEqual(list.prefix(2).map(\.type), [.Brand, .All])
        XCTAssertFalse(list[0].isSelectable())
        XCTAssertTrue(list[1].isSelectable())
        XCTAssertEqual(list[1].name, I18n.str("All Notes"))

        let outlineView = SidebarProjectView(frame: NSRect(x: 0, y: 0, width: 200, height: 300))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.dataSource = outlineView
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanSidebar-\(UUID().uuidString)")
        outlineView.sidebarItems = [
            SidebarItem(name: "MiaoYan", type: .Brand),
            SidebarItem(name: "All Notes", type: .All),
            SidebarItem(name: "Work", project: Project(url: work, label: "Work"), type: .Category),
        ]
        outlineView.reloadData()

        XCTAssertFalse(outlineView.outlineView(outlineView, shouldSelectItem: try XCTUnwrap(outlineView.item(atRow: 0))))
        outlineView.selectRowIndexes([0], byExtendingSelection: false)
        XCTAssertEqual(outlineView.selectedRow, 1)
        outlineView.selectRowIndexes([2], byExtendingSelection: false)
        XCTAssertEqual(outlineView.selectedRow, 2)
    }

    /// The SwiftUI sidebar draws the lockup over its rows; the rows start at
    /// All Notes and never include the lockup.
    @available(macOS 14, *)
    @MainActor
    func testShellSidebarRowsStartAtAllNotes() {
        let model = ShellModel()
        model.reload()
        XCTAssertEqual(model.sidebarRows.first?.id, .all)
        XCTAssertEqual(model.sidebarRows.first?.title, I18n.str("All Notes"))
        XCTAssertFalse(model.sidebarRows.contains { $0.kind == .Brand })
        XCTAssertFalse(model.brandTitle.isEmpty)
    }

    /// Left arrow on a closed subfolder in the SwiftUI shell goes to the row
    /// it sits under, as NSOutlineView does; a top-level row has none.
    @available(macOS 14, *)
    @MainActor
    func testShellLeftArrowParentIsTheNearestShallowerRowAbove() {
        func folder(_ path: String, depth: Int) -> ShellModel.SidebarRow {
            ShellModel.SidebarRow(id: .project(URL(fileURLWithPath: path)), title: path, kind: .Category, depth: depth)
        }
        let rows = [
            ShellModel.SidebarRow(id: .all, title: "All Notes", kind: .All),
            folder("/Work", depth: 0),
            folder("/Work/A", depth: 1),
            folder("/Work/A/Deep", depth: 2),
            folder("/Work/B", depth: 1),
            folder("/Archive", depth: 0),
        ]

        XCTAssertEqual(ShellModel.parentRow(of: 3, in: rows)?.id, rows[2].id)
        XCTAssertEqual(ShellModel.parentRow(of: 4, in: rows)?.id, rows[1].id)
        XCTAssertNil(ShellModel.parentRow(of: 5, in: rows))
        XCTAssertNil(ShellModel.parentRow(of: 0, in: rows))
    }

    /// V4.5.0 saved only a row number with All Notes at row 0; after the
    /// brand row took row 0 that number reopened the folder above.
    /// The lockup sat 23.5pt under the traffic lights and 27pt over All
    /// Notes, which read cramped at the top (maintainer, 2026-11-06). It now
    /// sits `sidebarBrandDrop` lower while the gap under it stays as it was.
    @MainActor
    func testTheBrandLockupDropsWithoutClosingTheGapUnderIt() throws {
        let cell = makeFolderCell()
        let outlineView = ReusingSidebar(frame: NSRect(x: 0, y: 0, width: 200, height: 300))
        outlineView.reusedCell = cell
        let brand = SidebarItem(name: "妙言", type: .Brand)
        let height = outlineView.outlineView(outlineView, heightOfRowByItem: brand)
        let drop = Theme.Metrics.sidebarBrandDrop
        XCTAssertEqual(height, 52 + drop)

        _ = try XCTUnwrap(outlineView.outlineView(outlineView, viewFor: nil, item: brand) as? SidebarCellView)
        cell.frame = NSRect(x: 0, y: 0, width: 200, height: height)
        cell.layoutSubtreeIfNeeded()
        // Auto Layout measures centerY downward; the cell is not flipped.
        let iconFromTop = height - cell.icon.frame.midY
        let iconToBottom = cell.icon.frame.midY
        let iconOffset = Theme.Metrics.sidebarBrandMarkIconOffsetY
        // Auto Layout snaps frames to device pixels: a half-point centre
        // lands half a point off on a 1x screen (CI) and exact on 2x.
        let snap = 0.5 / (NSScreen.main?.backingScaleFactor ?? 1) + 0.01
        XCTAssertEqual(iconFromTop, 26 + iconOffset + drop, accuracy: snap, "the lockup moves down by the drop")
        XCTAssertEqual(iconToBottom, 26 - iconOffset, accuracy: snap, "the gap under the lockup stays")
        XCTAssertEqual(height - cell.label.frame.midY, height / 2 + drop / 2, accuracy: snap, "the wordmark moves with the bird")
    }

    @MainActor
    func testAV450SidebarRowMovesDownOnceForTheBrandRow() throws {
        // Fixed names: a removed domain still leaves its empty plist in
        // ~/Library/Preferences, so UUID names left a file per run.
        let suite = "miaoyan-sidebar-row-tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(3, forKey: "lastProject")

        UserDefaultsManagement.migrateLegacySidebarRow(defaults)
        XCTAssertEqual(defaults.integer(forKey: "lastProject"), 4)
        UserDefaultsManagement.migrateLegacySidebarRow(defaults)
        XCTAssertEqual(defaults.integer(forKey: "lastProject"), 4, "the shift runs once")

        let pathSuite = "miaoyan-sidebar-path-tests"
        let withPath = try XCTUnwrap(UserDefaults(suiteName: pathSuite))
        withPath.removePersistentDomain(forName: pathSuite)
        defer { withPath.removePersistentDomain(forName: pathSuite) }
        withPath.set(3, forKey: "lastProject")
        withPath.set("/tmp/Work", forKey: "lastProjectPath")
        UserDefaultsManagement.migrateLegacySidebarRow(withPath)
        XCTAssertEqual(withPath.integer(forKey: "lastProject"), 3, "a folder saved by path is restored by path")
    }

    /// The folder list stays above the header in z-order. 4e081958 moved the
    /// header (`OutlineHeaderView`) after the list's scroll view to let the
    /// new-folder button sit over it, and AppKit then made no row views at
    /// all: the daily build showed an empty sidebar. The header comes first
    /// in the subviews, and the list is clear so the button shows through
    /// the 8pt they overlap.
    func testFolderListStaysAboveTheHeader() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let xml = try String(contentsOf: root.appendingPathComponent("Resources/Localization/Base.lproj/Main.storyboard"), encoding: .utf8)
        let header = try XCTUnwrap(xml.range(of: "id=\"vp7-cq-QSI\" customClass=\"OutlineHeaderView\""))
        let list = try XCTUnwrap(xml.range(of: "<scrollView ", options: .backwards, range: xml.startIndex..<XCTUnwrap(xml.range(of: "id=\"BdT-Ac-GAV\">")).upperBound))
        XCTAssertLessThan(header.lowerBound, list.lowerBound, "the header must be ordered below the folder list")
        let controller = try String(contentsOf: root.appendingPathComponent("Controllers/ViewController.swift"), encoding: .utf8)
        XCTAssertTrue(controller.contains("storageOutlineView.backgroundColor = .clear"))
    }

    /// The list overlaps the header's bottom 8pt and sits above it, so the
    /// lower part of the new-folder button lay under the list and a click
    /// there selected the brand row (All Notes) instead of adding a folder.
    @MainActor
    func testTheNewFolderButtonTakesClicksWhereTheListOverlapsIt() throws {
        let storage = StorageView(frame: NSRect(x: 0, y: 0, width: 170, height: 300))
        let header = OutlineHeaderView(frame: NSRect(x: 0, y: 264, width: 170, height: 36))
        let button = NSButton(frame: NSRect(x: 144, y: 2, width: 18, height: 18))
        header.addSubview(button)
        storage.addSubview(header)
        let list = NSScrollView(frame: NSRect(x: 0, y: 0, width: 170, height: 272))
        list.documentView = NSView(frame: list.bounds)
        storage.addSubview(list)
        let overlap = NSPoint(x: 153, y: 268)
        XCTAssertTrue(storage.hitTest(overlap) === button, "the button's lower part, under the list, still takes the click")
        XCTAssertFalse(storage.hitTest(NSPoint(x: 40, y: 268)) === button, "the rest of the overlap stays with the list")
        XCTAssertTrue(storage.hitTest(NSPoint(x: 153, y: 280)) === button, "above the list the button takes it as before")
    }
}
