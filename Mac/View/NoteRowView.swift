import AppKit
import Cocoa

class NoteRowView: NSTableRowView {
    override var isEmphasized: Bool {
        set {}
        get {
            false
        }
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
        set {
            // Ignore attempts to set background color
        }
    }
    
    override func drawSelection(in dirtyRect: NSRect) {
        if isSelected {
            // Create subtle rounded selection like modern macOS notelist
            let margin: CGFloat = 8
            let cornerRadius: CGFloat = 6
            let selectionRect = NSRect(
                x: margin,
                y: 2,
                width: max(0, bounds.width - 2 * margin),
                height: bounds.height - 4
            )
            
            let path = NSBezierPath(roundedRect: selectionRect, xRadius: cornerRadius, yRadius: cornerRadius)
            
            // Use system-appropriate colors that work across all macOS versions
            if NSApp.effectiveAppearance.isDark {
                // Dark mode: subtle highlight with proper contrast
                NSColor(calibratedWhite: 0.25, alpha: 1.0).setFill()
            } else {
                // Light mode: system-like selection with proper contrast
                NSColor(calibratedWhite: 0.85, alpha: 1.0).setFill()
            }
            
            path.fill()
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        // Draw our custom selection if selected
        if isSelected {
            drawSelection(in: dirtyRect)
            return  // 选中的时候不画分割线，直接返回
        }

        // 检查是否需要隐藏分割线
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
                
                // 如果当前行是选中行的上一行，隐藏分割线
                if currentRowIndex == selectedRow - 1 {
                    return true
                }
                
                // 如果当前行是选中行的下一行，也隐藏分割线
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
        
        // Use subtle separator color that works across all macOS versions
        if NSApp.effectiveAppearance.isDark {
            NSColor(calibratedWhite: 0.15, alpha: 1.0).setFill()
        } else {
            NSColor(calibratedWhite: 0.92, alpha: 1.0).setFill()
        }
        
        separatorRect.fill()
    }
    
    override func drawBackground(in dirtyRect: NSRect) {
        // Override to prevent any background drawing
    }
}
