import Cocoa
import KeyboardShortcuts

@MainActor
final class GeneralPrefsViewController: BasePrefsViewController {
    private var settings = GeneralSettings()

    private var storageRow: PrefsRowView!
    private var storageRestartButton: PrefsPillButton!
    private var appearanceDropdown: PrefsDropdown!
    private var languageDropdown: PrefsDropdown!
    private var languageRestartButton: PrefsPillButton!
    private var buttonDisplayDropdown: PrefsDropdown!
    private var alwaysOnTopSwitch: PrefsSwitch!
    private var shortcutRecorder: PrefsShortcutRecorder!

    /// What the running app was launched with, so the Restart pill shows only
    /// while a change is waiting for a relaunch.
    private var launchLanguage = 0
    private var launchStoragePath: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(handleAlwaysOnTopChanged), name: .alwaysOnTopChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAlwaysOnTopChanged() {
        alwaysOnTopSwitch?.isOn = UserDefaultsManagement.alwaysOnTop
    }

    override func setupUI() {
        let changeButton = PrefsPillButton(title: I18n.str("Change"), target: self, action: #selector(changeStorageLocation(_:)))
        storageRestartButton = makeRestartButton()
        storageRow = PrefsRowView(
            title: I18n.str("Note Location"), detail: "", controls: [storageRestartButton, changeButton], detailTruncation: .byTruncatingMiddle)

        appearanceDropdown = PrefsDropdown()
        appearanceDropdown.target = self
        appearanceDropdown.action = #selector(appearanceChanged(_:))
        appearanceDropdown.addOption(I18n.str("System"), value: AppearanceType.System.rawValue)
        appearanceDropdown.addOption(I18n.str("Light"), value: AppearanceType.Light.rawValue)
        appearanceDropdown.addOption(I18n.str("Dark"), value: AppearanceType.Dark.rawValue)

        languageDropdown = PrefsDropdown()
        languageDropdown.target = self
        languageDropdown.action = #selector(languageChanged(_:))
        for language in [LanguageType.Chinese, .English, .Japanese, .ChineseTC] {
            languageDropdown.addOption(language.description, value: language.rawValue)
        }
        languageRestartButton = makeRestartButton()

        buttonDisplayDropdown = PrefsDropdown()
        buttonDisplayDropdown.target = self
        buttonDisplayDropdown.action = #selector(buttonDisplayChanged(_:))
        buttonDisplayDropdown.addOption(I18n.str("Always"), value: "Always")
        buttonDisplayDropdown.addOption(I18n.str("On Hover"), value: "Hover")

        alwaysOnTopSwitch = PrefsSwitch(target: self, action: #selector(alwaysOnTopChanged(_:)))
        alwaysOnTopSwitch.setAccessibilityLabel(I18n.str("Always On Top"))
        shortcutRecorder = PrefsShortcutRecorder(for: .activateWindow)

        addSections([
            [storageRow],
            [
                PrefsRowView(title: I18n.str("Appearance"), detail: I18n.str("Follow the system, or stay light or dark"), controls: [appearanceDropdown]),
                PrefsRowView(title: I18n.str("Language"), detail: I18n.str("Takes effect after MiaoYan restarts"), controls: [languageRestartButton, languageDropdown]),
                PrefsRowView(title: I18n.str("Button Display"), detail: I18n.str("When the title bar buttons show"), controls: [buttonDisplayDropdown]),
            ],
            [
                PrefsRowView(title: I18n.str("Always On Top"), detail: I18n.str("Keep this window above other apps"), controls: [alwaysOnTopSwitch]),
                PrefsRowView(title: I18n.str("Activate Shortcut"), detail: I18n.str("Bring MiaoYan to the front from any app"), controls: [shortcutRecorder]),
            ],
        ])
    }

    override func setupValues() {
        launchLanguage = settings.defaultLanguage
        launchStoragePath = settings.storagePath
        appearanceDropdown.selectOption { $0 as? Int == settings.appearanceType.rawValue }
        languageDropdown.selectOption { $0 as? Int == settings.defaultLanguage }
        // "On Hover" is what older versions stored for the same choice.
        let buttonShow = ["Hover", "On Hover"].contains(settings.buttonShow) ? "Hover" : "Always"
        buttonDisplayDropdown.selectOption { $0 as? String == buttonShow }
        alwaysOnTopSwitch.isOn = UserDefaultsManagement.alwaysOnTop
        showStoragePath(settings.storagePath)
    }

    /// The folder as people know it, `~/Documents/Notes` rather than the full
    /// path, with the middle truncated when it is still too long.
    private func showStoragePath(_ path: String?) {
        guard let path, !path.isEmpty else {
            storageRow.detail = I18n.str("The folder your notes are stored in")
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let realHome = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? home
        let ownContainer = "iCloud~" + (Bundle.main.bundleIdentifier ?? "com.tw93.miaoyan").replacingOccurrences(of: ".", with: "~")
        let appName = Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String ?? "MiaoYan"
        storageRow.detail = Self.displayPath(
            path, homes: [realHome, home], iCloudDrive: I18n.str("iCloud Drive"),
            containerName: { container in
                container == ownContainer
                    ? appName
                    : FileManager.default.displayName(atPath: (realHome as NSString).appendingPathComponent("Library/Mobile Documents/" + container))
            })
    }

    /// A path as Finder names it. The iCloud library lives in the app's
    /// container, `~/Library/Mobile Documents/iCloud~com~tw93~miaoyan/Documents`
    /// on every Mac, and shown as it is people read the bundle id as the
    /// developer's own iCloud account; Finder shows the same folder as
    /// iCloud Drive/MiaoYan, and iCloud Drive's own folder as iCloud Drive.
    nonisolated static func displayPath(
        _ path: String, homes: [String], iCloudDrive: String, containerName: (String) -> String
    ) -> String {
        guard let home = homes.first(where: { path == $0 || path.hasPrefix($0 + "/") }) else { return path }
        let relative = String(path.dropFirst(home.count))
        let mobileDocuments = "/Library/Mobile Documents/"
        guard relative.hasPrefix(mobileDocuments) else { return "~" + relative }
        var parts = relative.dropFirst(mobileDocuments.count).split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let container = parts.first else { return "~" + relative }
        if container == "com~apple~CloudDocs" {
            parts[0] = iCloudDrive
        } else if container.hasPrefix("iCloud~") {
            // An app's container shows its Documents folder as the app's
            // folder; anything beside Documents is not in Finder at all.
            guard parts.count >= 2, parts[1] == "Documents" else { return "~" + relative }
            parts.replaceSubrange(0...1, with: [iCloudDrive, containerName(container)])
        } else {
            return "~" + relative
        }
        return parts.joined(separator: "/")
    }

    // MARK: - Actions
    @objc private func appearanceChanged(_ sender: PrefsDropdown) {
        guard let raw = sender.selectedItem?.representedObject as? Int, let appearanceType = AppearanceType(rawValue: raw) else { return }
        settings.appearanceType = appearanceType

        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.applyAppearance()
            appDelegate.mainWindowController?.applyMiaoYanAppearance()
        }

        if let prefsWindow = view.window?.windowController as? PrefsWindowController {
            prefsWindow.refreshThemeAppearance()
        }

        if let vc = ViewController.shared() {
            vc.editArea.recreatePreviewView()

            let sidebarSelectedRows = vc.storageOutlineView.selectedRowIndexes
            let notesSelectedRows = vc.notesTableView.selectedRowIndexes

            vc.storageOutlineView.reloadData()
            vc.notesTableView.reloadData()

            if !sidebarSelectedRows.isEmpty {
                vc.storageOutlineView.selectRowIndexes(sidebarSelectedRows, byExtendingSelection: false)
            }
            if !notesSelectedRows.isEmpty {
                vc.notesTableView.selectRowIndexes(notesSelectedRows, byExtendingSelection: false)
            }
        }
    }

    @objc private func languageChanged(_ sender: PrefsDropdown) {
        guard let raw = sender.selectedItem?.representedObject as? Int, let languageType = LanguageType(rawValue: raw) else { return }
        if settings.defaultLanguage != languageType.rawValue {
            settings.defaultLanguage = languageType.rawValue
            UserDefaults.standard.set([languageType.code, "en"], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
        languageRestartButton.isHidden = settings.defaultLanguage == launchLanguage
    }

    @objc private func changeStorageLocation(_ sender: NSButton) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.canChooseFiles = false

        let handleResult: (NSApplication.ModalResponse) -> Void = { result in
            guard result == .OK, let url = openPanel.url else { return }
            do {
                try StorageLocationValidator.validateWritableDirectory(url)
            } catch {
                self.showStorageLocationError(error)
                return
            }

            // The bookmark comes first: storageUrl prefers it over the path,
            // so saving the path alone left the next launch on the old folder
            // while Settings showed the new one.
            let bookmarkData: Data
            do {
                bookmarkData = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil)
            } catch {
                AppDelegate.trackError(error, context: "GeneralPrefsViewController.changeStorageLocation.bookmarkData")
                self.showStorageLocationError(error)
                return
            }
            UserDefaultsManagement.storageBookmark = bookmarkData
            self.settings.storagePath = url.path
            self.showStoragePath(url.path)

            UserDefaults.standard.synchronize()
            // The library is opened at launch; the new folder is used from the
            // next start, which the Restart pill offers right away.
            self.storageRestartButton.isHidden = url.path == self.launchStoragePath
        }

        if let window = view.window {
            openPanel.beginSheetModal(for: window, completionHandler: handleResult)
        } else {
            openPanel.begin(completionHandler: handleResult)
        }
    }

    private func showStorageLocationError(_ error: Error) {
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
            for: view.window
        )
    }

    @objc private func buttonDisplayChanged(_ sender: PrefsDropdown) {
        guard let raw = sender.selectedItem?.representedObject as? String else { return }
        settings.buttonShow = raw
        if let vc = ViewController.shared() {
            vc.applyButtonVisibilityPreference()
        }
    }

    @objc private func alwaysOnTopChanged(_ sender: PrefsSwitch) {
        UserDefaultsManagement.alwaysOnTop = sender.isOn
        NotificationCenter.default.post(name: .alwaysOnTopChanged, object: nil)
    }
}
