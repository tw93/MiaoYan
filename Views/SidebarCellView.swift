import Cocoa

class SidebarCellView: NSTableCellView {
    @IBOutlet var icon: NSImageView!
    @IBOutlet var label: NSTextField!

    var storage = Storage.sharedInstance()

    override func draw(_ dirtyRect: NSRect) {
        label?.font = UserDefaultsManagement.nameFont
        super.draw(dirtyRect)
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        guard let label = label else { return }

        // Enhanced text truncation behavior for better narrow width display
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        label.cell?.wraps = false

        // Set maximum layout width to help with text measurement
        label.preferredMaxLayoutWidth = 200
    }

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let trackingArea = self.trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }

    @IBAction func projectName(_ sender: NSTextField) {
        let cell = sender.superview as? SidebarCellView
        guard let si = cell?.objectValue as? SidebarItem, let project = si.project else { return }

        let newURL = project.url.deletingLastPathComponent().appendingPathComponent(sender.stringValue)

        do {
            try FileManager.default.moveItem(at: project.url, to: newURL)
            project.url = newURL
            project.label = newURL.lastPathComponent

        } catch {
            sender.stringValue = project.url.lastPathComponent
            let alert = NSAlert()
            alert.messageText = error.localizedDescription
            alert.runModal()
        }

        guard let vc = window?.contentViewController as? ViewController else { return }
        vc.storage.removeBy(project: project)
        vc.storage.loadLabel(project)
        vc.updateTable()
    }

    @IBAction func add(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }
        vc.storageOutlineView.addProject(self)
    }
}
