import Cocoa

final class TypographyPrefsViewController: BasePrefsViewController {
    private var settings = EditorSettings()
    private var fontStackView: NSStackView!

    // Font types from original implementation
    private enum FontType: String, CaseIterable {
        case tsanger = "TsangerJinKai02-W04"
        case lxgw = "LXGW WenKai Screen"
        case system = "SF Pro Text"
        case times = "Times New Roman"

        var editorFontName: String { self == .system ? "SF Mono" : rawValue }
        var windowFontName: String { self == .system ? "SF Pro Text" : rawValue }
        var previewFontName: String { self == .system ? "SF Pro Text" : rawValue }

        static func from(actualFontName: String) -> FontType? {
            return allCases.first { t in
                t.rawValue == actualFontName || t.editorFontName == actualFontName || t.windowFontName == actualFontName || t.previewFontName == actualFontName
            }
        }

        var isAvailable: Bool {
            return NSFont(name: rawValue, size: 12) != nil || NSFont(name: editorFontName, size: 12) != nil
        }
    }

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

        setupFontSection(in: contentView)

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

    private func setupFontSection(in parentView: NSView) {
        let sectionView = createSectionView(
            title: I18n.str("Fonts"),
            in: parentView,
            topAnchor: parentView.topAnchor,
            topConstant: 0
        )

        fontStackView = NSStackView()
        fontStackView.translatesAutoresizingMaskIntoConstraints = false
        fontStackView.orientation = .vertical
        fontStackView.spacing = 12
        fontStackView.alignment = .leading
        sectionView.addSubview(fontStackView)

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

        NSLayoutConstraint.activate([
            fontStackView.topAnchor.constraint(equalTo: sectionView.topAnchor, constant: 35),
            fontStackView.leadingAnchor.constraint(equalTo: sectionView.leadingAnchor, constant: 20),
            fontStackView.trailingAnchor.constraint(lessThanOrEqualTo: sectionView.trailingAnchor, constant: -20),
            fontStackView.bottomAnchor.constraint(equalTo: sectionView.bottomAnchor, constant: -16),
        ])
    }

    private func createSectionView(title: String, in parentView: NSView, topAnchor: NSLayoutAnchor<NSLayoutYAxisAnchor>, topConstant: CGFloat) -> NSView {
        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
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

    private func createFontRow(label: String, fontAction: Selector, sizeAction: Selector) -> NSView {
        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: label)
        label.translatesAutoresizingMaskIntoConstraints = false

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

        rowView.addSubview(label)
        rowView.addSubview(fontPopUp)
        rowView.addSubview(sizePopUp)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: rowView.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 170),

            fontPopUp.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 16),
            fontPopUp.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            fontPopUp.widthAnchor.constraint(equalToConstant: 220),

            sizePopUp.leadingAnchor.constraint(equalTo: fontPopUp.trailingAnchor, constant: 12),
            sizePopUp.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            sizePopUp.widthAnchor.constraint(equalToConstant: 60),

            rowView.heightAnchor.constraint(equalToConstant: 24),
            rowView.trailingAnchor.constraint(greaterThanOrEqualTo: sizePopUp.trailingAnchor),
        ])

        return rowView
    }

    private func createSingleFontRow(label: String, action: Selector) -> NSView {
        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: label)
        label.translatesAutoresizingMaskIntoConstraints = false

        let popUp = NSPopUpButton()
        popUp.translatesAutoresizingMaskIntoConstraints = false
        popUp.target = self
        popUp.action = action

        if action == #selector(codeFontChanged(_:)) {
            // Special option to follow editor font
            popUp.addItem(withTitle: "Editor Font")
            // Populate with current code font (if any)
            setupFontPopUp(popUp, currentName: settings.codeFontName)
        } else if action == #selector(windowFontChanged(_:)) {
            setupFontPopUp(popUp, currentName: settings.windowFontName)
        } else {
            setupFontPopUp(popUp, currentName: nil)
        }

        rowView.addSubview(label)
        rowView.addSubview(popUp)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: rowView.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 170),

            popUp.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 16),
            popUp.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            popUp.widthAnchor.constraint(equalToConstant: 220),

            rowView.heightAnchor.constraint(equalToConstant: 24),
            rowView.trailingAnchor.constraint(greaterThanOrEqualTo: popUp.trailingAnchor),
        ])

        return rowView
    }

    private func createSizeRow(label: String, action: Selector) -> NSView {
        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: label)
        label.translatesAutoresizingMaskIntoConstraints = false

        let popUp = NSPopUpButton()
        popUp.translatesAutoresizingMaskIntoConstraints = false
        popUp.target = self
        popUp.action = action
        setupFontSizePopUp(popUp)

        rowView.addSubview(label)
        rowView.addSubview(popUp)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: rowView.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 170),

            popUp.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 16),
            popUp.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            popUp.widthAnchor.constraint(equalToConstant: 70),

            rowView.heightAnchor.constraint(equalToConstant: 24),
            rowView.trailingAnchor.constraint(greaterThanOrEqualTo: popUp.trailingAnchor),
        ])

        return rowView
    }

    private func setupFontPopUp(_ popUp: NSPopUpButton, currentName: String?) {
        popUp.removeAllItems()

        // Show current exact value first if provided
        if let name = currentName, !name.isEmpty {
            popUp.addItem(withTitle: name)
        }

        // Known families (list by their actual face names for clarity)
        let candidates: [FontType] = FontType.allCases
        for font in candidates where font.isAvailable {
            if popUp.itemTitles.contains(font.editorFontName) { continue }
            popUp.addItem(withTitle: font.editorFontName)
        }

        // Add all installed font families so user can pick more
        let families = NSFontManager.shared.availableFontFamilies
        for family in families.sorted() {
            if candidates.contains(where: { $0.editorFontName == family || $0.rawValue == family }) { continue }
            if popUp.itemTitles.contains(family) { continue }
            popUp.addItem(withTitle: family)
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
        let rows = fontStackView.arrangedSubviews
        // Editor font + size
        if !rows.isEmpty {
            if let editorType = FontType.from(actualFontName: settings.editorFontName) {
                selectFontInPopUp(rows[0], fontType: editorType)
            } else if let pop = rows[0].subviews.first(where: { $0 is NSPopUpButton }) as? NSPopUpButton {
                pop.selectItem(withTitle: settings.editorFontName)
            }
            selectSizeInPopUp(rows[0], size: settings.editorFontSize)
        }
        // Preview font + size
        if rows.count > 1 {
            if let previewType = FontType.from(actualFontName: settings.previewFontName) {
                selectFontInPopUp(rows[1], fontType: previewType)
            } else if let pop = rows[1].subviews.first(where: { $0 is NSPopUpButton }) as? NSPopUpButton {
                pop.selectItem(withTitle: settings.previewFontName)
            }
            selectSizeInPopUp(rows[1], size: settings.previewFontSize)
        }
        // Interface font
        if rows.count > 2 {
            if let windowType = FontType.from(actualFontName: settings.windowFontName) {
                selectFontInPopUp(rows[2], fontType: windowType)
            } else if let pop = rows[2].subviews.first(where: { $0 is NSPopUpButton }) as? NSPopUpButton {
                pop.selectItem(withTitle: settings.windowFontName)
            }
        }
        // Code font
        if rows.count > 3 {
            if let codeType = FontType.from(actualFontName: settings.codeFontName) {
                selectFontInPopUp(rows[3], fontType: codeType)
            } else if settings.codeFontName == settings.editorFontName {
                selectCodeFontAsEditor(rows[3])
            } else if let pop = rows[3].subviews.first(where: { $0 is NSPopUpButton }) as? NSPopUpButton {
                pop.selectItem(withTitle: settings.codeFontName)
            }
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
        if let sizePopUp = rowView.subviews.last as? NSPopUpButton {
            sizePopUp.selectItem(withTitle: String(size))
        }
    }

    private func selectCodeFontAsEditor(_ rowView: NSView) {
        if let popUp = rowView.subviews.first(where: { $0 is NSPopUpButton }) as? NSPopUpButton {
            popUp.selectItem(withTitle: "Editor Font")
        }
    }

    // MARK: - Actions
    @objc private func editorFontChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        let actualFontName = getFontType(from: item.title)?.editorFontName ?? item.title
        if settings.codeFontName == settings.editorFontName {
            settings.codeFontName = actualFontName
            NotesTextProcessor.codeFont = NSFont(name: settings.codeFontName, size: CGFloat(settings.editorFontSize))
        }
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
        if item.title == "Editor Font" {
            settings.codeFontName = settings.editorFontName
        } else {
            settings.codeFontName = getFontType(from: item.title)?.editorFontName ?? item.title
        }
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

