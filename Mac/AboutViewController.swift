import Cocoa

class AboutViewController: NSViewController {
    override func viewDidLoad() {
        if let dictionary = Bundle.main.infoDictionary,
           let ver = dictionary["CFBundleShortVersionString"] as? String
        {
            versionLabel.stringValue = "Version \(ver)"
            versionLabel.isSelectable = true
        }
    }

    @IBOutlet var versionLabel: NSTextField!
}
