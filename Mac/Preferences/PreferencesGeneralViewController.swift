import Cocoa
import MASShortcut
import CoreData
import MiaoYanCore_macOS

class PreferencesGeneralViewController: NSViewController {
    override func viewWillAppear() {
        super.viewWillAppear()
        preferredContentSize = NSSize(width: 476, height: 413)
    }
    @IBOutlet weak var defaultStoragePath: NSPathControl!
    @IBOutlet weak var appearance: NSPopUpButton!
    @IBOutlet weak var appearanceLabel: NSTextField!

    //MARK: global variables

    let storage = Storage.sharedInstance()

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    @IBAction func appearanceClick(_ sender: NSPopUpButton) {
           if let type = AppearanceType(rawValue: sender.indexOfSelectedItem) {
               UserDefaultsManagement.appearanceType = type

               if type == .Dark {
                   UserDefaultsManagement.codeTheme = "atom-one-dark"
               } else if type == .System {
                   if #available(OSX 10.14, *) {
                       let mode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")

                       if mode == "Dark" {
                           UserDefaultsManagement.codeTheme = "atom-one-dark"
                       }else{
                           UserDefaultsManagement.codeTheme = "vs"
                       }
                   }
               } else {
                   UserDefaultsManagement.codeTheme = "vs"
               }
           }

           restart()
       }


    override func viewDidAppear() {
        self.view.window!.title = NSLocalizedString("Preferences", comment: "")

        if let url = UserDefaultsManagement.storageUrl {
            defaultStoragePath.stringValue = url.path
        }

        if #available(OSX 10.14, *) {
            appearance.selectItem(at: UserDefaultsManagement.appearanceType.rawValue)
        } else {
            appearanceLabel.isHidden = true
            appearance.isHidden = true
        }

    }

    @IBAction func changeDefaultStorage(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.canChooseFiles = false
        openPanel.begin { (result) -> Void in
            if result.rawValue == NSFileHandlingPanelOKButton {
                guard let url = openPanel.url else { return }
                guard let currentURL = UserDefaultsManagement.storageUrl else { return }

                let bookmark = SandboxBookmark.sharedInstance()
                bookmark.remove(url: currentURL)
                bookmark.store(url: url)
                bookmark.save()

                UserDefaultsManagement.storagePath = url.path
                self.defaultStoragePath.stringValue = url.path
                self.restart()
            }
        }
    }

    func restart() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()
        exit(0)
    }
}
