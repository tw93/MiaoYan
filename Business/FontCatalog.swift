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
    /// the app's own defaults, the face MiaoYan used to bundle, and the few
    /// Latin faces someone writing in English would reach for first.
    static let recommendedText = [
        "PingFang SC", "TsangerJinKai02", "Songti SC", "Hiragino Sans GB",
        "Helvetica Neue", "Georgia", "Avenir Next",
    ]
    static let recommendedCode = ["Menlo", "JetBrains Mono", "Monaco"]

    /// The default text face, bundled until 4.3.0, when redistributing it
    /// stopped being an option. It is still the default by name; while it is
    /// missing the popup keeps a row for it that points at the foundry.
    static let retiredBundledFamily = "TsangerJinKai02"
    /// The foundry's own file for the weight the default names (the same 18.9MB
    /// file MiaoYan used to bundle), so one click downloads it instead of
    /// landing on a product page. MiaoYan never hosts or redistributes it.
    static let retiredBundledDownloadURL = "https://tsanger.cn/download/%E4%BB%93%E8%80%B3%E4%BB%8A%E6%A5%B702-W04.ttf"

    /// A family qualifies as a text face when it can draw these. Three common
    /// hanzi are enough to separate a CJK face from a Latin-only one without
    /// walking the whole character set.
    private static let cjkProbe = "永妙言"
    /// Letters, digits and the punctuation a paragraph of English needs; a face
    /// that cannot draw all of it is a symbol or single-script font, not a
    /// choice for body text.
    private static let latinProbe = "The quick brown fox 0123"

    private static let cache = Cache()

    /// Families for this popup, ordered by label, recommendations excluded.
    static func families(for kind: FontListKind) -> [String] {
        cache.families(for: kind)
    }

    /// The same families split into the sections the popup draws. A text popup
    /// separates Chinese faces from Latin ones, because the two are never
    /// interchangeable for the same paragraph and a merged list makes the user
    /// read past 89 names to reach Georgia. A code popup has one section.
    ///
    /// Latin here means "draws ASCII but not 永". That keeps Arial, Times New
    /// Roman and Verdana, which a narrower rule would drop for covering Hebrew
    /// or Arabic as well, at the cost of leaving a few Thai and Korean faces in
    /// the section; their names say what they are.
    static func sections(for kind: FontListKind) -> [(title: String, families: [String])] {
        switch kind {
        case .code:
            return [("", families(for: .code))]
        case .text:
            return [("zh", families(for: .text)), ("latin", cache.latinFamilies())]
        }
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

    /// What to show for a family. macOS carries localized names in the font's own
    /// name table, so a Chinese user reads 苹方-简 and 宋体-简 rather than
    /// PingFang SC and Songti SC, and this works for third-party faces too
    /// (TsangerJinKai02 comes back as 仓耳今楷02). Faces with no localized name,
    /// Menlo among them, keep the name they already had. The family name stays
    /// the stored value; only the label changes.
    static func displayName(for family: String) -> String {
        NSFontManager.shared.localizedName(forFamily: family, face: nil)
    }

    /// The `font-family` stack for a chosen face.
    ///
    /// A face the user picked leads the stack and sets everything, Latin
    /// included. That is the whole point of picking it: TsangerJinKai02 draws
    /// its Latin to go with the楷书 it draws, single-storey a and g, and handing
    /// those words to the system face pulls the two halves of a line apart.
    ///
    /// PingFang is the one exception. Its Latin is drawn for interface labels,
    /// wider and looser than the system's, and it is the fallback rather than a
    /// face anyone picked for English. So for PingFang the system takes Latin
    /// and PingFang is named only as the CJK fallback, the way Claude's and
    /// Cursor's desktop apps order it.
    /// Main-actor bound because it reads the fallback from `FontConfiguration`;
    /// its only caller is `previewStyle()`, already there.
    @MainActor
    static func fontStack(forStored stored: String) -> String {
        let quoted = "\"\(stored)\""
        let system = "ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont"
        let cjkFallback = "\"PingFang SC\", \"Hiragino Sans GB\", \"Microsoft YaHei\""
        // Compare families, not the raw strings. The fallback is stored as a
        // PostScript name while every value the popup writes is a family name,
        // so picking 苹方-简 from the list, the row already shown as selected,
        // used to make this false and hand Latin back to PingFang for good,
        // with the two states indistinguishable in the UI.
        let untouched = familyName(forStored: stored) == familyName(forStored: FontConfiguration.fallbackFont)
        return untouched
            ? "\(system), \(quoted), \(cjkFallback), sans-serif"
            : "\(quoted), \(system), \(cjkFallback), sans-serif"
    }

    /// Families ordered the way their labels read, so a localized list is not
    /// sorted by an English name the user cannot see.
    static func sortedByDisplayName(_ families: [String]) -> [String] {
        families.sorted { displayName(for: $0).localizedStandardCompare(displayName(for: $1)) == .orderedAscending }
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
    /// installed-family set invalidates it so installed or removed faces appear
    /// the next time a font menu opens, including replacements at the same count.
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var installedFamilies: Set<String> = []
        private var text: [String] = []
        private var code: [String] = []
        private var latin: [String] = []

        func families(for kind: FontListKind) -> [String] {
            lock.lock()
            defer { lock.unlock() }
            rebuildIfNeeded()
            return kind == .text ? text : code
        }

        func latinFamilies() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            rebuildIfNeeded()
            return latin
        }

        private func rebuildIfNeeded() {
            let all = NSFontManager.shared.availableFontFamilies
            let installed = Set(all)
            guard installed != installedFamilies else { return }
            installedFamilies = installed
            var textFamilies: [String] = []
            var codeFamilies: [String] = []
            var latinFamilies: [String] = []
            let probe = Array(cjkProbe.unicodeScalars)
            let ascii = Array(latinProbe.unicodeScalars)
            for family in all {
                guard let font = NSFont(name: family, size: 12) else { continue }
                if font.isFixedPitch { codeFamilies.append(family) }
                let covered = font.coveredCharacterSet
                if probe.allSatisfy({ covered.contains($0) }) {
                    textFamilies.append(family)
                } else if ascii.allSatisfy({ covered.contains($0) }) {
                    latinFamilies.append(family)
                }
            }
            text = sortedByDisplayName(textFamilies)
            code = sortedByDisplayName(codeFamilies)
            latin = sortedByDisplayName(latinFamilies)
        }
    }
}
