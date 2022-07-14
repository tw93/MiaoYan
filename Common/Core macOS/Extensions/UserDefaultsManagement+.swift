import AppKit
import Foundation
import MASShortcut

extension UserDefaultsManagement {
    private enum Constants {
        static let AppearanceTypeKey = "appearanceType"
        static let codeTheme = "codeTheme"
        static let dockIcon = "dockIcon"
        static let NewNoteKeyModifier = "newNoteKeyModifier"
        static let NewNoteKeyCode = "newNoteKeyCode"
        static let SearchNoteKeyCode = "searchNoteKeyCode"
        static let SearchNoteKeyModifier = "searchNoteKeyModifier"
    }

    static var appearanceType: AppearanceType {
        get {
            if let result = UserDefaults.standard.object(forKey: Constants.AppearanceTypeKey) as? Int {
                return AppearanceType(rawValue: result)!
            }

            if #available(OSX 10.14, *) {
                return AppearanceType.System
            } else {
                return AppearanceType.Custom
            }
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Constants.AppearanceTypeKey)
        }
    }

    static var codeTheme: String {
        get {
            if let theme = UserDefaults.standard.object(forKey: Constants.codeTheme) as? String {
                return theme
            }

            if #available(OSX 10.14, *) {
                if NSAppearance.current.isDark {
                    UserDefaults.standard.set("night-owl", forKey: Constants.codeTheme)
                    return "night-owl"
                } else {
                    UserDefaults.standard.set("vs", forKey: Constants.codeTheme)
                    return "vs"
                }
            }

            return "vs"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.codeTheme)
        }
    }

    static var dockIcon: Int {
        get {
            if let tag = UserDefaults.standard.object(forKey: Constants.dockIcon) as? Int {
                return tag
            }

            return 0
        }

        set {
            UserDefaults.standard.set(newValue, forKey: Constants.dockIcon)
        }
    }
}
