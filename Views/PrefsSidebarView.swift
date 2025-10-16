import Cocoa

// MARK: - Preferences Sidebar Delegate Protocol
@MainActor
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
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        setupScrollView()
        setupTableView()
        setupConstraints()
        setupAppearance()
    }

    private func setupScrollView() {
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = NSColor.clear

        // Ensure the clip view is also transparent
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.layer?.backgroundColor = NSColor.clear.cgColor

        addSubview(scrollView)
    }

    private func setupTableView() {
        tableView = NSTableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.headerView = nil
        tableView.focusRingType = .none
        tableView.selectionHighlightStyle = .none  // Disable system selection drawing
        tableView.floatsGroupRows = false
        tableView.rowSizeStyle = .medium
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .clear  // Ensure table itself is transparent

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("CategoryColumn"))
        column.title = ""
        column.isEditable = false
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
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
        updateColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        guard let tableView else { return }
        let appearance = window?.effectiveAppearance ?? effectiveAppearance

        // Resolve the background color in the correct appearance context
        var backgroundColor: NSColor = .windowBackgroundColor
        appearance.performAsCurrentDrawingAppearance {
            backgroundColor = NSColor(named: "mainBackground") ?? .windowBackgroundColor
        }

        layer?.backgroundColor = backgroundColor.cgColor
        tableView.backgroundColor = backgroundColor

        // Refresh all rows to update appearance
        tableView.enumerateAvailableRowViews { rowView, row in
            rowView.needsDisplay = true
            // Force cell views to update their text colors immediately
            for case let cellView as PrefsSidebarCellView in rowView.subviews {
                cellView.refreshTextColor()
            }
        }
    }

    func refreshAppearance() {
        updateColors()
    }

    func selectCategory(_ category: PreferencesCategory) {
        guard let index = categories.firstIndex(of: category) else {
            AppDelegate.trackError(NSError(domain: "PrefsSidebarError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Category \(category) not found"]), context: "PrefsSidebarView.selectCategory")
            return
        }
        selectedCategory = category

        // Ensure selection is properly set and visible
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)

        // Force immediate display update
        if let rowView = tableView.rowView(atRow: index, makeIfNecessary: true) {
            rowView.needsDisplay = true
        }
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

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return PrefsSidebarRowView()
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
        titleLabel = NSTextField()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = NSColor.clear
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        updateTextColor()
        addSubview(titleLabel)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
    }

    func configure(with category: PreferencesCategory) {
        titleLabel.stringValue = category.title
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateTextColor()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            updateTextColor()
        }
    }

    private func updateTextColor() {
        if backgroundStyle == .emphasized {
            // Selected: use contrasting text color based on selection background
            let appearance = window?.effectiveAppearance ?? effectiveAppearance
            titleLabel.textColor = appearance.isDark ? .white : .black
        } else {
            // Unselected: use secondary label color for subtle appearance
            titleLabel.textColor = .secondaryLabelColor
        }
    }

    func refreshTextColor() {
        updateTextColor()
    }
}

// MARK: - Preferences Sidebar Row View
final class PrefsSidebarRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { return isSelected }
        set {}
    }

    override var isSelected: Bool {
        didSet {
            if oldValue != isSelected {
                needsDisplay = true
                // Notify cell views to update text colors
                updateCellTextColors()
            }
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        // Don't draw anything - we override drawSelection instead
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }

        // Resolve color in current appearance context
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        let selectionColor = Theme.selectionBackgroundColor.resolvedColor(for: appearance)

        selectionColor.setFill()
        let selectionRect = bounds.insetBy(dx: 8, dy: 2)
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6)
        path.fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            drawSelection(in: dirtyRect)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        updateCellTextColors()
    }

    override var backgroundColor: NSColor {
        get { return .clear }
        set {}
    }

    private func updateCellTextColors() {
        // Force cell views to update their text colors immediately
        for case let cellView as PrefsSidebarCellView in subviews {
            cellView.refreshTextColor()
        }
    }
}
