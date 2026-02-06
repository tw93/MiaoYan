import AppKit
import Cocoa

class NoteRowView: ThemedTableRowView {
    override func selectionRect() -> NSRect {
        let margin: CGFloat = 11
        return NSRect(
            x: margin,
            y: 2,
            width: max(0, bounds.width - 2 * margin),
            height: bounds.height - 4
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
        var parentView: NSView? = superview
        while parentView != nil {
            if let tableView = parentView as? NotesTableView {
                guard !tableView.selectedRowIndexes.isEmpty else {
                    return false
                }

                let selectedRow = tableView.selectedRowIndexes.first!
                let currentRowIndex = tableView.row(for: self)

                if currentRowIndex == selectedRow - 1 {
                    return true
                }

                if currentRowIndex == selectedRow + 1 {
                    return true
                }

                return false
            }
            parentView = parentView?.superview
        }

        return false
    }

    override func drawSeparator(in dirtyRect: NSRect) {
        let separatorHeight: CGFloat = 1.0
        let separatorRect = NSRect(
            x: 20,
            y: bounds.height - separatorHeight,
            width: bounds.width - 40,
            height: separatorHeight
        )

        var dividerColor = Theme.dividerColor
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
