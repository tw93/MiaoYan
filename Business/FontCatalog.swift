import AppKit

/// Which families a font popup should offer.
///
/// `NSFontManager.availableFontFamilies` returns everything installed, 270
/// families on a stock machine, sorted alphabetically. That puts Apple Braille,
/// Apple Color Emoji, Al Bayan and Arial Hebrew in the first screenful of a
/// list whose job is to pick a face for Chinese prose or for code. Each popup
/// asks for the families it can actually use instead.
enum FontListKind {
    /// Faces that can render Chinese, for the editor, the preview and the interface.
    case text
    /// Monospaced faces, for the code font.
    case code
}

enum FontCatalog {
    /// Recommended faces, shown above the rest. Kept short on purpose: these are
    /// the app's own defaults plus the face MiaoYan used to bundle, not a survey.
    static let recommendedText = ["PingFang SC", "TsangerJinKai02", "Songti SC", "Hiragino Sans GB"]
    static let recommendedCode = ["Menlo", "JetBrains Mono", "Monaco"]

    /// The face MiaoYan shipped until 4.3.0, when redistributing it stopped
    /// being an option. Selections were migrated to the system default, so
    /// someone who liked it has no way back from inside the app; the popup
    /// keeps a row for it and points at the foundry.
    static let retiredBundledFamily = "TsangerJinKai02"
    static let retiredBundledDownloadURL = "https://tsanger.cn"

    /// A family qualifies as a text face when it can draw these. Three common
    /// hanzi are enough to separate a CJK face from a Latin-only one without
    /// walking the whole character set.
    private static let cjkProbe = "永妙言"

    private static let cache = Cache()

    /// Families for this popup, alphabetically, recommendations excluded.
    static func families(for kind: FontListKind) -> [String] {
        cache.families(for: kind)
    }

    /// Recommendations for this popup that are actually installed.
    static func installedRecommendations(for kind: FontListKind) -> [String] {
        let all = kind == .text ? recommendedText : recommendedCode
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        return all.filter { installed.contains($0) }
    }

    static func isInstalled(family: String) -> Bool {
        NSFontManager.shared.availableFontFamilies.contains(family)
    }

    /// The family name for a stored preference.
    ///
    /// Stored values are not all family names. The shipped defaults are
    /// PostScript names (`PingFangSC-Regular`), while anything the user picks
    /// from the popup is a family name (`PingFang SC`), because the popup is
    /// built from families. Without this the default never matches a row and
    /// gets appended as a 271st orphan entry below the alphabetical list.
    static func familyName(forStored stored: String) -> String {
        guard !stored.isEmpty else { return stored }
        if isInstalled(family: stored) { return stored }
        return NSFont(name: stored, size: 12)?.familyName ?? stored
    }

    /// Classification walks every installed family and asks each one for its
    /// character set, which costs about 110ms for the text list. One shared
    /// cache keeps the four popups on a single pass, and a change in the
    /// installed-family count invalidates it so a newly installed face appears
    /// the next time Preferences opens.
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var stamp = -1
        private var text: [String] = []
        private var code: [String] = []

        func families(for kind: FontListKind) -> [String] {
            lock.lock()
            defer { lock.unlock() }
            let all = NSFontManager.shared.availableFontFamilies
            if all.count != stamp {
                stamp = all.count
                var textFamilies: [String] = []
                var codeFamilies: [String] = []
                let probe = Array(cjkProbe.unicodeScalars)
                for family in all {
                    guard let font = NSFont(name: family, size: 12) else { continue }
                    if font.isFixedPitch { codeFamilies.append(family) }
                    let covered = font.coveredCharacterSet
                    if probe.allSatisfy({ covered.contains($0) }) { textFamilies.append(family) }
                }
                text = textFamilies.sorted()
                code = codeFamilies.sorted()
            }
            return kind == .text ? text : code
        }
    }
}
