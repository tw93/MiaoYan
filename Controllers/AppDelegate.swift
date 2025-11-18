import Cocoa
import KeyboardShortcuts
import Sparkle
import TelemetryDeck
import os.log

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var mainWindowController: MainWindowController?
    var prefsWindowController: PrefsWindowController?
    var aboutWindowController: AboutWindowController?
    var statusItem: NSStatusItem?
    public var urls: [URL]?
    public var searchQuery: String?
    public var newName: String?
    public var newContent: String?
    private static var isTelemetryInitialized = false
    var appTitle: String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        return name ?? Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as! String
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        let config = TelemetryDeck.Config(appID: "49D82975-F243-4FEF-BC97-4291E56E1103")
        config.defaultSignalPrefix = "MiaoYan."
        config.defaultParameters = {
            [
                "miaoyanVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                "miaoyanBuild": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                "hostPlatform": "macOS",
                "macosVersion": ProcessInfo.processInfo.operatingSystemVersionString,
                "displayLanguage": NSLocale.preferredLanguages.first ?? "unknown",
            ]
        }
        #if DEBUG
            config.testMode = true
        #endif
        TelemetryDeck.initialize(config: config)
        Self.isTelemetryInitialized = true

        let storage = Storage.sharedInstance()
        storage.loadProjects()
        storage.loadDocuments {}
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        configureSystemLogging()
        NSFontManager.shared.fontPanel(false)?.orderOut(self)
        UserDefaultsManagement.resetEditorState()
        applyAppearance()

        addGlobalKeyboardMonitor()
        #if CLOUDKIT
            if let iCloudDocumentsURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents").resolvingSymlinksInPath() {
                if !FileManager.default.fileExists(atPath: iCloudDocumentsURL.path, isDirectory: nil) {
                    do {
                        try FileManager.default.createDirectory(at: iCloudDocumentsURL, withIntermediateDirectories: true, attributes: nil)
                    } catch {
                        AppDelegate.trackError(error, context: "AppDelegate.iCloudDocumentsSetup")
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
            AppDelegate.trackError(NSError(domain: "AppError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get main window controller"]), context: "AppDelegate.startup")

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
        mainWC.window?.makeKeyAndOrderFront(nil)
        mainWindowController = mainWC

        mainWC.applyMiaoYanAppearance()

        let startTime = CFAbsoluteTimeGetCurrent()
        #if DEBUG
            Self.setupNetworkDebugging()
        #endif
        let launchTime = Int(startTime * 1000)
        Self.signal(
            "Performance.AppLaunch",
            parameters: [
                "launchTimeMs": "\(launchTime)"
            ])
        Self.signal("App.SessionStart")
        Self.signal(
            "App.Attribute",
            parameters: [
                "Appearance": String(UserDataService.instance.isDark),
                "SingleMode": String(UserDefaultsManagement.isSingleMode),
                "Language": String(UserDefaultsManagement.defaultLanguage),
                "UploadType": UserDefaultsManagement.defaultPicUpload,
                "EditorFont": UserDefaultsManagement.fontName,
                "PreviewFont": UserDefaultsManagement.previewFontName,
                "WindowFont": UserDefaultsManagement.windowFontName,
                "EditorFontSize": String(UserDefaultsManagement.fontSize),
                "PreviewFontSize": String(UserDefaultsManagement.previewFontSize),
                "CodeFont": UserDefaultsManagement.codeFontName,
                "PreviewWidth": UserDefaultsManagement.previewWidth,
                "PreviewLocation": UserDefaultsManagement.previewLocation,
                "ButtonShow": UserDefaultsManagement.buttonShow,
                "EditorLineBreak": UserDefaultsManagement.editorLineBreak,
            ])

        if KeyboardShortcuts.getShortcut(for: .activateWindow) == nil {
            KeyboardShortcuts.setShortcut(.init(.m, modifiers: [.command, .option]), for: .activateWindow)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        Self.signal("App.SessionEnd")
        if let vc = ViewController.shared() {
            vc.persistCurrentViewState()
        }
        let webkitPreview = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wkPreview")
        try? FileManager.default.removeItem(at: webkitPreview)
        var temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        temporary.appendPathComponent("ThumbnailsBig")
        try? FileManager.default.removeItem(at: temporary)
    }
    // MARK: - TelemetryDeck Helper Methods
    static func signal(_ signalName: String, parameters: [String: String] = [:]) {
        guard isTelemetryInitialized else { return }
        TelemetryDeck.signal(signalName, parameters: parameters)
    }

    static func debugSignal(_ signalName: String, parameters: [String: String] = [:]) {
        signal(signalName, parameters: parameters)
    }
    static func trackError(_ error: Error, context: String) {
        var parameters: [String: String] = [:]
        parameters["context"] = context
        if let nsError = error as NSError? {
            parameters["errorDomain"] = nsError.domain
            parameters["errorCode"] = "\(nsError.code)"
        }
        signal("Error.Occurred", parameters: parameters)
    }
    static func trackPerformance(_ metric: String, value: String, additionalParameters: [String: String] = [:]) {
        var parameters = additionalParameters
        parameters["value"] = value
        signal("Performance.\(metric)", parameters: parameters)
    }
    #if DEBUG
        private static func setupNetworkDebugging() {
        }
    #endif
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        applyAppearance()
        if !flag {
            mainWindowController?.makeNew()
        } else {
            mainWindowController?.refreshEditArea()
        }
        return true
    }

    func applyAppearance() {
        if UserDefaultsManagement.appearanceType != .Custom {
            switch UserDefaultsManagement.appearanceType {
            case .Dark:
                NSApp.appearance = NSAppearance(named: NSAppearance.Name.darkAqua)
                UserDataService.instance.isDark = true
            case .Light:
                NSApp.appearance = NSAppearance(named: NSAppearance.Name.aqua)
                UserDataService.instance.isDark = false
            case .System:
                NSApp.appearance = nil
                UserDataService.instance.isDark = NSAppearance.current.isDark
            default:
                NSApp.appearance = nil
                UserDataService.instance.isDark = NSAppearance.current.isDark
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

    // MARK: - Global Keyboard Monitor
    private func addGlobalKeyboardMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 17,  // kVK_ANSI_T
                event.modifierFlags.contains(.command),
                event.modifierFlags.contains(.shift),
                !event.modifierFlags.contains(.option)
            {

                if let vc = ViewController.shared() {
                    vc.pin(vc.notesTableView.selectedRowIndexes)
                    return nil  // Consume the event
                }
            }

            return event  // Let the event continue
        }
    }
}
