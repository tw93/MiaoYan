import AppKit
import Cocoa

class NoteRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get {
            false
        }
        set {}
    }

    override var isSelected: Bool {
        didSet {
            if oldValue != isSelected {
                needsDisplay = true
            }
        }
    }

    override var backgroundColor: NSColor {
        get {
            return .clear
        }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {
        if isSelected {
            // Make selection slightly narrower to avoid system border overlap
            let margin: CGFloat = 11
            let cornerRadius: CGFloat = 8
            let selectionRect = NSRect(
                x: margin,
                y: 2,
                width: max(0, bounds.width - 2 * margin),
                height: bounds.height - 4
            )

            let path = NSBezierPath(roundedRect: selectionRect, xRadius: cornerRadius, yRadius: cornerRadius)

            Theme.selectionBackgroundColor.setFill()

            path.fill()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Draw our custom selection if selected
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
        // Find the table view by walking up the view hierarchy
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
        // Draw a subtle separator line at the bottom
        let separatorHeight: CGFloat = 1.0
        let separatorRect = NSRect(
            x: 20,
            y: bounds.height - separatorHeight,
            width: bounds.width - 40,
            height: separatorHeight
        )

        // Use divider color from Assets, resolved for current appearance
        var dividerColor = NSColor(named: "divider") ?? NSColor.separatorColor
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

    override func drawBackground(in dirtyRect: NSRect) {
        // Override to prevent any background drawing
    }
}
