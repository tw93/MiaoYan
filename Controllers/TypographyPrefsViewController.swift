import Cocoa

@MainActor
final class TypographyPrefsViewController: BasePrefsViewController, NSMenuDelegate {
    private var settings = EditorSettings()
    private var fontPopUps: [NSPopUpButton] = []
    private var editorSizePopUp: PrefsDropdown!
    private var previewSizePopUp: PrefsDropdown!
    private var presentationSizePopUp: PrefsDropdown!

    override func setupUI() {
        let editorFont = makeFontDropdown(kind: .text, currentName: settings.editorFontName, action: #selector(editorFontChanged(_:)))
        let previewFont = makeFontDropdown(kind: .text, currentName: settings.previewFontName, action: #selector(previewFontChanged(_:)))
        let codeFont = makeFontDropdown(kind: .code, currentName: settings.codeFontName, action: #selector(codeFontChanged(_:)))
        let windowFont = makeFontDropdown(kind: .text, currentName: settings.windowFontName, action: #selector(windowFontChanged(_:)))
        editorSizePopUp = makeSizeDropdown(action: #selector(editorFontSizeChanged(_:)))
        previewSizePopUp = makeSizeDropdown(action: #selector(previewFontSizeChanged(_:)))
        presentationSizePopUp = makeSizeDropdown(action: #selector(presentationFontSizeChanged(_:)))

        addSections([
            [
                PrefsRowView(title: I18n.str("Editor Font"), detail: "", controls: [editorFont, editorSizePopUp]),
                PrefsRowView(title: I18n.str("Preview Font"), detail: "", controls: [previewFont, previewSizePopUp]),
                PrefsRowView(title: I18n.str("Code Font"), detail: I18n.str("Used in fenced code blocks"), controls: [codeFont]),
                PrefsRowView(title: I18n.str("Interface Font"), detail: I18n.str("Used in the sidebar and note list"), controls: [windowFont]),
            ],
            [
                PrefsRowView(title: I18n.str("Presentation Font Size"), detail: I18n.str("Used for MiaoYan PPT slides"), controls: [presentationSizePopUp])
            ],
        ])
    }

    private func makeFontDropdown(kind: FontListKind, currentName: String, action: Selector) -> PrefsDropdown {
        let popUp = PrefsDropdown(maximumWidth: PrefsMetrics.fontDropdownMaxWidth)
        popUp.target = self
        popUp.action = action
        fontPopUps.append(popUp)
        setupFontPopUp(popUp, kind: kind, currentName: currentName)
        return popUp
    }

    private func makeSizeDropdown(action: Selector) -> PrefsDropdown {
        let popUp = PrefsDropdown()
        popUp.target = self
        popUp.action = action
        for size in [12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24, 26, 28] {
            popUp.addItem(withTitle: String(size))
            popUp.lastItem?.tag = size
        }
        return popUp
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
                // Carries the name older installs store, so a preference still
                // waiting for the face selects this row instead of an orphan.
                item.representedObject = FontCatalog.retiredBundledFace
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

    /// Returns the name to store. Picking TsangerJinKai02 before it is
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
            "MiaoYan does not bundle this font. "
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

    override func setupValues() {
        // Font rows select their family while their menus are built.
        _ = editorSizePopUp.selectItem(withTag: settings.editorFontSize)
        _ = previewSizePopUp.selectItem(withTag: settings.previewFontSize)
        _ = presentationSizePopUp.selectItem(withTag: settings.presentationFontSize)
    }

    // MARK: - Actions
    @objc private func editorFontChanged(_ sender: NSPopUpButton) {
        guard let actualFontName = resolveSelection(sender, previous: settings.editorFontName) else { return }
        settings.editorFontName = actualFontName
        settings.applyChanges()
    }

    @objc private func editorFontSizeChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        settings.editorFontSize = item.tag
        settings.applyChanges()
    }

    @objc private func windowFontChanged(_ sender: NSPopUpButton) {
        guard let actualFontName = resolveSelection(sender, previous: settings.windowFontName) else { return }
        if settings.windowFontName == actualFontName { return }
        settings.windowFontName = actualFontName
        // Live-apply interface font without restart
        if let vc = ViewController.shared() {
            vc.applyInterfacePreferences()
        } else {
            NotificationCenter.default.post(name: .editorSettingsChanged, object: nil)
        }
    }

    @objc private func previewFontChanged(_ sender: NSPopUpButton) {
        guard let actualFontName = resolveSelection(sender, previous: settings.previewFontName) else { return }
        settings.previewFontName = actualFontName
        settings.applyChanges()
    }

    @objc private func previewFontSizeChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        settings.previewFontSize = item.tag
        settings.applyChanges()
    }

    @objc private func codeFontChanged(_ sender: NSPopUpButton) {
        guard let actualFontName = resolveSelection(sender, previous: settings.codeFontName) else { return }
        settings.codeFontName = actualFontName
        settings.applyChanges()
    }

    @objc private func presentationFontSizeChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        settings.presentationFontSize = item.tag
        // Only a running presentation needs redrawing at the new size; outside
        // it the value is just stored, and opening a presentation picks it up.
        if let vc = ViewController.shared(), vc.sessionPresentationMode {
            vc.disablePresentation()
            vc.enablePresentation()
        } else if #available(macOS 14, *),
            let shell = (NSApp.delegate as? AppDelegate)?.shellWindowController as? ShellWindowController,
            shell.model.isPresenting
        {
            shell.model.applyEditorSettings()
        }
    }

}
