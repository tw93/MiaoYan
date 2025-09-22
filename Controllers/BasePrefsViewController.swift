import Cocoa

@MainActor
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
    @objc func setupUI() {}
    @objc func setupValues() {}
}
