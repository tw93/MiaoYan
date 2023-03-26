import AppKit.NSAppearance

extension NSAppearance {
    var isDark: Bool {
        if name == .vibrantDark { return true }

        switch name {
        case .accessibilityHighContrastDarkAqua,
             .accessibilityHighContrastVibrantDark,
             .darkAqua:
            return true
        default:
            return false
        }
    }
}
