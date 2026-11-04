import AppKit

/// How the editor hands a note to its preview: in place, as an update to the
/// note on screen, or as a full load behind a fade.
extension EditTextView {
    func renderPreviewContent(
        note: Note,
        previewView: MPreviewView,
        options: FillOptions,
        allowTransition: Bool,
        useIncremental: Bool,
        inPlace: Bool = false
    ) {
        if inPlace {
            previewView.alphaValue = 1.0
            previewView.showNoteInPlace(note)
            return
        }
        // Smooth transition: fade out -> load -> fade in (skip when animation is disabled)
        let needsTransition = allowTransition && !previewView.isHidden && previewView.alphaValue > 0
        if needsTransition {
            // The load waits for the fade-out. A fill that lands in those
            // 80ms loads its note at once; loading this one afterwards would
            // put the previous note back, and split mode then showed one note
            // in the editor beside another in the preview.
            let epoch = fillEpoch
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = Theme.Motion.previewFade
                    context.timingFunction = Theme.Motion.curve
                    previewView.animator().alphaValue = 0
                },
                completionHandler: { [weak self] in
                    Task { @MainActor in
                        guard let self, self.fillEpoch == epoch else { return }
                        previewView.load(note: note, force: options.force)
                        NSAnimationContext.runAnimationGroup({ context in
                            context.duration = Theme.Motion.feedback
                            context.timingFunction = Theme.Motion.curve
                            previewView.animator().alphaValue = 1.0
                        })
                    }
                })
        } else {
            if useIncremental, previewView.hasLoadedTemplate {
                // The note on screen changed underneath the reader, most often
                // because another app (an agent, a sync) wrote the file. Keep
                // the reading position; this used to jump back to the top.
                previewView.updateContent(note: note, preserveScroll: true)
                previewView.isHidden = false
                previewView.alphaValue = 1.0
            } else {
                let shouldGateReveal =
                    !MPreviewView.hasCompletedInitialLoad
                    || previewView.displayedNote !== note
                    || previewView.isHidden
                if shouldGateReveal {
                    previewView.alphaValue = 0
                } else {
                    // Fast reveal: show immediately to provide instant visual feedback
                    previewView.isHidden = false
                    previewView.alphaValue = 1.0
                }
                previewView.load(note: note, force: options.force) {
                    if shouldGateReveal {
                        DispatchQueue.main.asyncAfter(deadline: .now()) { [weak self] in
                            guard let self = self else { return }
                            let shouldShowPreview =
                                self.isPreviewModeActive
                                || self.isPresentationModeActive
                                || self.isMagicPPTModeActive
                                || self.isSplitModeActive
                            guard shouldShowPreview else { return }
                            previewView.isHidden = false
                            NSAnimationContext.runAnimationGroup({ context in
                                context.duration = Theme.Motion.previewFade
                                context.timingFunction = Theme.Motion.curve
                                previewView.animator().alphaValue = 1.0
                            })
                        }
                    }
                }
            }
        }
    }
}
