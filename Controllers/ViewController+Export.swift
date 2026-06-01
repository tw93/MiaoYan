import Cocoa

// MARK: - Export and Toast Surface
extension ViewController {
    func exportFile(type: String) {
        sessionIsExporting = true
        shouldRestorePreviewAfterExport = false

        if type == "Html" {
            sessionIsExportingHTML = true
            // HTML export can be done immediately without preview
            self.editArea.markdownView?.exportHtml()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.sessionIsExporting = false
                self.sessionIsExportingHTML = false
            }
            return
        }

        // For PDF and Image exports, enable preview and wait for proper loading
        // For PDF and Image exports, ensure preview is enabled
        // Only toggle if not already in preview to avoid unnecessary reload
        if !shouldShowPreview {
            enablePreview()
            shouldRestorePreviewAfterExport = true
        }

        // Wait briefly for view initialization if needed, then trigger export
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            switch type {
            case "Image":
                self.editArea.markdownView?.exportImage()
            case "PDF":
                self.editArea.markdownView?.exportPdf()
            default:
                break
            }
            // Logic for cleanup is handled in the completion callbacks (toastExport)
        }
    }

    public func toastExport(status: Bool) {
        if status {
            toast(message: I18n.str("Saved to Downloads folder~"), style: .success)
        } else {
            toast(message: I18n.str("Export failed"), style: .failure)
        }
        // After the export is completed, restore the original state.
        sessionIsExporting = false
        sessionIsExportingPPT = false
        sessionIsExportingHTML = false
        shouldDisablePPTAfterExport = false
        if shouldRestorePreviewAfterExport {
            disablePreview()
            shouldRestorePreviewAfterExport = false
        }
    }

    public func toastNoTitle() {
        toast(message: I18n.str("Please make sure your title exists~"), style: .failure)
    }

    public func toastMoreTitle() {
        toast(message: I18n.str("Found that there are multiple titles of this~"), style: .failure)
    }

    public func toastImageSet(name: String) {
        toast(message: String(format: I18n.str("Please make sure your Mac is installed %@ ~"), name), style: .failure)
    }

    public func toastUpload(status: Bool) {
        if status {
            toast(message: I18n.str("Image upload in progress~"))
        } else {
            toast(message: I18n.str("Image upload failed, Use local~"), style: .failure)
        }
    }
}
