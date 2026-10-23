import Cocoa

@MainActor
final class EditorPrefsViewController: BasePrefsViewController {
    private var settings = EditorSettings()
    private var defaultModeDropdown: PrefsDropdown!
    private var uploadDropdown: PrefsDropdown!
    private var lineBreakDropdown: PrefsDropdown!
    private var lineBreakRow: PrefsRowView!
    private var previewLocationDropdown: PrefsDropdown!
    private var previewWidthDropdown: PrefsDropdown!

    private static let previewWidths = ["600px", "800px", "1000px", "1200px", "1400px"]

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(handleSplitViewModeChanged), name: .splitViewModeChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleSplitViewModeChanged() {
        defaultModeDropdown?.selectOption { $0 as? Bool == UserDefaultsManagement.splitViewMode }
    }

    override func setupUI() {
        defaultModeDropdown = makeDropdown(action: #selector(defaultModeChanged(_:)))
        defaultModeDropdown.addOption(I18n.str("Editing"), value: false)
        defaultModeDropdown.addOption(I18n.str("Split"), value: true)

        uploadDropdown = makeDropdown(action: #selector(uploadServiceChanged(_:)))
        uploadDropdown.addOption(I18n.str("None"), value: "None")
        for service in ["uPic", "PicGo", "Picsee", "PicList"] {
            uploadDropdown.addOption(service, value: service)
        }

        lineBreakDropdown = makeDropdown(action: #selector(lineBreakChanged(_:)))
        lineBreakDropdown.addOption(I18n.str("Every Newline"), value: "MiaoYan")
        lineBreakDropdown.addOption(I18n.str("GitHub Style"), value: "Github")

        previewLocationDropdown = makeDropdown(action: #selector(previewLocationChanged(_:)))
        previewLocationDropdown.addOption(I18n.str("Top"), value: "Begin")
        previewLocationDropdown.addOption(I18n.str("Current Position"), value: "Editing")

        previewWidthDropdown = makeDropdown(action: #selector(previewWidthChanged(_:)))
        for width in Self.previewWidths {
            previewWidthDropdown.addOption(width, value: width)
        }
        previewWidthDropdown.addOption(I18n.str("Full Width"), value: UserDefaultsManagement.FullWidthValue)

        lineBreakRow = PrefsRowView(title: I18n.str("Line Breaks"), detail: "", controls: [lineBreakDropdown])

        addSections([
            [
                PrefsRowView(title: I18n.str("Default Mode"), detail: I18n.str("Write alone, or with the preview beside it"), controls: [defaultModeDropdown]),
                PrefsRowView(title: I18n.str("Image Upload"), detail: I18n.str("Send pasted images through an uploader app"), controls: [uploadDropdown]),
            ],
            [
                lineBreakRow,
                PrefsRowView(title: I18n.str("Open Preview At"), detail: "", controls: [previewLocationDropdown]),
                PrefsRowView(title: I18n.str("Preview Width"), detail: "", controls: [previewWidthDropdown]),
            ],
        ])
    }

    private func makeDropdown(action: Selector) -> PrefsDropdown {
        let dropdown = PrefsDropdown()
        dropdown.target = self
        dropdown.action = action
        return dropdown
    }

    override func setupValues() {
        defaultModeDropdown.selectOption { $0 as? Bool == UserDefaultsManagement.splitViewMode }
        uploadDropdown.selectOption { $0 as? String == UserDefaultsManagement.defaultPicUpload }
        lineBreakDropdown.selectOption { $0 as? String == settings.editorLineBreak }
        previewLocationDropdown.selectOption { $0 as? String == settings.previewLocation }
        previewWidthDropdown.selectOption { $0 as? String == settings.previewWidth }
        updateLineBreakDetail()
    }

    /// The detail says what the chosen value does, since the two names alone
    /// do not tell a single newline's fate.
    private func updateLineBreakDetail() {
        lineBreakRow.detail =
            settings.editorLineBreak == "Github"
            ? I18n.str("A new line in the preview needs a blank line")
            : I18n.str("Each newline starts a new line in the preview")
    }

    // MARK: - Actions

    @objc private func defaultModeChanged(_ sender: PrefsDropdown) {
        guard let isSplit = sender.selectedItem?.representedObject as? Bool else { return }
        if let vc = ViewController.shared() {
            vc.sessionSplitMode = isSplit
            vc.applyEditorModePreferenceChange()
        } else {
            UserDefaultsManagement.splitViewMode = isSplit
            NotificationCenter.default.post(name: .editorSettingsChanged, object: nil)
        }
    }

    @objc private func lineBreakChanged(_ sender: PrefsDropdown) {
        guard let raw = sender.selectedItem?.representedObject as? String else { return }
        settings.editorLineBreak = raw
        updateLineBreakDetail()
        settings.applyChanges()
    }

    @objc private func previewLocationChanged(_ sender: PrefsDropdown) {
        guard let raw = sender.selectedItem?.representedObject as? String else { return }
        settings.previewLocation = raw
        settings.applyChanges()
    }

    @objc private func previewWidthChanged(_ sender: PrefsDropdown) {
        guard let raw = sender.selectedItem?.representedObject as? String else { return }
        settings.previewWidth = raw
        settings.applyChanges()
    }

    @objc private func uploadServiceChanged(_ sender: PrefsDropdown) {
        guard let service = sender.selectedItem?.representedObject as? String else { return }
        UserDefaultsManagement.defaultPicUpload = service
        guard service != "None" else { return }
        if let vc = ViewController.shared() {
            vc.toastImageSet(name: service)
        } else if #available(macOS 14, *),
            let shell = (NSApp.delegate as? AppDelegate)?.shellWindowController as? ShellWindowController
        {
            shell.model.host?.toast(message: String(format: I18n.str("Install and set up %@ first"), service), style: .failure)
        }
    }
}
