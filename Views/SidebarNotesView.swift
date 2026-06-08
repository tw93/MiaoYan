import Cocoa

@MainActor
class SidebarNotesView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        fillMiaoYanPaneBackground(dirtyRect)
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated { [self] in
            applyMiaoYanPaneBackground()
        }
    }
}
