import Cocoa

final class PrefsWindowController: NSWindowController, NSWindowDelegate {
    private var splitViewController: NSSplitViewController!
    private var sidebarViewController: NSViewController!
    private var prefsContentViewController: NSViewController!
    private var sidebarView: PrefsSidebarView!

    private lazy var generalPrefsVC = GeneralPrefsViewController()
    private lazy var editorPrefsVC = EditorPrefsViewController()
    private lazy var typographyPrefsVC = TypographyPrefsViewController()

    private var currentCategory: PreferencesCategory = .general

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 1000),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        // Configure window properties
        window.minSize = NSSize(width: 700, height: 520)
        window.maxSize = NSSize(width: 1200, height: 1400)
        window.setFrameAutosaveName("ModernPreferencesWindow")
        window.isReleasedWhenClosed = false

        self.init(window: window)

        // Manually trigger UI setup since windowDidLoad might not be called
        DispatchQueue.main.async {
            self.setupUIComponents()
        }
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        setupUIComponents()
    }

    private func setupUIComponents() {
        window?.delegate = self

        // Initialize UI components in proper order
        setupWindow()
        setupSplitView()
        setupSidebar()
        setupContent()
        showCategory(.general)

        window?.title = I18n.str("Preferences")
        if #available(macOS 11.0, *) {
            window?.toolbarStyle = .preference
        }
        window?.center()
    }

    private func setupWindow() {
        // Window is already configured in init, just verify it exists
        guard window != nil else {
            fatalError("PrefsWindowController window should be initialized during init")
        }
    }

    private func setupSplitView() {
        splitViewController = NSSplitViewController()
        splitViewController.splitView.isVertical = true
        splitViewController.splitView.dividerStyle = .thin

        // Configure split view behavior
        if #available(macOS 11.0, *) {
            splitViewController.splitViewItems.forEach { item in
                item.canCollapse = false
            }
        }

        window?.contentViewController = splitViewController
    }

    private func setupSidebar() {
        sidebarView = PrefsSidebarView(frame: NSRect(x: 0, y: 0, width: 140, height: 400))
        sidebarView.delegate = self

        sidebarViewController = NSViewController()
        sidebarViewController.view = sidebarView

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.minimumThickness = 130
        sidebarItem.maximumThickness = 145
        sidebarItem.canCollapse = false

        if #available(macOS 11.0, *) {
            sidebarItem.titlebarSeparatorStyle = .none
        }

        splitViewController.addSplitViewItem(sidebarItem)
    }

    private func setupContent() {
        print("[DEBUG] Setting up content view")
        prefsContentViewController = NSViewController()
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = (NSColor(named: "mainBackground") ?? NSColor.controlBackgroundColor).cgColor
        prefsContentViewController.view = contentView

        let contentItem = NSSplitViewItem(viewController: prefsContentViewController)
        contentItem.canCollapse = false

        splitViewController.addSplitViewItem(contentItem)
        print("[DEBUG] Content view setup completed")
    }

    private func showCategory(_ category: PreferencesCategory) {
        currentCategory = category

        // Remove current content view controller
        if let currentVC = prefsContentViewController.children.first {

            currentVC.removeFromParent()
            currentVC.view.removeFromSuperview()
        }

        // Add new content view controller
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


        window?.title = "\(I18n.str("Preferences")) - \(category.title)"


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
        // Force load the window if it hasn't been loaded yet
        if !isWindowLoaded {
            _ = window
        }

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
}

extension PrefsWindowController {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window?.orderOut(self)
        return false
    }
}
