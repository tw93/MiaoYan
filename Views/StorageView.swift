import Cocoa
import Foundation

@MainActor
class StorageView: NSVisualEffectView {
    override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated { [self] in
            configureSidebarMaterial()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureSidebarMaterial()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        configureSidebarMaterial()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        configureSidebarMaterial()

        fillMiaoYanPaneBackground(dirtyRect)
        applyMiaoYanPaneBackground()
    }

    private func configureSidebarMaterial() {
        material = .contentBackground
        blendingMode = .withinWindow
        state = .inactive
        isEmphasized = false
        applyMiaoYanPaneBackground()
    }
}
