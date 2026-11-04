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

    /// The folder list runs 8pt up under the header and sits above it in
    /// z-order (I-15), so the lower part of the new-folder button lies under
    /// the list. A click there belongs to the button, not to the brand row.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for case let header as OutlineHeaderView in subviews where !header.isHidden {
            if let control = header.hitTest(local) as? NSControl, control.isEnabled {
                return control
            }
        }
        return super.hitTest(point)
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
