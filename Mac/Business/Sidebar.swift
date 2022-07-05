import Cocoa
typealias Image = NSImage

class Sidebar {
    var list = [Any]()
    let storage = Storage.sharedInstance()
    public var items = [[SidebarItem]]()
    
    init() {
        let night = ""
        var system = [SidebarItem]()
        
        let notes = SidebarItem(name: NSLocalizedString("MiaoYan", comment: ""), type: .All, icon: getImage(named: "home\(night).png"))
        system.append(notes)
        
        if system.count > 0 {
            list = system
        }
        
        let rootProjects = storage.getRootProjects()
              
        if(UserDefaultsManagement.isSingleMode){
            return
        }
        
        for project in rootProjects {
            let icon = getImage(named: "repository\(night).png")
            
            let childProjects = storage.getChildProjects(project: project)
            
            for childProject in childProjects {
                list.append(SidebarItem(name: childProject.label, project: childProject, type: .Category, icon: icon))
            }
        }
        
        if storage.getAllTrash().count > 0 {
            let trashProject = Storage.sharedInstance().getDefaultTrash()
            let trash = SidebarItem(name: NSLocalizedString("Trash", comment: ""), project: trashProject, type: .Trash, icon: getImage(named: "trash\(night)"))
            list.append(trash)
        }
    }
    
    public func getList() -> [Any] {
        return list
    }
    
    public func getProjects() -> [SidebarItem] {
        return list.filter { ($0 as? SidebarItem)?.type == .Category && ($0 as? SidebarItem)?.project != nil && ($0 as? SidebarItem)!.project!.showInSidebar } as! [SidebarItem]
    }
    
    private func getImage(named: String) -> Image? {
        if let image = NSImage(named: named) {
            return image
        }
        
        return nil
    }
}
