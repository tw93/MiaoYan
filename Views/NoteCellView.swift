import Cocoa

class NoteCellView: NSTableCellView {
    @IBOutlet var name: NSTextField!
    @IBOutlet var date: NSTextField!
    @IBOutlet var pin: NSImageView!

    public var note: Note?
    public var timestamp: Int64?

    /// The list fonts, resolved once per (face, sizes) instead of on every
    /// redraw; a font preference or size change changes the key and rebuilds.
    struct ListFonts: Equatable {
        let key: String
        let name: NSFont
        let date: NSFont
    }

    static var cachedListFonts: ListFonts?

    static func listFonts() -> ListFonts {
        let key = "\(UserDefaultsManagement.windowFontName)|\(UserDefaultsManagement.nameFontSize)|\(UserDefaultsManagement.dateFontSize)"
        if let cached = cachedListFonts, cached.key == key { return cached }
        let fonts = ListFonts(key: key, name: UserDefaultsManagement.nameFont, date: UserDefaultsManagement.dateFont)
        cachedListFonts = fonts
        return fonts
    }

    // Use Theme.secondaryTextColor instead of a hard-coded gray
    public var tableView: NotesTableView? {
        guard let vc = AppContext.shared.viewController else { return nil }

        return vc.notesTableView
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        renderPin()
        updateSelectionHighlight()
    }

    public func configure(note: Note) {
        self.note = note
    }

    // these views' color when the cell is selected.
    override var backgroundStyle: NSView.BackgroundStyle {
        get {
            super.backgroundStyle
        }
        set(newValue) {
            super.backgroundStyle = newValue
            updateSelectionHighlight()
        }
    }

    public func updateSelectionHighlight() {

        let fonts = Self.listFonts()
        name.font = fonts.name
        date.font = fonts.date
        name.addCharacterSpacing()
        date.addCharacterSpacing()

        applyTextColor(Theme.secondaryTextColor, to: date)
        applyTextColor(Theme.textColor, to: name)
        configureTitleTruncation()
    }

    private func applyTextColor(_ color: NSColor, to field: NSTextField) {
        field.textColor = color
        let attributed = NSMutableAttributedString(attributedString: field.attributedStringValue)
        let range = NSRange(location: 0, length: attributed.length)
        if range.length > 0 {
            attributed.addAttribute(.foregroundColor, value: color, range: range)
            field.attributedStringValue = attributed
        }
    }

    private func configureTitleTruncation() {
        name.lineBreakMode = .byTruncatingMiddle
        name.maximumNumberOfLines = 1
        name.cell?.lineBreakMode = .byTruncatingMiddle
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    func renderPin() {
        if let value = objectValue, let note = value as? Note {
            if let image = NSImage(named: "pinNote") {
                image.isTemplate = true
                pin.image = image
            }
            pin.contentTintColor = Theme.secondaryTextColor
            pin.isHidden = !note.isPinned
        }

        adjustPinPosition()
    }

    func hasTitle() -> Bool {
        if let value = objectValue, let note = value as? Note {
            return !note.title.isEmpty
        } else {
            return false
        }
    }

    public func adjustPinPosition() {
        for constraint in constraints {
            if let firstItem = constraint.firstItem as? NSImageView, firstItem === pin, constraint.firstAttribute == .leading {
                if let note = objectValue as? Note, !note.showIconInList() {
                    constraint.constant = -17
                } else {
                    constraint.constant = 5
                }
            }
        }
    }

    public func attachHeaders(note: Note) {
        if let title = note.getTitle() {
            name.stringValue = title
        }

        if let viewController = AppContext.shared.viewController,
            let sidebarItem = viewController.getSidebarItem(),
            let sort = sidebarItem.project?.sortBy,
            sort == .creationDate,
            let date = note.getCreationDateForLabel()
        {
            self.date.stringValue = date
        } else {
            date.stringValue = note.getDateForLabel()
        }
        updateSelectionHighlight()
    }
}
