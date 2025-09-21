import Cocoa

class NameTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let status = super.becomeFirstResponder()

        // Use centralized theme color with proper fallbacks
        textColor = Theme.textColor

        return status
    }
}
