import AppKit

@MainActor
final class VersionHistoryViewController: NSViewController {

    private enum VersionEntry {
        case current
        case saved(date: Date, url: URL)
    }

    private let note: Note
    private var entries: [VersionEntry] = []

    private let tableView = NSTableView()
    private let previewTextView = NSTextView()
    private let restoreButton = NSButton()

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
    private let todayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
    private let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    init(note: Note) {
        self.note = note
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 440))
        preferredContentSize = NSSize(width: 660, height: 440)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let saved = NoteVersionManager.shared.versions(for: note)
        entries = [.current] + saved.map { .saved(date: $0.date, url: $0.url) }
        buildLayout()
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        updateRestoreButtonState()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { dismiss(self) } else { super.keyDown(with: event) }
    }

    // MARK: - Layout

    private func buildLayout() {
        let header = buildHeader()
        let topSep = makeSeparator()

        if entries.count <= 1 {
            let emptyView = buildEmptyState()
            let botSep = makeSeparator()
            let footer = buildFooter(showRestore: false)

            let stack = NSStackView(views: [header, topSep, emptyView, botSep, footer])
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.orientation = .vertical
            stack.spacing = 0
            view.addSubview(stack)

            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                stack.topAnchor.constraint(equalTo: view.topAnchor),
                stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                header.heightAnchor.constraint(equalToConstant: 54),
                topSep.heightAnchor.constraint(equalToConstant: 1),
                emptyView.heightAnchor.constraint(equalToConstant: 335),
                botSep.heightAnchor.constraint(equalToConstant: 1),
                footer.heightAnchor.constraint(equalToConstant: 50),
            ])
        } else {
            let content = buildContent()
            let botSep = makeSeparator()
            let footer = buildFooter(showRestore: true)

            let stack = NSStackView(views: [header, topSep, content, botSep, footer])
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.orientation = .vertical
            stack.spacing = 0
            view.addSubview(stack)

            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                stack.topAnchor.constraint(equalTo: view.topAnchor),
                stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                header.heightAnchor.constraint(equalToConstant: 54),
                topSep.heightAnchor.constraint(equalToConstant: 1),
                content.heightAnchor.constraint(equalToConstant: 334),
                botSep.heightAnchor.constraint(equalToConstant: 1),
                footer.heightAnchor.constraint(equalToConstant: 50),
            ])
        }
    }

    private func buildEmptyState() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 11, *),
            let img = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        {
            let cfg = NSImage.SymbolConfiguration(pointSize: 32, weight: .light)
            icon.image = img.withSymbolConfiguration(cfg)
            icon.contentTintColor = Theme.secondaryTextColor
        }
        icon.imageScaling = .scaleProportionallyUpOrDown

        let label = NSTextField(labelWithString: I18n.str("No Version History"))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        label.textColor = Theme.secondaryTextColor
        label.alignment = .center

        let hint = NSTextField(labelWithString: I18n.str("Versions are saved automatically every 5 minutes while editing"))
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = Theme.secondaryTextColor.withAlphaComponent(0.6)
        hint.alignment = .center
        hint.maximumNumberOfLines = 2
        hint.preferredMaxLayoutWidth = 280

        let stack = NSStackView(views: [icon, label, hint])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
        ])
        return container
    }

    private func buildHeader() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: note.getTitleWithoutLabel())
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .boldSystemFont(ofSize: 13)
        title.textColor = Theme.textColor
        title.lineBreakMode = .byTruncatingTail

        let sub = NSTextField(labelWithString: I18n.str("Version History"))
        sub.translatesAutoresizingMaskIntoConstraints = false
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = Theme.secondaryTextColor

        let textStack = NSStackView(views: [title, sub])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3

        let closeBtn = NSButton(title: "", target: self, action: #selector(cancelAction))
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.isBordered = false
        if #available(macOS 11, *),
            let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        {
            let cfg = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            closeBtn.image = img.withSymbolConfiguration(cfg)
            closeBtn.imageScaling = .scaleProportionallyDown
            closeBtn.contentTintColor = Theme.secondaryTextColor
        } else {
            closeBtn.title = "✕"
            closeBtn.font = .systemFont(ofSize: 11)
        }

        v.addSubview(textStack)
        v.addSubview(closeBtn)
        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 18),
            textStack.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: closeBtn.leadingAnchor, constant: -8),
            closeBtn.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -14),
            closeBtn.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 20),
            closeBtn.heightAnchor.constraint(equalToConstant: 20),
        ])
        return v
    }

    private func buildContent() -> NSView {
        // ── left sidebar background
        let sidebarBg = NSView()
        sidebarBg.translatesAutoresizingMaskIntoConstraints = false
        sidebarBg.wantsLayer = true
        sidebarBg.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.06).cgColor

        let tableColumn = NSTableColumn(identifier: .init("v"))
        tableColumn.title = ""
        tableView.addTableColumn(tableColumn)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 52
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.allowsEmptySelection = false

        let listScroll = NSScrollView()
        listScroll.translatesAutoresizingMaskIntoConstraints = false
        listScroll.documentView = tableView
        listScroll.hasVerticalScroller = true
        listScroll.borderType = .noBorder
        listScroll.drawsBackground = false

        sidebarBg.addSubview(listScroll)
        NSLayoutConstraint.activate([
            listScroll.leadingAnchor.constraint(equalTo: sidebarBg.leadingAnchor),
            listScroll.trailingAnchor.constraint(equalTo: sidebarBg.trailingAnchor),
            listScroll.topAnchor.constraint(equalTo: sidebarBg.topAnchor),
            listScroll.bottomAnchor.constraint(equalTo: sidebarBg.bottomAnchor),
        ])

        // ── vertical divider
        let vDiv = NSBox()
        vDiv.translatesAutoresizingMaskIntoConstraints = false
        vDiv.boxType = .separator

        // ── preview
        previewTextView.isEditable = false
        previewTextView.isRichText = false
        previewTextView.font = .systemFont(ofSize: 13)
        previewTextView.textContainerInset = NSSize(width: 20, height: 16)
        previewTextView.drawsBackground = false
        previewTextView.textColor = Theme.textColor
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        previewTextView.defaultParagraphStyle = paragraphStyle

        let previewScroll = NSScrollView()
        previewScroll.translatesAutoresizingMaskIntoConstraints = false
        previewScroll.documentView = previewTextView
        previewScroll.hasVerticalScroller = true
        previewScroll.borderType = .noBorder
        previewScroll.drawsBackground = false

        // ── assemble
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebarBg)
        content.addSubview(vDiv)
        content.addSubview(previewScroll)

        NSLayoutConstraint.activate([
            sidebarBg.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebarBg.topAnchor.constraint(equalTo: content.topAnchor),
            sidebarBg.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebarBg.widthAnchor.constraint(equalToConstant: 176),

            vDiv.leadingAnchor.constraint(equalTo: sidebarBg.trailingAnchor),
            vDiv.topAnchor.constraint(equalTo: content.topAnchor),
            vDiv.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            vDiv.widthAnchor.constraint(equalToConstant: 1),

            previewScroll.leadingAnchor.constraint(equalTo: vDiv.trailingAnchor),
            previewScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            previewScroll.topAnchor.constraint(equalTo: content.topAnchor),
            previewScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        return content
    }

    private func buildFooter(showRestore: Bool) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false

        let cancel = NSButton(title: I18n.str("Cancel"), target: self, action: #selector(cancelAction))
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.bezelStyle = .rounded

        v.addSubview(cancel)

        if showRestore {
            restoreButton.translatesAutoresizingMaskIntoConstraints = false
            restoreButton.title = I18n.str("Restore to This Version")
            restoreButton.bezelStyle = .rounded
            restoreButton.target = self
            restoreButton.action = #selector(restoreAction)
            restoreButton.keyEquivalent = "\r"

            v.addSubview(restoreButton)
            NSLayoutConstraint.activate([
                restoreButton.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16),
                restoreButton.centerYAnchor.constraint(equalTo: v.centerYAnchor),
                cancel.trailingAnchor.constraint(equalTo: restoreButton.leadingAnchor, constant: -8),
                cancel.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                cancel.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16),
                cancel.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            ])
        }
        return v
    }

    private func makeSeparator() -> NSView {
        let b = NSBox()
        b.translatesAutoresizingMaskIntoConstraints = false
        b.boxType = .separator
        return b
    }

    // MARK: - Data helpers

    private func primaryLabel(for entry: VersionEntry) -> String {
        switch entry {
        case .current: return I18n.str("Current Version")
        case .saved(let date, _):
            return Calendar.current.isDateInToday(date)
                ? todayFormatter.string(from: date)
                : fullFormatter.string(from: date)
        }
    }

    private func secondaryLabel(for entry: VersionEntry) -> String? {
        switch entry {
        case .current:
            return relativeFormatter.localizedString(for: note.modifiedLocalAt, relativeTo: Date())
        case .saved(let date, _):
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
    }

    // MARK: - Preview & restore

    private func loadPreview(for index: Int) {
        guard index >= 0, index < entries.count else { previewTextView.string = ""; return }
        switch entries[index] {
        case .current:
            previewTextView.string = note.content.string
            previewTextView.scrollToBeginningOfDocument(nil)
        case .saved(_, let url):
            previewTextView.string = ""
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                DispatchQueue.main.async { [weak self] in
                    self?.previewTextView.string = text
                    self?.previewTextView.scrollToBeginningOfDocument(nil)
                }
            }
        }
    }

    private func updateRestoreButtonState() {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count else { restoreButton.isEnabled = false; return }
        if case .current = entries[row] { restoreButton.isEnabled = false } else { restoreButton.isEnabled = true }
    }

    @objc private func cancelAction() {
        dismiss(self)
        reselect()
    }

    @objc private func restoreAction() {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count,
              case .saved(let date, let url) = entries[row],
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return }

        NoteVersionManager.shared.saveVersionIfNeeded(for: note, force: true)
        guard let vc = ViewController.shared() else { return }

        note.save(content: NSMutableAttributedString(string: text))
        vc.editArea.fill(note: note, options: .forced)
        dismiss(self)
        reselect()

        let timeStr = primaryLabel(for: .saved(date: date, url: url))
        vc.toast(message: String(format: I18n.str("Restored to version from %@"), timeStr), style: .success)
    }

    private func reselect() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let vc = ViewController.shared(),
                  let index = vc.notesTableView.getIndex(self.note)
            else { return }
            vc.notesTableView.selectRowIndexes([index], byExtendingSelection: false)
        }
    }
}

// MARK: - Table DataSource & Delegate

extension VersionHistoryViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
}

extension VersionHistoryViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        VersionHistoryRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let cell = VersionHistoryCellView()
        cell.configure(
            primary: primaryLabel(for: entry),
            secondary: secondaryLabel(for: entry),
            isCurrent: { if case .current = entry { return true }; return false }()
        )
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        loadPreview(for: tableView.selectedRow)
        updateRestoreButtonState()
    }
}

// MARK: - Row view (rounded selection)

@MainActor
private final class VersionHistoryRowView: NSTableRowView {
    override var isEmphasized: Bool { get { false } set {} }

    override var isSelected: Bool {
        didSet {
            subviews.compactMap { $0 as? VersionHistoryCellView }.first?.setSelected(isSelected)
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 6, dy: 3)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        Theme.selectionBackgroundColor.setFill()
        path.fill()
    }
}

// MARK: - Cell view (two-line)

@MainActor
private final class VersionHistoryCellView: NSView {
    private let primaryField = NSTextField(labelWithString: "")
    private let secondaryField = NSTextField(labelWithString: "")
    private let dotView = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)

        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3.5

        primaryField.translatesAutoresizingMaskIntoConstraints = false
        primaryField.font = .systemFont(ofSize: 12.5)
        primaryField.textColor = Theme.textColor
        primaryField.lineBreakMode = .byTruncatingTail

        secondaryField.translatesAutoresizingMaskIntoConstraints = false
        secondaryField.font = .systemFont(ofSize: 10.5)
        secondaryField.textColor = Theme.secondaryTextColor
        secondaryField.lineBreakMode = .byTruncatingTail

        addSubview(dotView)
        addSubview(primaryField)
        addSubview(secondaryField)

        NSLayoutConstraint.activate([
            dotView.widthAnchor.constraint(equalToConstant: 7),
            dotView.heightAnchor.constraint(equalToConstant: 7),
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            dotView.centerYAnchor.constraint(equalTo: primaryField.centerYAnchor),

            primaryField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            primaryField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            primaryField.topAnchor.constraint(equalTo: topAnchor, constant: 12),

            secondaryField.leadingAnchor.constraint(equalTo: primaryField.leadingAnchor),
            secondaryField.trailingAnchor.constraint(equalTo: primaryField.trailingAnchor),
            secondaryField.topAnchor.constraint(equalTo: primaryField.bottomAnchor, constant: 3),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private var isCurrent = false

    func configure(primary: String, secondary: String?, isCurrent: Bool) {
        self.isCurrent = isCurrent
        primaryField.stringValue = primary
        secondaryField.stringValue = secondary ?? ""
        secondaryField.isHidden = secondary == nil
        applyStyle(selected: false)
    }

    func setSelected(_ selected: Bool) {
        applyStyle(selected: selected)
    }

    private func applyStyle(selected: Bool) {
        let active = isCurrent || selected
        primaryField.font = active ? .boldSystemFont(ofSize: 12.5) : .systemFont(ofSize: 12.5)
        dotView.layer?.backgroundColor = active
            ? Theme.accentColor.cgColor
            : Theme.secondaryTextColor.withAlphaComponent(0.4).cgColor
    }
}

