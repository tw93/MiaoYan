import Cocoa
import Foundation

// Centralized theme helpers for macOS colors used across the app
enum Theme {
    typealias Color = NSColor

    // Primary text color (dynamic in System mode)
    static var textColor: Color {
        if UserDefaultsManagement.appearanceType != .Custom {
            return NSColor.labelColor
        } else {
            return UserDefaultsManagement.fontColor
        }
    }

    // Secondary text color for subtitles / timestamps
    static var secondaryTextColor: Color {
        if UserDefaultsManagement.appearanceType != .Custom {
            return NSColor.secondaryLabelColor
        } else {
            return UserDefaultsManagement.fontColor.withAlphaComponent(0.6)
        }
    }

    // App background surface color
    static var backgroundColor: Color {
        NSColor(named: "mainBackground") ?? NSColor.windowBackgroundColor
    }

    // Unified selection background color used in tables/lists
    static var selectionBackgroundColor: Color {
        NSColor(named: "selectionBackground") ?? NSColor.selectedTextBackgroundColor
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
