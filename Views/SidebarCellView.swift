import Cocoa

final class SidebarLabelCell: NSTextFieldCell {
    var verticalNudge: CGFloat = 0

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        nudgedRect(forBounds: rect)
    }

    override func edit(
        withFrame cellFrame: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: nudgedRect(forBounds: cellFrame),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame cellFrame: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: nudgedRect(forBounds: cellFrame),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let copied = super.copy(with: zone) as! SidebarLabelCell
        copied.verticalNudge = verticalNudge
        return copied
    }

    private func nudgedRect(forBounds rect: NSRect) -> NSRect {
        var textRect = super.drawingRect(forBounds: rect)
        textRect.origin.y += verticalNudge
        return textRect
    }
}

@MainActor
class SidebarCellView: NSTableCellView {
    private enum LayoutConstants {
        static let trailingPadding: CGFloat = 6
    }

    @IBOutlet var icon: NSImageView!
    @IBOutlet var label: NSTextField!

    var storage: Storage { AppEnvironment.current.storage }

    override func draw(_ dirtyRect: NSRect) {
        label?.font = UserDefaultsManagement.nameFont
        super.draw(dirtyRect)
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        MainActor.assumeIsolated { [self] in
            guard let label = label else { return }

            installSidebarLabelCellIfNeeded(label)
            label.lineBreakMode = .byTruncatingTail
            label.cell?.truncatesLastVisibleLine = true
            label.cell?.wraps = false
            label.cell?.usesSingleLineMode = true
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
    }

    private func installSidebarLabelCellIfNeeded(_ label: NSTextField) {
        guard !(label.cell is SidebarLabelCell),
            let existingCell = label.cell as? NSTextFieldCell
        else { return }

        let labelCell = SidebarLabelCell(textCell: existingCell.stringValue)
        labelCell.font = existingCell.font
        labelCell.textColor = existingCell.textColor
        labelCell.alignment = existingCell.alignment
        labelCell.lineBreakMode = existingCell.lineBreakMode
        labelCell.isEditable = existingCell.isEditable
        labelCell.isSelectable = existingCell.isSelectable
        labelCell.isBordered = existingCell.isBordered
        labelCell.isBezeled = existingCell.isBezeled
        labelCell.drawsBackground = existingCell.drawsBackground
        labelCell.backgroundColor = existingCell.backgroundColor
        labelCell.sendsActionOnEndEditing = existingCell.sendsActionOnEndEditing
        labelCell.wraps = false
        labelCell.usesSingleLineMode = true
        labelCell.truncatesLastVisibleLine = true
        label.cell = labelCell
    }

    override func layout() {
        super.layout()
        updatePreferredLabelWidth()
    }

    private func updatePreferredLabelWidth() {
        guard let label else { return }

        let availableWidth = max(0, bounds.width - label.frame.minX - LayoutConstants.trailingPadding)
        guard abs(label.preferredMaxLayoutWidth - availableWidth) > 0.5 else { return }

        label.preferredMaxLayoutWidth = availableWidth
        label.invalidateIntrinsicContentSize()
    }

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        MainActor.assumeIsolated { [self] in
            if let trackingArea = self.trackingArea {
                removeTrackingArea(trackingArea)
            }

            let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
            let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(trackingArea)
        }
    }

    @IBAction func projectName(_ sender: NSTextField) {
        let cell = sender.superview as? SidebarCellView
        guard let si = cell?.objectValue as? SidebarItem, let project = si.project else { return }

        let oldURL = project.url
        let newURL = project.url.deletingLastPathComponent().appendingPathComponent(sender.stringValue)

        do {
            try FileManager.default.moveItem(at: project.url, to: newURL)
            project.url = newURL
            project.label = newURL.lastPathComponent

            // Update all notes' URLs in this project to reflect the new folder path
            for note in storage.noteList where note.project == project {
                let relativePath = note.url.path.replacingOccurrences(of: oldURL.path, with: "")
                let newNoteURL = URL(fileURLWithPath: newURL.path + relativePath)
                note.url = newNoteURL
            }

        } catch {
            sender.stringValue = project.url.lastPathComponent
            MiaoYanAlert.show(
                message: error.localizedDescription,
                style: .warning,
                for: window
            )
        }

        guard let vc = window?.contentViewController as? ViewController else { return }
        vc.storage.removeBy(project: project)
        vc.storage.loadLabel(project)
        vc.updateTable()
    }

    @IBAction func add(_ sender: Any) {
        guard let vc = AppContext.shared.viewController else { return }
        vc.storageOutlineView.addProject(self)
    }
}
