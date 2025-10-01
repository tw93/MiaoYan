import Cocoa

@MainActor
final class EditorPrefsViewController: BasePrefsViewController {
    private var settings = EditorSettings()
    private var settingsStackView: NSStackView!

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

        setupEditorSettingsSection(in: contentView)

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

    private func setupEditorSettingsSection(in parentView: NSView) {
        let (sectionView, _) = createSectionView(
            in: parentView,
            topAnchor: parentView.topAnchor,
            topConstant: 0
        )

        let rowSpacing: CGFloat = 16
        let topSpacing: CGFloat = rowSpacing
        let horizontalInset: CGFloat = 24

        settingsStackView = NSStackView()
        settingsStackView.translatesAutoresizingMaskIntoConstraints = false
        settingsStackView.orientation = .vertical
        settingsStackView.spacing = rowSpacing
        settingsStackView.alignment = .leading
        sectionView.addSubview(settingsStackView)

        let lineBreakRow = createSettingRow(
            label: I18n.str("Line Break:"),
            options: [localizedLineBreak("MiaoYan"), localizedLineBreak("Github")],
            action: #selector(lineBreakChanged(_:))
        )
        settingsStackView.addArrangedSubview(lineBreakRow)

        let uploadRow = createSettingRow(
            label: I18n.str("Upload Service:"),
            options: [I18n.str("None"), "uPic", "PicGo", "Picsee", "PicList"],
            action: #selector(uploadServiceChanged(_:))
        )
        settingsStackView.addArrangedSubview(uploadRow)

        let locationRow = createSettingRow(
            label: I18n.str("Preview Location:"),
            options: [localizedPreviewLocation("Begin"), localizedPreviewLocation("Editing")],
            action: #selector(previewLocationChanged(_:))
        )
        settingsStackView.addArrangedSubview(locationRow)

        let widthRow = createSettingRow(
            label: I18n.str("Preview Width:"),
            options: [
                localizedPreviewWidth("600px"), localizedPreviewWidth("800px"), localizedPreviewWidth("1000px"), localizedPreviewWidth("1200px"), localizedPreviewWidth("1400px"), localizedPreviewWidth(UserDefaultsManagement.FullWidthValue),
            ],
            action: #selector(previewWidthChanged(_:))
        )
        settingsStackView.addArrangedSubview(widthRow)

        NSLayoutConstraint.activate([
            settingsStackView.topAnchor.constraint(equalTo: sectionView.topAnchor, constant: topSpacing),
            settingsStackView.leadingAnchor.constraint(equalTo: sectionView.leadingAnchor, constant: horizontalInset),
            settingsStackView.trailingAnchor.constraint(lessThanOrEqualTo: sectionView.trailingAnchor, constant: -horizontalInset),
            settingsStackView.bottomAnchor.constraint(equalTo: sectionView.bottomAnchor, constant: -16),
            sectionView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor, constant: -20),
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

    private func createSettingRow(label: String, options: [String], action: Selector) -> NSView {
        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .left

        let popUp = NSPopUpButton()
        popUp.translatesAutoresizingMaskIntoConstraints = false
        popUp.target = self
        popUp.action = action

        for option in options {
            popUp.addItem(withTitle: option)
        }

        rowView.addSubview(label)
        rowView.addSubview(popUp)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: rowView.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 140),

            popUp.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 16),
            popUp.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            popUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

            rowView.heightAnchor.constraint(equalToConstant: 24),
            rowView.trailingAnchor.constraint(greaterThanOrEqualTo: popUp.trailingAnchor),
        ])

        return rowView
    }

    override func setupValues() {
        selectLineBreakOption(settings.editorLineBreak)

        selectUploadServiceOption(UserDefaultsManagement.defaultPicUpload)
        selectPreviewLocationOption(settings.previewLocation)
        selectPreviewWidthOption(settings.previewWidth)
    }

    private func selectLineBreakOption(_ value: String) {
        guard !settingsStackView.arrangedSubviews.isEmpty,
            let popUp = settingsStackView.arrangedSubviews[0].subviews.first(where: { $0 is NSPopUpButton }) as? NSPopUpButton
        else { return }
        popUp.selectItem(withTitle: localizedLineBreak(value))
    }

    private func selectPreviewLocationOption(_ value: String) {
        guard settingsStackView.arrangedSubviews.count > 2,
            let popUp = settingsStackView.arrangedSubviews[2].subviews.first(where: { $0 is NSPopUpButton }) as? NSPopUpButton
        else { return }
        popUp.selectItem(withTitle: localizedPreviewLocation(value))
    }

    private func selectPreviewWidthOption(_ value: String) {
        guard settingsStackView.arrangedSubviews.count > 3,
            let popUp = settingsStackView.arrangedSubviews[3].subviews.first(where: { $0 is NSPopUpButton }) as? NSPopUpButton
        else { return }
        popUp.selectItem(withTitle: localizedPreviewWidth(value))
    }

    private func selectUploadServiceOption(_ value: String) {
        guard settingsStackView.arrangedSubviews.count > 1,
            let popUp = settingsStackView.arrangedSubviews[1].subviews.first(where: { $0 is NSPopUpButton }) as? NSPopUpButton
        else { return }
        if value == "None" {
            popUp.selectItem(withTitle: I18n.str("None"))
        } else {
            popUp.selectItem(withTitle: value)
        }
    }

    // MARK: - Actions

    @objc private func lineBreakChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        settings.editorLineBreak = rawLineBreak(from: item.title)
        settings.applyChanges()
    }

    @objc private func previewLocationChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        settings.previewLocation = rawPreviewLocation(from: item.title)
        settings.applyChanges()
    }

    @objc private func previewWidthChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        settings.previewWidth = rawPreviewWidth(from: item.title)
        settings.applyChanges()
    }

    @objc private func uploadServiceChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        let title = item.title
        UserDefaultsManagement.defaultPicUpload = (title == I18n.str("None")) ? "None" : title
        if title != "None", let vc = ViewController.shared() {
            vc.toastImageSet(name: title)
        }
    }

    // MARK: - Localization Helpers for raw/display mapping
    private func localizedLineBreak(_ raw: String) -> String {
        switch raw {
        case "MiaoYan": return I18n.str("MiaoYan")
        case "Github": return I18n.str("Github")
        default: return raw
        }
    }

    private func rawLineBreak(from display: String) -> String {
        if display == I18n.str("MiaoYan") { return "MiaoYan" }
        if display == I18n.str("Github") { return "Github" }
        return display
    }

    private func localizedPreviewLocation(_ raw: String) -> String {
        switch raw {
        case "Begin": return I18n.str("Begin")
        case "Editing": return I18n.str("Editing")
        default: return raw
        }
    }

    private func rawPreviewLocation(from display: String) -> String {
        if display == I18n.str("Begin") { return "Begin" }
        if display == I18n.str("Editing") { return "Editing" }
        return display
    }

    private func localizedPreviewWidth(_ raw: String) -> String {
        if raw == UserDefaultsManagement.FullWidthValue { return I18n.str("Full Width") }
        return raw
    }

    private func rawPreviewWidth(from display: String) -> String {
        if display == I18n.str("Full Width") { return UserDefaultsManagement.FullWidthValue }
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
