import Cocoa

@MainActor
final class TypographyPrefsViewController: BasePrefsViewController {
    private var settings = EditorSettings()
    private var fontStackView: NSStackView!

    // Font types bundled with the app
    private enum FontType: String, CaseIterable {
        case tsanger = "TsangerJinKai02-W04"

        var editorFontName: String { rawValue }
        var windowFontName: String { rawValue }
        var previewFontName: String { rawValue }

        static func from(actualFontName: String) -> FontType? {
            return allCases.first { t in
                t.rawValue == actualFontName || t.editorFontName == actualFontName || t.windowFontName == actualFontName || t.previewFontName == actualFontName
            }
        }

        var isAvailable: Bool {
            return NSFont(name: rawValue, size: 12) != nil
        }
    }

    override func setupUI() {
        setupFontSection(in: installPreferencesStack())
    }

    private func setupFontSection(in stackView: NSStackView) {
        fontStackView = stackView

        let editorFontRow = createFontRow(
            label: I18n.str("Editor Font:"),
            fontAction: #selector(editorFontChanged(_:)),
            sizeAction: #selector(editorFontSizeChanged(_:))
        )
        fontStackView.addArrangedSubview(editorFontRow)

        let previewFontRow = createFontRow(
            label: I18n.str("Preview Font:"),
            fontAction: #selector(previewFontChanged(_:)),
            sizeAction: #selector(previewFontSizeChanged(_:))
        )
        fontStackView.addArrangedSubview(previewFontRow)

        let windowFontRow = createSingleFontRow(
            label: I18n.str("Interface Font:"),
            action: #selector(windowFontChanged(_:))
        )
        fontStackView.addArrangedSubview(windowFontRow)

        let codeFontRow = createSingleFontRow(
            label: I18n.str("Code Font:"),
            action: #selector(codeFontChanged(_:))
        )
        fontStackView.addArrangedSubview(codeFontRow)

        // Presentation font size
        let presentationSizeRow = createSizeRow(
            label: I18n.str("Presentation Font Size:"),
            action: #selector(presentationFontSizeChanged(_:))
        )
        fontStackView.addArrangedSubview(presentationSizeRow)
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

    private func createFontRow(label: String, fontAction: Selector, sizeAction: Selector) -> NSView {
        let fontPopUp = NSPopUpButton()
        fontPopUp.translatesAutoresizingMaskIntoConstraints = false
        fontPopUp.target = self
        fontPopUp.action = fontAction
        // Initialize with the correct current font for this row
        if fontAction == #selector(editorFontChanged(_:)) {
            setupFontPopUp(fontPopUp, currentName: settings.editorFontName)
        } else if fontAction == #selector(previewFontChanged(_:)) {
            setupFontPopUp(fontPopUp, currentName: settings.previewFontName)
        } else {
            setupFontPopUp(fontPopUp, currentName: nil)
        }

        let sizePopUp = NSPopUpButton()
        sizePopUp.translatesAutoresizingMaskIntoConstraints = false
        sizePopUp.target = self
        sizePopUp.action = sizeAction
        setupFontSizePopUp(sizePopUp)

        fontPopUp.widthAnchor.constraint(equalToConstant: 220).isActive = true
        sizePopUp.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let controls = makeControlStack([fontPopUp, sizePopUp])
        return makePreferencesRow(labelText: label, control: controls, controlWidth: nil)
    }

    private func createSingleFontRow(label: String, action: Selector) -> NSView {
        let popUp = NSPopUpButton()
        popUp.translatesAutoresizingMaskIntoConstraints = false
        popUp.target = self
        popUp.action = action

        if action == #selector(codeFontChanged(_:)) {
            setupFontPopUp(popUp, currentName: settings.codeFontName)
        } else if action == #selector(windowFontChanged(_:)) {
            setupFontPopUp(popUp, currentName: settings.windowFontName)
        } else {
            setupFontPopUp(popUp, currentName: nil)
        }

        return makePreferencesRow(labelText: label, control: popUp)
    }

    private func createSizeRow(label: String, action: Selector) -> NSView {
        let popUp = NSPopUpButton()
        popUp.translatesAutoresizingMaskIntoConstraints = false
        popUp.target = self
        popUp.action = action
        setupFontSizePopUp(popUp)

        return makePreferencesRow(labelText: label, control: popUp, controlWidth: PrefsFormMetrics.compactControlWidth)
    }

    private func setupFontPopUp(_ popUp: NSPopUpButton, currentName: String?) {
        popUp.removeAllItems()

        // Known families (list by their actual face names for clarity)
        let candidates: [FontType] = FontType.allCases
        for font in candidates where font.isAvailable {
            popUp.addItem(withTitle: font.editorFontName)
        }

        // Add all installed font families so user can pick more
        let families = NSFontManager.shared.availableFontFamilies
        for family in families.sorted() {
            if candidates.contains(where: { $0.editorFontName == family || $0.rawValue == family }) { continue }
            if popUp.itemTitles.contains(family) { continue }
            popUp.addItem(withTitle: family)
        }

        // Add current value if not in the list and select it
        if let name = currentName, !name.isEmpty, !popUp.itemTitles.contains(name) {
            popUp.addItem(withTitle: name)
        }

        // Select the current font after all items are added
        if let name = currentName, !name.isEmpty {
            popUp.selectItem(withTitle: name)
        }
    }

    private func getFontType(from title: String) -> FontType? {
        // Match by raw/editor/preview/window names only (no localized alias)
        for t in FontType.allCases {
            if title == t.rawValue || title == t.editorFontName || title == t.windowFontName || title == t.previewFontName {
                return t
            }
        }
        return nil
    }

    private func setupFontSizePopUp(_ popUp: NSPopUpButton) {
        popUp.removeAllItems()
        let sizes = [12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24, 26, 28]
        for s in sizes { popUp.addItem(withTitle: String(s)) }
    }

    override func setupValues() {
        // Font selections are already handled in setupFontPopUp during createFontRow
        // Only need to set size selections here to avoid double-setting font selections
        let rows = fontStackView.arrangedSubviews

        // Editor font size
        if !rows.isEmpty {
            selectSizeInPopUp(rows[0], size: settings.editorFontSize)
        }
        // Preview font size
        if rows.count > 1 {
            selectSizeInPopUp(rows[1], size: settings.previewFontSize)
        }
        // Presentation font size
        if rows.count > 4 {
            selectSizeInPopUp(rows[4], size: settings.presentationFontSize)
        }
    }

    private func selectFontInPopUp(_ rowView: NSView, fontType: FontType) {
        if let fontPopUp = rowView.subviews.first(where: { $0 is NSPopUpButton }) as? NSPopUpButton {
            // Match against actual face name we populate with
            fontPopUp.selectItem(withTitle: fontType.editorFontName)
        }
    }

    private func selectSizeInPopUp(_ rowView: NSView, size: Int) {
        guard let sizePopUp = lastPopUpButton(in: rowView) else { return }
        sizePopUp.selectItem(withTitle: String(size))
    }

    private func lastPopUpButton(in view: NSView) -> NSPopUpButton? {
        for subview in view.subviews.reversed() {
            if let popUp = subview as? NSPopUpButton { return popUp }
            if let found = lastPopUpButton(in: subview) { return found }
        }
        return nil
    }

    // MARK: - Actions
    @objc private func editorFontChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        let actualFontName = getFontType(from: item.title)?.editorFontName ?? item.title
        settings.editorFontName = actualFontName
        settings.applyChanges()
    }

    @objc private func editorFontSizeChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        settings.editorFontSize = Int(item.title) ?? UserDefaultsManagement.DefaultFontSize
        settings.applyChanges()
    }

    @objc private func windowFontChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        let actualFontName = getFontType(from: item.title)?.windowFontName ?? item.title
        if settings.windowFontName == actualFontName { return }
        settings.windowFontName = actualFontName
        // Live-apply interface font without restart
        if let vc = ViewController.shared() {
            vc.applyInterfacePreferences()
        }
    }

    @objc private func previewFontChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        let actualFontName = getFontType(from: item.title)?.previewFontName ?? item.title
        settings.previewFontName = actualFontName
        settings.applyChanges()
    }

    @objc private func previewFontSizeChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        settings.previewFontSize = Int(item.title) ?? UserDefaultsManagement.DefaultPreviewFontSize
        settings.applyChanges()
    }

    @objc private func codeFontChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        let actualFontName = getFontType(from: item.title)?.editorFontName ?? item.title
        settings.codeFontName = actualFontName
        NotesTextProcessor.codeFont = NSFont(name: settings.codeFontName, size: CGFloat(settings.editorFontSize))
        settings.applyChanges()
    }

    @objc private func presentationFontSizeChanged(_ sender: NSPopUpButton) {
        guard let vc = ViewController.shared() else { return }
        guard let item = sender.selectedItem else { return }
        settings.presentationFontSize = Int(item.title) ?? UserDefaultsManagement.DefaultPresentationFontSize
        if !vc.isMiaoYanPPT(needToast: false) {
            vc.disablePresentation()
            vc.enablePresentation()
        }
    }

}
