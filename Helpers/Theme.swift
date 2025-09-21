import Cocoa
import Foundation

// All theme colors are read on main thread to avoid cross-actor access to UI state
@MainActor
enum Theme {
    typealias Color = NSColor

    // Primary text color (dynamic in System mode)
    static var textColor: Color {
        if UserDefaultsManagement.appearanceType != .Custom {
            return .labelColor
        } else {
            return UserDefaultsManagement.fontColor
        }
    }

    // Secondary text color for subtitles / timestamps
    static var secondaryTextColor: Color {
        if UserDefaultsManagement.appearanceType != .Custom {
            return .secondaryLabelColor
        } else {
            return UserDefaultsManagement.fontColor.withAlphaComponent(0.6)
        }
    }

    // App background surface color
    static var backgroundColor: Color {
        NSColor(named: "mainBackground") ?? .windowBackgroundColor
    }

    // Unified selection background color used in tables/lists
    static var selectionBackgroundColor: Color {
        NSColor(named: "selectionBackground") ?? .selectedTextBackgroundColor
    }

    // Semantic colors used by syntax highlighting
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
}

// Optional: Use this to get a color "snapshot" from non-main threads
// Usage: let snap = await ThemeSnapshot.make()
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
                underlineColor: Theme.underlineColor
            )
        }
    }
}
