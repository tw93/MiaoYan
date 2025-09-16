import Cocoa

final class EditorPrefsViewController: BasePrefsViewController {
    private var settings = EditorSettings()
    private var behaviorStackView: NSStackView!
    private var previewStackView: NSStackView!
    private var uploadStackView: NSStackView!

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

        // Setup sections (fonts moved to Typography preferences)
        setupEditorBehaviorSection(in: contentView)
        setupImageUploadSection(in: contentView)
        setupPreviewSection(in: contentView)

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

    // Fonts section removed: moved to Typography preferences

    private func setupEditorBehaviorSection(in parentView: NSView) {
        // Position at top if it's the first section
        let anchor: NSLayoutAnchor<NSLayoutYAxisAnchor>
        let topConstant: CGFloat
        if let last = parentView.subviews.last {
            anchor = last.bottomAnchor
            topConstant = 20
        } else {
            anchor = parentView.topAnchor
            topConstant = 0
        }
        let sectionView = createSectionView(
            title: I18n.str("Editor Behavior"),
            in: parentView,
            topAnchor: anchor,
            topConstant: topConstant
        )

        behaviorStackView = NSStackView()
        behaviorStackView.translatesAutoresizingMaskIntoConstraints = false
        behaviorStackView.orientation = .vertical
        behaviorStackView.spacing = 12
        behaviorStackView.alignment = .leading
        sectionView.addSubview(behaviorStackView)

        // Line break
        let lineBreakRow = createSettingRow(
            label: I18n.str("Line Break:"),
            options: [localizedLineBreak("MiaoYan"), localizedLineBreak("Github")],
            action: #selector(lineBreakChanged(_:))
        )
        behaviorStackView.addArrangedSubview(lineBreakRow)

        // Code background setting removed: default is no background

        NSLayoutConstraint.activate([
            behaviorStackView.topAnchor.constraint(equalTo: sectionView.topAnchor, constant: 35),
            behaviorStackView.leadingAnchor.constraint(equalTo: sectionView.leadingAnchor, constant: 20),
            behaviorStackView.trailingAnchor.constraint(lessThanOrEqualTo: sectionView.trailingAnchor, constant: -20),
            behaviorStackView.bottomAnchor.constraint(equalTo: sectionView.bottomAnchor, constant: -16),
        ])
    }

    private func setupImageUploadSection(in parentView: NSView) {
        let anchor: NSLayoutAnchor<NSLayoutYAxisAnchor> = parentView.subviews.last?.bottomAnchor ?? parentView.topAnchor
        let top: CGFloat = parentView.subviews.isEmpty ? 0 : 20
        let sectionView = createSectionView(
            title: I18n.str("Image Upload"),
            in: parentView,
            topAnchor: anchor,
            topConstant: top
        )

        uploadStackView = NSStackView()
        uploadStackView.translatesAutoresizingMaskIntoConstraints = false
        uploadStackView.orientation = .vertical
        uploadStackView.spacing = 12
        uploadStackView.alignment = .leading
        sectionView.addSubview(uploadStackView)

        // Upload service selection
        let uploadRow = createSettingRow(
            label: I18n.str("Upload Service:"),
            options: [I18n.str("None"), "PicGo", "uPic", "Picsee"],
            action: #selector(uploadServiceChanged(_:))
        )
        uploadStackView.addArrangedSubview(uploadRow)

        NSLayoutConstraint.activate([
            uploadStackView.topAnchor.constraint(equalTo: sectionView.topAnchor, constant: 35),
            uploadStackView.leadingAnchor.constraint(equalTo: sectionView.leadingAnchor, constant: 20),
            uploadStackView.trailingAnchor.constraint(lessThanOrEqualTo: sectionView.trailingAnchor, constant: -20),
            uploadStackView.bottomAnchor.constraint(equalTo: sectionView.bottomAnchor, constant: -16),
        ])
    }

    private func setupPreviewSection(in parentView: NSView) {
        let anchor: NSLayoutAnchor<NSLayoutYAxisAnchor> = parentView.subviews.last?.bottomAnchor ?? parentView.topAnchor
        let top: CGFloat = parentView.subviews.isEmpty ? 0 : 20
        let sectionView = createSectionView(
            title: I18n.str("Preview"),
            in: parentView,
            topAnchor: anchor,
            topConstant: top
        )

        previewStackView = NSStackView()
        previewStackView.translatesAutoresizingMaskIntoConstraints = false
        previewStackView.orientation = .vertical
        previewStackView.spacing = 12
        previewStackView.alignment = .leading
        sectionView.addSubview(previewStackView)

        // Preview location (legacy behavior: Begin / Editing)
        let locationRow = createSettingRow(
            label: I18n.str("Preview Location:"),
            options: [localizedPreviewLocation("Begin"), localizedPreviewLocation("Editing")],
            action: #selector(previewLocationChanged(_:))
        )
        previewStackView.addArrangedSubview(locationRow)

        // Preview width
        let widthRow = createSettingRow(
            label: I18n.str("Preview Width:"),
            options: [localizedPreviewWidth("600px"), localizedPreviewWidth("800px"), localizedPreviewWidth("1000px"), localizedPreviewWidth("1200px"), localizedPreviewWidth("1400px"), localizedPreviewWidth("Full Width")],
            action: #selector(previewWidthChanged(_:))
        )
        previewStackView.addArrangedSubview(widthRow)

        NSLayoutConstraint.activate([
            previewStackView.topAnchor.constraint(equalTo: sectionView.topAnchor, constant: 35),
            previewStackView.leadingAnchor.constraint(equalTo: sectionView.leadingAnchor, constant: 20),
            previewStackView.trailingAnchor.constraint(lessThanOrEqualTo: sectionView.trailingAnchor, constant: -20),
            previewStackView.bottomAnchor.constraint(equalTo: sectionView.bottomAnchor, constant: -16),
            sectionView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor, constant: -20),
        ])
    }

    // Helper methods for creating UI components
    private func createSectionView(title: String, in parentView: NSView, topAnchor: NSLayoutAnchor<NSLayoutYAxisAnchor>, topConstant: CGFloat) -> NSView {
        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false

        // Keep background consistent with parent (no separate gray panel)
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

    // Font UI rows and helpers removed here (managed in TypographyPrefsViewController)

    private func createSettingRow(label: String, options: [String], action: Selector) -> NSView {
        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: label)
        label.translatesAutoresizingMaskIntoConstraints = false

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
            label.widthAnchor.constraint(equalToConstant: 180),

            popUp.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 12),
            popUp.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            popUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

            rowView.heightAnchor.constraint(equalToConstant: 24),
            rowView.trailingAnchor.constraint(greaterThanOrEqualTo: popUp.trailingAnchor),
        ])

        return rowView
    }

    // Font helpers removed

    override func setupValues() {
        // Set editor behavior values
        selectLineBreakOption(settings.editorLineBreak)

        // Set preview settings
        selectPreviewLocationOption(settings.previewLocation)
        selectPreviewWidthOption(settings.previewWidth)

        // Set upload service
        selectUploadServiceOption(UserDefaultsManagement.defaultPicUpload)
    }

    // Font selection helpers removed

    private func selectLineBreakOption(_ value: String) {
        // Find and set line break popup using behaviorStackView
        if !behaviorStackView.arrangedSubviews.isEmpty,
            let popUp = behaviorStackView.arrangedSubviews[0].subviews.first(where: { $0 is NSPopUpButton }) as? NSPopUpButton
        {
            popUp.selectItem(withTitle: localizedLineBreak(value))
        }
    }

    // Code background selection removed

    private func selectPreviewLocationOption(_ value: String) {
        // Find and set preview location popup using previewStackView
        if !previewStackView.arrangedSubviews.isEmpty,
            let popUp = previewStackView.arrangedSubviews[0].subviews.first(where: { $0 is NSPopUpButton }) as? NSPopUpButton
        {
            popUp.selectItem(withTitle: localizedPreviewLocation(value))
        }
    }

    private func selectPreviewWidthOption(_ value: String) {
        // Find and set preview width popup using previewStackView
        if previewStackView.arrangedSubviews.count > 1,
            let popUp = previewStackView.arrangedSubviews[1].subviews.first(where: { $0 is NSPopUpButton }) as? NSPopUpButton
        {
            popUp.selectItem(withTitle: localizedPreviewWidth(value))
        }
    }

    private func selectUploadServiceOption(_ value: String) {
        if let uploadRow = uploadStackView?.arrangedSubviews.first,
            let popUp = uploadRow.subviews.first(where: { $0 is NSPopUpButton }) as? NSPopUpButton
        {
            if value == "None" {
                popUp.selectItem(withTitle: I18n.str("None"))
            } else {
                popUp.selectItem(withTitle: value)
            }
        }
    }

    // MARK: - Actions
    // Font-related actions removed from Editor preferences

    @objc private func lineBreakChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        // Map localized display to raw value
        settings.editorLineBreak = rawLineBreak(from: item.title)
        settings.applyChanges()
    }

    // Code background change handler removed

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
        if raw == "Full Width" { return I18n.str("Full Width") }
        return raw
    }

    private func rawPreviewWidth(from display: String) -> String {
        if display == I18n.str("Full Width") { return "Full Width" }
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

