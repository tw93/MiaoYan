import Cocoa

// MARK: - Preferences Sidebar Delegate Protocol
protocol PrefsSidebarDelegate: AnyObject {
    func sidebarDidSelectCategory(_ category: PreferencesCategory)
}

// MARK: - Preferences Sidebar View
final class PrefsSidebarView: NSView {
    weak var delegate: PrefsSidebarDelegate?
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var categories: [PreferencesCategory] = PreferencesCategory.allCases
    private var selectedCategory: PreferencesCategory = .general

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        print("[DEBUG] PrefsSidebarView.init(frame:) called")
        setupUI()
        print("[DEBUG] PrefsSidebarView.init(frame:) completed")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        print("[DEBUG] PrefsSidebarView.setupUI called")
        setupScrollView()
        setupTableView()
        setupConstraints()
        setupAppearance()
        print("[DEBUG] PrefsSidebarView.setupUI completed")
    }

    private func setupScrollView() {
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = NSColor.clear
        addSubview(scrollView)
    }

    private func setupTableView() {
        tableView = NSTableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.headerView = nil
        tableView.focusRingType = .none
        tableView.selectionHighlightStyle = .sourceList
        tableView.floatsGroupRows = false
        tableView.rowSizeStyle = .medium
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.delegate = self
        tableView.dataSource = self

        // Create a single column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("CategoryColumn"))
        column.title = ""
        column.isEditable = false
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView

        // Select first category by default
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func setupAppearance() {
        wantsLayer = true
        layer?.backgroundColor = (NSColor(named: "mainBackground") ?? NSColor.controlBackgroundColor).cgColor

        // Add modern translucent sidebar appearance on supported macOS versions
        if #available(macOS 10.14, *) {
            let visualEffect = NSVisualEffectView()
            visualEffect.translatesAutoresizingMaskIntoConstraints = false
            visualEffect.material = .sidebar
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active

            addSubview(visualEffect, positioned: .below, relativeTo: scrollView)

            NSLayoutConstraint.activate([
                visualEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
                visualEffect.trailingAnchor.constraint(equalTo: trailingAnchor),
                visualEffect.topAnchor.constraint(equalTo: topAnchor),
                visualEffect.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    func selectCategory(_ category: PreferencesCategory) {
        guard let index = categories.firstIndex(of: category) else {
            AppDelegate.trackError(NSError(domain: "PrefsSidebarError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Category \(category) not found"]), context: "PrefsSidebarView.selectCategory")
            return
        }
        selectedCategory = category
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
    }
}

// MARK: - NSTableViewDataSource
extension PrefsSidebarView: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return categories.count
    }
}

// MARK: - NSTableViewDelegate
extension PrefsSidebarView: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let category = categories[row]
        let cellView = PrefsSidebarCellView()
        cellView.configure(with: category)
        return cellView
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 28
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 && selectedRow < categories.count else { return }

        let category = categories[selectedRow]
        selectedCategory = category
        delegate?.sidebarDidSelectCategory(category)
    }
}

// MARK: - Preferences Sidebar Cell View
final class PrefsSidebarCellView: NSTableCellView {
    private var titleLabel: NSTextField!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        // Title
        titleLabel = NSTextField()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = NSColor.clear
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.textColor = NSColor.labelColor
        addSubview(titleLabel)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Title constraints - centered without icon
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
    }

    func configure(with category: PreferencesCategory) {
        titleLabel.stringValue = category.title
    }
}
