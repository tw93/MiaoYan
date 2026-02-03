import Cocoa
import KeyboardShortcuts
import Sparkle
import os.log

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    var mainWindowController: MainWindowController?
    var prefsWindowController: PrefsWindowController?
    var aboutWindowController: AboutWindowController?
    var statusItem: NSStatusItem?
    public var urls: [URL]?
    public var searchQuery: String?
    public var newName: String?
    public var newContent: String?
    var appTitle: String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        return name ?? Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as! String
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        migratePreferences()
        let storage = Storage.sharedInstance()
        storage.loadProjects()
        storage.loadDocuments {}
    }

    // Attempt to migrate preferences from the old suite "com.tw93.MiaoYan" to the standard suite
    private func migratePreferences() {
        let migrationKey = "HasMigratedFromOldSuite"
        let standardDefaults = UserDefaults.standard

        // Skip if already migrated
        guard !standardDefaults.bool(forKey: migrationKey) else { return }

        let oldSuiteName = "com.tw93.MiaoYan"
        guard let oldDefaults = UserDefaults(suiteName: oldSuiteName) else {
            standardDefaults.set(true, forKey: migrationKey)
            return
        }

        let oldDict = oldDefaults.dictionaryRepresentation()

        // Migrate all values from old suite that don't exist in standard defaults
        for (key, value) in oldDict {
            if standardDefaults.object(forKey: key) == nil {
                standardDefaults.set(value, forKey: key)
            }
        }

        // Mark migration as completed
        standardDefaults.set(true, forKey: migrationKey)
        standardDefaults.synchronize()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.mainMenu?.applyMenuIcons()
        
        NSApp.mainMenu?.update()
        
        configureSystemLogging()
        NSFontManager.shared.fontPanel(false)?.orderOut(self)

        applyAppearance()

        addGlobalKeyboardMonitor()
        #if CLOUDKIT
            if let iCloudDocumentsURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents").resolvingSymlinksInPath() {
                if !FileManager.default.fileExists(atPath: iCloudDocumentsURL.path, isDirectory: nil) {
                    do {
                        try FileManager.default.createDirectory(at: iCloudDocumentsURL, withIntermediateDirectories: true, attributes: nil)
                    } catch {
                        print("Error creating iCloud directory: \(error)")
                    }
                }
            }
        #endif
        if UserDefaultsManagement.storagePath == nil {
            requestStorageDirectory()
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
        if UserDefaultsManagement.isFirstLaunch {
            let size = NSSize(width: 1280, height: 700)
            mainWC.window?.setContentSize(size)
            mainWC.window?.center()
        } else {
            if let window = mainWC.window {
                let currentFrame = window.frame
                let isOffScreen = NSScreen.screens.allSatisfy { screen in
                    !screen.visibleFrame.intersects(currentFrame)
                }

                if isOffScreen {
                    window.center()
                }
            }
        }

        // Apply fade-in for first launch to match re-open behavior and hide initial blank state
        mainWC.window?.alphaValue = 0
        mainWC.window?.makeKeyAndOrderFront(nil)

        mainWindowController = mainWC

        mainWC.applyMiaoYanAppearance()

        // Failsafe: Ensure window reveals after 3 seconds even if list loading hangs or fails
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            mainWC.revealWindowWhenReady()
        }

        if KeyboardShortcuts.getShortcut(for: .activateWindow) == nil {
            KeyboardShortcuts.setShortcut(.init(.m, modifiers: [.command, .option]), for: .activateWindow)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        if let vc = ViewController.shared() {
            vc.persistCurrentViewState()
        }
        let webkitPreview = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wkPreview")
        try? FileManager.default.removeItem(at: webkitPreview)
        var temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        temporary.appendPathComponent("ThumbnailsBig")
        try? FileManager.default.removeItem(at: temporary)
    }

    static func trackError(_ error: Error, context: String) {
        #if DEBUG
            print("Error in \(context): \(error)")
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            applyAppearance()
            mainWindowController?.makeNew()
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
        panel.message = "Please select default storage directory"
        panel.begin { result in
            if result == NSApplication.ModalResponse.OK {
                guard let url = panel.url else {
                    return
                }
                UserDefaultsManagement.storagePath = url.path
                self.restartApp()
            } else {
                exit(EXIT_SUCCESS)
            }
        }
    }
    // MARK: IBActions
    @IBAction func openMainWindow(_ sender: Any) {
        mainWindowController?.makeNew()
    }
    @IBAction func openMiaoYan(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://miaoyan.app")!)
    }
    @IBAction func openCats(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://miaoyan.app/cats.html")!)
    }
    @IBAction func openGithub(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://github.com/tw93/MiaoYan")!)
    }
    @IBAction func openRelease(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://github.com/tw93/MiaoYan/releases")!)
    }
    @IBAction func openTwitter(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://twitter.com/intent/follow?&original_referer=https://miaoyan.app&screen_name=HiTw93")!)
    }
    @IBAction func openIssue(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://github.com/tw93/MiaoYan/issues")!)
    }
    @IBAction func openTelegram(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://t.me/+GclQS9ZnxyI2ODQ1")!)
    }
    @IBAction func openPreferences(_ sender: Any?) {
        if prefsWindowController == nil {
            prefsWindowController = PrefsWindowController()
        }
        prefsWindowController?.show()
    }
    @IBAction func new(_ sender: Any?) {
        mainWindowController?.makeNew()
        NSApp.activate(ignoringOtherApps: true)
        ViewController.shared()?.fileMenuNewNote(self)
    }
    @IBAction func searchAndCreate(_ sender: Any?) {
        mainWindowController?.makeNew()
        NSApp.activate(ignoringOtherApps: true)
        guard let vc = ViewController.shared() else { return }
        DispatchQueue.main.async {
            vc.search.window?.makeFirstResponder(vc.search)
        }
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
        
        if let vc = ViewController.shared() {
            let message = newValue ? I18n.str("📌 Window stays on top") : I18n.str("📋 Window normal mode")
            vc.toast(message: message)
        }
    }
    
    private func addGlobalKeyboardMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 17,  // kVK_ANSI_T
                event.modifierFlags.contains(.command),
                event.modifierFlags.contains(.shift),
                !event.modifierFlags.contains(.option)
            {
                if let vc = ViewController.shared() {
                    vc.pin(vc.notesTableView.selectedRowIndexes)
                    return nil
                }
            }
            
            if event.keyCode == 35,  // kVK_ANSI_P
                event.modifierFlags.contains(.command),
                event.modifierFlags.contains(.option),
                !event.modifierFlags.contains(.shift),
                !event.modifierFlags.contains(.control)
            {
                if let vc = ViewController.shared() {
                    vc.toggleMagicPPT(self)
                    return nil
                }
            }

            return event
        }
    }
}
