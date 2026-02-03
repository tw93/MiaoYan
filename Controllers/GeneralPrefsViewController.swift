import Cocoa
import KeyboardShortcuts

private final class AppearanceAwareSeparatorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateColor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 0.5
        updateColor()
    }

    private func updateColor() {
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        layer?.backgroundColor = Theme.dividerColor.resolvedColor(for: appearance).cgColor
    }
}

@MainActor
final class GeneralPrefsViewController: BasePrefsViewController {
    private var settings = GeneralSettings()

    private var appearancePopUp: NSPopUpButton!
    private var languagePopUp: NSPopUpButton!
    private var storagePathControl: NSPathControl!
    private var storageChangeButton: NSButton!
    private var buttonShowPopUp: NSPopUpButton!
    private var alwaysOnTopPopUp: NSPopUpButton!
    private var activateShortcutRecorder: ThemeAwareShortcutRecorderView!

    // Editor settings controls
    // Editor settings controls
    private var editorModePopUp: NSPopUpButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(handleSplitViewModeChanged), name: .splitViewModeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAlwaysOnTopChanged), name: .alwaysOnTopChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleSplitViewModeChanged() {
        guard let editorModePopUp = editorModePopUp else { return }
        editorModePopUp.selectItem(withTitle: localizedEditorMode(UserDefaultsManagement.splitViewMode))
    }
    
    @objc private func handleAlwaysOnTopChanged() {
        guard let alwaysOnTopPopUp = alwaysOnTopPopUp else { return }
        alwaysOnTopPopUp.selectItem(withTag: UserDefaultsManagement.alwaysOnTop ? 1 : 0)
    }

    override func setupUI() {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        // Ensure the clip view (contentView) is also transparent
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.layer?.backgroundColor = NSColor.clear.cgColor

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
        
        let noItem = NSMenuItem(title: I18n.str("No"), action: nil, keyEquivalent: "")
        noItem.tag = 0
        alwaysOnTopPopUp.menu?.addItem(noItem)
        
        let yesItem = NSMenuItem(title: I18n.str("Yes"), action: nil, keyEquivalent: "")
        yesItem.tag = 1
        alwaysOnTopPopUp.menu?.addItem(yesItem)

        activateShortcutRecorder = ThemeAwareShortcutRecorderView(for: .activateWindow)
        activateShortcutRecorder.translatesAutoresizingMaskIntoConstraints = false
        let appearanceRow = createPreferencesRow(labelText: I18n.str("Appearance:"), control: appearancePopUp, controlWidth: controlWidth)
        let languageRow = createPreferencesRow(labelText: I18n.str("Language:"), control: languagePopUp, controlWidth: controlWidth)
        let buttonRow = createPreferencesRow(labelText: I18n.str("Button Display:"), control: buttonShowPopUp, controlWidth: controlWidth)
        let alwaysRow = createPreferencesRow(labelText: I18n.str("Always On Top:"), control: alwaysOnTopPopUp, controlWidth: controlWidth)
        let shortcutRow = createPreferencesRow(labelText: I18n.str("Activate Shortcut:"), control: activateShortcutRecorder, controlWidth: controlWidth)

        // Editor settings
        editorModePopUp = NSPopUpButton()
        editorModePopUp.translatesAutoresizingMaskIntoConstraints = false
        editorModePopUp.target = self
        editorModePopUp.action = #selector(editorModeChanged(_:))
        editorModePopUp.addItem(withTitle: localizedEditorMode(false))
        editorModePopUp.addItem(withTitle: localizedEditorMode(true))

        let editorModeRow = createPreferencesRow(labelText: I18n.str("Editor Mode:"), control: editorModePopUp, controlWidth: controlWidth)

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

        let line = AppearanceAwareSeparatorView()
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
        alwaysOnTopPopUp.selectItem(withTag: UserDefaultsManagement.alwaysOnTop ? 1 : 0)

        // Editor settings values
        editorModePopUp.selectItem(withTitle: localizedEditorMode(UserDefaultsManagement.splitViewMode))

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

        openPanel.begin { result in
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
    }

    @objc private func buttonShowChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        settings.buttonShow = rawButtonShow(from: title)
        if let vc = ViewController.shared() {
            vc.applyButtonVisibilityPreference()
        }
    }

    @objc private func alwaysOnTopChanged(_ sender: NSPopUpButton) {
        let enabled = sender.selectedTag() == 1
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

    private func showRestartAlert(completion: ((Bool) -> Void)? = nil) {
        guard let window = view.window else {
            completion?(false)
            return
        }
        let alert = NSAlert()
        alert.messageText = I18n.str("Restart to MiaoYan to take effect")
        alert.addButton(withTitle: I18n.str("Confirm"))
        alert.addButton(withTitle: I18n.str("Cancel"))
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                completion?(true)
                UserDefaultsManagement.isFirstLaunch = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    AppDelegate.relaunchApp()
                }
            } else {
                completion?(false)
            }
        }
    }

    // MARK: - Editor Settings Actions

    @objc private func editorModeChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem,
            let isSplit = rawEditorMode(from: item.title)
        else {
            return
        }
        UserDefaultsManagement.splitViewMode = isSplit
        if let vc = ViewController.shared() {
            vc.applyEditorModePreferenceChange()
        }
    }

    private func localizedEditorMode(_ isSplit: Bool) -> String {
        if isSplit {
            return I18n.str("Split Mode")
        } else {
            return I18n.str("Pure Editing")
        }
    }

    private func rawEditorMode(from display: String) -> Bool? {
        if display == localizedEditorMode(false) {
            return false
        }
        if display == localizedEditorMode(true) {
            return true
        }
        return nil
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
        let backgroundColor = Theme.backgroundColor.resolvedColor(for: appearance)
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
