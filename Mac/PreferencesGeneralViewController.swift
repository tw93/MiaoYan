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
    @IBOutlet var picPopUp: NSPopUpButton!

    @IBOutlet var previewLocation: NSPopUpButton!
    @IBOutlet var previewWidth: NSPopUpButton!
    @IBOutlet var codeFontName: NSPopUpButton!

    @IBOutlet var editorFontWidthConstraint: NSLayoutConstraint!
    @IBOutlet var previewFontWidthConstraint: NSLayoutConstraint!
    @IBOutlet var windowFontWidthConstraint: NSLayoutConstraint!
    @IBOutlet var languageFontWidthConstraint: NSLayoutConstraint!
    @IBOutlet var codeFontWidthConstraint: NSLayoutConstraint!

    @IBOutlet var editorLineBreak: NSPopUpButton!
    @IBOutlet var buttonShow: NSPopUpButton!

    // MARK: global variables

    let storage = Storage.sharedInstance()

    override func viewDidLoad() {
        // 为了隐藏xcode警告的被迫操作
        editorFontWidthConstraint.constant = 100.0
        previewFontWidthConstraint.constant = 100.0
        windowFontWidthConstraint.constant = 100.0
        languageFontWidthConstraint.constant = 100.0
        codeFontWidthConstraint.constant = 100.0

        super.viewDidLoad()
    }

    @IBAction func editorLineBreakClick(_ sender: NSPopUpButton) {
        guard let vc = ViewController.shared() else {
            return
        }
        guard let item = sender.selectedItem else {
            return
        }
        UserDefaultsManagement.editorLineBreak = item.title
        NotesTextProcessor.hl = nil

        vc.disablePreview()
        vc.enablePreview()
    }

    @IBAction func editorFontSizeClick(_ sender: NSPopUpButton) {
        guard let vc = ViewController.shared() else {
            return
        }
        guard let item = sender.selectedItem else {
            return
        }

        UserDefaultsManagement.fontSize = Int(item.title) ?? UserDefaultsManagement.DefaultFontSize

        NotesTextProcessor.hl = nil
        vc.refillEditArea()
        vc.disablePreview()
    }

    @IBAction func editorFontNameClick(_ sender: NSPopUpButton) {
        guard let vc = ViewController.shared() else {
            return
        }
        guard let item = sender.selectedItem else {
            return
        }

        // 处理好代码字体变化
        if UserDefaultsManagement.codeFontName == UserDefaultsManagement.fontName {
            UserDefaultsManagement.codeFontName = item.title
            NotesTextProcessor.codeFont = Font(name: UserDefaultsManagement.codeFontName, size: CGFloat(UserDefaultsManagement.fontSize))
        }

        UserDefaultsManagement.fontName = item.title

        NotesTextProcessor.hl = nil
        vc.refillEditArea()
        vc.disablePreview()
    }

    @IBAction func buttonShow(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else {
            return
        }

        if UserDefaultsManagement.buttonShow == item.title {
            return
        }

        UserDefaultsManagement.buttonShow = item.title

        NotesTextProcessor.hl = nil
        restart()
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

    @IBAction func codeFontNameClick(_ sender: NSPopUpButton) {
        guard let vc = ViewController.shared() else {
            return
        }
        guard let item = sender.selectedItem else {
            return
        }
        if item.title == "Editor Font" {
            UserDefaultsManagement.codeFontName = UserDefaultsManagement.fontName
        } else {
            UserDefaultsManagement.codeFontName = item.title
        }

        NotesTextProcessor.codeFont = Font(name: UserDefaultsManagement.codeFontName, size: CGFloat(UserDefaultsManagement.fontSize))
        NotesTextProcessor.hl = nil
        vc.disablePreview()
        vc.refillEditArea(force: true)
    }

    @IBAction func previewWidthClick(_ sender: NSPopUpButton) {
        guard let vc = ViewController.shared() else {
            return
        }
        guard let item = sender.selectedItem else {
            return
        }
        UserDefaultsManagement.previewWidth = item.title
        NotesTextProcessor.hl = nil

        vc.disablePreview()
        vc.enablePreview()
    }

    @IBAction func previewLocation(_ sender: NSPopUpButton) {
        guard let vc = ViewController.shared() else {
            return
        }
        guard let item = sender.selectedItem else {
            return
        }

        UserDefaultsManagement.previewLocation = item.title

        NotesTextProcessor.hl = nil

        vc.disablePreview()
        vc.enablePreview()
    }

    @IBAction func previewFontNameClick(_ sender: NSPopUpButton) {
        guard let vc = ViewController.shared() else {
            return
        }
        guard let item = sender.selectedItem else {
            return
        }

        UserDefaultsManagement.previewFontName = item.title

        NotesTextProcessor.hl = nil

        vc.disablePreview()
        vc.enablePreview()
    }

    @IBAction func previewFontSizeClick(_ sender: NSPopUpButton) {
        guard let vc = ViewController.shared() else {
            return
        }
        guard let item = sender.selectedItem else {
            return
        }

        UserDefaultsManagement.previewFontSize = Int(item.title) ?? UserDefaultsManagement.DefaultPreviewFontSize

        vc.disablePreview()
        vc.enablePreview()
    }

    @IBAction func presentationFontSizeClick(_ sender: NSPopUpButton) {
        guard let vc = ViewController.shared() else {
            return
        }
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
        picPopUp.selectItem(withTitle: String(UserDefaultsManagement.defaultPicUpload))
        editorLineBreak.selectItem(withTitle: String(UserDefaultsManagement.editorLineBreak))
        buttonShow.selectItem(withTitle: String(UserDefaultsManagement.buttonShow))

        if UserDefaultsManagement.codeFontName == UserDefaultsManagement.fontName {
            codeFontName.selectItem(withTitle: "Editor Font")
        } else {
            codeFontName.selectItem(withTitle: String(UserDefaultsManagement.codeFontName))
        }
        previewWidth.selectItem(withTitle: String(UserDefaultsManagement.previewWidth))

        previewLocation.selectItem(withTitle: String(UserDefaultsManagement.previewLocation))
    }

    @IBAction func changeDefaultStorage(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.canChooseFiles = false
        openPanel.begin { result in
            if result == NSApplication.ModalResponse.OK {
                guard let url = openPanel.url else {
                    return
                }
                guard UserDefaultsManagement.storageUrl != nil else {
                    return
                }

                UserDefaultsManagement.storagePath = url.path
                self.defaultStoragePath.stringValue = url.path
                self.restart()
            }
        }
    }

    @IBAction func picPopUp(_ sender: NSPopUpButton) {
        guard let vc = ViewController.shared() else {
            return
        }
        guard let item = sender.selectedItem else {
            return
        }
        UserDefaultsManagement.defaultPicUpload = item.title
        if item.title != "None" {
            vc.toastImageSet(name: item.title)
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
        guard let vc = ViewController.shared(), let w = vc.view.window else {
            return
        }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Restart to MiaoYan to take effect", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Confirm", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.beginSheetModal(for: w) { (returnCode: NSApplication.ModalResponse) in
            if returnCode == NSApplication.ModalResponse.alertFirstButtonReturn {
                UserDefaultsManagement.isFirstLaunch = true
                do {
                    let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
                    let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
                    let task = Process()
                    task.launchPath = "/usr/bin/open"
                    task.arguments = [path]
                    task.launch()
                    exit(0)
                }
            }
        }
    }
}
