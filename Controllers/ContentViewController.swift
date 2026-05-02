import AppKit

@MainActor
class ContentViewController: NSViewController, NSPopoverDelegate {
    private var wordCount: NSTextField!
    private var updateTime: NSTextField!
    private var createTime: NSTextField!
    private var backlinksLabel: NSTextField!
    private var backlinksListView: NSTextView!
    private var scrollView: NSScrollView!

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 200))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])

        wordCount = makeLabel()
        updateTime = makeLabel()
        createTime = makeLabel()

        stack.addArrangedSubview(wordCount)
        stack.addArrangedSubview(updateTime)
        stack.addArrangedSubview(createTime)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 256).isActive = true
        stack.addArrangedSubview(separator)

        backlinksLabel = makeLabel()
        backlinksLabel.font = NSFont.boldSystemFont(ofSize: 11)
        stack.addArrangedSubview(backlinksLabel)

        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 80).isActive = true
        scrollView.widthAnchor.constraint(equalToConstant: 256).isActive = true

        backlinksListView = NSTextView()
        backlinksListView.isEditable = false
        backlinksListView.isSelectable = true
        backlinksListView.font = NSFont.systemFont(ofSize: 11)
        backlinksListView.textColor = .secondaryLabelColor
        scrollView.documentView = backlinksListView

        stack.addArrangedSubview(scrollView)
    }

    private func makeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard let vc = ViewController.shared() else { return }
        guard let note = vc.notesTableView.getSelectedNote() else { return }

        var words = note.getPrettifiedContent()
        words = vc.replace(validateString: words, regex: "*+", content: "")
        words = vc.replace(validateString: words, regex: "#+", content: "")
        words = vc.replace(validateString: words, regex: "\\r\n", content: "")
        words = vc.replace(validateString: words, regex: "\\n", content: "")
        words = vc.replace(validateString: words, regex: "\\s", content: "")

        wordCount.stringValue = "字数: \(words.count)"
        updateTime.stringValue = "修改: \(note.getUpdateTime() ?? "")"
        createTime.stringValue = "创建: \(note.getCreateTime() ?? "")"

        let backlinks = WikilinkIndex.shared.getBacklinks(for: note.title)
        if backlinks.isEmpty {
            backlinksLabel.stringValue = "反向链接: 无"
            backlinksListView.string = ""
            scrollView.isHidden = true
        } else {
            backlinksLabel.stringValue = "反向链接: \(backlinks.count)"
            backlinksListView.string = backlinks.joined(separator: "\n")
            scrollView.isHidden = false
        }
    }
}
