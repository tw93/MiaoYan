import Foundation

// MARK: - Preferences Category Model
enum PreferencesCategory: String, CaseIterable {
    case general
    case typography
    case editor

    var title: String {
        switch self {
        case .general:
            return I18n.str("General")
        case .editor:
            return I18n.str("Editor")
        case .typography:
            // Reuse localized title for Fonts
            return I18n.str("Fonts")
        }
    }
}

// MARK: - Settings Configuration Protocol
protocol SettingsConfigurable {
    var category: PreferencesCategory { get }
    var title: String { get }

    func applyChanges()
}

// MARK: - General Settings Model
/// Concrete configuration for the General preferences pane backed by `UserDefaultsManagement`.
struct GeneralSettings: SettingsConfigurable {
    let category: PreferencesCategory = .general
    let title: String = I18n.str("General")
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

    var defaultPicUpload: String {
        get { UserDefaultsManagement.defaultPicUpload }
        set { UserDefaultsManagement.defaultPicUpload = newValue }
    }

    func applyChanges() {
        // General settings typically require app restart
        NotificationCenter.default.post(name: .preferencesChanged, object: self.category)
    }
}

// MARK: - Editor Settings Model
/// Configuration wrapper exposing editor related defaults for the preferences UI.
struct EditorSettings: SettingsConfigurable {
    let category: PreferencesCategory = .editor
    let title: String = I18n.str("Editor")
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
        // Editor settings need immediate refresh but should preserve preview state
        guard let vc = ViewController.shared() else { return }
        NotesTextProcessor.hl = nil
        let wasPreviewOn = UserDefaultsManagement.preview
        if wasPreviewOn {
            vc.disablePreview()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak vc] in
                vc?.refillEditArea()
                if let vc = vc, !vc.isMiaoYanPPT(needToast: false) {
                    vc.enablePreview()
                }
            }
        } else {
            // Do not turn preview on if user was editing
            vc.refillEditArea()
        }
    }
}

