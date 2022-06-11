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

    @IBAction func openMiaoYan(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://miaoyan.vercel.app")!)
    }

    @IBAction func openVersion(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://miaoyan.vercel.app")!)
    }

    @IBAction func openContributorsPage(_ sender: Any) {
        let url = URL(string: "")!
        NSWorkspace.shared.open(url)
    }
}
