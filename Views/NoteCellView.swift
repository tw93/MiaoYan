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

    /// Everything the pin and the two labels are styled from. A draw redoes
    /// that work only when one of these differs from the last draw's.
    struct DrawState: Equatable {
        let fontsKey: String
        let name: String
        let date: String
        let appearanceType: Int
        let customColor: NSColor?
        let appearanceName: NSAppearance.Name
        let backgroundStyle: NSView.BackgroundStyle
        let noteID: ObjectIdentifier?
        let isPinned: Bool
        let showsIcon: Bool
        /// Whether both labels still carry the restyle's letter spacing. The
        /// date's binding sets the same plain text again after a restyle, so
        /// the text alone looked unchanged while the spacing was gone.
        let labelsStyled: Bool
    }

    private var lastDrawState: DrawState?
    /// How many times a draw has restyled the cell, for the test that holds
    /// repeated draws of an unchanged cell to one.
    private(set) var drawRestyleCount = 0

    private func currentDrawState() -> DrawState {
        let note = objectValue as? Note
        let custom = UserDefaultsManagement.appearanceType == .Custom
        return DrawState(
            fontsKey: Self.listFonts().key,
            name: name.stringValue,
            date: date.stringValue,
            appearanceType: UserDefaultsManagement.appearanceType.rawValue,
            customColor: custom ? UserDefaultsManagement.fontColor : nil,
            appearanceName: effectiveAppearance.name,
            backgroundStyle: backgroundStyle,
            noteID: note.map { ObjectIdentifier($0) },
            isPinned: note?.isPinned ?? false,
            showsIcon: note?.showIconInList() ?? true,
            labelsStyled: Self.isStyled(name) && Self.isStyled(date))
    }

    private static func isStyled(_ field: NSTextField) -> Bool {
        let text = field.attributedStringValue
        return text.length == 0 || text.attribute(.kern, at: 0, effectiveRange: nil) != nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard currentDrawState() != lastDrawState else { return }
        drawRestyleCount += 1
        renderPin()
        updateSelectionHighlight()
        // Read after the restyle, which is what puts the spacing on.
        lastDrawState = currentDrawState()
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
        name.lineBreakMode = .byTruncatingTail
        name.maximumNumberOfLines = 1
        name.cell?.lineBreakMode = .byTruncatingTail
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
