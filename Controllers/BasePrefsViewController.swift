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
        view = PrefsBackgroundView()
    }

    // MARK: - Hooks for subclasses
    @objc func setupUI() {}
    @objc func setupValues() {}
}

private final class PrefsBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        updateColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        let resolvedColor = Theme.backgroundColor.resolvedColor(for: appearance)
        layer?.backgroundColor = resolvedColor.cgColor
    }
}
