import Cocoa

class NoteRowView: NSTableRowView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    override func drawSelection(in dirtyRect: NSRect) {
        if self.selectionHighlightStyle != .none {
            var selectionRect = NSInsetRect(self.bounds, 10, 0.5)
            
            if NSAppearance.current.isDark {
                NSColor(red: 0.27, green: 0.27, blue: 0.27, alpha: 1).setStroke()
                NSColor(red: 0.27, green: 0.27, blue: 0.27, alpha: 1).setFill()
            } else {
                NSColor(red: 0.86, green: 0.86, blue: 0.86, alpha: 1).setStroke()
                NSColor(red: 0.86, green: 0.86, blue: 0.86, alpha: 1).setFill()
            }
            var selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 4, yRadius: 4)
            if #available(OSX 10.15.8, *) {} else {
                selectionRect = NSInsetRect(self.bounds, 0, 0)
                selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 0, yRadius: 0)
            }
           
            selectionPath.fill()
            selectionPath.stroke()
        }
    }
}
