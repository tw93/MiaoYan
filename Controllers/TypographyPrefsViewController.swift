import Cocoa

@MainActor
final class TypographyPrefsViewController: BasePrefsViewController {
    private var settings = EditorSettings()
    private var fontStackView: NSStackView!

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

    private func createFontRow(label: String, fontAction: Selector, sizeAction: Selector) -> NSView {
        let fontPopUp = NSPopUpButton()
        fontPopUp.translatesAutoresizingMaskIntoConstraints = false
        fontPopUp.target = self
        fontPopUp.action = fontAction
        // Initialize with the correct current font for this row
        if fontAction == #selector(editorFontChanged(_:)) {
            setupFontPopUp(fontPopUp, kind: .text, currentName: settings.editorFontName)
        } else if fontAction == #selector(previewFontChanged(_:)) {
            setupFontPopUp(fontPopUp, kind: .text, currentName: settings.previewFontName)
        } else {
            setupFontPopUp(fontPopUp, kind: .text, currentName: nil)
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
            setupFontPopUp(popUp, kind: .code, currentName: settings.codeFontName)
        } else if action == #selector(windowFontChanged(_:)) {
            setupFontPopUp(popUp, kind: .text, currentName: settings.windowFontName)
        } else {
            setupFontPopUp(popUp, kind: .text, currentName: nil)
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

    private func setupFontPopUp(_ popUp: NSPopUpButton, kind: FontListKind, currentName: String?) {
        popUp.removeAllItems()
        guard let menu = popUp.menu else { return }

        let recommended = FontCatalog.installedRecommendations(for: kind)
        let missingRetired =
            kind == .text && !FontCatalog.isInstalled(family: FontCatalog.retiredBundledFamily)
            ? FontCatalog.retiredBundledFamily : nil

        if !recommended.isEmpty || missingRetired != nil {
            menu.addItem(sectionHeader(I18n.str("Recommended")))
            for family in recommended { menu.addItem(fontItem(family: family)) }
            if let missing = missingRetired {
                let item = NSMenuItem(
                    title: "\(FontCatalog.displayName(for: missing)) (\(I18n.str("Not installed")))",
                    action: nil, keyEquivalent: "")
                item.tag = Self.retiredFontTag
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        for section in FontCatalog.sections(for: kind) {
            let families = section.families.filter { !recommended.contains($0) }
            guard !families.isEmpty else { continue }
            menu.addItem(sectionHeader(sectionTitle(section.title)))
            for family in families { menu.addItem(fontItem(family: family)) }
        }

        // A stored value can be a PostScript name, or a face this popup filters
        // out, or one that is no longer installed. Resolve it to a family, then
        // keep it as its own row when it still is not here, so the popup shows
        // what is in effect rather than silently selecting something else.
        guard let name = currentName, !name.isEmpty else { return }
        let family = FontCatalog.familyName(forStored: name)
        if item(in: menu, family: family) == nil {
            menu.addItem(.separator())
            menu.addItem(fontItem(family: family))
        }
        if let match = item(in: menu, family: family) { popUp.select(match) }
    }

    private static let retiredFontTag = 9001

    private func sectionTitle(_ key: String) -> String {
        switch key {
        case "zh": return I18n.str("Chinese")
        case "latin": return I18n.str("Latin")
        default: return I18n.str("All Fonts")
        }
    }

    private func item(in menu: NSMenu, family: String) -> NSMenuItem? {
        menu.items.first { $0.representedObject as? String == family }
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// The row reads as the localized name while the family stays on
    /// `representedObject`, because that is what gets stored and matched.
    private func fontItem(family: String) -> NSMenuItem {
        let item = NSMenuItem(title: FontCatalog.displayName(for: family), action: nil, keyEquivalent: "")
        item.representedObject = family
        return item
    }

    /// Returns the family to store, or nil when the row was the retired face and
    /// the popup should bounce back to what it had.
    private func resolveSelection(_ sender: NSPopUpButton, previous: String) -> String? {
        guard let item = sender.selectedItem else { return nil }
        if item.tag == Self.retiredFontTag {
            if let menu = sender.menu,
                let match = self.item(in: menu, family: FontCatalog.familyName(forStored: previous))
            {
                sender.select(match)
            }
            presentRetiredFontGuidance()
            return nil
        }
        return item.representedObject as? String ?? item.title
    }

    private func presentRetiredFontGuidance() {
        let alert = NSAlert()
        alert.messageText = I18n.str("Install the font first")
        alert.informativeText = I18n.str(
            "MiaoYan no longer bundles this font. Personal non-commercial use is free; commercial work needs a separate licence."
        )
        alert.addButton(withTitle: I18n.str("Open Download Page"))
        alert.addButton(withTitle: I18n.str("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn,
            let url = URL(string: FontCatalog.retiredBundledDownloadURL)
        else { return }
        NSWorkspace.shared.open(url)
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
        guard let actualFontName = resolveSelection(sender, previous: settings.editorFontName) else { return }
        settings.editorFontName = actualFontName
        settings.applyChanges()
    }

    @objc private func editorFontSizeChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        settings.editorFontSize = Int(item.title) ?? UserDefaultsManagement.DefaultFontSize
        settings.applyChanges()
    }

    @objc private func windowFontChanged(_ sender: NSPopUpButton) {
        guard let actualFontName = resolveSelection(sender, previous: settings.windowFontName) else { return }
        if settings.windowFontName == actualFontName { return }
        settings.windowFontName = actualFontName
        // Live-apply interface font without restart
        if let vc = ViewController.shared() {
            vc.applyInterfacePreferences()
        }
    }

    @objc private func previewFontChanged(_ sender: NSPopUpButton) {
        guard let actualFontName = resolveSelection(sender, previous: settings.previewFontName) else { return }
        settings.previewFontName = actualFontName
        settings.applyChanges()
    }

    @objc private func previewFontSizeChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        settings.previewFontSize = Int(item.title) ?? UserDefaultsManagement.DefaultPreviewFontSize
        settings.applyChanges()
    }

    @objc private func codeFontChanged(_ sender: NSPopUpButton) {
        guard let actualFontName = resolveSelection(sender, previous: settings.codeFontName) else { return }
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
