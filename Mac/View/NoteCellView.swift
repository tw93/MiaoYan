import Cocoa

class NoteCellView: NSTableCellView {

    @IBOutlet var name: NSTextField!
    @IBOutlet var date: NSTextField!
    @IBOutlet var pin: NSImageView!

    public var note: Note?
    public var timestamp: Int64?
    public let cellSpacing: CGFloat = 33

    private let labelColor = NSColor(deviceRed: 0.6, green: 0.6, blue: 0.6, alpha: 1)

    public var tableView: NotesTableView? {
        get {
            guard let vc = ViewController.shared() else { return nil }

            return vc.notesTableView
        }
    }

    override func viewWillDraw() {
        if let originY = UserDefaultsManagement.cellViewFrameOriginY {
            adjustTopMargin(margin: originY)
        }

        super.viewWillDraw()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        renderPin()
        udpateSelectionHighlight()

        pin.frame.origin.y = CGFloat(-4) + CGFloat(cellSpacing) + CGFloat(0)
    }

    public func configure(note: Note) {
        self.note = note
    }

    // This NoteCellView has multiple contained views; this method changes
    // these views' color when the cell is selected.
    override var backgroundStyle: NSView.BackgroundStyle {
        set {
            if let rowView = self.superview as? NSTableRowView {
                super.backgroundStyle = rowView.isSelected ? NSView.BackgroundStyle.dark : NSView.BackgroundStyle.light
            }
            self.udpateSelectionHighlight()
        }
        get {
            return super.backgroundStyle;
        }
    }

    public func udpateSelectionHighlight() {
        if ( self.backgroundStyle == NSView.BackgroundStyle.dark ) {
            date.textColor = NSColor.white
            name.textColor = NSColor.white
        } else {
            date.textColor = labelColor

            if self.name.stringValue == "Untitled Note" {
                name.textColor = NSColor(red:0.41, green:0.42, blue:0.46, alpha:1.0)
                return
            }

            if #available(OSX 10.13, *) {
                name.textColor = NSColor.init(named: "mainText")
            } else {
                name.textColor = NSColor.black
            }
        }
    }

    func renderPin() {
        if let value = objectValue, let note = value as? Note  {
                pin.image = NSImage(named: "pin")
                pin.isHidden = !note.isPinned
        }

        adjustPinPosition()
    }

    public func adjustPinPosition() {
        for constraint in self.constraints {
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
        for constraint in self.constraints {
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
            self.name.stringValue = title
        } else {
            self.name.stringValue = ""
        }

        if let viewController = ViewController.shared(),
            let sidebarItem = viewController.getSidebarItem(),
            let sort = sidebarItem.project?.sortBy,
            sort == .creationDate,
            let date = note.getCreationDateForLabel() {
            self.date.stringValue = date
        } else {
            self.date.stringValue = note.getDateForLabel()
        }

        self.udpateSelectionHighlight()
    }
}
