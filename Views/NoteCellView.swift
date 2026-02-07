import Cocoa

class NoteCellView: NSTableCellView {
    @IBOutlet var name: NSTextField!
    @IBOutlet var date: NSTextField!
    @IBOutlet var pin: NSImageView!

    public var note: Note?
    public var timestamp: Int64?
    public let cellSpacing: CGFloat = 34

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

        name.font = UserDefaultsManagement.nameFont
        date.font = UserDefaultsManagement.dateFont
        name.addCharacterSpacing()
        date.addCharacterSpacing()

        if backgroundStyle == NSView.BackgroundStyle.emphasized {
            date.textColor = Theme.selectionTextColor
            name.textColor = Theme.selectionTextColor
        } else {
            date.textColor = Theme.secondaryTextColor
            name.textColor = Theme.textColor
        }
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
