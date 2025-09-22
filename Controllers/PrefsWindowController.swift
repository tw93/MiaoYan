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
        splitViewController.splitView.isVertical = true
        splitViewController.splitView.dividerStyle = .thin

        splitViewController.splitView.autoresizesSubviews = false

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
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = Theme.backgroundColor.cgColor

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
}

extension PrefsWindowController {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window?.orderOut(self)
        return false
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
