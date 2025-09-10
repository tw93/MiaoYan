import Cocoa
import Sparkle
import TelemetryDeck
import os.log

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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
        let storage = Storage.sharedInstance()
        storage.loadProjects()
        storage.loadDocuments {}
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Configure system logging to reduce harmless warning noise
        configureSystemLogging()

        // Ensure the font panel is closed when the app starts, in case it was
        // left open when the app quit.
        NSFontManager.shared.fontPanel(false)?.orderOut(self)

        applyAppearance()

        #if CLOUDKIT
            if let iCloudDocumentsURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents").resolvingSymlinksInPath() {
                if !FileManager.default.fileExists(atPath: iCloudDocumentsURL.path, isDirectory: nil) {
                    do {
                        try FileManager.default.createDirectory(at: iCloudDocumentsURL, withIntermediateDirectories: true, attributes: nil)
                    } catch {
                        print("Home directory creation: \(error)")
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
            fatalError("Error getting main window controller")
        }

        if UserDefaultsManagement.isFirstLaunch {
            let size = NSSize(width: 1280, height: 700)
            mainWC.window?.setContentSize(size)
            mainWC.window?.center()
        }
        mainWC.window?.makeKeyAndOrderFront(nil)
        mainWindowController = mainWC

        // Configure TelemetryDeck
        let startTime = CFAbsoluteTimeGetCurrent()
        let config = TelemetryDeck.Config(appID: "49D82975-F243-4FEF-BC97-4291E56E1103")

        // Add default signal prefix for consistent naming
        config.defaultSignalPrefix = "MiaoYan."

        // Add global default parameters for all events
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

        #if DEBUG
            // Monitor network requests for debugging
            Self.setupNetworkDebugging()
        #endif

        // Track app launch performance
        let launchTime = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        TelemetryDeck.signal(
            "Performance.AppLaunch",
            parameters: [
                "launchTimeMs": "\(launchTime)"
            ])

        // Track session start
        TelemetryDeck.signal("App.SessionStart")
        print("📊 Sent TelemetryDeck signal: App.SessionStart")

        TelemetryDeck.signal(
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
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Track session end
        TelemetryDeck.signal("App.SessionEnd")

        // Save current scroll position before terminating
        if let vc = ViewController.shared() {
            vc.notesTableView.saveScrollPosition()
        }

        let webkitPreview = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wkPreview")
        try? FileManager.default.removeItem(at: webkitPreview)

        var temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        temporary.appendPathComponent("ThumbnailsBig")
        try? FileManager.default.removeItem(at: temporary)
    }

    // MARK: - TelemetryDeck Helper Methods

    /// Debug helper to track signal sending
    static func debugSignal(_ signalName: String, parameters: [String: String] = [:]) {
        #if DEBUG
            print("📊 Sending TelemetryDeck signal: \(signalName)")
            if !parameters.isEmpty {
                print("   Parameters: \(parameters)")
            }
        #endif
        TelemetryDeck.signal(signalName, parameters: parameters)
    }

    /// Track errors and exceptions throughout the app (privacy-safe)
    static func trackError(_ error: Error, context: String) {
        var parameters: [String: String] = [:]
        parameters["context"] = context

        if let nsError = error as NSError? {
            parameters["errorDomain"] = nsError.domain
            parameters["errorCode"] = "\(nsError.code)"
        }

        TelemetryDeck.signal("Error.Occurred", parameters: parameters)
    }

    /// Track performance metrics throughout the app
    static func trackPerformance(_ metric: String, value: String, additionalParameters: [String: String] = [:]) {
        var parameters = additionalParameters
        parameters["value"] = value

        TelemetryDeck.signal("Performance.\(metric)", parameters: parameters)
    }

    #if DEBUG
        /// Setup network debugging to monitor TelemetryDeck requests
        private static func setupNetworkDebugging() {
            // Enable network logging via environment variable or custom URLProtocol
            print("🌐 Network debugging enabled for TelemetryDeck")

            // You can add URLProtocol monitoring here if needed
            // This will help you see actual HTTP requests being made
        }
    #endif

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            mainWindowController?.makeNew()
        } else {
            mainWindowController?.refreshEditArea()
        }

        return true
    }


    private func applyAppearance() {
        if #available(OSX 10.14, *) {
            if UserDefaultsManagement.appearanceType != .Custom {
                if UserDefaultsManagement.appearanceType == .Dark {
                    NSApp.appearance = NSAppearance(named: NSAppearance.Name.darkAqua)
                    UserDataService.instance.isDark = true
                }

                if UserDefaultsManagement.appearanceType == .Light {
                    NSApp.appearance = NSAppearance(named: NSAppearance.Name.aqua)
                    UserDataService.instance.isDark = false
                }

                if UserDefaultsManagement.appearanceType == .System, NSAppearance.current.isDark {
                    UserDataService.instance.isDark = true
                }
            } else {
                NSApp.appearance = NSAppearance(named: NSAppearance.Name.aqua)
            }
        }
    }

    private func restartApp() {
        guard let resourcePath = Bundle.main.resourcePath else { return }

        let url = URL(fileURLWithPath: resourcePath)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()

        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()

        exit(0)
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
            let storyboard = NSStoryboard(name: "Main", bundle: nil)
            prefsWindowController = storyboard.instantiateController(withIdentifier: "Preferences") as? PrefsWindowController
        }

        guard let prefsWindowController = prefsWindowController else { return }

        prefsWindowController.showWindow(nil)
        prefsWindowController.window?.makeKeyAndOrderFront(prefsWindowController)

        NSApp.activate(ignoringOtherApps: true)
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
        // Disable verbose system activity tracing
        setenv("OS_ACTIVITY_MODE", "disable", 1)

        // Reduce Metal debug output noise
        setenv("MTL_HUD_ENABLED", "0", 1)
        setenv("MTL_DEBUG_LAYER", "0", 1)

        // Simple logging configuration
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.tw93.MiaoYan",
            category: "Application")
        logger.info("System logging configured")
    }
}
