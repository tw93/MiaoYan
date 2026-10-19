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
        if wasPPT {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            // Leaving full screen ends the slides; the preview then left is
            // not the deck, so it is not printed as one.
            guard let preview = self.preview, self.isPPT else {
                UserDefaultsManagement.isOnExportPPT = false
                self.host?.toast(message: I18n.str("Export failed"), style: .failure)
                self.finishPPTExport()
                self.finishExport()
                return
            }
            preview.exportPPTOptimized()
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
