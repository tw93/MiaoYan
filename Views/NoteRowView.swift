import AppKit
import Cocoa

class NoteRowView: ThemedTableRowView {
    override func selectionRect() -> NSRect {
        let margin: CGFloat = 8
        let rowBounds = visibleRowBounds()
        return NSRect(
            x: rowBounds.minX + margin,
            y: 2,
            width: max(0, rowBounds.width - 2 * margin),
            height: max(0, bounds.height - 4)
        )
    }

    // Rows are parted by a 0.5pt hairline inset to the title, hidden beside
    // the selection plate (maintainer's pick, 2026-10-19). AppKit sets
    // `isNextRowSelected` in the same selection change as `isSelected`, so
    // the plate and the hidden lines redraw together; the selection rows the
    // list used to track by hand redrew a step apart and the lines flashed.
    override var isNextRowSelected: Bool {
        didSet {
            if oldValue != isNextRowSelected { needsDisplay = true }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            drawSelection(in: dirtyRect)
            return
        }
        guard !isNextRowSelected else { return }
        let inset: CGFloat = 20
        let height = 1 / (window?.backingScaleFactor ?? 2)
        let rowBounds = visibleRowBounds()
        let line = NSRect(
            x: rowBounds.minX + inset,
            y: bounds.height - height,
            width: max(0, rowBounds.width - 2 * inset),
            height: height
        )
        Theme.fillDivider(line, color: Theme.columnHairline, appearance: effectiveAppearance)
    }

    private func visibleRowBounds() -> NSRect {
        guard let tableView = enclosingNotesTableView(),
            let clipView = tableView.enclosingScrollView?.contentView
        else {
            return bounds
        }

        let visibleRect = convert(clipView.bounds, from: clipView)
        let clippedBounds = bounds.intersection(visibleRect)
        return clippedBounds.isNull || clippedBounds.isEmpty ? bounds : clippedBounds
    }

    private func enclosingNotesTableView() -> NotesTableView? {
        var parentView: NSView? = superview
        while let view = parentView {
            if let tableView = view as? NotesTableView {
                return tableView
            }
            parentView = view.superview
        }
        return nil
    }
}
