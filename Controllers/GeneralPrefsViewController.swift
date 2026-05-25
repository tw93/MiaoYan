import Cocoa
import KeyboardShortcuts

@MainActor
final class GeneralPrefsViewController: BasePrefsViewController {
    private var settings = GeneralSettings()

    private var appearancePopUp: NSPopUpButton!
    private var languagePopUp: NSPopUpButton!
    private var storagePathControl: NSPathControl!
    private var storageChangeButton: NSButton!
    private var buttonShowSegmented: PrefsSegmentedControl!
    private var alwaysOnTopCheckbox: NSButton!
    private var activateShortcutRecorder: ThemeAwareShortcutRecorderView!

    // Editor settings controls
    private var editorModeSegmented: PrefsSegmentedControl!

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(handleSplitViewModeChanged), name: .splitViewModeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAlwaysOnTopChanged), name: .alwaysOnTopChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleSplitViewModeChanged() {
        guard let editorModeSegmented = editorModeSegmented else { return }
        editorModeSegmented.selectedSegment = UserDefaultsManagement.splitViewMode ? 1 : 0
    }

    @objc private func handleAlwaysOnTopChanged() {
        guard let alwaysOnTopCheckbox = alwaysOnTopCheckbox else { return }
        alwaysOnTopCheckbox.state = UserDefaultsManagement.alwaysOnTop ? .on : .off
    }

    override func setupUI() {
        setupAppearanceSection(in: installPreferencesStack())
    }

    private func setupAppearanceSection(in stackView: NSStackView) {
        let storageRow = createStorageRow()
        let storageSeparator = makePreferencesSeparator()

        appearancePopUp = NSPopUpButton()
        appearancePopUp.translatesAutoresizingMaskIntoConstraints = false
        appearancePopUp.target = self
        appearancePopUp.action = #selector(appearanceChanged(_:))

        appearancePopUp.addItem(withTitle: I18n.str("System"))
        appearancePopUp.addItem(withTitle: I18n.str("Light"))
        appearancePopUp.addItem(withTitle: I18n.str("Dark"))

        buttonShowSegmented = makeSegmentedControl(
            labels: [I18n.str("Always"), I18n.str("On Hover")],
            action: #selector(buttonShowChanged(_:))
        )

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

        alwaysOnTopCheckbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(alwaysOnTopChanged(_:)))
        alwaysOnTopCheckbox.translatesAutoresizingMaskIntoConstraints = false

        activateShortcutRecorder = ThemeAwareShortcutRecorderView(for: .activateWindow)
        activateShortcutRecorder.translatesAutoresizingMaskIntoConstraints = false
        let appearanceRow = makePreferencesRow(labelText: I18n.str("Appearance:"), control: appearancePopUp)
        let languageRow = makePreferencesRow(labelText: I18n.str("Language:"), control: languagePopUp)
        let buttonRow = makePreferencesRow(labelText: I18n.str("Button Display:"), control: buttonShowSegmented)
        let alwaysRow = makePreferencesRow(labelText: I18n.str("Always On Top:"), control: alwaysOnTopCheckbox, controlWidth: nil)
        let shortcutRow = makePreferencesRow(labelText: I18n.str("Activate Shortcut:"), control: activateShortcutRecorder)

        editorModeSegmented = makeSegmentedControl(
            labels: [localizedEditorMode(false), localizedEditorMode(true)],
            action: #selector(editorModeChanged(_:))
        )

        let editorModeRow = makePreferencesRow(labelText: I18n.str("Editor Mode:"), control: editorModeSegmented)

        [
            storageRow,
            storageSeparator,
            editorModeRow,
            appearanceRow,
            languageRow,
            buttonRow,
            alwaysRow,
            shortcutRow,
        ].forEach { stackView.addArrangedSubview($0) }
        stackView.setCustomSpacing(PrefsFormMetrics.groupSpacing, after: storageSeparator)
    }

    private func createStorageRow() -> NSView {
        storagePathControl = NSPathControl()
        storagePathControl.translatesAutoresizingMaskIntoConstraints = false
        storagePathControl.pathStyle = .standard
        storagePathControl.lineBreakMode = .byTruncatingMiddle
        storagePathControl.widthAnchor.constraint(equalToConstant: 270).isActive = true

        storageChangeButton = NSButton(title: I18n.str("Change"), target: self, action: #selector(changeStorageLocation(_:)))
        storageChangeButton.translatesAutoresizingMaskIntoConstraints = false
        storageChangeButton.widthAnchor.constraint(equalToConstant: 82).isActive = true

        let controls = makeControlStack([storagePathControl, storageChangeButton], spacing: 12)
        return makePreferencesRow(labelText: "\(I18n.str("Note Location")):", control: controls, controlWidth: nil)
    }

    override func setupValues() {
        appearancePopUp.selectItem(at: settings.appearanceType.rawValue)

        languagePopUp.selectItem(at: settings.defaultLanguage)

        if let storagePath = settings.storagePath {
            storagePathControl.url = URL(fileURLWithPath: storagePath)
        }

        buttonShowSegmented.selectedSegment = rawButtonShow(from: localizedButtonShow(settings.buttonShow)) == "Hover" ? 1 : 0
        alwaysOnTopCheckbox.state = UserDefaultsManagement.alwaysOnTop ? .on : .off

        // Editor settings values
        editorModeSegmented.selectedSegment = UserDefaultsManagement.splitViewMode ? 1 : 0

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

            if let prefsWindow = view.window?.windowController as? PrefsWindowController {
                prefsWindow.refreshThemeAppearance()
            }
            activateShortcutRecorder.refreshAppearance()

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

        let handleResult: (NSApplication.ModalResponse) -> Void = { result in
            if result == .OK, let url = openPanel.url {
                // Save old values for rollback if user cancels restart
                let oldPath = self.settings.storagePath
                let oldBookmark = UserDefaultsManagement.storageBookmark

                // 1. Save string path for legacy compatibility and display
                self.settings.storagePath = url.path
                self.storagePathControl.url = url

                // 2. Create and observe Security Scoped Bookmark for Sandbox persistence
                do {
                    let bookmarkData = try url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil)
                    UserDefaultsManagement.storageBookmark = bookmarkData
                } catch {
                    AppDelegate.trackError(error, context: "GeneralPrefsViewController.changeStorageLocation.bookmarkData")
                }

                UserDefaults.standard.synchronize()
                self.showRestartAlert { userConfirmedRestart in
                    if !userConfirmedRestart {
                        // Rollback changes if user cancels restart
                        self.settings.storagePath = oldPath
                        self.storagePathControl.url = oldPath.map { URL(fileURLWithPath: $0) }
                        UserDefaultsManagement.storageBookmark = oldBookmark
                        UserDefaults.standard.synchronize()
                    }
                }
            }
        }

        if let window = view.window {
            openPanel.beginSheetModal(for: window, completionHandler: handleResult)
        } else {
            openPanel.begin(completionHandler: handleResult)
        }
    }

    @objc private func buttonShowChanged(_ sender: PrefsSegmentedControl) {
        let title = sender.label(forSegment: sender.selectedSegment) ?? I18n.str("Always")
        settings.buttonShow = rawButtonShow(from: title)
        if let vc = ViewController.shared() {
            vc.applyButtonVisibilityPreference()
        }
    }

    @objc private func alwaysOnTopChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaultsManagement.alwaysOnTop = enabled
        NotificationCenter.default.post(name: .alwaysOnTopChanged, object: nil)
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

    // MARK: - Editor Settings Actions

    @objc private func editorModeChanged(_ sender: PrefsSegmentedControl) {
        let isSplit = sender.selectedSegment == 1
        if let vc = ViewController.shared() {
            vc.sessionSplitMode = isSplit
            vc.applyEditorModePreferenceChange()
        } else {
            UserDefaultsManagement.splitViewMode = isSplit
        }
    }

    private func localizedEditorMode(_ isSplit: Bool) -> String {
        if isSplit {
            return I18n.str("Split Mode")
        } else {
            return I18n.str("Pure Editing")
        }
    }

}

private final class ThemeAwareShortcutRecorderView: NSView {
    private let recorder: KeyboardShortcuts.RecorderCocoa
    private var isRecording = false
    private let contentInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

    init(for name: KeyboardShortcuts.Name, onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil) {
        recorder = KeyboardShortcuts.RecorderCocoa(for: name, onChange: onChange)
        super.init(frame: .zero)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override var intrinsicContentSize: NSSize {
        let baseSize = recorder.intrinsicContentSize
        return NSSize(
            width: baseSize.width + contentInsets.left + contentInsets.right,
            height: baseSize.height + contentInsets.top + contentInsets.bottom
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let pointInRecorder = convert(point, to: recorder)
        if recorder.bounds.contains(pointInRecorder) {
            return recorder.hitTest(pointInRecorder)
        }
        return super.hitTest(point)
    }

    var recorderView: KeyboardShortcuts.RecorderCocoa {
        recorder
    }

    func refreshAppearance() {
        updateAppearance()
    }

    @objc private func handleRecorderActiveStatusChange(_ notification: Notification) {
        guard let isActive = notification.userInfo?["isActive"] as? Bool else { return }
        isRecording = isActive
        updateAppearance()
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        addSubview(recorder)
        recorder.translatesAutoresizingMaskIntoConstraints = false
        configureRecorder()

        NotificationCenter.default.addObserver(self, selector: #selector(handleRecorderActiveStatusChange(_:)), name: .keyboardShortcutsRecorderActiveStatusDidChange, object: nil)

        updateAppearance()
    }

    private func configureRecorder() {
        recorder.focusRingType = .none
        recorder.isBordered = false
        recorder.isBezeled = false
        recorder.drawsBackground = false
        recorder.wantsLayer = false
        recorder.setContentHuggingPriority(.defaultLow, for: .horizontal)
        recorder.setContentHuggingPriority(.defaultLow, for: .vertical)
        recorder.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        recorder.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        if let searchCell = recorder.cell as? NSSearchFieldCell {
            searchCell.drawsBackground = false
            searchCell.backgroundColor = .clear
            searchCell.focusRingType = .none
        }

        NSLayoutConstraint.activate([
            recorder.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInsets.left),
            recorder.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentInsets.right),
            recorder.topAnchor.constraint(equalTo: topAnchor, constant: contentInsets.top),
            recorder.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -contentInsets.bottom),
        ])
    }

    private func updateAppearance() {
        guard let layer else { return }
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        let backgroundColor = Theme.settingsContentBackgroundColor.resolvedColor(for: appearance)
        let borderColor: NSColor

        if isRecording {
            borderColor = Theme.accentColor.resolvedColor(for: appearance)
        } else {
            borderColor = Theme.dividerColor.resolvedColor(for: appearance)
        }

        layer.backgroundColor = backgroundColor.cgColor
        layer.borderColor = borderColor.cgColor

        let resolvedTextColor = Theme.textColor.resolvedColor(for: appearance)
        recorder.textColor = resolvedTextColor
        if let searchCell = recorder.cell as? NSSearchFieldCell {
            searchCell.textColor = resolvedTextColor
            if let placeholder = searchCell.placeholderString {
                let attributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: resolvedTextColor.withAlphaComponent(0.6)
                ]
                searchCell.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: attributes)
            }
        }
    }
}

extension Notification.Name {
    fileprivate static let keyboardShortcutsRecorderActiveStatusDidChange = Notification.Name("KeyboardShortcuts_recorderActiveStatusDidChange")
}
