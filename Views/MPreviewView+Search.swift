import Cocoa
import WebKit

extension MPreviewView {
    private static var searchBarKey: UInt8 = 0
    private static var lastSearchTextKey: UInt8 = 0
    private static var searchMatchCountKey: UInt8 = 0
    private static var searchCurrentIndexKey: UInt8 = 0
    private static var searchTimerKey: UInt8 = 0
    private static var searchSequenceKey: UInt8 = 0
    private static var searchBarHeightConstraintKey: UInt8 = 0

    private var searchBar: PreviewSearchBar? {
        get {
            objc_getAssociatedObject(self, &MPreviewView.searchBarKey) as? PreviewSearchBar
        }
        set {
            objc_setAssociatedObject(self, &MPreviewView.searchBarKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private var lastSearchText: String {
        get {
            objc_getAssociatedObject(self, &MPreviewView.lastSearchTextKey) as? String ?? ""
        }
        set {
            objc_setAssociatedObject(self, &MPreviewView.lastSearchTextKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private var searchMatchCount: Int {
        get {
            objc_getAssociatedObject(self, &MPreviewView.searchMatchCountKey) as? Int ?? 0
        }
        set {
            objc_setAssociatedObject(self, &MPreviewView.searchMatchCountKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private var searchCurrentMatchIndex: Int {
        get {
            objc_getAssociatedObject(self, &MPreviewView.searchCurrentIndexKey) as? Int ?? 0
        }
        set {
            objc_setAssociatedObject(self, &MPreviewView.searchCurrentIndexKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private var searchTimer: Timer? {
        get {
            objc_getAssociatedObject(self, &MPreviewView.searchTimerKey) as? Timer
        }
        set {
            objc_setAssociatedObject(self, &MPreviewView.searchTimerKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private var searchSequence: Int {
        get {
            objc_getAssociatedObject(self, &MPreviewView.searchSequenceKey) as? Int ?? 0
        }
        set {
            objc_setAssociatedObject(self, &MPreviewView.searchSequenceKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private var searchBarHeightConstraint: NSLayoutConstraint? {
        get {
            objc_getAssociatedObject(self, &MPreviewView.searchBarHeightConstraintKey) as? NSLayoutConstraint
        }
        set {
            objc_setAssociatedObject(self, &MPreviewView.searchBarHeightConstraintKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    var isSearchBarVisible: Bool {
        searchBar != nil
    }

    private func getViewController() -> ViewController? {
        return self.window?.contentViewController as? ViewController
    }

    func showSearchBar(mode: PreviewSearchBar.Mode = .find) {
        if let existingBar = searchBar {
            existingBar.setMode(mode)

            let newHeight: CGFloat = (mode == .replace) ? 76 : 40
            searchBarHeightConstraint?.constant = newHeight

            existingBar.focusSearchField(selectAll: true)
            if !lastSearchText.isEmpty {
                performSearch(lastSearchText)
            }

            if let vc = getViewController(), existingBar.superview !== vc.view {
                existingBar.removeFromSuperview()
            } else if existingBar.superview != nil {
                return
            }
        }

        let bar = searchBar ?? PreviewSearchBar(frame: .zero)
        if searchBar == nil {
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.configureAppearance(baseColor: determineBackgroundColor())

            bar.onSearch = { [weak self] text in
                self?.scheduleSearch(text)
            }

            bar.onNext = { [weak self] in
                self?.findNext()
            }

            bar.onPrevious = { [weak self] in
                self?.findPrevious()
            }

            bar.onReplace = { [weak self] replaceText in
                self?.replaceNext(with: replaceText)
            }

            bar.onReplaceAll = { [weak self] replaceText in
                self?.replaceAll(with: replaceText)
            }

            bar.onClose = { [weak self] in
                self?.hideSearchBar()
            }
            searchBar = bar
        }

        bar.setMode(mode)

        var targetContainer: NSView?
        var layoutGuideView: NSView?

        if let vc = getViewController() {
            targetContainer = vc.view
            layoutGuideView = self.enclosingScrollView ?? self
        } else if let scrollView = self.enclosingScrollView, let parent = scrollView.superview {
            targetContainer = parent
            layoutGuideView = scrollView
        } else {
            targetContainer = self
            layoutGuideView = self
        }

        if let container = targetContainer, let guide = layoutGuideView {
            if bar.superview !== container {
                container.addSubview(bar)
                activateSearchBarConstraints(bar: bar, container: container, guide: guide, mode: mode)
            }
        }

        DispatchQueue.main.async {
            bar.focusSearchField(selectAll: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if !self.lastSearchText.isEmpty {
                    self.performSearch(self.lastSearchText)
                }
            }
        }
    }

    private func activateSearchBarConstraints(bar: NSView, container: NSView, guide: NSView, mode: PreviewSearchBar.Mode = .find) {
        let barHeight: CGFloat = (mode == .replace) ? 76 : 40
        let barWidth: CGFloat = 360
        let marginRight: CGFloat = 26
        let marginTop: CGFloat = 0

        let heightConstraint = bar.heightAnchor.constraint(equalToConstant: barHeight)
        searchBarHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: guide.topAnchor, constant: marginTop),
            bar.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -marginRight),
            bar.widthAnchor.constraint(equalToConstant: barWidth),
            heightConstraint,
        ])
    }

    func hideSearchBar() {
        searchTimer?.invalidate()
        searchTimer = nil
        clearSearchHighlights()
        searchBar?.removeFromSuperview()
        searchBar = nil
        lastSearchText = ""
        searchMatchCount = 0
        searchCurrentMatchIndex = 0
    }

    private func scheduleSearch(_ text: String) {
        // Cancel previous timer
        searchTimer?.invalidate()

        // If text is empty, clear immediately
        guard !text.isEmpty else {
            performSearch(text)
            return
        }

        // Schedule search with delay (0.15s for quick response)
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performSearch(text)
            }
        }
    }

    private func performSearch(_ text: String) {
        searchSequence += 1
        let currentSequence = searchSequence
        let shouldResetSelection = text != lastSearchText

        guard !text.isEmpty else {
            clearSearchHighlights()
            searchBar?.updateMatchInfo(current: 0, total: 0)
            lastSearchText = ""
            searchMatchCount = 0
            searchCurrentMatchIndex = 0
            return
        }

        let executeSearch: () -> Void = { [weak self] in
            guard
                let self,
                self.searchSequence == currentSequence
            else { return }

            self.lastSearchText = text
            if shouldResetSelection {
                self.searchCurrentMatchIndex = 0
            } else {
                self.searchCurrentMatchIndex = min(self.searchCurrentMatchIndex, max(self.searchMatchCount - 1, 0))
            }
            if #available(macOS 13.0, *) {
                self.performModernSearch(text, sequence: currentSequence, resetIndex: shouldResetSelection)
            } else {
                self.performJavaScriptSearch(text, sequence: currentSequence, resetIndex: shouldResetSelection)
            }
        }

        if shouldResetSelection {
            resetSearchSelection { [weak self] in
                guard
                    let self,
                    self.searchSequence == currentSequence
                else { return }
                executeSearch()
            }
        } else {
            executeSearch()
        }
    }

    @available(macOS 13.0, *)
    private func performModernSearch(_ text: String, sequence: Int, resetIndex: Bool) {
        let config = WKFindConfiguration()
        config.caseSensitive = false
        config.backwards = false
        config.wraps = true

        find(text, configuration: config) { [weak self] result in
            guard let self = self, self.searchSequence == sequence else { return }
            DispatchQueue.main.async {
                if result.matchFound {
                    self.countMatches(text, sequence: sequence, resetIndex: resetIndex)
                } else {
                    self.searchBar?.updateMatchInfo(current: 0, total: 0)
                }
            }
        }
    }

    private func performJavaScriptSearch(_ text: String, sequence: Int, resetIndex: Bool) {
        let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let script = """
            window.find('\(escapedText)', false, false, true, false, false, false);
            """

        evaluateJavaScript(script) { [weak self] _, _ in
            guard let self = self, self.searchSequence == sequence else { return }
            self.countMatches(text, sequence: sequence, resetIndex: resetIndex)
        }
    }

    private func countMatches(_ text: String, sequence: Int, resetIndex: Bool) {
        let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let script = """
            (function() {
                const text = '\(escapedText)';
                const regex = new RegExp(text, 'gi');
                const bodyText = document.body.innerText || document.body.textContent;
                const matches = bodyText.match(regex);
                return matches ? matches.length : 0;
            })();
            """

        evaluateJavaScript(script) { [weak self] result, _ in
            guard let self = self, self.searchSequence == sequence else { return }
            DispatchQueue.main.async {
                if let count = result as? Int {
                    self.searchMatchCount = count
                    if count == 0 {
                        self.searchCurrentMatchIndex = 0
                        self.searchBar?.updateMatchInfo(current: 0, total: 0)
                        return
                    }

                    if resetIndex {
                        self.searchCurrentMatchIndex = 0
                        self.focusFirstPreviewMatch(with: text)
                    } else if self.searchCurrentMatchIndex >= count {
                        self.searchCurrentMatchIndex = max(count - 1, 0)
                    }

                    self.searchBar?.updateMatchInfo(current: self.searchCurrentMatchIndex + 1, total: count)
                }
            }
        }
    }

    func findNext() {
        guard !lastSearchText.isEmpty, searchMatchCount > 0 else { return }

        searchCurrentMatchIndex = (searchCurrentMatchIndex + 1) % searchMatchCount
        searchBar?.updateMatchInfo(current: searchCurrentMatchIndex + 1, total: searchMatchCount)

        performWebFind(backwards: false)
    }

    func findPrevious() {
        guard !lastSearchText.isEmpty, searchMatchCount > 0 else { return }

        searchCurrentMatchIndex = (searchCurrentMatchIndex - 1 + searchMatchCount) % searchMatchCount
        searchBar?.updateMatchInfo(current: searchCurrentMatchIndex + 1, total: searchMatchCount)

        performWebFind(backwards: true)
    }

    func replaceNext(with replaceText: String) {
        guard let editArea = getViewController()?.editArea else { return }
        editArea.replaceNext(with: replaceText)
    }

    func replaceAll(with replaceText: String) {
        guard let editArea = getViewController()?.editArea else { return }
        editArea.replaceAll(with: replaceText)
    }

    private func performWebFind(backwards: Bool) {
        guard !lastSearchText.isEmpty else { return }

        if #available(macOS 13.0, *) {
            let config = WKFindConfiguration()
            config.caseSensitive = false
            config.backwards = backwards
            config.wraps = true

            find(lastSearchText, configuration: config) { _ in }
        } else {
            let escapedText = lastSearchText.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let script = "window.find('\(escapedText)', false, \(backwards ? "true" : "false"), true, false, false, false);"
            evaluateJavaScript(script, completionHandler: nil)
        }
    }

    private func focusFirstPreviewMatch(with text: String) {
        guard !text.isEmpty else { return }

        let escapedText =
            text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")

        let script = """
            (function() {
                const query = '\(escapedText)';
                if (!query) { return false; }
                const lowerQuery = query.toLowerCase();
                const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT, null);
                if (!walker) { return false; }
                const selection = window.getSelection();
                if (!selection) { return false; }
                while (walker.nextNode()) {
                    const node = walker.currentNode;
                    if (!node || !node.textContent) { continue; }
                    const textContent = node.textContent;
                    const index = textContent.toLowerCase().indexOf(lowerQuery);
                    if (index !== -1) {
                        const range = document.createRange();
                        range.setStart(node, index);
                        range.setEnd(node, index + query.length);
                        selection.removeAllRanges();
                        selection.addRange(range);
                        const element = node.parentElement || node.parentNode;
                        if (element && element.scrollIntoView) {
                            element.scrollIntoView({ block: 'center', behavior: 'auto' });
                        }
                        return true;
                    }
                }
                return false;
            })();
            """

        evaluateJavaScript(script, completionHandler: nil)
    }

    private func clearSearchHighlights() {
        let script = "window.getSelection().removeAllRanges();"
        evaluateJavaScript(script, completionHandler: nil)
    }

    private func resetSearchSelection(completion: @escaping () -> Void) {
        let script = """
            (function() {
                const selection = window.getSelection();
                if (!selection) { return false; }
                const root = document.body || document.documentElement;
                if (!root) { return false; }
                const range = document.createRange();
                range.selectNodeContents(root);
                range.collapse(true);
                selection.removeAllRanges();
                selection.addRange(range);
                return true;
            })();
            """
        evaluateJavaScript(script) { _, _ in
            completion()
        }
    }
}
