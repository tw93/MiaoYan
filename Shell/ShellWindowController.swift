import AppKit
import KeyboardShortcuts
import SwiftUI

/// Hosts the SwiftUI shell in a window of its own. Until it reaches parity
/// with the storyboard window it opens only when launched with
/// `-MiaoYanShell YES` (an Xcode scheme argument), so the shipping window is
/// untouched.
@available(macOS 14, *)
final class ShellWindowController: NSWindowController, NSWindowDelegate {
    static var isRequested: Bool {
        UserDefaults.standard.bool(forKey: "MiaoYanShell")
    }

    let model = ShellModel()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 720, height: 420)
        window.backgroundColor = ShellPalette.background
        window.isReleasedWhenClosed = false
        // An empty unified toolbar gives the title bar Notes' 52pt height and
        // centres the traffic lights in it; the columns draw their own
        // controls on that line.
        window.toolbar = NSToolbar(identifier: "MiaoYanShellToolbar")
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        super.init(window: window)

        window.contentViewController = ShellSplitViewController(model: model)
        // The panes have no preferred size, so assigning the controller
        // shrinks the window to its minimum; restore the default first.
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.delegate = self
        if !window.setFrameUsingName("MiaoYanShellWindow") {
            window.center()
        }
        window.setFrameAutosaveName("MiaoYanShellWindow")
        applyWindowLevel()
        windowLevelObserver = NotificationCenter.default.addObserver(
            forName: .alwaysOnTopChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyWindowLevel() }
        }
        KeyboardShortcuts.onKeyUp(for: .activateWindow) { [weak self] in
            self?.toggleFrontmost()
        }
        observePresentation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Window level and activation

    private var windowLevelObserver: NSObjectProtocol?

    /// View ▸ Always on Top, applied the way `MainWindowController` does.
    private func applyWindowLevel() {
        window?.level = UserDefaultsManagement.alwaysOnTop ? .floating : .normal
    }

    /// The activate shortcut and Window ▸ Active Window: hide MiaoYan when it
    /// is already in front, otherwise bring this window forward.
    func toggleFrontmost() {
        guard let window else { return }
        if NSApp.isActive, !NSApp.isHidden, !window.isMiniaturized {
            NSApp.hide(nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Presentation

    private var escapeMonitor: Any?

    /// Presentation fills the screen; leaving full screen by any route, or
    /// pressing Escape, ends it.
    func observePresentation() {
        let presenting = withObservationTracking {
            model.isPresenting
        } onChange: { [weak self] in
            Task { @MainActor in self?.observePresentation() }
        }
        guard let window else { return }
        let isFullScreen = window.styleMask.contains(.fullScreen)
        if presenting {
            if !isFullScreen { window.toggleFullScreen(nil) }
            escapeMonitor =
                escapeMonitor
                ?? NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard event.keyCode == 53, let self, self.model.isPresenting else { return event }
                    self.model.setPresenting(false)
                    return nil
                }
        } else {
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
            escapeMonitor = nil
            if isFullScreen, didEnterFullScreenForPresentation { window.toggleFullScreen(nil) }
        }
    }

    private var didEnterFullScreenForPresentation = false

    func windowDidEnterFullScreen(_ notification: Notification) {
        didEnterFullScreenForPresentation = model.isPresenting
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        didEnterFullScreenForPresentation = false
        model.setPresenting(false)
    }

    func windowWillClose(_ notification: Notification) {
        model.setPresenting(false)
    }
}

/// Folders, notes and the open note side by side. The split stays AppKit so
/// the panes keep their widths when the window resizes and the dividers are
/// remembered; each pane is SwiftUI. Plain split items, not the sidebar kind,
/// so no translucent material appears behind the folders.
@available(macOS 14, *)
final class ShellSplitViewController: NSSplitViewController {
    private let model: ShellModel

    init(model: ShellModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        splitView = ShellSplitView()
        super.loadView()
    }

    override func viewDidLoad() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let sidebar = NSSplitViewItem(viewController: Self.host(ShellSidebar(model: model)))
        sidebar.minimumThickness = 150
        sidebar.maximumThickness = 280
        sidebar.canCollapse = true
        sidebar.holdingPriority = NSLayoutConstraint.Priority(260)

        let list = NSSplitViewItem(viewController: Self.host(ShellNoteList(model: model)))
        list.canCollapse = true
        list.minimumThickness = Theme.Metrics.noteListMinimumWidth
        list.maximumThickness = 420
        list.holdingPriority = NSLayoutConstraint.Priority(255)

        let detail = NSSplitViewItem(viewController: Self.host(ShellDetail(model: model)))
        detail.minimumThickness = 320
        detail.holdingPriority = NSLayoutConstraint.Priority(240)

        for item in [sidebar, list, detail] {
            addSplitViewItem(item)
        }
        splitView.autosaveName = "MiaoYanShellSplit"
        super.viewDidLoad()
        model.host = self
        observeLayout()
    }

    /// Collapses the folders and the list as the layout button cycles.
    private func observeLayout() {
        let layout = withObservationTracking {
            model.layout
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeLayout() }
        }
        let items = splitViewItems
        guard items.count == 3 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            items[0].animator().isCollapsed = layout != .all
            items[1].animator().isCollapsed = layout == .noteOnly
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !hasAppliedDefaultWidths else { return }
        hasAppliedDefaultWidths = true
        // First launch only: the autosaved positions win afterwards.
        if UserDefaults.standard.object(forKey: "NSSplitView Subview Frames MiaoYanShellSplit") == nil {
            splitView.setPosition(180, ofDividerAt: 0)
            splitView.setPosition(180 + 1 + 280, ofDividerAt: 1)
        }
    }

    private var hasAppliedDefaultWidths = false

    /// Without clearing `sizingOptions` the hosting controllers would size
    /// the panes to their SwiftUI content instead of leaving that to the split.
    private static func host(_ view: some View) -> NSViewController {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = []
        return controller
    }
}

/// Every column shares one tone, so each divider is a hairline.
@available(macOS 14, *)
final class ShellSplitView: NSSplitView {
    override func drawDivider(in rect: NSRect) {
        ShellPalette.background.setFill()
        rect.fill()
        ShellPalette.hairline.setFill()
        rect.fill(using: .sourceOver)
    }
}
