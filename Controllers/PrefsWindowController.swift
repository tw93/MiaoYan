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
    private var hasRestoredAutosavedFrame = false

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.minSize = NSSize(width: 700, height: 520)
        window.maxSize = NSSize(width: 1200, height: 520)

        window.styleMask.remove(.resizable)
        window.styleMask.insert(.titled)
        window.styleMask.insert(.closable)
        window.styleMask.insert(.miniaturizable)
        let autosaveName: NSWindow.FrameAutosaveName = "ModernPreferencesWindow"
        let restoredFrame = window.setFrameUsingName(autosaveName)
        window.setFrameAutosaveName(autosaveName)
        window.isReleasedWhenClosed = false

        // Always use light appearance for settings panel
        window.appearance = NSAppearance(named: .aqua)

        self.init(window: window)
        hasRestoredAutosavedFrame = restoredFrame

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
        window?.title = ""
        window?.toolbarStyle = .preference
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
        sidebarView = PrefsSidebarView(frame: NSRect(x: 0, y: 0, width: 140, height: 400))
        sidebarView.delegate = self

        sidebarViewController = NSViewController()
        sidebarViewController.view = sidebarView

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.minimumThickness = 140
        sidebarItem.maximumThickness = 140
        sidebarItem.canCollapse = false

        sidebarItem.titlebarSeparatorStyle = .none

        splitViewController.addSplitViewItem(sidebarItem)
    }

    private func setupContent() {
        prefsContentViewController = NSViewController()
        let contentView = PrefsContentBackgroundView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))

        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.widthAnchor.constraint(equalToConstant: 600),
            contentView.heightAnchor.constraint(equalToConstant: 400),
        ])

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

        // Always use light appearance for settings panel
        window.appearance = NSAppearance(named: .aqua)
        window.contentView?.appearance = NSAppearance(named: .aqua)

        updateWindowBackgroundColors()
    }

    fileprivate func updateWindowBackgroundColors() {
        guard let window, let splitViewController else { return }

        // Get the effective appearance to ensure correct color resolution
        let effectiveAppearance = window.effectiveAppearance

        // Resolve the background color in the context of the window's appearance
        var backgroundColor: NSColor = .windowBackgroundColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            backgroundColor = NSColor(named: "mainBackground") ?? .windowBackgroundColor
        }

        window.backgroundColor = backgroundColor

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = backgroundColor.cgColor
        }

        let controllerView = splitViewController.view
        controllerView.wantsLayer = true
        controllerView.layer?.backgroundColor = backgroundColor.cgColor

        let splitView = splitViewController.splitView
        splitView.wantsLayer = true
        splitView.layer?.backgroundColor = backgroundColor.cgColor

        // Update prefsContentViewController view
        if let prefsView = prefsContentViewController?.view {
            prefsView.wantsLayer = true
            prefsView.layer?.backgroundColor = backgroundColor.cgColor
        }

        // Update sidebar view
        if let sidebarView = sidebarViewController?.view {
            sidebarView.wantsLayer = true
            sidebarView.layer?.backgroundColor = backgroundColor.cgColor
        }
    }
}

private final class PrefsContentBackgroundView: NSView {
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

// MARK: - Custom SplitView for Preferences
final class PrefsSplitView: NSSplitView {
    override func drawDivider(in rect: NSRect) {
        let appearance = window?.effectiveAppearance ?? effectiveAppearance

        // Get divider color in the correct appearance context
        var dividerColor: NSColor = .separatorColor
        appearance.performAsCurrentDrawingAppearance {
            dividerColor = NSColor(named: "divider") ?? .separatorColor
        }

        dividerColor.setFill()
        rect.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

extension PrefsWindowController {
    fileprivate func prepareWindowForDisplayIfNeeded() {
        guard let window else { return }

        window.contentView?.layoutSubtreeIfNeeded()

        if !hasPreparedWindowForDisplay {
            if !hasRestoredAutosavedFrame {
                window.center()
            }
            hasPreparedWindowForDisplay = true
        }
    }
}
