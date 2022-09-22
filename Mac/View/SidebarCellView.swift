import Cocoa

class SidebarCellView: NSTableCellView {
    @IBOutlet var icon: NSImageView!
    @IBOutlet var label: NSTextField!
    @IBOutlet var labelToIconConstraint: NSLayoutConstraint!

    var storage = Storage.sharedInstance()

    override func draw(_ dirtyRect: NSRect) {
        label.font = UserDefaultsManagement.nameFont
        label.addCharacterSpacing()
        checkLabelTopConstraint()
        super.draw(dirtyRect)
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

        guard let project = cell?.objectValue as? Project else { return }

        let src = project.url
        let dst = project.url.deletingLastPathComponent().appendingPathComponent(sender.stringValue, isDirectory: true)

        project.url = dst
        project.loadLabel()

        do {
            try FileManager.default.moveItem(at: src, to: dst)
        } catch {
            sender.stringValue = project.url.lastPathComponent
            let alert = NSAlert()
            alert.messageText = error.localizedDescription
            alert.runModal()
        }

        storage.unload(project: project)
        storage.loadLabel(project)

        guard let vc = window?.contentViewController as? ViewController else { return }
        vc.fsManager?.restart()
        vc.loadMoveMenu()

        vc.updateTable()
    }

    @IBAction func add(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }
        vc.storageOutlineView.addProject(self)
    }

    func checkLabelTopConstraint() {
        let font = UserDefaultsManagement.windowFontName
        if font == "JetBrains Mono" || font == "Helvetica Neue" {
            labelToIconConstraint.constant = -1.8
        } else if font == "Times New Roman" {
            labelToIconConstraint.constant = 1.0
        } else {
            labelToIconConstraint.constant = -1.26
        }
    }
}
