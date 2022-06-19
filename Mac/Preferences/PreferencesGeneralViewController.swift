import Cocoa
import CoreData
import MASShortcut
import MiaoYanCore_macOS

class PreferencesGeneralViewController: NSViewController {
    override func viewWillAppear() {
        super.viewWillAppear()
        preferredContentSize = NSSize(width: 476, height: 413)
    }

    @IBOutlet var windowFontName: NSPopUpButton!
    @IBOutlet var previewFontName: NSPopUpButton!
    @IBOutlet var editorFontName: NSPopUpButton!
    @IBOutlet var defaultStoragePath: NSPathControl!
    @IBOutlet var languagePopUp: NSPopUpButton!
    @IBOutlet var appearance: NSPopUpButton!
    @IBOutlet var appearanceLabel: NSTextField!
    @IBOutlet var editorFontSize: NSPopUpButton!
    @IBOutlet var previewFontSize: NSPopUpButton!
    @IBOutlet var presentationFontSize: NSPopUpButton!

    // MARK: global variables

    let storage = Storage.sharedInstance()

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    @IBAction func eidtorFontSizeClick(_ sender: NSPopUpButton) {
        guard let vc = ViewController.shared() else { return }
        guard let item = sender.selectedItem else {
            return
        }

        UserDefaultsManagement.fontSize = Int(item.title) ?? UserDefaultsManagement.DefaultFontSize

        NotesTextProcessor.hl = nil
        vc.refillEditArea()
        vc.disablePreview()
    }

    @IBAction func eidtorFontNameClick(_ sender: NSPopUpButton) {
        guard let vc = ViewController.shared() else { return }
        guard let item = sender.selectedItem else {
            return
        }

        UserDefaultsManagement.fontName = item.title

        NotesTextProcessor.hl = nil
        vc.refillEditArea()
        vc.disablePreview()
    }

    @IBAction func windowFontNameClick(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else {
            return
        }

        if UserDefaultsManagement.windowFontName == item.title {
            return
        }

        UserDefaultsManagement.windowFontName = item.title

        NotesTextProcessor.hl = nil
        restart()
    }

    @IBAction func previewFontNameClick(_ sender: NSPopUpButton) {
        guard let vc = ViewController.shared() else { return }
        guard let item = sender.selectedItem else {
            return
        }

        UserDefaultsManagement.previewFontName = item.title

        NotesTextProcessor.hl = nil

        vc.disablePreview()
        vc.enablePreview()
    }

    @IBAction func previewFontSizeClick(_ sender: NSPopUpButton) {
        guard let vc = ViewController.shared() else { return }
        guard let item = sender.selectedItem else {
            return
        }

        UserDefaultsManagement.previewFontSize = Int(item.title) ?? UserDefaultsManagement.DefaultPreviewFontSize

        vc.disablePreview()
        vc.enablePreview()
    }

    @IBAction func presentationFontSizeClick(_ sender: NSPopUpButton) {
        guard let vc = ViewController.shared() else { return }
        guard let item = sender.selectedItem else {
            return
        }

        UserDefaultsManagement.presentationFontSize = Int(item.title) ?? UserDefaultsManagement.DefaultPresentationFontSize

        vc.disablePresentation()
        vc.enablePresentation()
    }
    
    @IBAction func appearanceClick(_ sender: NSPopUpButton) {
        if let type = AppearanceType(rawValue: sender.indexOfSelectedItem) {
            if UserDefaultsManagement.appearanceType == type {
                return
            }

            UserDefaultsManagement.appearanceType = type

            if type == .Dark {
                UserDefaultsManagement.codeTheme = "atom-one-dark"
            } else if type == .System {
                if #available(OSX 10.14, *) {
                    let mode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")

                    if mode == "Dark" {
                        UserDefaultsManagement.codeTheme = "atom-one-dark"
                    } else {
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
        view.window!.title = NSLocalizedString("Preferences", comment: "")

        let languages = [
            LanguageType(rawValue: 0x00),
            LanguageType(rawValue: 0x01)
        ]

        for language in languages {
            if let lang = language?.description, let id = language?.rawValue {
                languagePopUp.addItem(withTitle: lang)
                languagePopUp.lastItem?.state = (id == UserDefaultsManagement.defaultLanguage) ? .on : .off
                if id == UserDefaultsManagement.defaultLanguage {
                    languagePopUp.selectItem(withTitle: lang)
                }
            }
        }

        if let url = UserDefaultsManagement.storageUrl {
            defaultStoragePath.stringValue = url.path
        }

        if #available(OSX 10.14, *) {
            appearance.selectItem(at: UserDefaultsManagement.appearanceType.rawValue)
        } else {
            appearanceLabel.isHidden = true
            appearance.isHidden = true
        }

        editorFontSize.selectItem(withTitle: String(UserDefaultsManagement.fontSize))
        previewFontSize.selectItem(withTitle: String(UserDefaultsManagement.previewFontSize))
        presentationFontSize.selectItem(withTitle: String(UserDefaultsManagement.presentationFontSize))
        editorFontName.selectItem(withTitle: String(UserDefaultsManagement.fontName))
        windowFontName.selectItem(withTitle: String(UserDefaultsManagement.windowFontName))
        previewFontName.selectItem(withTitle: String(UserDefaultsManagement.previewFontName))
    }

    @IBAction func changeDefaultStorage(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.canChooseFiles = false
        openPanel.begin { result in
            if result.rawValue == NSFileHandlingPanelOKButton {
                guard let url = openPanel.url else { return }
                guard UserDefaultsManagement.storageUrl != nil else { return }

                UserDefaultsManagement.storagePath = url.path
                self.defaultStoragePath.stringValue = url.path
                self.restart()
            }
        }
    }

    @IBAction func languagePopUp(_ sender: NSPopUpButton) {
        let type = LanguageType.withName(rawValue: sender.title)

        if UserDefaultsManagement.defaultLanguage == type.rawValue {
            return
        }
        UserDefaultsManagement.defaultLanguage = type.rawValue

        UserDefaults.standard.set([type.code], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        restart()
    }

    private func restart() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()
        exit(0)
    }
}
