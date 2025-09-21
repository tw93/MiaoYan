import Cocoa
import KeyboardShortcuts

@MainActor
final class GeneralPrefsViewController: BasePrefsViewController {
    private var settings = GeneralSettings()

    // UI Controls
    private var appearancePopUp: NSPopUpButton!
    private var languagePopUp: NSPopUpButton!
    private var storagePathControl: NSPathControl!
    private var storageChangeButton: NSButton!
    private var buttonShowPopUp: NSPopUpButton!
    private var alwaysOnTopPopUp: NSPopUpButton!
    private var activateShortcutRecorder: KeyboardShortcuts.RecorderCocoa!

    override func setupUI() {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        view.addSubview(scrollView)

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.documentView = contentView

        setupAppearanceSection(in: contentView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),

            contentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
    }

    private func setupAppearanceSection(in parentView: NSView) {
        let (sectionView, _) = createSectionView(
            in: parentView,
            topAnchor: parentView.topAnchor,
            topConstant: 0
        )

        let rowSpacing: CGFloat = 16
        let topSpacing: CGFloat = rowSpacing
        let horizontalInset: CGFloat = 24
        let controlWidth: CGFloat = 200

        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.spacing = rowSpacing
        stackView.alignment = .leading
        sectionView.addSubview(stackView)

        let storageRow = createStorageRow(controlWidth: controlWidth)
        let storageSeparator = createSeparatorView()

        appearancePopUp = NSPopUpButton()
        appearancePopUp.translatesAutoresizingMaskIntoConstraints = false
        appearancePopUp.target = self
        appearancePopUp.action = #selector(appearanceChanged(_:))

        appearancePopUp.addItem(withTitle: I18n.str("System"))
        appearancePopUp.addItem(withTitle: I18n.str("Light"))
        appearancePopUp.addItem(withTitle: I18n.str("Dark"))

        buttonShowPopUp = NSPopUpButton()
        buttonShowPopUp.translatesAutoresizingMaskIntoConstraints = false
        buttonShowPopUp.target = self
        buttonShowPopUp.action = #selector(buttonShowChanged(_:))

        buttonShowPopUp.addItem(withTitle: I18n.str("Always"))
        buttonShowPopUp.addItem(withTitle: I18n.str("On Hover"))

        languagePopUp = NSPopUpButton()
        languagePopUp.translatesAutoresizingMaskIntoConstraints = false
        languagePopUp.target = self
        languagePopUp.action = #selector(languageChanged(_:))

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

        alwaysOnTopPopUp = NSPopUpButton()
        alwaysOnTopPopUp.translatesAutoresizingMaskIntoConstraints = false
        alwaysOnTopPopUp.target = self
        alwaysOnTopPopUp.action = #selector(alwaysOnTopChanged(_:))
        alwaysOnTopPopUp.addItem(withTitle: I18n.str("No"))
        alwaysOnTopPopUp.addItem(withTitle: I18n.str("Yes"))

        activateShortcutRecorder = KeyboardShortcuts.RecorderCocoa(for: .activateWindow)
        activateShortcutRecorder.translatesAutoresizingMaskIntoConstraints = false
        let appearanceRow = createPreferencesRow(labelText: I18n.str("Appearance:"), control: appearancePopUp, controlWidth: controlWidth)
        let languageRow = createPreferencesRow(labelText: I18n.str("Language:"), control: languagePopUp, controlWidth: controlWidth)
        let buttonRow = createPreferencesRow(labelText: I18n.str("Button Display:"), control: buttonShowPopUp, controlWidth: controlWidth)
        let alwaysRow = createPreferencesRow(labelText: I18n.str("Always On Top:"), control: alwaysOnTopPopUp, controlWidth: controlWidth)
        let shortcutRow = createPreferencesRow(labelText: I18n.str("Activate Shortcut:"), control: activateShortcutRecorder, controlWidth: controlWidth)

        [storageRow, storageSeparator, appearanceRow, languageRow, buttonRow, alwaysRow, shortcutRow].forEach { stackView.addArrangedSubview($0) }
        stackView.setCustomSpacing(rowSpacing * 1.5, after: storageSeparator)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: sectionView.topAnchor, constant: topSpacing),
            stackView.leadingAnchor.constraint(equalTo: sectionView.leadingAnchor, constant: horizontalInset),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: sectionView.trailingAnchor, constant: -horizontalInset),
            stackView.bottomAnchor.constraint(equalTo: sectionView.bottomAnchor, constant: -rowSpacing),
        ])
    }

    private func createSectionView(in parentView: NSView, topAnchor: NSLayoutAnchor<NSLayoutYAxisAnchor>, topConstant: CGFloat, title: String? = nil) -> (container: NSView, titleLabel: NSTextField?) {
        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        // Keep the same background as parent
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor

        var titleLabel: NSTextField?
        if let title = title {
            let label = NSTextField(labelWithString: title)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = NSFont.boldSystemFont(ofSize: 13)
            label.textColor = Theme.textColor
            containerView.addSubview(label)
            titleLabel = label
        }

        parentView.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor, constant: topConstant),
            containerView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
        ])

        if let titleLabel {
            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
                titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            ])
        }

        return (containerView, titleLabel)
    }

    private func createPreferencesRow(labelText: String, control: NSView, controlWidth: CGFloat? = nil) -> NSView {
        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: labelText)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .left

        control.translatesAutoresizingMaskIntoConstraints = false

        rowView.addSubview(label)
        rowView.addSubview(control)

        let spacing: CGFloat = 16

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: rowView.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 140),

            control.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: spacing),
            control.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            rowView.trailingAnchor.constraint(equalTo: control.trailingAnchor),
        ])

        if let controlWidth {
            control.widthAnchor.constraint(equalToConstant: controlWidth).isActive = true
        }

        rowView.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true

        return rowView
    }

    private func createSeparatorView() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let line = NSView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        container.addSubview(line)

        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            line.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])

        container.setContentHuggingPriority(.defaultLow, for: .horizontal)
        container.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return container
    }

    private func createStorageRow(controlWidth: CGFloat) -> NSView {
        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "\(I18n.str("Note Location")):")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .left

        storagePathControl = NSPathControl()
        storagePathControl.translatesAutoresizingMaskIntoConstraints = false
        storagePathControl.pathStyle = .standard
        storagePathControl.lineBreakMode = .byTruncatingMiddle

        storageChangeButton = NSButton(title: I18n.str("Change"), target: self, action: #selector(changeStorageLocation(_:)))
        storageChangeButton.translatesAutoresizingMaskIntoConstraints = false

        rowView.addSubview(label)
        rowView.addSubview(storagePathControl)
        rowView.addSubview(storageChangeButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: rowView.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 140),

            storagePathControl.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 16),
            storagePathControl.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            storagePathControl.widthAnchor.constraint(greaterThanOrEqualToConstant: controlWidth),

            storageChangeButton.leadingAnchor.constraint(equalTo: storagePathControl.trailingAnchor, constant: 12),
            storageChangeButton.trailingAnchor.constraint(equalTo: rowView.trailingAnchor),
            storageChangeButton.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            storageChangeButton.widthAnchor.constraint(equalToConstant: 80),
        ])

        rowView.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true

        return rowView
    }

    override func setupValues() {
        appearancePopUp.selectItem(at: settings.appearanceType.rawValue)

        languagePopUp.selectItem(at: settings.defaultLanguage)

        if let storagePath = settings.storagePath {
            storagePathControl.url = URL(fileURLWithPath: storagePath)
        }

        buttonShowPopUp.selectItem(withTitle: localizedButtonShow(settings.buttonShow))
        alwaysOnTopPopUp.selectItem(withTitle: UserDefaultsManagement.alwaysOnTop ? I18n.str("Yes") : I18n.str("No"))
    }

    // MARK: - Actions
    @objc private func appearanceChanged(_ sender: NSPopUpButton) {
        if let appearanceType = AppearanceType(rawValue: sender.indexOfSelectedItem) {
            settings.appearanceType = appearanceType

            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.applyAppearance()
            }

            if let appDelegate = NSApp.delegate as? AppDelegate,
                let mainWindowController = appDelegate.mainWindowController
            {
                mainWindowController.applyMiaoYanAppearance()
            }

            if let vc = ViewController.shared() {
                vc.editArea.recreatePreviewView()

                let sidebarSelectedRow = vc.storageOutlineView.selectedRow
                let notesSelectedRows = vc.notesTableView.selectedRowIndexes

                vc.storageOutlineView.reloadData()
                vc.notesTableView.reloadData()

                if sidebarSelectedRow >= 0 {
                    vc.storageOutlineView.selectRowIndexes([sidebarSelectedRow], byExtendingSelection: false)
                }
                if !notesSelectedRows.isEmpty {
                    vc.notesTableView.selectRowIndexes(notesSelectedRows, byExtendingSelection: false)
                }
            }
        }
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let languageType = LanguageType.withName(rawValue: sender.title)
        if settings.defaultLanguage != languageType.rawValue {
            settings.defaultLanguage = languageType.rawValue
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
                UserDefaults.standard.synchronize()
                self.showRestartAlert()
            }
        }
    }

    @objc private func buttonShowChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        settings.buttonShow = rawButtonShow(from: title)
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
