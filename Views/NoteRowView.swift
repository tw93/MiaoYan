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

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            drawSelection(in: dirtyRect)
            return
        }

        if shouldHideSeparator() {
            return
        }

        drawSeparator(in: dirtyRect)
    }

    private func shouldHideSeparator() -> Bool {
        if let tableView = enclosingNotesTableView() {
            return tableView.shouldHideNoteSeparator(for: self)
        }

        return false
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

    override func drawSeparator(in dirtyRect: NSRect) {
        let separatorHeight: CGFloat = 1.0
        let rowBounds = visibleRowBounds()
        let separatorRect = NSRect(
            x: rowBounds.minX + 20,
            y: bounds.height - separatorHeight,
            width: max(0, rowBounds.width - 40),
            height: separatorHeight
        )

        var dividerColor = Theme.noteSeparatorColor
        let app = self.effectiveAppearance
        var cg: CGColor?
        app.performAsCurrentDrawingAppearance {
            cg = dividerColor.cgColor
        }
        if let cg, let fixed = NSColor(cgColor: cg) {
            dividerColor = fixed
        }
        dividerColor.setFill()

        separatorRect.fill()
    }
}
