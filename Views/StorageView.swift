import Cocoa
import Foundation

@MainActor
class StorageView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        layer?.backgroundColor = Theme.backgroundColor.cgColor
    }
}
