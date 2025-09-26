import Cocoa
import Foundation

@MainActor
enum Theme {
    typealias Color = NSColor

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

    static var selectionBackgroundColor: Color {
        NSColor(named: "selectionBackground") ?? .selectedTextBackgroundColor
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
        NSColor(named: "divider") ?? .separatorColor
    }

    static var previewDarkBackgroundColor: Color {
        NSColor(srgbRed: 0x23 / 255.0, green: 0x28 / 255.0, blue: 0x2D / 255.0, alpha: 1.0)
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
