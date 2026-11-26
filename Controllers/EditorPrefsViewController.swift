import Cocoa

@MainActor
final class EditorPrefsViewController: BasePrefsViewController {
    private var settings = EditorSettings()
    private var defaultModeDropdown: PrefsDropdown!
    private var uploadDropdown: PrefsDropdown!
    private var uploadRow: PrefsRowView!
    private var s3SetupButton: PrefsPillButton!
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
        uploadDropdown.addOption("S3 / R2", value: Self.s3Service)
        s3SetupButton = PrefsPillButton(title: I18n.str("Set Up"), target: self, action: #selector(editS3Settings(_:)))
        uploadRow = PrefsRowView(
            title: I18n.str("Image Upload"), detail: "", controls: [s3SetupButton, uploadDropdown], detailTruncation: .byTruncatingMiddle)

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
                uploadRow,
            ],
            [
                lineBreakRow,
                PrefsRowView(title: I18n.str("Open Preview At"), detail: I18n.str("Where the preview starts when you open it"), controls: [previewLocationDropdown]),
                PrefsRowView(title: I18n.str("Preview Width"), detail: I18n.str("How wide the text runs in the preview"), controls: [previewWidthDropdown]),
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
        updateUploadRow()
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

    private static let s3Service = "S3"

    /// With S3 / R2 chosen the row names the address images are read from
    /// and offers its settings again; the uploader apps keep the plain line.
    private func updateUploadRow() {
        let isS3 = UserDefaultsManagement.defaultPicUpload == Self.s3Service
        s3SetupButton.isHidden = !isS3
        // The Keychain is read only with S3 chosen.
        if isS3, case let config = S3UploadSettings.load(), config.isComplete, let host = URL(string: config.publicLink(forKey: ""))?.host {
            uploadRow.detail = String(format: I18n.str("Pasted images upload to %@"), host)
        } else {
            uploadRow.detail = I18n.str("Send pasted images through an uploader app")
        }
    }

    @objc private func editS3Settings(_ sender: Any?) {
        presentS3Settings { _ in }
    }

    /// The bucket's settings in one sheet; Save stays off until every field
    /// but Region is filled. Answers whether they were saved.
    private func presentS3Settings(completion: @escaping (Bool) -> Void) {
        let config = S3UploadSettings.load()
        let form = S3SettingsForm(config: config)
        let alert = MiaoYanAlert.make(
            message: I18n.str("Upload to S3 or R2"),
            informativeText: I18n.str("Images go to your bucket and the note links them through the public URL. The secret key is kept in your Keychain."),
            buttons: [I18n.str("Save"), I18n.str("Cancel")])
        alert.accessoryView = form.view
        alert.window.initialFirstResponder = form.firstField
        form.onChange = { [weak alert, weak form] in alert?.buttons.first?.isEnabled = form?.config.isComplete ?? false }
        alert.buttons.first?.isEnabled = config.isComplete
        MiaoYanAlert.present(alert, for: view.window) { [weak self] response in
            guard response == .alertFirstButtonReturn, form.config.isComplete else {
                completion(false)
                return
            }
            guard S3UploadSettings.save(form.config) else {
                AppDelegate.trackError(
                    NSError(domain: "MiaoYan.S3UploadSettings", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not save the secret key to the Keychain"]),
                    context: "EditorPrefsViewController.presentS3Settings")
                // After this sheet has gone, or the second sheet is refused.
                Task { @MainActor [weak self] in
                    MiaoYanAlert.show(message: I18n.str("Could not save the secret key to the Keychain"), style: .warning, for: self?.view.window)
                }
                completion(false)
                return
            }
            self?.updateUploadRow()
            completion(true)
        }
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
        if service == Self.s3Service {
            let previous = UserDefaultsManagement.defaultPicUpload
            // Choosing S3 / R2 opens its settings, and Cancel puts the menu
            // back to what it was.
            presentS3Settings { [weak self] saved in
                guard let self else { return }
                if saved {
                    UserDefaultsManagement.defaultPicUpload = Self.s3Service
                } else {
                    self.uploadDropdown.selectOption { $0 as? String == previous }
                }
                self.updateUploadRow()
            }
            return
        }
        UserDefaultsManagement.defaultPicUpload = service
        updateUploadRow()
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

/// The fields of the S3 / R2 sheet, a label above each, sized for the alert.
@MainActor
private final class S3SettingsForm: NSObject, NSTextFieldDelegate {
    let view: NSView
    private(set) var firstField: NSTextField?
    var onChange: () -> Void = {}
    private var fields: [WritableKeyPath<S3UploadConfig, String>: NSTextField] = [:]
    private(set) var config: S3UploadConfig

    init(config: S3UploadConfig) {
        self.config = config
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        view = stack
        super.init()
        struct Row {
            let title: String
            let placeholder: String
            let keyPath: WritableKeyPath<S3UploadConfig, String>
            var isSecret = false
        }
        let rows = [
            Row(title: "Endpoint", placeholder: "https://<account>.r2.cloudflarestorage.com", keyPath: \.endpoint),
            Row(title: "Bucket", placeholder: "images", keyPath: \.bucket),
            Row(title: "Access Key ID", placeholder: "", keyPath: \.accessKeyID),
            Row(title: "Secret Access Key", placeholder: "", keyPath: \.secretAccessKey, isSecret: true),
            Row(title: I18n.str("Public URL"), placeholder: "https://img.example.com", keyPath: \.publicURL),
            Row(title: I18n.str("Region"), placeholder: "auto", keyPath: \.region),
        ]
        for (index, row) in rows.enumerated() {
            let label = NSTextField(labelWithString: row.title)
            label.font = .systemFont(ofSize: 12)
            label.textColor = Theme.Ink.secondary
            let field = row.isSecret ? NSSecureTextField() : NSTextField()
            field.stringValue = config[keyPath: row.keyPath]
            field.placeholderString = row.placeholder
            field.focusRingType = .none
            field.delegate = self
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 300).isActive = true
            fields[row.keyPath] = field
            if index == 0 { firstField = field }
            stack.addArrangedSubview(label)
            stack.addArrangedSubview(field)
            stack.setCustomSpacing(10, after: field)
        }
        stack.layoutSubtreeIfNeeded()
        stack.frame.size = stack.fittingSize
    }

    func controlTextDidChange(_ obj: Notification) {
        for (keyPath, field) in fields {
            config[keyPath: keyPath] = field.stringValue
        }
        onChange()
    }
}
