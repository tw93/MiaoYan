import Foundation

// MARK: - Preferences Category Model
enum PrefsSection: CaseIterable, Sendable {
    case general, editor, typography

    @MainActor
    var title: String {
        switch self {
        case .general: return I18n.str("General")
        case .editor: return I18n.str("Editor")
        case .typography: return I18n.str("Fonts")
        }
    }
}

// MARK: - General Settings Model
@MainActor
struct GeneralSettings {
    var appearanceType: AppearanceType {
        get { UserDefaultsManagement.appearanceType }
        set { UserDefaultsManagement.appearanceType = newValue }
    }

    var defaultLanguage: Int {
        get { UserDefaultsManagement.defaultLanguage }
        set { UserDefaultsManagement.defaultLanguage = newValue }
    }

    var storagePath: String? {
        get { UserDefaultsManagement.storagePath }
        set { UserDefaultsManagement.storagePath = newValue }
    }

    var buttonShow: String {
        get { UserDefaultsManagement.buttonShow }
        set { UserDefaultsManagement.buttonShow = newValue }
    }
}

// MARK: - Editor Settings Model
@MainActor
struct EditorSettings {
    var editorFontName: String {
        get { UserDefaultsManagement.fontName }
        set { UserDefaultsManagement.fontName = newValue }
    }

    var editorFontSize: Int {
        get { UserDefaultsManagement.fontSize }
        set { UserDefaultsManagement.fontSize = newValue }
    }

    var windowFontName: String {
        get { UserDefaultsManagement.windowFontName }
        set { UserDefaultsManagement.windowFontName = newValue }
    }

    var previewFontName: String {
        get { UserDefaultsManagement.previewFontName }
        set { UserDefaultsManagement.previewFontName = newValue }
    }

    var previewFontSize: Int {
        get { UserDefaultsManagement.previewFontSize }
        set { UserDefaultsManagement.previewFontSize = newValue }
    }

    var presentationFontSize: Int {
        get { UserDefaultsManagement.presentationFontSize }
        set { UserDefaultsManagement.presentationFontSize = newValue }
    }

    var codeFontName: String {
        get { UserDefaultsManagement.codeFontName }
        set { UserDefaultsManagement.codeFontName = newValue }
    }

    var editorLineBreak: String {
        get { UserDefaultsManagement.editorLineBreak }
        set { UserDefaultsManagement.editorLineBreak = newValue }
    }

    var previewLocation: String {
        get { UserDefaultsManagement.previewLocation }
        set { UserDefaultsManagement.previewLocation = newValue }
    }

    var previewWidth: String {
        get { UserDefaultsManagement.previewWidth }
        set { UserDefaultsManagement.previewWidth = newValue }
    }

    func applyChanges() {
        // The SwiftUI shell has no ViewController; it re-renders on this note.
        guard let vc = ViewController.shared() else {
            NotesTextProcessor.hl = nil
            NotesTextProcessor.refreshFonts()
            NotificationCenter.default.post(name: .editorSettingsChanged, object: nil)
            return
        }
        NotesTextProcessor.hl = nil
        NotesTextProcessor.refreshFonts()

        let wasPreviewOn = UserDefaultsManagement.preview
        if wasPreviewOn {
            vc.disablePreview()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak vc] in
                vc?.refillEditArea(force: true)
                if let vc, !vc.isMiaoYanPPT(needToast: false) {
                    vc.enablePreview()
                }
            }
        } else {
            vc.refillEditArea(force: true)
        }
    }
}
