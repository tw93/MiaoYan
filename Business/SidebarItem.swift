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

    public func isSelectable() -> Bool { true }

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
        switch language {
        case 1:  // English
            return "MiaoYan"
        default:  // Chinese, Japanese, etc.
            return "妙言"
        }
    }

    public func isSame(as other: SidebarItem) -> Bool {
        if type != other.type { return false }
        if type == .Category || type == .Trash {
            return project?.url == other.project?.url
        }
        if type == .All {
            return true
        }
        return name == other.name
    }
}

extension SidebarItem: @unchecked Sendable {}
