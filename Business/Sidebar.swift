import Cocoa

typealias Image = NSImage

@MainActor
class Sidebar {
    var list = [Any]()
    let storage = Storage.sharedInstance()
    public var items = [[SidebarItem]]()

    init() {
        let night = ""
        var system = [SidebarItem]()

        let appName = getLocalizedAppName()
        system.append(SidebarItem(name: appName, type: .Brand, icon: getImage(named: "home\(night).png")))
        system.append(SidebarItem(name: I18n.str("All Notes"), type: .All, icon: getImage(named: "allNotes")))

        if !system.isEmpty {
            list = system
        }

        let rootProjects = storage.getRootProjects()
        var categoryItems: [SidebarItem] = []

        for project in rootProjects {
            let icon = getImage(named: "repository\(night).png")

            let childProjects = storage.getChildProjects(project: project)

            for childProject in childProjects {
                categoryItems.append(SidebarItem(name: childProject.label, project: childProject, type: .Category, icon: icon))
            }
        }

        if let savedOrder = loadSidebarOrder() {
            categoryItems = applySavedOrder(to: categoryItems, savedOrder: savedOrder)
        }

        list.append(contentsOf: categoryItems)

        if !storage.getAllTrash().isEmpty {
            let trashProject = Storage.sharedInstance().getDefaultTrash()
            let trash = SidebarItem(name: I18n.str("Trash"), project: trashProject, type: .Trash, icon: getImage(named: "trash\(night)"))
            list.append(trash)
        }
    }

    public func getList() -> [Any] { list }

    public func getProjects() -> [SidebarItem] {
        list.compactMap { $0 as? SidebarItem }
            .filter { item in
                guard item.type == .Category, let project = item.project else { return false }
                return project.showInSidebar
            }
    }

    private func getLocalizedAppName() -> String {
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

    private func getImage(named: String) -> Image? {
        if let image = NSImage(named: named) {
            return image
        }

        return nil
    }

    private func loadSidebarOrder() -> [String]? {
        return UserDefaults.standard.object(forKey: "SidebarProjectOrder") as? [String]
    }

    private func applySavedOrder(to items: [SidebarItem], savedOrder: [String]) -> [SidebarItem] {
        var orderedItems: [SidebarItem] = []
        var remainingItems = items

        for projectPath in savedOrder {
            if let index = remainingItems.firstIndex(where: { $0.project?.url.path == projectPath }) {
                orderedItems.append(remainingItems.remove(at: index))
            }
        }

        orderedItems.append(contentsOf: remainingItems)

        return orderedItems
    }
}
