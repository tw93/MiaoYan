import Cocoa

extension NSTextField {
    /// Tracks the whole label by `letterSpacingEm`. The range used to stop
    /// one character short (counted in Characters, not UTF-16), which put
    /// the last character in a run of its own; the system face then set it
    /// about 1.7pt apart at 14pt, so list titles read `SO P` and `PP T`.
    func addCharacterSpacing(isTitle: Bool = false) {
        guard let string = attributedStringValue.mutableCopy() as? NSMutableAttributedString, string.length > 0 else { return }
        let range = NSRange(location: 0, length: string.length)
        let spacing = (font?.pointSize ?? NSFont.systemFontSize) * UserDefaultsManagement.letterSpacingEm
        string.addAttribute(.kern, value: spacing, range: range)
        string.fixAttributes(in: range)
        attributedStringValue = string
    }
}
