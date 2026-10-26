import Cocoa

class SidebarItem {
    var name: String
    var project: Project?
    var type: SidebarItemType
    public var icon: Image?
    public var children: [SidebarItem]?

    init(name: String, project: Project? = nil, type: SidebarItemType, icon: Image? = nil) {
        self.name = name
        self.project = project
        self.type = type
        self.icon = icon
    }

    public func getName() -> String { name }

    public func isSelectable() -> Bool { type != .Brand }

    public func isTrash() -> Bool { type == .Trash }

    @MainActor public func isGroupItem() -> Bool {
        let notesLabel = getLocalizedAppName()
        let trashLabel = I18n.str("Trash")
        if project == nil, [notesLabel, trashLabel].contains(name) {
            return true
        }
        return false
    }

    @MainActor private func getLocalizedAppName() -> String {
        let language = UserDefaultsManagement.defaultLanguage
        // Chinese reads the Chinese name; every other language takes the
        // Latin one, as miaoyan.app's header does (maintainer, 2026-10-26).
        switch language {
        case 0, 3:  // Simplified and Traditional Chinese
            return "妙言"
        default:
            return "MiaoYan"
        }
    }

    public func isSame(as other: SidebarItem) -> Bool {
        if type != other.type { return false }
        if type == .Category || type == .Trash {
            return project?.url == other.project?.url
        }
        if type == .All || type == .Brand {
            return true
        }
        return name == other.name
    }
}

extension SidebarItem: @unchecked Sendable {}
