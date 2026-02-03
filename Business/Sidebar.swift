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
        let notes = SidebarItem(name: appName, type: .All, icon: getImage(named: "home\(night).png"))
        system.append(notes)

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
        list.filter { ($0 as? SidebarItem)?.type == .Category && ($0 as? SidebarItem)?.project != nil && ($0 as? SidebarItem)!.project!.showInSidebar } as! [SidebarItem]
    }

    private func getLocalizedAppName() -> String {
        let language = UserDefaultsManagement.defaultLanguage
        switch language {
        case 1:  // English
            return "MiaoYan"
        default:  // Chinese, Japanese, etc.
            return "妙言"
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
