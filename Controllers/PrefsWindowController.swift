import Cocoa

@MainActor
final class PrefsWindowController: NSWindowController, NSWindowDelegate {
    private var splitViewController: NSSplitViewController!
    private var sidebarViewController: NSViewController!
    private var prefsContentViewController: NSViewController!
    private var sidebarView: PrefsSidebarView!

    private lazy var generalPrefsVC = GeneralPrefsViewController()
    private lazy var editorPrefsVC = EditorPrefsViewController()
    private lazy var typographyPrefsVC = TypographyPrefsViewController()

    private var currentCategory: PreferencesCategory = .general
    private var hasPreparedWindowForDisplay = false

    private enum Metrics {
        static let windowSize = NSSize(width: 800, height: 520)
        static let sidebarWidth: CGFloat = 176
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Metrics.windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.minSize = Metrics.windowSize
        window.maxSize = Metrics.windowSize

        window.styleMask.insert(.titled)
        window.styleMask.insert(.closable)
        window.styleMask.insert(.fullSizeContentView)
        window.isReleasedWhenClosed = false

        self.init(window: window)

        setupUIComponents()
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        if splitViewController == nil {
            setupUIComponents()
        }
    }

    private func setupUIComponents() {
        guard window != nil else { return }

        window?.delegate = self

        setupWindow()
        setupSplitView()
        setupSidebar()
        setupContent()
        showCategory(.general)
        applyWindowAppearance()

        window?.titleVisibility = .hidden
        window?.titlebarAppearsTransparent = true
        window?.title = currentCategory.title
        window?.toolbarStyle = .preference
        window?.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window?.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func setupWindow() {
        guard window != nil else {
            fatalError("PrefsWindowController window should be initialized during init")
        }
    }

    private func setupSplitView() {
        splitViewController = NSSplitViewController()

        // Replace default splitView with custom one
        let customSplitView = PrefsSplitView()
        customSplitView.isVertical = true
        customSplitView.dividerStyle = .thin
        customSplitView.autoresizesSubviews = false

        splitViewController.splitView = customSplitView

        splitViewController.splitViewItems.forEach { item in
            item.canCollapse = false
        }

        window?.contentViewController = splitViewController
    }

    private func setupSidebar() {
        sidebarView = PrefsSidebarView(frame: NSRect(x: 0, y: 0, width: Metrics.sidebarWidth, height: Metrics.windowSize.height))
        sidebarView.delegate = self

        sidebarViewController = NSViewController()
        sidebarViewController.view = sidebarView

        let sidebarItem = NSSplitViewItem(viewController: sidebarViewController)
        sidebarItem.minimumThickness = Metrics.sidebarWidth
        sidebarItem.maximumThickness = Metrics.sidebarWidth
        sidebarItem.canCollapse = false

        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.titlebarSeparatorStyle = .none

        splitViewController.addSplitViewItem(sidebarItem)
    }

    private func setupContent() {
        prefsContentViewController = NSViewController()
        let contentView = PrefsContentBackgroundView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: Metrics.windowSize.width - Metrics.sidebarWidth,
                height: Metrics.windowSize.height
            ))
        prefsContentViewController.view = contentView

        let contentItem = NSSplitViewItem(viewController: prefsContentViewController)
        contentItem.canCollapse = false

        splitViewController.addSplitViewItem(contentItem)
    }

    private func showCategory(_ category: PreferencesCategory) {
        currentCategory = category

        if let currentVC = prefsContentViewController.children.first {
            currentVC.removeFromParent()
            currentVC.view.removeFromSuperview()
        }

        let newVC = viewController(for: category)
        window?.title = category.title

        prefsContentViewController.addChild(newVC)

        newVC.view.translatesAutoresizingMaskIntoConstraints = false
        prefsContentViewController.view.addSubview(newVC.view)

        NSLayoutConstraint.activate([
            newVC.view.leadingAnchor.constraint(equalTo: prefsContentViewController.view.leadingAnchor),
            newVC.view.trailingAnchor.constraint(equalTo: prefsContentViewController.view.trailingAnchor),
            newVC.view.topAnchor.constraint(equalTo: prefsContentViewController.view.topAnchor),
            newVC.view.bottomAnchor.constraint(equalTo: prefsContentViewController.view.bottomAnchor),
        ])

        sidebarView?.selectCategory(category)
    }

    private func viewController(for category: PreferencesCategory) -> NSViewController {
        switch category {
        case .general:
            return generalPrefsVC
        case .typography:
            return typographyPrefsVC
        case .editor:
            return editorPrefsVC
        }
    }

    func show() {
        if !isWindowLoaded {
            _ = window
        }

        prepareWindowForDisplayIfNeeded()

        showWindow(self)
        window?.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    func selectCategory(_ category: PreferencesCategory) {
        showCategory(category)
    }
}

extension PrefsWindowController: PrefsSidebarDelegate {
    func sidebarDidSelectCategory(_ category: PreferencesCategory) {
        guard category != currentCategory else { return }
        showCategory(category)
    }

    func refreshThemeAppearance() {
        updateWindowBackgroundColors()
        sidebarView?.refreshAppearance()
    }
}

extension PrefsWindowController {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window?.orderOut(self)
        return false
    }

    func windowDidChangeEffectiveAppearance(_ notification: Notification) {
        applyWindowAppearance()
    }
}

extension PrefsWindowController {
    fileprivate func applyWindowAppearance() {
        guard let window else { return }

        let targetAppearance: NSAppearance? =
            switch UserDefaultsManagement.appearanceType {
            case .Light: NSAppearance(named: .aqua)
            case .Dark: NSAppearance(named: .darkAqua)
            case .System, .Custom: nil
            }

        window.appearance = targetAppearance
        window.contentView?.appearance = targetAppearance

        updateWindowBackgroundColors()

        // Ensure subviews refresh their appearance
        sidebarView?.refreshAppearance()
    }

    fileprivate func updateWindowBackgroundColors() {
        guard let window else { return }

        let effectiveAppearance = window.effectiveAppearance
        var backgroundColor: NSColor = .windowBackgroundColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            backgroundColor = Theme.settingsWindowBackgroundColor
        }

        window.backgroundColor = backgroundColor
    }
}

private final class PrefsContentBackgroundView: NSView {
    override var isFlipped: Bool { true }

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
        let resolvedColor = Theme.settingsContentBackgroundColor.resolvedColor(for: appearance)
        layer?.backgroundColor = resolvedColor.cgColor
    }
}

// MARK: - Custom SplitView for Preferences
final class PrefsSplitView: NSSplitView {
    override func drawDivider(in rect: NSRect) {
        Theme.settingsDividerColor.resolvedColor(for: effectiveAppearance).setFill()

        guard Theme.usesModernSystemChrome else {
            rect.fill()
            return
        }

        NSBezierPath(rect: hairlineRect(in: rect)).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func hairlineRect(in rect: NSRect) -> NSRect {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let thickness = 1 / scale

        if isVertical {
            return NSRect(
                x: rect.midX - thickness / 2,
                y: rect.minY,
                width: thickness,
                height: rect.height
            )
        }

        return NSRect(
            x: rect.minX,
            y: rect.midY - thickness / 2,
            width: rect.width,
            height: thickness
        )
    }
}

extension PrefsWindowController {
    fileprivate func prepareWindowForDisplayIfNeeded() {
        guard let window else { return }

        window.contentView?.layoutSubtreeIfNeeded()

        if !hasPreparedWindowForDisplay {
            window.setContentSize(Metrics.windowSize)
            window.center()
            hasPreparedWindowForDisplay = true
        }
    }
}
