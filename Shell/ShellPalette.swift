import AppKit

/// The shell's colours as one set of named roles. One warm paper tone runs
/// through every column; text steps down through Kami's four solid warm
/// greys; selection is Kami's warm sand; MiaoYan green is the one accent. The
/// editor and preview backgrounds (`mainBackground`, the DownView themes)
/// carry the same tone.
@available(macOS 14, *)
enum ShellPalette {
    static let background = Theme.paper
    static let text = Theme.Ink.primary
    static let secondaryText = Theme.Ink.secondary
    static let tertiaryText = Theme.Ink.tertiary
    static let icon = tertiaryText
    static let accent = Theme.brand
    static let sidebarSelection = Theme.sand
    static let listSelection = pair(0xEFEDE4, 0xFFFFFF, darkAlpha: 0.07)
    /// The only line, between columns.
    static let hairline = Theme.columnHairline
    static let field = pair(0x1F1E1C, 0xFFFFFF, lightAlpha: 0.045, darkAlpha: 0.06)

    private static func pair(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
        Theme.dynamic(light, dark, lightAlpha: lightAlpha, darkAlpha: darkAlpha)
    }
}
