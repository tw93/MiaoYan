import AppKit

@MainActor
class ContentViewController: NSViewController, NSPopoverDelegate {
    private var wordCount: NSTextField!
    private var updateTime: NSTextField!
    private var createTime: NSTextField!
    private var backlinksLabel: NSTextField!
    private var backlinksListView: NSTextView!
    private var scrollView: NSScrollView!
    private var separatorView: NSView!
    /// The note to describe; the storyboard window leaves it nil and the
    /// list's selection is used.
    var note: Note?

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 210))
        view.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
        ])

        wordCount = makeLabel()
        updateTime = makeLabel()
        createTime = makeLabel()

        stack.addArrangedSubview(wordCount)
        stack.addArrangedSubview(updateTime)
        stack.addArrangedSubview(createTime)

        separatorView = NSView()
        separatorView.wantsLayer = true
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.widthAnchor.constraint(equalToConstant: 272).isActive = true
        separatorView.heightAnchor.constraint(equalToConstant: 1).isActive = true
        stack.addArrangedSubview(separatorView)

        backlinksLabel = makeLabel()
        backlinksLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        stack.addArrangedSubview(backlinksLabel)

        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 82).isActive = true
        scrollView.widthAnchor.constraint(equalToConstant: 272).isActive = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        backlinksListView = NSTextView()
        backlinksListView.isEditable = false
        backlinksListView.isSelectable = true
        backlinksListView.font = NSFont.systemFont(ofSize: 12)
        backlinksListView.drawsBackground = false
        backlinksListView.textContainerInset = NSSize(width: 0, height: 2)
        scrollView.documentView = backlinksListView

        stack.addArrangedSubview(scrollView)
        updateAppearance()
    }

    private func makeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func updateAppearance() {
        view.layer?.backgroundColor = Theme.panelBackgroundColor.resolvedColor(for: view.effectiveAppearance).cgColor
        [wordCount, updateTime, createTime].forEach { label in
            label?.textColor = Theme.secondaryTextColor
        }
        backlinksLabel?.textColor = Theme.textColor
        backlinksListView?.textColor = Theme.secondaryTextColor
        separatorView?.layer?.backgroundColor = Theme.panelHairlineColor.resolvedColor(for: view.effectiveAppearance).cgColor
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateAppearance()

        guard let note = note ?? ViewController.shared()?.notesTableView.getSelectedNote() else { return }

        var words = note.getPrettifiedContent()
        words = ViewController.replace(validateString: words, regex: "*+", content: "")
        words = ViewController.replace(validateString: words, regex: "#+", content: "")
        words = ViewController.replace(validateString: words, regex: "\\r\n", content: "")
        words = ViewController.replace(validateString: words, regex: "\\n", content: "")
        words = ViewController.replace(validateString: words, regex: "\\s", content: "")

        wordCount.stringValue = "\(I18n.str("Words")): \(words.count)"
        updateTime.stringValue = "\(I18n.str("Modified")): \(note.getUpdateTime() ?? "")"
        createTime.stringValue = "\(I18n.str("Created")): \(note.getCreateTime() ?? "")"

        let backlinks = WikilinkIndex.shared.getBacklinks(for: note.title)
        if backlinks.isEmpty {
            backlinksLabel.stringValue = "\(I18n.str("Backlinks")): \(I18n.str("None"))"
            backlinksListView.string = ""
            scrollView.isHidden = true
        } else {
            backlinksLabel.stringValue = "\(I18n.str("Backlinks")): \(backlinks.count)"
            backlinksListView.string = backlinks.joined(separator: "\n")
            scrollView.isHidden = false
        }
    }
}
