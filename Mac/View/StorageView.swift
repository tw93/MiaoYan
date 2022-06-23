import Cocoa
import Foundation

class StorageView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        layer?.backgroundColor = NSColor(red:0.96, green:0.96, blue:0.96, alpha:1.0).cgColor
    }
    override func awakeFromNib() {
        var f = self.frame
        f.size.width = 138
        self.frame = f
        self.setFrameSize(f.size)
        self.setBoundsSize(f.size)
    }
}
