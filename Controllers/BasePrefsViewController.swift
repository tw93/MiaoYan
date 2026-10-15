import Cocoa

/// One Settings tab: rows in sections inside a scroll view, so every tab
/// shares the window's one height and a long tab scrolls instead of resizing
/// the window.
@MainActor
class BasePrefsViewController: NSViewController {
    private let stackView = NSStackView()

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        // The page already starts below the title bar band; the automatic
        // inset would push it down a second time.
        scrollView.automaticallyAdjustsContentInsets = false

        let documentView = PrefsFlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 0
        documentView.addSubview(stackView)

        let clipView = scrollView.contentView
        NSLayoutConstraint.activate([
            documentView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: clipView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: PrefsMetrics.sideInset),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -PrefsMetrics.sideInset),
            stackView.topAnchor.constraint(equalTo: documentView.topAnchor, constant: PrefsMetrics.pageTopInset),
            stackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -PrefsMetrics.pageBottomInset),
        ])

        view = scrollView
        setupUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupValues()
    }

    // MARK: - Hooks for subclasses
    @objc func setupUI() {}
    @objc func setupValues() {}

    /// The height this tab needs without scrolling; the window takes the
    /// tallest tab's.
    var contentHeight: CGFloat {
        _ = view
        return PrefsMetrics.pageTopInset + stackView.fittingSize.height + PrefsMetrics.pageBottomInset
    }

    /// Lays rows out in sections: a 12% hairline between sections, a 6.5%
    /// one between rows, no headings.
    func addSections(_ sections: [[NSView]]) {
        for (sectionIndex, rows) in sections.enumerated() {
            for (rowIndex, row) in rows.enumerated() {
                if sectionIndex > 0 || rowIndex > 0 {
                    append(PrefsHairline(color: rowIndex == 0 ? Theme.Settings.sectionHairline : Theme.Settings.rowHairline))
                }
                append(row)
            }
        }
    }

    private func append(_ view: NSView) {
        stackView.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    /// Restarts MiaoYan to apply a change that only takes effect at launch.
    @objc func restartToApply(_ sender: Any?) {
        UserDefaultsManagement.isFirstLaunch = true
        DispatchQueue.main.asyncAfter(deadline: .now() + UIDelay.short) {
            AppDelegate.relaunchApp()
        }
    }

    func makeRestartButton() -> PrefsPillButton {
        let button = PrefsPillButton(title: I18n.str("Restart"), target: self, action: #selector(restartToApply(_:)))
        button.isHidden = true
        return button
    }
}

private final class PrefsFlippedView: NSView {
    override var isFlipped: Bool { true }
}
