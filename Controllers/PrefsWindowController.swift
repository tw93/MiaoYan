import Cocoa

/// The Settings window: General, Editor and Fonts as a centred tab group on
/// the title bar's line, one fixed size for every tab, warm paper behind it.
@MainActor
final class PrefsWindowController: NSWindowController, NSWindowDelegate {
    private let generalPrefsVC = GeneralPrefsViewController()
    private let editorPrefsVC = EditorPrefsViewController()
    private let typographyPrefsVC = TypographyPrefsViewController()

    private let tabBar = PrefsTabBar(titles: PrefsSection.allCases.map(\.title))
    private let pageContainer = NSView()
    private(set) var currentCategory: PrefsSection = .general
    private var hasPreparedWindowForDisplay = false

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: PrefsMetrics.windowWidth, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // An empty unified toolbar makes the title bar the 52pt band the
        // tabs sit in, with the traffic lights centred on the same line.
        window.toolbar = NSToolbar(identifier: "MiaoYanSettingsToolbar")
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        self.init(window: window)
        window.delegate = self
        setupContent()
        applyWindowAppearance()

        NotificationCenter.default.addObserver(self, selector: #selector(updateAlwaysOnTopState), name: .alwaysOnTopChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .alwaysOnTopChanged, object: nil)
    }

    private var pages: [NSViewController] {
        PrefsSection.allCases.map(viewController(for:))
    }

    private func setupContent() {
        guard let window else { return }
        let root = PrefsRootView()
        window.contentView = root

        root.addSubview(tabBar)
        pageContainer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(pageContainer)
        NSLayoutConstraint.activate([
            tabBar.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            tabBar.centerYAnchor.constraint(equalTo: root.topAnchor, constant: PrefsMetrics.headerHeight / 2),
            pageContainer.topAnchor.constraint(equalTo: root.topAnchor, constant: PrefsMetrics.headerHeight),
            pageContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            pageContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            pageContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        tabBar.onSelect = { [weak self] index in
            self?.showCategory(PrefsSection.allCases[index])
        }

        // One height for every tab: the tallest tab's, so switching never
        // resizes the window and a longer tab would scroll inside it.
        let pageHeight = pages.compactMap { ($0 as? BasePrefsViewController)?.contentHeight }.max() ?? 360
        window.setContentSize(NSSize(width: PrefsMetrics.windowWidth, height: PrefsMetrics.headerHeight + ceil(pageHeight)))
        showCategory(.general)
    }

    private func showCategory(_ category: PrefsSection) {
        currentCategory = category
        let page = viewController(for: category)
        for child in pageContainer.subviews where child !== page.view {
            child.removeFromSuperview()
        }
        if page.view.superview !== pageContainer {
            page.view.translatesAutoresizingMaskIntoConstraints = false
            pageContainer.addSubview(page.view)
            NSLayoutConstraint.activate([
                page.view.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
                page.view.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
                page.view.topAnchor.constraint(equalTo: pageContainer.topAnchor),
                page.view.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor),
            ])
        }
        tabBar.select(index: PrefsSection.allCases.firstIndex(of: category) ?? 0)
        window?.title = category.title
    }

    private func viewController(for category: PrefsSection) -> BasePrefsViewController {
        switch category {
        case .general: return generalPrefsVC
        case .editor: return editorPrefsVC
        case .typography: return typographyPrefsVC
        }
    }

    func show() {
        if !hasPreparedWindowForDisplay {
            window?.center()
            hasPreparedWindowForDisplay = true
        }
        updateAlwaysOnTopState()
        showWindow(self)
        window?.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func updateAlwaysOnTopState() {
        window?.level = UserDefaultsManagement.alwaysOnTop ? .floating : .normal
    }

    func selectCategory(_ category: PrefsSection) {
        showCategory(category)
    }

    /// Follows a change of the Appearance setting while the window is open.
    func refreshThemeAppearance() {
        applyWindowAppearance()
    }

    private func applyWindowAppearance() {
        guard let window else { return }
        window.appearance =
            switch UserDefaultsManagement.appearanceType {
            case .Light: NSAppearance(named: .aqua)
            case .Dark: NSAppearance(named: .darkAqua)
            case .System, .Custom: nil
            }
        window.backgroundColor = Theme.Settings.background
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window?.orderOut(self)
        return false
    }
}

/// The window's opaque warm paper, title bar band included.
private final class PrefsRootView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.Settings.background.setFill()
        dirtyRect.fill()
    }
}
