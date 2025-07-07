import Cocoa

class NoteCellView: NSTableCellView {
    @IBOutlet var name: NSTextField!
    @IBOutlet var date: NSTextField!
    @IBOutlet var pin: NSImageView!

    public var note: Note?
    public var timestamp: Int64?
    public let cellSpacing: CGFloat = 34

    private let labelColor = NSColor(deviceRed: 0.6, green: 0.6, blue: 0.6, alpha: 1)

    public var tableView: NotesTableView? {
        guard let vc = ViewController.shared() else { return nil }

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
        set {
            updateSelectionHighlight()
        }
        get {
            super.backgroundStyle
        }
    }

    public func updateSelectionHighlight() {
        
        // 字体和间距
        name.font = UserDefaultsManagement.nameFont
        date.font = UserDefaultsManagement.dateFont
        name.addCharacterSpacing()
        date.addCharacterSpacing()
        
        if backgroundStyle == NSView.BackgroundStyle.emphasized {
            date.textColor = NSColor.white
            name.textColor = NSColor.white
        } else {
            date.textColor = labelColor
            if #available(OSX 10.13, *) {
                name.textColor = NSColor(named: "mainText")
            } else {
                name.textColor = NSColor.black
            }
        }
    }

    func renderPin() {
        if let value = objectValue, let note = value as? Note {
            pin.image = NSImage(named: "pin")
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
            if constraint.secondAttribute == .leading, let im = constraint.firstItem as? NSImageView {
                if im.identifier?.rawValue == "pin" {
                    if let note = objectValue as? Note, !note.showIconInList() {
                        constraint.constant = -17
                    } else {
                        constraint.constant = 3
                    }
                }
            }
        }
    }

    private func adjustTopMargin(margin: CGFloat) {
        for constraint in constraints {
            if constraint.secondAttribute == .top, let item = constraint.firstItem {
                if let firstItem = item as? NSImageView, firstItem.identifier?.rawValue == "pin" {
                    constraint.constant = margin - 1
                    continue
                }
                if item.isKind(of: NameTextField.self) {
                    constraint.constant = margin
                    continue
                }

                if let item = item as? NSTextField, item.identifier?.rawValue == "cellDate" {
                    constraint.constant = margin
                }
            }
        }
    }

    public func attachHeaders(note: Note) {
        if let title = note.getTitle() {
            name.stringValue = title
        }

        if let viewController = ViewController.shared(),
           let sidebarItem = viewController.getSidebarItem(),
           let sort = sidebarItem.project?.sortBy,
           sort == .creationDate,
           let date = note.getCreationDateForLabel() {
            self.date.stringValue = date
        } else {
            date.stringValue = note.getDateForLabel()
        }
        updateSelectionHighlight()
    }
}
