import Cocoa

@MainActor
final class TypographyPrefsViewController: BasePrefsViewController, NSMenuDelegate {
    private var settings = EditorSettings()
    private var fontPopUps: [NSPopUpButton] = []
    private var editorSizePopUp: NSPopUpButton!
    private var previewSizePopUp: NSPopUpButton!
    private var presentationSizePopUp: NSPopUpButton!

    override func setupUI() {
        setupFontSection(in: installPreferencesStack())
    }

    private func setupFontSection(in stackView: NSStackView) {
        let (editorFontRow, editorSize) = createFontRow(
            label: I18n.str("Editor Font:"),
            fontAction: #selector(editorFontChanged(_:)),
            sizeAction: #selector(editorFontSizeChanged(_:))
        )
        let (previewFontRow, previewSize) = createFontRow(
            label: I18n.str("Preview Font:"),
            fontAction: #selector(previewFontChanged(_:)),
            sizeAction: #selector(previewFontSizeChanged(_:))
        )
        editorSizePopUp = editorSize
        previewSizePopUp = previewSize

        let windowFontRow = createSingleFontRow(
            label: I18n.str("Interface Font:"),
            action: #selector(windowFontChanged(_:))
        )
        let codeFontRow = createSingleFontRow(
            label: I18n.str("Code Font:"),
            action: #selector(codeFontChanged(_:))
        )

        presentationSizePopUp = NSPopUpButton()
        presentationSizePopUp.translatesAutoresizingMaskIntoConstraints = false
        presentationSizePopUp.target = self
        presentationSizePopUp.action = #selector(presentationFontSizeChanged(_:))
        setupFontSizePopUp(presentationSizePopUp)
        let presentationSizeRow = makePreferencesRow(
            labelText: I18n.str("Presentation Font Size:"),
            control: presentationSizePopUp,
            controlWidth: PrefsFormMetrics.sizeControlWidth
        )

        addPreferencesGroups(
            [
                [editorFontRow, previewFontRow, windowFontRow, codeFontRow],
                [presentationSizeRow],
            ], to: stackView)
    }

    private func createFontRow(label: String, fontAction: Selector, sizeAction: Selector) -> (NSView, NSPopUpButton) {
        let fontPopUp = NSPopUpButton()
        fontPopUp.translatesAutoresizingMaskIntoConstraints = false
        fontPopUp.target = self
        fontPopUp.action = fontAction
        fontPopUps.append(fontPopUp)
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

        let spacing: CGFloat = 12
        let fontWidth = PrefsFormMetrics.controlWidth - spacing - PrefsFormMetrics.sizeControlWidth
        fontPopUp.widthAnchor.constraint(equalToConstant: fontWidth).isActive = true
        sizePopUp.widthAnchor.constraint(equalToConstant: PrefsFormMetrics.sizeControlWidth).isActive = true

        let controls = makeControlStack([fontPopUp, sizePopUp], spacing: spacing)
        return (makePreferencesRow(labelText: label, control: controls), sizePopUp)
    }

    private func createSingleFontRow(label: String, action: Selector) -> NSView {
        let popUp = NSPopUpButton()
        popUp.translatesAutoresizingMaskIntoConstraints = false
        popUp.target = self
        popUp.action = action
        fontPopUps.append(popUp)

        if action == #selector(codeFontChanged(_:)) {
            setupFontPopUp(popUp, kind: .code, currentName: settings.codeFontName)
        } else if action == #selector(windowFontChanged(_:)) {
            setupFontPopUp(popUp, kind: .text, currentName: settings.windowFontName)
        } else {
            setupFontPopUp(popUp, kind: .text, currentName: nil)
        }

        return makePreferencesRow(labelText: label, control: popUp)
    }

    private func setupFontPopUp(_ popUp: NSPopUpButton, kind: FontListKind, currentName: String?) {
        popUp.removeAllItems()
        // NSPopUpButton enables its items on its own by default, which overrode
        // the section headings' `isEnabled = false` and let them be picked as if
        // they were fonts.
        popUp.autoenablesItems = false
        guard let menu = popUp.menu else { return }
        menu.delegate = self

        if kind == .code {
            let follow = NSMenuItem(title: I18n.str("Same as Text"), action: nil, keyEquivalent: "")
            follow.representedObject = FontConfiguration.followTextFont
            menu.addItem(follow)
            menu.addItem(.separator())
        }

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
                // Carries the name the default stores, so a preference still
                // waiting for the face selects this row instead of an orphan.
                item.representedObject = FontConfiguration.defaultPreviewFont
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let popup = fontPopUps.first(where: { $0.menu === menu }) else { return }
        let currentName: String
        switch popup.action {
        case #selector(editorFontChanged(_:)): currentName = settings.editorFontName
        case #selector(previewFontChanged(_:)): currentName = settings.previewFontName
        case #selector(windowFontChanged(_:)): currentName = settings.windowFontName
        case #selector(codeFontChanged(_:)): currentName = settings.codeFontName
        default: return
        }
        let kind: FontListKind = popup.action == #selector(codeFontChanged(_:)) ? .code : .text
        setupFontPopUp(popup, kind: kind, currentName: currentName)
    }

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

    /// Returns the name to store. Picking the default face before it is
    /// installed keeps the choice, and the face takes over once installed.
    private func resolveSelection(_ sender: NSPopUpButton, previous: String) -> String? {
        guard let item = sender.selectedItem else { return nil }
        if item.tag == Self.retiredFontTag {
            presentRetiredFontGuidance()
        }
        return item.representedObject as? String ?? item.title
    }

    private func presentRetiredFontGuidance() {
        let alert = NSAlert()
        alert.messageText = I18n.str("Install the font first")
        // Joined at runtime into the exact key the strings files use.
        let guidance =
            "MiaoYan uses this font by default but no longer bundles it. "
            + "Double-click the downloaded file to install it, and MiaoYan switches to it on its own. "
            + "Personal non-commercial use is free; commercial work needs a licence from Tsanger."
        alert.informativeText = I18n.str(guidance)
        alert.addButton(withTitle: I18n.str("Download Font"))
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
        editorSizePopUp.selectItem(withTitle: String(settings.editorFontSize))
        previewSizePopUp.selectItem(withTitle: String(settings.previewFontSize))
        presentationSizePopUp.selectItem(withTitle: String(settings.presentationFontSize))
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
