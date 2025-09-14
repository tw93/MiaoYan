import Cocoa

class EditorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if UserDefaultsManagement.appearanceType != AppearanceType.Custom, #available(OSX 10.13, *) {
            Theme.backgroundColor.setFill()
            __NSRectFill(dirtyRect)
        } else {
            layer?.backgroundColor = Theme.backgroundColor.cgColor
        }
    }
}
