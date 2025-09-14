import Cocoa

/// Base class for preferences view controllers to eliminate duplicate setup code
class BasePrefsViewController: NSViewController {

    override func loadView() {
        setupBaseView()
        setupUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupValues()
    }

    private func setupBaseView() {
        if #available(macOS 10.14, *) {
            let effect = NSVisualEffectView()
            effect.state = .active
            effect.blendingMode = .withinWindow
            effect.material = .contentBackground
            view = effect
        } else {
            view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = (NSColor(named: "mainBackground") ?? NSColor.windowBackgroundColor).cgColor
        }
    }
}
