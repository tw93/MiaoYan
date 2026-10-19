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

    // Rows are parted by space alone, as in the shell's list: a line under
    // each row had to be hidden next to the selection plate and flickered as
    // the selection moved (maintainer, 2026-10-19).
    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            drawSelection(in: dirtyRect)
        }
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
