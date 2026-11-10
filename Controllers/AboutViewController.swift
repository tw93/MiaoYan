import Cocoa

@MainActor
class AboutViewController: NSViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        updateAppearance()

        if let dictionary = Bundle.main.infoDictionary,
            let ver = dictionary["CFBundleShortVersionString"] as? String
        {
            versionLabel.stringValue = "\(I18n.str("Version")) \(ver)"
            versionLabel.isSelectable = true
        }
        addMobileAppLink()
    }

    /// One quiet line under the copyright, opening the iPhone and iPad app's
    /// App Store page. The storyboard view is 175pt tall; the line adds its
    /// own height below.
    private func addMobileAppLink() {
        guard let copyright = view.subviews.compactMap({ $0 as? NSTextField }).min(by: { $0.frame.minY < $1.frame.minY }) else { return }
        let link = NSButton(title: I18n.str("MiaoYan for iPhone and iPad"), target: NSApp.delegate, action: #selector(AppDelegate.openMobileApp(_:)))
        link.isBordered = false
        link.focusRingType = .none
        link.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        link.contentTintColor = Theme.brand
        link.attributedTitle = NSAttributedString(
            string: link.title, attributes: [.foregroundColor: Theme.brand, .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])
        link.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(link)
        NSLayoutConstraint.activate([
            link.topAnchor.constraint(equalTo: copyright.bottomAnchor, constant: 6),
            link.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
        mobileLink = link
        preferredContentSize = NSSize(width: 300, height: 175 + 26)
    }

    private var mobileLink: NSButton?

    override func viewDidAppear() {
        super.viewDidAppear()
        updateAppearance()
    }

    private func updateAppearance() {
        view.wantsLayer = true
        view.layer?.backgroundColor = Theme.panelBackgroundColor.resolvedColor(for: view.effectiveAppearance).cgColor

        for case let label as NSTextField in view.subviews {
            label.textColor = label.stringValue == "MiaoYan" ? Theme.textColor : Theme.secondaryTextColor
        }
    }

    @IBOutlet var versionLabel: NSTextField!
}
