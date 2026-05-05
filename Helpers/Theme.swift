import Cocoa
import Foundation

@MainActor
enum Theme {
    typealias Color = NSColor
    private static let noTintProminenceRawValue = 1

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

        return Color(name: nil) { appearance in
            if appearance.isDark {
                return backgroundColor
            }
            return Color(srgbRed: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)
        }
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
                return Color(srgbRed: 0x42 / 255.0, green: 0x4A / 255.0, blue: 0x54 / 255.0, alpha: 1.0)
            }

            return Color(srgbRed: 0xCC / 255.0, green: 0xCC / 255.0, blue: 0xCC / 255.0, alpha: 0.96)
        }
    }

    static var sidebarSelectionStrokeColor: Color {
        guard usesModernSystemChrome else {
            return .clear
        }

        return Color(name: nil) { appearance in
            if appearance.isDark {
                return Color.white.withAlphaComponent(0.14)
            }

            return Color.separatorColor.withAlphaComponent(0.22)
        }
    }

    static var settingsWindowBackgroundColor: Color {
        if UserDefaultsManagement.appearanceType == .Custom {
            return UserDefaultsManagement.bgColor
        }

        return usesModernSystemChrome ? .windowBackgroundColor : backgroundColor
    }

    static var settingsContentBackgroundColor: Color {
        if UserDefaultsManagement.appearanceType == .Custom {
            return UserDefaultsManagement.bgColor
        }

        return backgroundColor
    }

    static var settingsSidebarBackgroundColor: Color {
        if UserDefaultsManagement.appearanceType == .Custom {
            return UserDefaultsManagement.bgColor
        }

        return usesModernSystemChrome ? .clear : backgroundColor
    }

    static var settingsDividerColor: Color {
        if usesModernSystemChrome {
            return .separatorColor.withAlphaComponent(0.10)
        }

        return dividerColor
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

    static var panelHairlineColor: Color {
        if usesModernSystemChrome {
            return .separatorColor.withAlphaComponent(0.12)
        }

        return dividerColor
    }

    static var noteSeparatorColor: Color {
        if usesModernSystemChrome {
            return .separatorColor.withAlphaComponent(0.07)
        }

        return dividerColor
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

        if usesModernSystemChrome {
            return .secondaryLabelColor
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
        if usesModernSystemChrome {
            return noteSeparatorColor
        }

        return dividerColor
    }

    static var previewDarkBackgroundColor: Color {
        NSColor(srgbRed: 0x23 / 255.0, green: 0x28 / 255.0, blue: 0x2D / 255.0, alpha: 1.0)
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

    static func present(
        _ alert: NSAlert,
        for window: NSWindow?,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
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
