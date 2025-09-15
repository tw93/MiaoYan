import AppKit

class ContentViewController: NSViewController, NSPopoverDelegate {
    @IBOutlet var wordCount: NSTextField!
    @IBOutlet var updateTime: NSTextField!
    @IBOutlet var createTime: NSTextField!

    override func viewDidAppear() {
        guard let vc = ViewController.shared() else { return }
        let note = vc.notesTableView.getSelectedNote()
        var words = note?.getPrettifiedContent()

        words = vc.replace(validateString: words!, regex: "*+", content: "")
        words = vc.replace(validateString: words!, regex: "#+", content: "")
        words = vc.replace(validateString: words!, regex: "\\r\n", content: "")
        words = vc.replace(validateString: words!, regex: "\\n", content: "")
        words = vc.replace(validateString: words!, regex: "\\s", content: "")

        wordCount.stringValue = String(words!.count)
        updateTime.stringValue = note?.getUpdateTime() ?? ""
        createTime.stringValue = note?.getCreateTime() ?? ""
        super.viewDidAppear()
    }
}
