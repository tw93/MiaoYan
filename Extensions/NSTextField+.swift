import Cocoa

extension NSTextField {
    func addCharacterSpacing(isTitle: Bool = false) {
        if let string = attributedStringValue.mutableCopy() as? NSMutableAttributedString {
            let labelText = stringValue
            let range = NSRange(location: 0, length: labelText.count - 1)
            let spacing = (font?.pointSize ?? NSFont.systemFontSize) * UserDefaultsManagement.letterSpacingEm
            string.addAttribute(.kern, value: spacing, range: range)
            string.fixAttributes(in: range)
            attributedStringValue = string
        }
    }
}
