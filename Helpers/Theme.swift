import Cocoa
import Foundation

@MainActor
enum Theme {
    typealias Color = NSColor
    private static let noTintProminenceRawValue = 1

    /// The two animation lengths, both eased out: feedback on the control
    /// under the pointer, and a change to what the window shows (panels,
    /// disclosure, collapse, a window appearing).
    enum Motion {
        static let feedback: TimeInterval = 0.12
        static let change: TimeInterval = 0.25
        /// Shorter on purpose: switching notes in preview waits for this
        /// fade-out before loading, so it is a load gate more than an effect.
        static let previewFade: TimeInterval = 0.08
        static var curve: CAMediaTimingFunction { CAMediaTimingFunction(name: .easeOut) }
    }

    /// The sidebar wordmark, as miaoyan.app sets the name: upright Charter for
    /// MiaoYan, and Source Han Serif SC for 妙言 (maintainer, 2026-10-26).
    /// Charter has no Han, so 妙言 used to fall back to whatever serif the
    /// system picked. `MiaoYanMark.otf` is a two-glyph cut of Source Han Serif
    /// SC, renamed as the OFL asks of a modified copy, loaded without
    /// registering so it never shows up in the font menus.
    static func brandWordmarkFont(for title: String, size: CGFloat) -> NSFont? {
        if title.unicodeScalars.contains(where: { !$0.isASCII }), let mark = brandMarkDescriptor {
            return CTFontCreateWithFontDescriptor(mark, size, nil) as NSFont
        }
        return NSFont(name: "Charter-Roman", size: size)
    }

    private static let brandMarkDescriptor: CTFontDescriptor? = {
        guard let url = Bundle.main.url(forResource: "MiaoYanMark", withExtension: "otf"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return CTFontManagerCreateFontDescriptorFromData(data as CFData)
    }()

    /// Shared layout metrics for the list / sidebar surfaces. Seeded with the
    /// values we actively tune so future tweaks have one home instead of
    /// scattered literals. Editor and preferences internals keep their own
    /// constants for now (different subsystems, different values).
    enum Metrics {
        /// Corner radius for the rounded selection pill (sidebar rows).
        static let selectionCornerRadius: CGFloat = 8
        /// Horizontal inset of the selection pill from the row edge.
        static let selectionInsetH: CGFloat = 6
        /// Vertical inset of the selection pill from the row edge.
        static let selectionInsetV: CGFloat = 3
        /// Split widths below this are treated as collapsed.
        static let collapsedSplitWidthEpsilon: CGFloat = 1
        /// Project sidebar snap point when dragging toward the closed state.
        static let sidebarCollapseSnapWidth: CGFloat = 86
        /// Smallest useful note-list width. Below this the list shows clipped
        /// dates and titles instead of a usable column.
        static let noteListMinimumWidth: CGFloat = 220
        /// Note-list snap point when dragging toward the closed state.
        static let noteListCollapseSnapWidth: CGFloat = 180
        /// Standard sidebar rows keep icon and label on the same Auto Layout
        /// center. Text drawing is nudged separately to account for CJK ink.
        static let sidebarStandardIconOffsetY: CGFloat = 0
        static let sidebarLabelOffsetY: CGFloat = 0
        static let sidebarStandardLabelVerticalNudge: CGFloat = 1.5
        static let sidebarBrandLabelVerticalNudge: CGFloat = 1.5
        static let sidebarBrandIconOffsetY: CGFloat = -3.5
        /// 妙言 in Source Han Serif sits higher in its line than Charter's
        /// MiaoYan, so the Chinese lockup has its own pair: the bird level with
        /// the folder rows' rhythm and the wordmark's ink centre a point below
        /// the bird's (maintainer, 2026-10-26).
        static let sidebarBrandMarkLabelVerticalNudge: CGFloat = 5
        static let sidebarBrandMarkIconOffsetY: CGFloat = -0.5
        /// Right-side gutter so long note titles truncate before the pane edge.
        /// The visible gutter inside the selection pill varies by title because
        /// truncation snaps to whole glyphs (CJK chars are ~14pt), so this is
        /// tuned to center that spread near the ~12pt left padding rather than
        /// to a single exact value.
        static let noteListContentInset: CGFloat = 30
    }

    static var textColor: Color {
        if UserDefaultsManagement.appearanceType != .Custom {
            return .labelColor
        } else {
            return UserDefaultsManagement.fontColor
        }
    }

    static var secondaryTextColor: Color {
        if UserDefaultsManagement.appearanceType != .Custom {
            return .secondaryLabelColor
        } else {
            return UserDefaultsManagement.fontColor.withAlphaComponent(0.6)
        }
    }

    static var backgroundColor: Color {
        NSColor(named: "mainBackground") ?? .windowBackgroundColor
    }

    static var usesModernSystemChrome: Bool {
        guard UserDefaultsManagement.appearanceType != .Custom else { return false }
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    static var windowChromeBackgroundColor: Color {
        if UserDefaultsManagement.appearanceType == .Custom {
            return UserDefaultsManagement.bgColor
        }

        return usesModernSystemChrome ? .windowBackgroundColor : backgroundColor
    }

    static var paneBackgroundColor: Color {
        if UserDefaultsManagement.appearanceType == .Custom {
            return UserDefaultsManagement.bgColor
        }

        return backgroundColor
    }

    static var editorSurfaceBackgroundColor: Color {
        if UserDefaultsManagement.appearanceType == .Custom {
            return UserDefaultsManagement.bgColor
        }

        return backgroundColor
    }

    static var selectionBackgroundColor: Color {
        return NSColor(named: "selectionBackground") ?? .selectedTextBackgroundColor
    }

    static var sidebarSelectionBackgroundColor: Color {
        guard usesModernSystemChrome else {
            return selectionBackgroundColor
        }

        return Color(name: nil) { appearance in
            if appearance.isDark {
                return Color(srgbRed: 0x30 / 255.0, green: 0x2F / 255.0, blue: 0x2D / 255.0, alpha: 1.0)
            }

            return Color(srgbRed: 0xE8 / 255.0, green: 0xE6 / 255.0, blue: 0xDC / 255.0, alpha: 1.0)
        }
    }

    static var sidebarSelectionStrokeColor: Color {
        return .clear
    }

    /// The faint outline of controls that sit on the page (the search
    /// field, toasts). Lines that divide the window use `columnHairline`.
    static var hairlineColor: Color {
        .separatorColor.withAlphaComponent(0.10)
    }

    /// The one line that divides the window, in both windows: between
    /// columns, between the editor and preview in split mode, and across
    /// panels such as version history. Warm ink at 7% on the paper tone,
    /// white at 7% in dark (maintainer, 2026-09-28). The system separator grey
    /// it replaced read cool on paper and too bright in dark, and the note
    /// list no longer draws lines between rows (2026-10-19).
    nonisolated static let columnHairline = dynamic(0x1F1E1C, 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.07)

    /// Fills a divider: the paper first, then the hairline over it, so its
    /// alpha reads the same over any backing. A clear colour (a hidden
    /// divider) draws nothing.
    static func fillDivider(_ rect: NSRect, color: NSColor, appearance: NSAppearance?) {
        let line = color.resolvedColor(for: appearance)
        guard line.alphaComponent > 0 else { return }
        if line.alphaComponent < 1 {
            backgroundColor.resolvedColor(for: appearance).setFill()
            rect.fill()
        }
        line.setFill()
        rect.fill(using: .sourceOver)
    }

    /// The one shadow, for layers that float over the page (the find bar,
    /// and the preview's TOC panel in `tocbot.css`), heavier on a dark
    /// surface where a light one would not read.
    enum FloatingShadow {
        static func apply(to layer: CALayer?, onDarkSurface dark: Bool) {
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = dark ? 0.3 : 0.1
            layer?.shadowRadius = dark ? 8 : 6
            layer?.shadowOffset = NSSize(width: 0, height: dark ? -2 : -1.5)
        }
    }

    /// Kami's warm text greys, read by the shell and the Settings window
    /// alike: primary to read, secondary for supporting text, tertiary for
    /// meta and icons. Primary is the product sites' 长石灰 `#363433`;
    /// `#141413` read too black on the paper.
    enum Ink {
        static let primary = dynamic(0x363433, 0xF2F0EA)
        static let secondary = dynamic(0x504E49, 0xB5B1A7)
        static let tertiary = dynamic(0x6B6A64, 0x8E8B83)
    }

    /// The warm paper every column and window sits on.
    nonisolated static let paper = dynamic(0xFDFCF9, 0x1E1D1B)
    /// MiaoYan green, lifted in dark mode.
    nonisolated static let brand = dynamic(0x1C5D33, 0x54C59F)
    /// Kami's warm sand, the selection plate.
    nonisolated static let sand = dynamic(0xE8E6DC, 0xFFFFFF, darkAlpha: 0.08)

    /// The Settings window's colours: the shell's warm paper, Kami's warm
    /// greys and sand, and MiaoYan green for switches and actions. Opaque on
    /// purpose; a translucent settings surface reads like the rejected glass
    /// sidebar.
    @MainActor
    enum Settings {
        static let background = paper
        static let primaryText = Ink.primary
        static let secondaryText = Ink.secondary
        static let tertiaryText = Ink.tertiary
        static let tabSelection = sand
        static let controlFill = dynamic(0x141413, 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.07)
        static let controlHoverFill = dynamic(0x141413, 0xFFFFFF, lightAlpha: 0.09, darkAlpha: 0.10)
        static let switchOffFill = dynamic(0x141413, 0xFFFFFF, lightAlpha: 0.14, darkAlpha: 0.16)
        /// Between sections, and the fainter one between rows of a section.
        static let sectionHairline = dynamic(0x141413, 0xF2F0EA, lightAlpha: 0.12, darkAlpha: 0.12)
        static let rowHairline = dynamic(0x141413, 0xF2F0EA, lightAlpha: 0.065, darkAlpha: 0.065)
        static let accent = brand
    }

    static var panelBackgroundColor: Color {
        if UserDefaultsManagement.appearanceType == .Custom {
            return UserDefaultsManagement.bgColor
        }

        return backgroundColor
    }

    static var panelSecondaryBackgroundColor: Color {
        if UserDefaultsManagement.appearanceType == .Custom {
            return UserDefaultsManagement.bgColor
        }

        return Color(name: nil) { appearance in
            if appearance.isDark {
                return Color.white.withAlphaComponent(0.045)
            }

            return Color.black.withAlphaComponent(0.035)
        }
    }

    /// A Custom appearance paints its own background, so its lines keep the
    /// opaque `divider` colour instead of the paper-tuned hairline.
    static var panelHairlineColor: Color {
        UserDefaultsManagement.appearanceType == .Custom ? dividerColor : columnHairline
    }

    /// A colour that follows light and dark from two hex values, shared with
    /// `ShellPalette`.
    nonisolated static func dynamic(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return Color(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        }
    }

    /// The editor's body text and its quiet markup colour, Kaku's text and
    /// muted values (kaku/src/kaku_theme.rs). The highlight roles in the asset
    /// catalogue (`title`, `link`, `html`, `list`, `highlight`) carry Kaku's
    /// purple, teal and gold for the same reason: one palette across Kaku,
    /// Mole and MiaoYan. A custom theme keeps its own text colour.
    static var editorTextColor: Color {
        UserDefaultsManagement.appearanceType == .Custom ? textColor : dynamic(0x403E3C, 0xD5D4D6)
    }

    static var editorMarkupColor: Color {
        UserDefaultsManagement.appearanceType == .Custom ? textColor : dynamic(0x7A7872, 0x8E8B83)
    }

    /// Code in the editor, inline code, HTML tags and code-block text alike,
    /// takes the bold gold lightened, with keywords in Kaku's purple. Both are mixed toward the
    /// paper, 30% in light and 15% in dark (maintainer's pick, 2026-10-25):
    /// at full strength a whole block read loud beside the prose.
    static var editorCodeColor: Color {
        UserDefaultsManagement.appearanceType == .Custom ? textColor : dynamic(0xB89D4B, 0xBE9868)
    }

    static var editorCodeKeywordColor: Color {
        dynamic(0x8E76C8, 0x7D5EBC)
    }

    static var titleColor: Color {
        NSColor(named: "title") ?? textColor
    }
    static var linkColor: Color {
        NSColor(named: "link") ?? textColor
    }
    static var listColor: Color {
        NSColor(named: "list") ?? textColor
    }
    static var htmlColor: Color {
        NSColor(named: "html") ?? textColor
    }
    static var underlineColor: Color {
        NSColor(named: "underlineColor") ?? .black
    }
    static var highlightColor: Color {
        NSColor(named: "highlight") ?? .systemBlue
    }

    static var accentColor: Color {
        NSColor(named: "accentColor") ?? .controlAccentColor
    }

    static var inactiveIconColor: Color {
        if usesModernSystemChrome {
            return .secondaryLabelColor
        }

        return NSColor(calibratedWhite: 0.53, alpha: 1.0)
    }

    static var sidebarActionColor: Color {
        if UserDefaultsManagement.appearanceType == .Custom {
            return UserDefaultsManagement.fontColor
        }

        return NSColor(named: "toolbarIcon") ?? .labelColor
    }

    static var selectionTextColor: Color {
        .selectedMenuItemTextColor
    }

    static var toastBackgroundColor: Color {
        NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.95)
    }

    static var toastTextColor: Color {
        .white
    }

    static var dividerColor: Color {
        if usesModernSystemChrome {
            return .separatorColor.withAlphaComponent(0.18)
        }

        return NSColor(named: "divider") ?? .separatorColor
    }

    static var splitDividerColor: Color {
        panelHairlineColor
    }

    static var previewDarkBackgroundColor: Color {
        NSColor(srgbRed: 0x1E / 255.0, green: 0x1D / 255.0, blue: 0x1B / 255.0, alpha: 1.0)
    }

    static func configureChromeIconButton(_ button: NSButton?) {
        guard let button else { return }

        button.imagePosition = .imageOnly
        button.image?.isTemplate = true

        guard usesModernSystemChrome else {
            button.isBordered = false
            button.bezelStyle = .texturedRounded
            return
        }

        if #available(macOS 26.0, *) {
            button.isBordered = false
            button.bezelStyle = .texturedRounded
            button.controlSize = .small
            button.showsBorderOnlyWhileMouseInside = false
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.clear.cgColor
            setAppKitValue(noTintProminenceRawValue, forKey: "tintProminence", setter: "setTintProminence:", on: button)
            configureModernControlMetrics(button)
        }
    }

    static func configureModernControlMetrics(_ view: NSView?) {
        guard usesModernSystemChrome, let view else { return }
        if #available(macOS 26.0, *) {
            setAppKitValue(true, forKey: "prefersCompactControlSizeMetrics", setter: "setPrefersCompactControlSizeMetrics:", on: view)
        }
    }

    private static func setAppKitValue(_ value: Any, forKey key: String, setter: String, on object: NSObject) {
        guard object.responds(to: NSSelectorFromString(setter)) else { return }
        object.setValue(value, forKey: key)
    }
}

@MainActor
extension NSView {
    func applyMiaoYanPaneBackground() {
        wantsLayer = true
        let color = Theme.paneBackgroundColor.resolvedColor(for: effectiveAppearance)
        layer?.backgroundColor = color.cgColor
    }

    func fillMiaoYanPaneBackground(_ dirtyRect: NSRect) {
        Theme.paneBackgroundColor.resolvedColor(for: effectiveAppearance).setFill()
        dirtyRect.fill()
    }
}

@MainActor
enum MiaoYanAlert {
    static func make(
        message: String,
        informativeText: String? = nil,
        style: NSAlert.Style = .informational,
        buttons: [String]
    ) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informativeText ?? ""
        alert.alertStyle = style
        // The bird alone on the paper, without the app icon's tile and shadow.
        if let bird = NSImage(named: "alertIcon") {
            alert.icon = bird
        }

        for title in buttons {
            alert.addButton(withTitle: title)
        }

        if let primaryButton = alert.buttons.first {
            primaryButton.keyEquivalent = "\r"
        }
        if alert.buttons.count > 1, let cancelButton = alert.buttons.last {
            cancelButton.keyEquivalent = "\u{1b}"
        }

        return alert
    }

    /// Puts the alert on the app's paper: the title in the shell's primary
    /// ink instead of label black, and, on macOS 26, the paper over the
    /// grey glass the alert sits on. Views are found by their text and type,
    /// so if AppKit lays the alert out differently this simply does nothing.
    static func style(_ alert: NSAlert) {
        alert.layout()
        guard let content = alert.window.contentView else { return }
        var stack = [content]
        while let view = stack.popLast() {
            if let field = view as? NSTextField, field.stringValue == alert.messageText {
                // The title carries its own colour in its attributed string,
                // which wins over `textColor`.
                let title = NSMutableAttributedString(attributedString: field.attributedStringValue)
                title.addAttribute(.foregroundColor, value: Theme.Ink.primary, range: NSRange(location: 0, length: title.length))
                field.attributedStringValue = title
                field.textColor = Theme.Ink.primary
                break
            }
            stack.append(contentsOf: view.subviews)
        }
        // The glass is a sibling under the content; matching its corner keeps
        // the system's shape and shadow while the paper covers the grey.
        let cornerKey = "cornerRadius"
        guard
            let glass = content.superview?.subviews.first(where: { String(describing: type(of: $0)).contains("Glass") }),
            // KVC on a key the view lacks raises; a future glass class may not have it.
            glass.responds(to: NSSelectorFromString(cornerKey)),
            let radius = glass.value(forKey: cornerKey) as? CGFloat
        else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.paper.resolvedColor(for: alert.window.effectiveAppearance).cgColor
        content.layer?.cornerRadius = radius
        content.layer?.cornerCurve = .continuous
    }

    static func present(
        _ alert: NSAlert,
        for window: NSWindow?,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        style(alert)
        if let window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    static func show(
        message: String,
        informativeText: String? = nil,
        style: NSAlert.Style = .informational,
        buttonTitle: String = I18n.str("OK"),
        for window: NSWindow? = NSApp.keyWindow ?? NSApp.mainWindow,
        completion: ((NSApplication.ModalResponse) -> Void)? = nil
    ) {
        let alert = make(
            message: message,
            informativeText: informativeText,
            style: style,
            buttons: [buttonTitle]
        )
        present(alert, for: window) { response in
            completion?(response)
        }
    }

    static func confirm(
        message: String,
        informativeText: String? = nil,
        confirmTitle: String,
        cancelTitle: String = I18n.str("Cancel"),
        style: NSAlert.Style = .warning,
        for window: NSWindow?,
        completion: @escaping (Bool) -> Void
    ) {
        let alert = make(
            message: message,
            informativeText: informativeText,
            style: style,
            buttons: [confirmTitle, cancelTitle]
        )
        present(alert, for: window) { response in
            completion(response == .alertFirstButtonReturn)
        }
    }
}

extension NSColor {
    func resolvedColor(for appearance: NSAppearance?) -> NSColor {
        guard let appearance else { return self }

        var resolved = self
        appearance.performAsCurrentDrawingAppearance {
            resolved = self.usingColorSpace(.deviceRGB) ?? self
        }
        return resolved
    }
}

struct ThemeSnapshot {
    let textColor: NSColor
    let secondaryTextColor: NSColor
    let backgroundColor: NSColor
    let selectionBackgroundColor: NSColor
    let titleColor: NSColor
    let linkColor: NSColor
    let listColor: NSColor
    let htmlColor: NSColor
    let underlineColor: NSColor
    let highlightColor: NSColor
    let accentColor: NSColor
    let selectionTextColor: NSColor
    let toastBackgroundColor: NSColor
    let toastTextColor: NSColor
    let dividerColor: NSColor
    let previewDarkBackgroundColor: NSColor

    static func make() async -> ThemeSnapshot {
        await MainActor.run {
            ThemeSnapshot(
                textColor: Theme.textColor,
                secondaryTextColor: Theme.secondaryTextColor,
                backgroundColor: Theme.backgroundColor,
                selectionBackgroundColor: Theme.selectionBackgroundColor,
                titleColor: Theme.titleColor,
                linkColor: Theme.linkColor,
                listColor: Theme.listColor,
                htmlColor: Theme.htmlColor,
                underlineColor: Theme.underlineColor,
                highlightColor: Theme.highlightColor,
                accentColor: Theme.accentColor,
                selectionTextColor: Theme.selectionTextColor,
                toastBackgroundColor: Theme.toastBackgroundColor,
                toastTextColor: Theme.toastTextColor,
                dividerColor: Theme.dividerColor,
                previewDarkBackgroundColor: Theme.previewDarkBackgroundColor
            )
        }
    }
}
