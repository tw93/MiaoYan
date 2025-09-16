import Cocoa
import KeyboardShortcuts

final class GeneralPrefsViewController: BasePrefsViewController {
    private var settings = GeneralSettings()

    // UI Controls
    private var appearancePopUp: NSPopUpButton!
    private var languagePopUp: NSPopUpButton!
    private var storagePathControl: NSPathControl!
    private var storageChangeButton: NSButton!
    private var buttonShowPopUp: NSPopUpButton!
    private var alwaysOnTopLabel: NSTextField!
    private var alwaysOnTopPopUp: NSPopUpButton!
    private var activateShortcutLabel: NSTextField!
    private var activateShortcutRecorder: KeyboardShortcuts.RecorderCocoa!

    override func setupUI() {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        // Let the NSVisualEffectView provide adaptive background
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        view.addSubview(scrollView)

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.documentView = contentView

        // Sections: Appearance & Language, File Storage
        setupAppearanceSection(in: contentView)
        setupFileStorageSection(in: contentView)

        // Setup scroll view constraints using contentView anchors for compatibility
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),

            contentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
    }

    private func setupAppearanceSection(in parentView: NSView) {
        let sectionView = createSectionView(
            title: I18n.str("Appearance & Language"),
            in: parentView,
            topAnchor: parentView.topAnchor,
            topConstant: 0
        )

        // Appearance theme
        let appearanceLabel = NSTextField(labelWithString: I18n.str("Appearance:"))
        appearanceLabel.translatesAutoresizingMaskIntoConstraints = false

        appearancePopUp = NSPopUpButton()
        appearancePopUp.translatesAutoresizingMaskIntoConstraints = false
        appearancePopUp.target = self
        appearancePopUp.action = #selector(appearanceChanged(_:))

        appearancePopUp.addItem(withTitle: I18n.str("System"))
        appearancePopUp.addItem(withTitle: I18n.str("Light"))
        appearancePopUp.addItem(withTitle: I18n.str("Dark"))

        // Button display (moved into Appearance section)
        let buttonLabel = NSTextField(labelWithString: I18n.str("Button Display:"))
        buttonLabel.translatesAutoresizingMaskIntoConstraints = false

        buttonShowPopUp = NSPopUpButton()
        buttonShowPopUp.translatesAutoresizingMaskIntoConstraints = false
        buttonShowPopUp.target = self
        buttonShowPopUp.action = #selector(buttonShowChanged(_:))

        buttonShowPopUp.addItem(withTitle: I18n.str("Always"))
        buttonShowPopUp.addItem(withTitle: I18n.str("On Hover"))

        sectionView.addSubview(appearanceLabel)
        sectionView.addSubview(appearancePopUp)
        sectionView.addSubview(buttonLabel)
        sectionView.addSubview(buttonShowPopUp)

        // Language (move into Appearance section)
        let languageLabel = NSTextField(labelWithString: I18n.str("Language:"))
        languageLabel.translatesAutoresizingMaskIntoConstraints = false

        languagePopUp = NSPopUpButton()
        languagePopUp.translatesAutoresizingMaskIntoConstraints = false
        languagePopUp.target = self
        languagePopUp.action = #selector(languageChanged(_:))

        // Add language options
        let languages = [
            LanguageType(rawValue: 0x00),
            LanguageType(rawValue: 0x01),
            LanguageType(rawValue: 0x02),
            LanguageType(rawValue: 0x03),
        ]
        for language in languages {
            if let lang = language?.description {
                languagePopUp.addItem(withTitle: lang)
            }
        }

        sectionView.addSubview(languageLabel)
        sectionView.addSubview(languagePopUp)

        // Always On Top (label + options for consistency)
        alwaysOnTopLabel = NSTextField(labelWithString: I18n.str("Always On Top:"))
        alwaysOnTopLabel.translatesAutoresizingMaskIntoConstraints = false
        sectionView.addSubview(alwaysOnTopLabel)

        alwaysOnTopPopUp = NSPopUpButton()
        alwaysOnTopPopUp.translatesAutoresizingMaskIntoConstraints = false
        alwaysOnTopPopUp.target = self
        alwaysOnTopPopUp.action = #selector(alwaysOnTopChanged(_:))
        alwaysOnTopPopUp.addItem(withTitle: I18n.str("No"))
        alwaysOnTopPopUp.addItem(withTitle: I18n.str("Yes"))
        sectionView.addSubview(alwaysOnTopPopUp)

        // Activate shortcut recorder (Command+Option+M by default)
        activateShortcutLabel = NSTextField(labelWithString: I18n.str("Activate Shortcut:"))
        activateShortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        sectionView.addSubview(activateShortcutLabel)

        // Recorder control provided by KeyboardShortcuts
        // Use recorder without forcing a default on clear so user can set Command+Option+M again
        activateShortcutRecorder = KeyboardShortcuts.RecorderCocoa(for: .activateWindow)
        activateShortcutRecorder.translatesAutoresizingMaskIntoConstraints = false
        sectionView.addSubview(activateShortcutRecorder)

        NSLayoutConstraint.activate([
            // Appearance row (first)
            appearanceLabel.topAnchor.constraint(equalTo: sectionView.topAnchor, constant: 35),
            appearanceLabel.leadingAnchor.constraint(equalTo: sectionView.leadingAnchor, constant: 20),
            appearanceLabel.widthAnchor.constraint(equalToConstant: 140),

            appearancePopUp.centerYAnchor.constraint(equalTo: appearanceLabel.centerYAnchor),
            appearancePopUp.leadingAnchor.constraint(equalTo: appearanceLabel.trailingAnchor, constant: 16),
            appearancePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

            // Language row (second)
            languageLabel.topAnchor.constraint(equalTo: appearanceLabel.bottomAnchor, constant: 16),
            languageLabel.leadingAnchor.constraint(equalTo: appearanceLabel.leadingAnchor),
            languageLabel.widthAnchor.constraint(equalTo: appearanceLabel.widthAnchor),

            languagePopUp.centerYAnchor.constraint(equalTo: languageLabel.centerYAnchor),
            languagePopUp.leadingAnchor.constraint(equalTo: languageLabel.trailingAnchor, constant: 16),
            languagePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            languagePopUp.widthAnchor.constraint(equalTo: appearancePopUp.widthAnchor),

            // Button display row (third)
            buttonLabel.topAnchor.constraint(equalTo: languageLabel.bottomAnchor, constant: 16),
            buttonLabel.leadingAnchor.constraint(equalTo: appearanceLabel.leadingAnchor),
            buttonLabel.widthAnchor.constraint(equalTo: appearanceLabel.widthAnchor),

            buttonShowPopUp.centerYAnchor.constraint(equalTo: buttonLabel.centerYAnchor),
            buttonShowPopUp.leadingAnchor.constraint(equalTo: buttonLabel.trailingAnchor, constant: 16),
            buttonShowPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            buttonShowPopUp.widthAnchor.constraint(equalTo: appearancePopUp.widthAnchor),

            // Always-on-top row (fourth)
            alwaysOnTopLabel.topAnchor.constraint(equalTo: buttonLabel.bottomAnchor, constant: 16),
            alwaysOnTopLabel.leadingAnchor.constraint(equalTo: appearanceLabel.leadingAnchor),
            alwaysOnTopLabel.widthAnchor.constraint(equalTo: appearanceLabel.widthAnchor),

            alwaysOnTopPopUp.centerYAnchor.constraint(equalTo: alwaysOnTopLabel.centerYAnchor),
            alwaysOnTopPopUp.leadingAnchor.constraint(equalTo: alwaysOnTopLabel.trailingAnchor, constant: 16),
            alwaysOnTopPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            alwaysOnTopPopUp.widthAnchor.constraint(equalTo: appearancePopUp.widthAnchor),

            // Shortcut row (fifth)
            activateShortcutLabel.topAnchor.constraint(equalTo: alwaysOnTopLabel.bottomAnchor, constant: 16),
            activateShortcutLabel.leadingAnchor.constraint(equalTo: appearanceLabel.leadingAnchor),
            activateShortcutLabel.widthAnchor.constraint(equalTo: appearanceLabel.widthAnchor),

            activateShortcutRecorder.centerYAnchor.constraint(equalTo: activateShortcutLabel.centerYAnchor),
            activateShortcutRecorder.leadingAnchor.constraint(equalTo: activateShortcutLabel.trailingAnchor, constant: 16),
            // Match popup width for visual consistency
            activateShortcutRecorder.widthAnchor.constraint(equalTo: appearancePopUp.widthAnchor),
            // Tighten overall section height by anchoring content to bottom instead of fixed height
            activateShortcutRecorder.bottomAnchor.constraint(equalTo: sectionView.bottomAnchor, constant: -16),
        ])
    }

    private func setupFileStorageSection(in parentView: NSView) {
        // Tighten spacing to previous section
        let previousSection = parentView.subviews.last!
        let sectionView = createSectionView(
            title: I18n.str("File Storage"),
            in: parentView,
            topAnchor: previousSection.bottomAnchor,
            topConstant: 0
        )

        // Storage path
        storagePathControl = NSPathControl()
        storagePathControl.translatesAutoresizingMaskIntoConstraints = false
        storagePathControl.pathStyle = .standard

        storageChangeButton = NSButton(title: I18n.str("Change"), target: self, action: #selector(changeStorageLocation(_:)))
        storageChangeButton.translatesAutoresizingMaskIntoConstraints = false

        sectionView.addSubview(storagePathControl)
        sectionView.addSubview(storageChangeButton)

        NSLayoutConstraint.activate([
            // Storage row (add more space below section title)
            storagePathControl.topAnchor.constraint(equalTo: sectionView.topAnchor, constant: 36),
            storagePathControl.leadingAnchor.constraint(equalTo: sectionView.leadingAnchor, constant: 20),
            storagePathControl.trailingAnchor.constraint(equalTo: storageChangeButton.leadingAnchor, constant: -12),

            storageChangeButton.centerYAnchor.constraint(equalTo: storagePathControl.centerYAnchor),
            storageChangeButton.trailingAnchor.constraint(equalTo: sectionView.trailingAnchor, constant: -20),
            storageChangeButton.widthAnchor.constraint(equalToConstant: 80),

            // Adaptive height: pin content to bottom instead of fixing height
            storagePathControl.bottomAnchor.constraint(equalTo: sectionView.bottomAnchor, constant: -20),
            sectionView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor, constant: -20),
        ])
    }

    private func createSectionView(title: String, in parentView: NSView, topAnchor: NSLayoutAnchor<NSLayoutYAxisAnchor>, topConstant: CGFloat) -> NSView {
        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        // Keep the same background as parent
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        titleLabel.textColor = Theme.textColor

        containerView.addSubview(titleLabel)
        parentView.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor, constant: topConstant),
            containerView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
        ])

        return containerView
    }

    override func setupValues() {
        // Set current values
        appearancePopUp.selectItem(at: settings.appearanceType.rawValue)

        languagePopUp.selectItem(at: settings.defaultLanguage)

        if let storagePath = settings.storagePath {
            storagePathControl.url = URL(fileURLWithPath: storagePath)
        }

        // Select localized display titles for current stored raw values
        buttonShowPopUp.selectItem(withTitle: localizedButtonShow(settings.buttonShow))
        alwaysOnTopPopUp.selectItem(withTitle: UserDefaultsManagement.alwaysOnTop ? I18n.str("Yes") : I18n.str("No"))
    }

    // MARK: - Actions
    @objc private func appearanceChanged(_ sender: NSPopUpButton) {
        if let appearanceType = AppearanceType(rawValue: sender.indexOfSelectedItem) {
            settings.appearanceType = appearanceType

            // Apply appearance immediately instead of requiring restart
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.applyAppearance()
            }

            // Update main window appearance immediately
            if let appDelegate = NSApp.delegate as? AppDelegate,
                let mainWindowController = appDelegate.mainWindowController
            {
                mainWindowController.applyMiaoYanAppearance()
            }

            // Recreate preview view with new appearance
            if let vc = ViewController.shared() {
                vc.editArea.recreatePreviewView()
            }
        }
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let languageType = LanguageType.withName(rawValue: sender.title)
        if settings.defaultLanguage != languageType.rawValue {
            settings.defaultLanguage = languageType.rawValue
            // Set primary language with English fallback to ensure proper resolution
            UserDefaults.standard.set([languageType.code, "en"], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
            showRestartAlert()
        }
    }

    @objc private func changeStorageLocation(_ sender: NSButton) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.canChooseFiles = false

        openPanel.begin { result in
            if result == .OK, let url = openPanel.url {
                self.settings.storagePath = url.path
                self.storagePathControl.url = url
                self.showRestartAlert()
            }
        }
    }

    @objc private func buttonShowChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        settings.buttonShow = rawButtonShow(from: title)
        // Apply button visibility behavior immediately
        if let vc = ViewController.shared() {
            vc.applyButtonVisibilityPreference()
        }
    }

    @objc private func alwaysOnTopChanged(_ sender: NSPopUpButton) {
        let enabled = sender.title == I18n.str("Yes")
        UserDefaultsManagement.alwaysOnTop = enabled
        if let window = MainWindowController.shared() {
            window.level = enabled ? .floating : .normal
        }
    }

    // MARK: - Localization helpers for raw/display mapping
    private func localizedButtonShow(_ raw: String) -> String {
        switch raw {
        case "Always":
            return I18n.str("Always")
        case "Hover", "On Hover":  // backward compatibility for previously saved value
            return I18n.str("On Hover")
        default:
            return raw
        }
    }

    private func rawButtonShow(from display: String) -> String {
        if display == I18n.str("Always") { return "Always" }
        if display == I18n.str("On Hover") { return "Hover" }
        return display
    }

    private func showRestartAlert() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = I18n.str("Restart to MiaoYan to take effect")
        alert.addButton(withTitle: I18n.str("Confirm"))
        alert.addButton(withTitle: I18n.str("Cancel"))
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                UserDefaultsManagement.isFirstLaunch = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    AppDelegate.relaunchApp()
                }
            }
        }
    }
}

