import Cocoa

class NameTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let status = super.becomeFirstResponder()

        if UserDefaultsManagement.appearanceType != AppearanceType.Custom, #available(OSX 10.13, *) {
            textColor = NSColor(named: "mainText")
        } else {
            textColor = NSColor.black
        }

        return status
    }
}
