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

//    override func viewWillDraw() {
//        if let originY = UserDefaultsManagement.cellViewFrameOriginY {
//            adjustTopMargin(margin: originY)
//        }
//        super.viewWillDraw()
//    }

    override func draw(_ dirtyRect: NSRect) {
        name.font = UserDefaultsManagement.nameFont
        date.font = UserDefaultsManagement.dateFont
        updateSelectionHighlight()
        
        super.draw(dirtyRect)
        
        renderPin()
        pin.frame.origin.y = CGFloat(-4) + CGFloat(cellSpacing) + CGFloat(0)
        
        
    }

    public func configure(note: Note) {
        self.note = note
    }

    // This NoteCellView has multiple contained views; this method changes

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
        if backgroundStyle == NSView.BackgroundStyle.dark {
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
        name.addCharacterSpacing()
        date.addCharacterSpacing()
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
