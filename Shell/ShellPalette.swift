import AppKit

/// The shell's colours as one set of named roles. One warm paper tone runs
/// through every column; text steps down through Kami's four solid warm
/// greys; selection is Kami's warm sand; MiaoYan green is the one accent. The
/// editor and preview backgrounds (`mainBackground`, the DownView themes)
/// carry the same tone.
@available(macOS 14, *)
enum ShellPalette {
    static let background = pair(0xFDFCF9, 0x1E1D1B)
    static let text = pair(0x141413, 0xF2F0EA)
    static let secondaryText = pair(0x504E49, 0xB5B1A7)
    static let tertiaryText = pair(0x6B6A64, 0x8E8B83)
    static let icon = tertiaryText
    static let accent = pair(0x1C5D33, 0x54C59F)
    static let sidebarSelection = pair(0xE8E6DC, 0xFFFFFF, darkAlpha: 0.08)
    static let listSelection = pair(0xEFEDE4, 0xFFFFFF, darkAlpha: 0.07)
    /// The only line, between columns.
    static let hairline = Theme.columnHairline
    static let field = pair(0x1F1E1C, 0xFFFFFF, lightAlpha: 0.045, darkAlpha: 0.06)

    private static func pair(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
        Theme.dynamic(light, dark, lightAlpha: lightAlpha, darkAlpha: darkAlpha)
    }
}
