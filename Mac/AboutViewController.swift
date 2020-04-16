import Cocoa

class AboutViewController: NSViewController {
    override func viewDidLoad() {
        if let dictionary = Bundle.main.infoDictionary,
            let ver = dictionary["CFBundleShortVersionString"] as? String,
            let build = dictionary["CFBundleVersion"] as? String {
            versionLabel.stringValue = "Version \(ver) (\(build))"
            versionLabel.isSelectable = true
        }
    }

    @IBOutlet weak var versionLabel: NSTextField!
    
    @IBAction func openContributorsPage(_ sender: Any) {
        let url = URL(string: "")!
        NSWorkspace.shared.open(url)
    }
}
