import Cocoa

class NoteRowView: NSTableRowView {
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
            
    override var isEmphasized: Bool {
        set {}
        get {
            false
        }
    }
}
