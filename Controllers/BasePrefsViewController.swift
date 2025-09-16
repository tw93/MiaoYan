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
        let effect = NSVisualEffectView()
        effect.state = .active
        effect.blendingMode = .withinWindow
        effect.material = .contentBackground
        view = effect
    }

    // MARK: - Hooks for subclasses
    // Subclasses can override these to build UI and populate values.
    @objc func setupUI() {}
    @objc func setupValues() {}
}

