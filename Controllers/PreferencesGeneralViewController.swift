import Cocoa
import CoreData

class PreferencesGeneralViewController: NSViewController {

    // 字体配置枚举
    private enum FontType: String, CaseIterable {
        case tsanger = "TsangerJinKai02-W04"
        case lxgw = "LXGW WenKai Screen"
        case system = "SF Pro Text"
        case times = "Times New Roman"

        var editorFontName: String {
            self == .system ? "SF Mono" : rawValue
        }

        var windowFontName: String {
            self == .system ? "SF Pro Text" : rawValue
        }

        var previewFontName: String {
            self == .system ? "SF Pro Text" : rawValue
        }

        static func from(actualFontName: String) -> FontType? {
            return allCases.first {
                $0.rawValue == actualFontName || $0.editorFontName == actualFontName || $0.windowFontName == actualFontName || $0.previewFontName == actualFontName
            }
        }

        var isAvailable: Bool {
            return Font(name: rawValue, size: 12) != nil || Font(name: editorFontName, size: 12) != nil
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        // 设置窗口的首选尺寸和最小尺寸
        preferredContentSize = NSSize(width: 520, height: 413)

        // 设置窗口最小尺寸，防止在边缘时被挤压
        if let window = view.window {
            window.minSize = NSSize(width: 520, height: 413)
            window.contentMinSize = NSSize(width: 520, height: 413)
        }
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
    @IBOutlet var codeBackground: NSPopUpButton!

    // 修复缺失的outlet
    @IBOutlet var popUpWidthConstraint: NSLayoutConstraint!
    @IBOutlet var previewWith: NSPopUpButton!

    let storage = Storage.sharedInstance()

    func refreshEditor() {
        guard let vc = ViewController.shared() else { return }
        NotesTextProcessor.hl = nil
        vc.disablePreview()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            vc.refillEditArea()
        }
    }

    func refreshPreview() {
        guard let vc = ViewController.shared() else { return }
        if UserDefaultsManagement.preview { vc.disablePreview() }

        // PPT场景下使用预览会很难看
        if !vc.isMiaoYanPPT(needToast: false) {
            vc.enablePreview()
        }
    }

    @IBAction func editorLineBreakClick(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        UserDefaultsManagement.editorLineBreak = item.title
        refreshPreview()
    }

    @IBAction func editorFontSizeClick(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        UserDefaultsManagement.fontSize = Int(item.title) ?? UserDefaultsManagement.DefaultFontSize
        refreshEditor()
    }

    @IBAction func editorFontNameClick(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem,
            let fontType = getFontType(from: item.title)
        else { return }

        let actualFontName = fontType.editorFontName

        // 处理好代码字体变化
        if UserDefaultsManagement.codeFontName == UserDefaultsManagement.fontName {
            UserDefaultsManagement.codeFontName = actualFontName
            NotesTextProcessor.codeFont = Font(name: UserDefaultsManagement.codeFontName, size: CGFloat(UserDefaultsManagement.fontSize))
        }
        UserDefaultsManagement.fontName = actualFontName
        refreshEditor()
    }

    @IBAction func buttonShow(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        UserDefaultsManagement.buttonShow = item.title
        NotesTextProcessor.hl = nil
        restart()
    }

    @IBAction func codeBackground(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        UserDefaultsManagement.codeBackground = item.title
        refreshEditor()
    }

    @IBAction func windowFontNameClick(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem,
            let fontType = getFontType(from: item.title)
        else { return }

        let actualFontName = fontType.windowFontName

        if UserDefaultsManagement.windowFontName == actualFontName { return }
        UserDefaultsManagement.windowFontName = actualFontName
        restart()
    }

    @IBAction func codeFontNameClick(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }

        if item.title == "Editor Font" {
            UserDefaultsManagement.codeFontName = UserDefaultsManagement.fontName
        } else if let fontType = getFontType(from: item.title) {
            UserDefaultsManagement.codeFontName = fontType.editorFontName
        } else {
            UserDefaultsManagement.codeFontName = item.title
        }

        NotesTextProcessor.codeFont = Font(name: UserDefaultsManagement.codeFontName, size: CGFloat(UserDefaultsManagement.fontSize))
        refreshEditor()
    }

    @IBAction func previewWidthClick(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        UserDefaultsManagement.previewWidth = item.title
        refreshPreview()
    }

    @IBAction func previewLocation(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        UserDefaultsManagement.previewLocation = item.title
        refreshPreview()
    }

    @IBAction func previewFontNameClick(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem,
            let fontType = getFontType(from: item.title)
        else { return }

        let actualFontName = fontType.previewFontName
        UserDefaultsManagement.previewFontName = actualFontName
        refreshPreview()
    }

    @IBAction func previewFontSizeClick(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        UserDefaultsManagement.previewFontSize = Int(item.title) ?? UserDefaultsManagement.DefaultPreviewFontSize
        refreshPreview()
    }

    @IBAction func presentationFontSizeClick(_ sender: NSPopUpButton) {
        guard let vc = ViewController.shared() else {
            return
        }
        guard let item = sender.selectedItem else {
            return
        }

        UserDefaultsManagement.presentationFontSize = Int(item.title) ?? UserDefaultsManagement.DefaultPresentationFontSize

        // PPT场景下使用预览会很难看
        if !vc.isMiaoYanPPT(needToast: false) {
            vc.disablePresentation()
            vc.enablePresentation()
        }
    }

    @IBAction func appearanceClick(_ sender: NSPopUpButton) {
        if let type = AppearanceType(rawValue: sender.indexOfSelectedItem) {
            if UserDefaultsManagement.appearanceType == type { return }
            UserDefaultsManagement.appearanceType = type
        }
        restart()
    }

    override func viewDidAppear() {
        view.window!.title = NSLocalizedString("Preferences", comment: "")

        // 设置本地化的字体名称
        setupLocalizedFontNames()

        // 清空现有语言选项并重新设置
        languagePopUp.removeAllItems()

        let languages = [
            LanguageType(rawValue: 0x00),
            LanguageType(rawValue: 0x01),
            LanguageType(rawValue: 0x02),
            LanguageType(rawValue: 0x03),
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

        // 使用FontType枚举将实际字体名称转换为显示名称
        let editorDisplayName = FontType.from(actualFontName: UserDefaultsManagement.fontName).map { getLocalizedFontName(for: $0) } ?? UserDefaultsManagement.fontName
        let windowDisplayName = FontType.from(actualFontName: UserDefaultsManagement.windowFontName).map { getLocalizedFontName(for: $0) } ?? UserDefaultsManagement.windowFontName
        let previewDisplayName = FontType.from(actualFontName: UserDefaultsManagement.previewFontName).map { getLocalizedFontName(for: $0) } ?? UserDefaultsManagement.previewFontName

        editorFontName.selectItem(withTitle: editorDisplayName)
        windowFontName.selectItem(withTitle: windowDisplayName)
        previewFontName.selectItem(withTitle: previewDisplayName)
        picPopUp.selectItem(withTitle: String(UserDefaultsManagement.defaultPicUpload))
        editorLineBreak.selectItem(withTitle: String(UserDefaultsManagement.editorLineBreak))
        buttonShow.selectItem(withTitle: String(UserDefaultsManagement.buttonShow))
        codeBackground.selectItem(withTitle: String(UserDefaultsManagement.codeBackground))

        if UserDefaultsManagement.codeFontName == UserDefaultsManagement.fontName {
            codeFontName.selectItem(withTitle: "Editor Font")
        } else if let fontType = FontType.from(actualFontName: UserDefaultsManagement.codeFontName) {
            codeFontName.selectItem(withTitle: getLocalizedFontName(for: fontType))
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

    private func getLocalizedFontName(for fontType: FontType) -> String {
        let currentLanguage = UserDefaultsManagement.defaultLanguage

        let fontNames: [FontType: [String]] = [
            .tsanger: ["仓耳今楷", "Tsanger JinKai", "蒼耳今楷", "倉耳今楷"],
            .lxgw: ["霞鹜文楷", "LXGW WenKai", "霞鶩文楷", "霞鶩文楷"],
            .system: ["系统字体", "System Font", "システムフォント", "系統字體"],
            .times: ["新罗马体", "Times New Roman", "Times New Roman", "新羅馬體"],
        ]

        let names = fontNames[fontType] ?? []
        guard !names.isEmpty else { return fontType.rawValue }
        
        // Ensure language index is within bounds
        let safeIndex = max(0, min(currentLanguage, names.count - 1))
        return names[safeIndex]
    }

    private func getFontType(from displayName: String) -> FontType? {
        for fontType in FontType.allCases where getLocalizedFontName(for: fontType) == displayName {
            return fontType
        }
        return nil
    }

    private func setupLocalizedFontNames() {
        // 按照期望的顺序设置字体列表：仓耳今楷，霞鹜文楷，新罗马体，系统字体
        let fontOrder: [FontType] = [.tsanger, .lxgw, .times, .system]
        let fontNames = fontOrder.map { getLocalizedFontName(for: $0) }

        // 清空现有菜单项并添加新的本地化菜单项
        editorFontName.removeAllItems()
        previewFontName.removeAllItems()
        windowFontName.removeAllItems()

        for fontName in fontNames {
            editorFontName.addItem(withTitle: fontName)
            previewFontName.addItem(withTitle: fontName)
            windowFontName.addItem(withTitle: fontName)
        }
    }

    private func restart() {
        guard let vc = ViewController.shared(), let w = vc.view.window else { return }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Restart to MiaoYan to take effect", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Confirm", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.beginSheetModal(for: w) { (returnCode: NSApplication.ModalResponse) in
            if returnCode == NSApplication.ModalResponse.alertFirstButtonReturn {
                UserDefaultsManagement.isFirstLaunch = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
}
