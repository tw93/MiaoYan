import Cocoa

class EditorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if UserDefaultsManagement.appearanceType != AppearanceType.Custom {
            Theme.backgroundColor.setFill()
            __NSRectFill(dirtyRect)
        } else {
            layer?.backgroundColor = Theme.backgroundColor.cgColor
        }
    }
}
