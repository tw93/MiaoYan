import AppKit
import MiaoYanCore

/// PDF, image, HTML and deck export from the shell window.
@available(macOS 14, *)
extension ShellModel {
    enum ExportFormat {
        case pdf
        case image
        case html
        /// The Reveal.js deck, one slide a page.
        case ppt
    }

    /// Whether the open note can be shown as a deck: it has a `---` slide
    /// break. A note whose text is not loaded yet is let through, and the
    /// deck itself says so.
    var selectedNoteHasSlides: Bool {
        selectedNote.map(hasSlides) ?? false
    }

    func hasSlides(_ note: Note) -> Bool {
        !note.isContentLoaded || note.content.string.contains("---")
    }

    /// HTML is rendered straight from the note. PDF and image capture the
    /// preview's rendering, so an export from the editor shows the preview
    /// first and returns to the editor after, as the storyboard window does.
    func export(_ format: ExportFormat) {
        guard !isExporting, selectedNote != nil else { return }
        if format == .ppt {
            exportDeck()
            return
        }
        isExporting = true
        if format == .html {
            MPreviewView.exportHtml()
            return
        }
        if editorMode == .edit {
            restoreEditAfterExport = true
            setMode(.preview)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            guard let preview = self.preview else {
                self.host?.toast(message: I18n.str("Export failed"), style: .failure)
                self.finishExport()
                return
            }
            switch format {
            case .pdf: preview.exportPdf()
            case .image: preview.exportImage()
            case .html, .ppt: break
            }
        }
    }

    /// The deck prints from PPT mode, as the storyboard window's export does:
    /// the note opens as slides, is saved as a PDF, and closes again unless
    /// it was already showing as slides.
    private func exportDeck() {
        let wasPPT = isPPT
        guard wasPPT || !isPresenting else { return }
        // ppt.html lays the deck out one slide a page only when it is rendered
        // with this set; the export clears it once the PDF is made.
        UserDefaultsManagement.isOnExportPPT = true
        var stalePage: Int?
        if wasPPT {
            // The page on screen goes on answering until the reload lands; after
            // an earlier export it is already `?print-pdf` and read ready.
            stalePage = preview?.loadEpoch
            previewStyleRevision &+= 1
        } else {
            setPresenting(true, ppt: true)
            // Without a --- separator setPresenting has said so and stayed put.
            guard isPPT else {
                UserDefaultsManagement.isOnExportPPT = false
                return
            }
        }
        isExporting = true
        leavePPTAfterExport = !wasPPT
        printDeckWhenShown(after: stalePage)
    }

    /// Whether `preview` shows a page loaded after the load `stalePage`
    /// names; any page will do when there is none to wait out.
    static func deckPageIsFresh(_ preview: MPreviewView, after stalePage: Int?) -> Bool {
        stalePage.map { preview.shownLoadEpoch > $0 } ?? true
    }

    /// How far the deck export's wait has gone. The reload a second export
    /// waits for has its own budget, so a slow reload does not use up the
    /// 50 polls (5s) the slides are given, which then read as Export failed.
    struct DeckWait: Equatable {
        /// 10s for the reloaded page, 5s for the slides to show, as before.
        static let reloadBudget = 100
        static let slideBudget = 50

        var reloadPolls = 0
        var slidePolls = 0

        enum Step: Equatable {
            case print
            case poll(DeckWait)
            case fail
        }

        func next(isPPT: Bool, pageIsFresh: Bool, slidesShown: Bool) -> Step {
            // Leaving full screen ends the slides; the preview then left is
            // not the deck, so it is not printed as one.
            guard isPPT else { return .fail }
            if !pageIsFresh {
                guard reloadPolls < Self.reloadBudget else { return .fail }
                return .poll(DeckWait(reloadPolls: reloadPolls + 1, slidePolls: slidePolls))
            }
            if !slidesShown {
                guard slidePolls < Self.slideBudget else { return .fail }
                return .poll(DeckWait(reloadPolls: reloadPolls, slidePolls: slidePolls + 1))
            }
            return .print
        }
    }

    /// Hands the deck to the preview that shows it. Entering PPT from the
    /// editor or split view makes a new preview on SwiftUI's next pass, so
    /// the export waits for one showing slides; the preview then waits for
    /// the deck itself (`MPreviewView.deckReadyScript`), where a fixed 1.2s
    /// printed Mermaid slides before they were drawn. A second export while
    /// already in PPT mode ran that check on the `?print-pdf` page of the
    /// first, before the reload its `previewStyleRevision` bump starts had
    /// landed, so it waits for a page newer than `stalePage` first.
    private func printDeckWhenShown(after stalePage: Int?, wait: DeckWait = DeckWait()) {
        let pageIsFresh = preview.map { Self.deckPageIsFresh($0, after: stalePage) } ?? true
        let slidesShown = preview.map { $0.window != nil && $0.pageIsSlides } ?? false
        switch wait.next(isPPT: isPPT, pageIsFresh: pageIsFresh, slidesShown: slidesShown) {
        case .print:
            preview?.exportPPTOptimized(awaitingPrintPage: true)
        case .poll(let next):
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.printDeckWhenShown(after: stalePage, wait: next)
            }
        case .fail:
            UserDefaultsManagement.isOnExportPPT = false
            host?.toast(message: I18n.str("Export failed"), style: .failure)
            finishPPTExport()
            finishExport()
        }
    }

    /// Called once the deck is printed, before the file is written.
    func finishPPTExport() {
        guard leavePPTAfterExport else { return }
        leavePPTAfterExport = false
        setPresenting(false)
    }

    func finishExport() {
        isExporting = false
        if restoreEditAfterExport {
            restoreEditAfterExport = false
            setMode(.edit)
        }
    }
}
