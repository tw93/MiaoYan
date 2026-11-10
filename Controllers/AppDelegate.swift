import Cocoa
import KeyboardShortcuts
import Sparkle
import os.log

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    var mainWindowController: MainWindowController?
    /// The SwiftUI main window, opened instead of the storyboard one only
    /// under `-MiaoYanShell YES`.
    var shellWindowController: NSWindowController?
    var prefsWindowController: PrefsWindowController?
    var aboutWindowController: AboutWindowController?
    public var urls: [URL]?
    public var searchQuery: String?
    public var newName: String?
    public var newContent: String?
    /// A miaoyan://goto that arrived before the window, as the CLI's
    /// `miao open` sends when it launches the app.
    public var pendingGoto: URL?
    let appContext = AppContext.shared
    private var updaterController: SPUStandardUpdaterController?

    private func resolveViewController() -> ViewController? {
        if let cached = appContext.viewController {
            return cached
        }

        let candidates: [NSViewController?] = [
            mainWindowController?.window?.contentViewController,
            mainWindowController?.contentViewController,
            NSApp.mainWindow?.contentViewController,
            NSApp.keyWindow?.contentViewController,
        ]

        for candidate in candidates {
            if let vc = candidate as? ViewController {
                appContext.bind(viewController: vc)
                return vc
            }
        }

        return nil
    }
    var appTitle: String {
        if let display = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            return display
        }
        return Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String ?? "MiaoYan"
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        migratePreferences()
        UserDefaultsManagement.migrateFontDefaultsIfNeeded()
        UserDefaultsManagement.clearSingleMode()
        let storage = appContext.storage
        storage.loadProjects()
        storage.loadDocuments {}
    }

    /// The preferences domain from before the bundle id was lowercased. On a
    /// case-insensitive volume it is the same file as `com.tw93.miaoyan`'s,
    /// so a build with any other bundle id (`com.tw93.miaoyan.qa` for local
    /// tests) read the maintainer's real settings through it and copied them
    /// in on first launch, fonts and library location included.
    static let legacyPreferencesDomain = "com.tw93.MiaoYan"
    static let shippedBundleIdentifier = "com.tw93.miaoyan"
    static let legacyMigrationKey = "HasMigratedFromOldSuite"

    private func migratePreferences() {
        Self.migrateLegacyPreferences(
            into: UserDefaults.standard,
            legacy: UserDefaults.standard.persistentDomain(forName: Self.legacyPreferencesDomain),
            bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    /// Copies keys the standard domain lacks from the legacy domain, once, and
    /// only for the shipped bundle id. `legacy` is that domain's own keys, not
    /// a suite's `dictionaryRepresentation()`, which also carries the global
    /// domain (AppleLanguages and the like).
    static func migrateLegacyPreferences(into standard: UserDefaults, legacy: [String: Any]?, bundleIdentifier: String?) {
        guard bundleIdentifier == shippedBundleIdentifier else { return }
        guard !standard.bool(forKey: legacyMigrationKey) else { return }
        for (key, value) in legacy ?? [:] where standard.object(forKey: key) == nil {
            standard.set(value, forKey: key)
        }
        standard.set(true, forKey: legacyMigrationKey)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil)

        NSApp.mainMenu?.applyMenuIcons()
        Self.applyMenuShortcuts(to: NSApp.mainMenu)

        NSApp.mainMenu?.update()

        configureSystemLogging()
        NSFontManager.shared.fontPanel(false)?.orderOut(self)

        applyAppearance()

        addGlobalKeyboardMonitor()
        if UserDefaultsManagement.storagePath == nil {
            requestStorageDirectory()
            return
        }
        // Option-Command-M brings the window forward unless someone set
        // another key; both windows need it, so it is set before either opens.
        if KeyboardShortcuts.getShortcut(for: .activateWindow) == nil {
            KeyboardShortcuts.setShortcut(.init(.m, modifiers: [.command, .option]), for: .activateWindow)
        }
        if #available(macOS 14, *), ShellWindowController.isRequested {
            let shell = ShellWindowController()
            shell.showWindow(nil)
            shellWindowController = shell
            // A file double-clicked in Finder can arrive before the window.
            // So can a link that arrived before it.
            if let url = urls?.first {
                urls = nil
                shell.model.openSingle(url, siblingFiles: Self.siblingNoteFiles(of: url))
            } else if let query = searchQuery {
                searchQuery = nil
                shell.model.search(for: query)
            } else if newName != nil || newContent != nil {
                shell.model.createNote(name: newName ?? "", content: newContent ?? "")
                newName = nil
                newContent = nil
            } else if let goto = pendingGoto {
                pendingGoto = nil
                RouteMiaoYanGoto(goto)
            }
            return
        }
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        guard let mainWC = storyboard.instantiateController(withIdentifier: "MainWindowController") as? MainWindowController else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = I18n.str("Critical Error")
            alert.informativeText = I18n.str("Failed to initialize main window. Please restart the application.")
            alert.addButton(withTitle: I18n.str("Quit"))
            alert.runModal()

            NSApplication.shared.terminate(nil)
            return
        }
        normalizeMainWindowFrame(mainWC.window)

        // Apply fade-in for first launch to match re-open behavior and hide initial blank state
        mainWC.window?.alphaValue = 0
        mainWC.window?.makeKeyAndOrderFront(nil)

        mainWindowController = mainWC
        appContext.bind(viewController: mainWC.window?.contentViewController as? ViewController)
        normalizeMainWindowFrame(mainWC.window)
        DispatchQueue.main.async { [weak self, weak window = mainWC.window] in
            self?.normalizeMainWindowFrame(window)
        }

        mainWC.applyMiaoYanAppearance()

        // Failsafe: Ensure window reveals after 3 seconds even if list loading hangs or fails
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            mainWC.revealWindowWhenReady()
        }

    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppEnvironment.current.storage.deferUntilFolderMoveFinishes({
            sender.reply(toApplicationShouldTerminate: true)
        }) {
            return .terminateLater
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        UserDefaultsManagement.clearSingleMode()
        if let vc = resolveViewController() {
            vc.persistCurrentViewState()
            // Capture the current editor buffer into the active note before
            // we drain the debounce queue, otherwise an in-flight keystroke
            // from the last 1.5s would never reach Note.content.
            // Only while the editor shows the note: in preview a ticked task is
            // saved to the note alone, and the hidden buffer would undo it.
            if let activeNote = EditTextView.note, vc.shouldUseEditorTextContent {
                vc.editArea.saveTextStorageContent(to: activeNote)
            }
            vc.storage.flushPendingSaves()
        } else if #available(macOS 14, *), let shell = shellWindowController as? ShellWindowController {
            shell.flushEdits()
        }
        try? FileManager.default.removeItem(at: HtmlManager.previewBundleURL())
        var temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        temporary.appendPathComponent("ThumbnailsBig")
        try? FileManager.default.removeItem(at: temporary)
    }

    static func trackError(_ error: Error, context: String) {
        #if DEBUG
            print("Error in \(context): \(error)")
        #endif
        Diagnostics.record(error: error, context: context)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            applyAppearance()
            mainWindowController?.makeNew()
            shellWindowController?.showWindow(nil)
        }
        return true
    }

    func applyAppearance() {
        if UserDefaultsManagement.appearanceType != .Custom {
            var targetAppearance: NSAppearance?
            var isDark = false

            switch UserDefaultsManagement.appearanceType {
            case .Dark:
                targetAppearance = NSAppearance(named: .darkAqua)
                isDark = true
            case .Light:
                targetAppearance = NSAppearance(named: .aqua)
                isDark = false
            case .System:
                targetAppearance = nil
                isDark = NSAppearance.current.isDark
            default:
                targetAppearance = nil
                isDark = NSAppearance.current.isDark
            }

            UserDataService.instance.isDark = isDark

            if NSApp.appearance != targetAppearance {
                NSApp.appearance = targetAppearance
            }
        }
    }

    private func restartApp() {
        AppDelegate.relaunchApp()
    }

    private func requestStorageDirectory() {
        var directoryURL: URL?
        if let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
            directoryURL = URL(fileURLWithPath: path)
        }
        let panel = NSOpenPanel()
        panel.directoryURL = directoryURL
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = I18n.str("Please select default storage directory")
        panel.begin { result in
            if result == NSApplication.ModalResponse.OK {
                guard let url = panel.url else {
                    return
                }
                do {
                    try StorageLocationValidator.validateWritableDirectory(url)
                } catch {
                    self.showStorageDirectoryError(error) {
                        self.requestStorageDirectory()
                    }
                    return
                }
                // Bookmark first: storageUrl prefers it, so a failed bookmark
                // with a saved path would reopen the old folder.
                do {
                    let bookmarkData = try url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil)
                    UserDefaultsManagement.storageBookmark = bookmarkData
                } catch {
                    AppDelegate.trackError(error, context: "AppDelegate.requestStorageDirectory.bookmarkData")
                    self.showStorageDirectoryError(error) {
                        self.requestStorageDirectory()
                    }
                    return
                }
                UserDefaultsManagement.storagePath = url.path
                self.restartApp()
            } else {
                exit(EXIT_SUCCESS)
            }
        }
    }

    private func showStorageDirectoryError(_ error: Error, completion: @escaping () -> Void) {
        let message: String
        if let validationError = error as? StorageLocationValidationError {
            message = validationError.localizedMessage
        } else {
            message = error.localizedDescription
        }
        MiaoYanAlert.show(
            message: I18n.str("Could not use this folder"),
            informativeText: message,
            style: .warning,
            for: NSApp.keyWindow ?? NSApp.mainWindow
        ) { _ in
            completion()
        }
    }

    private func normalizeMainWindowFrame(_ window: NSWindow?) {
        guard let window else { return }

        let savedFrame = window.frame
        let isOffScreen = NSScreen.screens.allSatisfy { screen in
            !screen.visibleFrame.intersects(savedFrame)
        }
        let layoutMinimum = NSSize(width: 1100, height: 680)
        let isTooSmall = savedFrame.width < layoutMinimum.width || savedFrame.height < layoutMinimum.height

        window.minSize = NSSize(width: 960, height: 600)

        guard UserDefaultsManagement.isFirstLaunch || isTooSmall || isOffScreen else { return }

        let preferredSize = NSSize(width: 1280, height: 760)
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let targetFrame: NSRect
        if let visibleFrame {
            let size = NSSize(
                width: min(preferredSize.width, max(900, visibleFrame.width - 40)),
                height: min(preferredSize.height, max(620, visibleFrame.height - 40))
            )
            targetFrame = NSRect(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        } else {
            targetFrame = NSRect(origin: savedFrame.origin, size: preferredSize)
        }

        window.setFrame(targetFrame, display: true)
    }

    // MARK: IBActions
    @IBAction func openMainWindow(_ sender: Any) {
        mainWindowController?.makeNew()
        shellWindowController?.showWindow(nil)
    }

    /// Quit, for both windows. Active Window's storyboard item targets a
    /// stand-in `ViewController`; the shell points it at the first responder,
    /// and the app delegate is the one link of that chain that is there
    /// whichever window is in front.
    @IBAction func quiteApp(_ sender: Any?) {
        guard UserDefaultsManagement.isSingleMode else {
            NSApp.terminate(sender)
            return
        }
        UserDefaultsManagement.clearSingleMode()
        UserDefaultsManagement.isFirstLaunch = true
        DispatchQueue.main.asyncAfter(deadline: .now() + UIDelay.short) {
            NSApp.terminate(nil)
        }
    }

    @IBAction func activeWindow(_ sender: Any?) {
        if #available(macOS 14, *), let shell = shellWindowController as? ShellWindowController {
            shell.toggleFrontmost()
        }
    }
    @IBAction func checkForUpdates(_ sender: Any?) {
        updaterController?.checkForUpdates(sender)
    }
    @IBAction func openPreferences(_ sender: Any?) {
        if prefsWindowController == nil {
            prefsWindowController = PrefsWindowController()
        }
        prefsWindowController?.show()
    }
    @IBAction func new(_ sender: Any?) {
        if #available(macOS 14, *), let shell = shellWindowController as? ShellWindowController {
            shell.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            shell.fileMenuNewNote(sender)
            return
        }
        mainWindowController?.makeNew()
        NSApp.activate(ignoringOtherApps: true)
        resolveViewController()?.fileMenuNewNote(self)
    }
    /// File ▸ New Note with the shell window closed: the item targets the
    /// first responder there, so with no window it reaches this delegate,
    /// which brings the window back first as the storyboard window does.
    @IBAction func fileMenuNewNote(_ sender: Any?) { new(sender) }
    @IBAction func searchAndCreate(_ sender: Any?) {
        if #available(macOS 14, *), let shell = shellWindowController as? ShellWindowController {
            shell.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            shell.searchAndCreate(sender)
            return
        }
        mainWindowController?.makeNew()
        NSApp.activate(ignoringOtherApps: true)
        guard let vc = resolveViewController() else { return }
        DispatchQueue.main.async {
            vc.search.window?.makeFirstResponder(vc.search)
        }
    }
    /// The iPhone and iPad app's App Store page: a menu item and a line in
    /// About, nothing that appears on its own.
    static let mobileAppURL = URL(string: "https://apps.apple.com/app/miaoyan/id6759252269")

    @IBAction func openMobileApp(_ sender: Any?) {
        guard let url = AppDelegate.mobileAppURL else { return }
        NSWorkspace.shared.open(url)
    }

    @IBAction func showAboutWindow(_ sender: AnyObject) {
        if aboutWindowController == nil {
            let storyboard = NSStoryboard(name: "Main", bundle: nil)
            aboutWindowController = storyboard.instantiateController(withIdentifier: "About") as? AboutWindowController
        }
        guard let aboutWindowController = aboutWindowController else { return }
        aboutWindowController.showWindow(nil)
        aboutWindowController.window?.makeKeyAndOrderFront(aboutWindowController)
        NSApp.activate(ignoringOtherApps: true)
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == NSEvent.EventType.leftMouseDown {
            mainWindowController?.makeNew()
        }
    }

    /// Clean Unused Attachments is Shift-Option-Command-Delete. The storyboard
    /// stores Control-Option-Command, which only the storyboard window
    /// rewrote, while validating its menu; set once here, both windows show
    /// and take the same keys.
    static func applyMenuShortcuts(to menu: NSMenu?) {
        for item in menu?.items ?? [] {
            if item.identifier?.rawValue == "cleanAttachmentsMenu" {
                item.keyEquivalentModifierMask = [.command, .option, .shift]
            }
            applyMenuShortcuts(to: item.submenu)
        }
    }

    @IBAction func toggleAlwaysOnTop(_ sender: NSMenuItem) {
        toggleAlwaysOnTop()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.identifier?.rawValue == "viewMenu.alwaysOnTop" {
            menuItem.state = UserDefaultsManagement.alwaysOnTop ? .on : .off
            return true
        }
        // Only validate menu items that AppDelegate can actually handle
        if let action = menuItem.action {
            return self.responds(to: action)
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    // MARK: - Logging Configuration
    private func configureSystemLogging() {
        setenv("OS_ACTIVITY_MODE", "disable", 1)
        setenv("MTL_HUD_ENABLED", "0", 1)
        setenv("MTL_DEBUG_LAYER", "0", 1)
        setenv("MTL_SHADER_VALIDATION", "0", 1)
        setenv("MTL_CAPTURE_ENABLED", "0", 1)
        setenv("METAL_PERFORMANCE_SHADERS_LOGGING", "0", 1)
        configureURLCache()
    }

    private func configureURLCache() {
        let memoryCapacity = 50 * 1024 * 1024  // 50MB
        let diskCapacity = 0  // Disable disk cache to prevent I/O errors
        let cache = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: nil)
        URLCache.shared = cache
    }

    // MARK: - Always On Top Management
    private func toggleAlwaysOnTop() {
        let newValue = !UserDefaultsManagement.alwaysOnTop
        UserDefaultsManagement.alwaysOnTop = newValue

        NotificationCenter.default.post(name: .alwaysOnTopChanged, object: nil)

        let message = newValue ? I18n.str("Window stays on top") : I18n.str("Window normal mode")
        if let vc = resolveViewController() {
            vc.toast(message: message)
        } else if #available(macOS 14, *), let shell = shellWindowController as? ShellWindowController {
            shell.model.host?.toast(message: message)
        }
    }

    private func addGlobalKeyboardMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let key = event.charactersIgnoringModifiers?.lowercased()

            if event.keyCode == 17 || key == "t",  // kVK_ANSI_T
                flags == [.command, .shift]
            {
                if let vc = self.resolveViewController() {
                    vc.pin(vc.notesTableView.selectedRowIndexes)
                    return nil
                }
                if #available(macOS 14, *), let shell = self.shellWindowController as? ShellWindowController,
                    !shell.model.isPresenting, let note = shell.model.selectedNote
                {
                    shell.model.togglePin(note)
                    return nil
                }
            }

            if event.keyCode == 35 || key == "p",  // kVK_ANSI_P
                flags == [.command, .option]
            {
                if let vc = self.resolveViewController() {
                    vc.toggleMagicPPT(self)
                    return nil
                }
                if #available(macOS 14, *), let shell = self.shellWindowController as? ShellWindowController {
                    let model = shell.model
                    // An export keeps the mode it captures until it is written.
                    if !model.isExporting {
                        model.setPresenting(!(model.isPresenting && model.isPPT), ppt: true)
                    }
                    return nil
                }
            }

            return event
        }
    }
}
