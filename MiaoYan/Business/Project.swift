//
//  Project.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 4/7/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

public class Project: Equatable {
    var url: URL
    public var label: String
    var isTrash: Bool
    var isCloudDrive: Bool = false
    var isRoot: Bool
    var parent: Project?
    var isDefault: Bool
    var isArchive: Bool
    public var isExternal: Bool = false

    public var sortBy: SortBy = UserDefaultsManagement.sort
    public var sortDirection: SortDirection = UserDefaultsManagement.sortDirection ? .desc : .asc

    public var sortBySettings: SortBy = .none
    public var sortDirectionSettings: SortDirection = .desc

    public var showInCommon: Bool
    public var showInSidebar: Bool = true

    #if os(iOS)
    public var firstLineAsTitle: Bool = true
    #else
    public var firstLineAsTitle: Bool = false
    #endif
    
    init(url: URL, label: String? = nil, isTrash: Bool = false, isRoot: Bool = false, parent: Project? = nil, isDefault: Bool = false, isArchive: Bool = false, isExternal: Bool = false) {
        self.url = url.resolvingSymlinksInPath()
        self.isTrash = isTrash
        self.isRoot = isRoot
        self.parent = parent
        self.isDefault = isDefault
        self.isArchive = isArchive
        self.isExternal = isExternal

        showInCommon = (isTrash || isArchive) ? false : true

        #if os(iOS)
        if isRoot && isDefault {
            showInSidebar = false
        }
        #endif

        if let l = label {
            self.label = l
        } else {
            self.label = url.lastPathComponent
        }

        var localizedName: AnyObject?
        try? (url as NSURL).getResourceValue(&localizedName, forKey: URLResourceKey.localizedNameKey)
        if let name = localizedName as? String, name.count > 0 {
            self.label = name
        }
        
        isCloudDrive = isCloudDriveFolder(url: url)
        loadSettings()
    }
    
    func fileExist(fileName: String, ext: String) -> Bool {        
        let fileURL = url.appendingPathComponent(fileName + "." + ext)
        
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    public static func == (lhs: Project, rhs: Project) -> Bool {
        return lhs.url == rhs.url
    }
    
    private func isCloudDriveFolder(url: URL) -> Bool {
        if let iCloudDocumentsURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents").resolvingSymlinksInPath() {
            
            if FileManager.default.fileExists(atPath: iCloudDocumentsURL.path, isDirectory: nil), url.path.contains(iCloudDocumentsURL.path) {
                return true
            }
        }
        
        return false
    }
    
    public func getParent() -> Project {
        if isRoot {
            return self
        }
        
        if let parent = self.parent {
            return parent.getParent()
        }
        
        return self
    }
    
    public func getFullLabel() -> String {
        if isRoot  {
            if isExternal {
                return "External › " + label
            }
            
            return label
        }

        if isTrash {
            return "Trash"
        }

        if isArchive {
            return label
        }
        
        return "\(getParent().getFullLabel()) › \(label)"
    }

    public func saveSettings() {
        let data = [
            "sortBy": sortBySettings.rawValue,
            "sortDirection": sortDirectionSettings.rawValue,
            "showInCommon": showInCommon,
            "showInSidebar": showInSidebar,
            "firstLineAsTitle": firstLineAsTitle
        ] as [String : Any]

        if let relativePath = getRelativePath() {
            let keyStore = NSUbiquitousKeyValueStore()
            let key = relativePath.count == 0 ? "root-directory" : relativePath

            keyStore.set(data, forKey: key)
            keyStore.synchronize()
            return
        }

        UserDefaults.standard.set(data, forKey: url.path)
    }

    public func loadSettings() {
        if let relativePath = getRelativePath() {
            let keyStore = NSUbiquitousKeyValueStore()
            let key = relativePath.count == 0 ? "root-directory" : relativePath

            if let settings = keyStore.dictionary(forKey: key) {
                if let common = settings["showInCommon"] as? Bool {
                    self.showInCommon = common
                }

                if let sidebar = settings["showInSidebar"] as? Bool {
                    self.showInSidebar = sidebar
                }

                if let sortString = settings["sortBy"] as? String, let sort = SortBy(rawValue: sortString) {
                    if sort != .none {
                        sortBy = sort
                        sortBySettings = sort

                        if let directionString = settings["sortDirection"] as? String, let direction = SortDirection(rawValue: directionString) {
                            sortDirection = direction
                            sortDirectionSettings = direction
                        }
                    }
                }

                if let firstLineAsTitle = settings["firstLineAsTitle"] as? Bool {
                    self.firstLineAsTitle = firstLineAsTitle
                } else {
                    self.firstLineAsTitle = UserDefaultsManagement.firstLineAsTitle
                }
            }
            return
        }

        if let settings = UserDefaults.standard.object(forKey: url.path) as? NSObject {
            if let common = settings.value(forKey: "showInCommon") as? Bool {
                self.showInCommon = common
            }

            if let sidebar = settings.value(forKey: "showInSidebar") as? Bool {
                self.showInSidebar = sidebar
            }

            if let sortString = settings.value(forKey: "sortBy") as? String, let sort = SortBy(rawValue: sortString) {
                if sort != .none {
                    sortBy = sort
                    sortBySettings = sort

                    if let directionString = settings.value(forKey: "sortDirection") as? String, let direction = SortDirection(rawValue: directionString) {
                        sortDirection = direction
                        sortDirectionSettings = direction
                    }
                }
            }

            if isRoot {
                self.firstLineAsTitle = UserDefaultsManagement.firstLineAsTitle
            } else if let firstLineAsTitle = settings.value(forKey: "firstLineAsTitle") as? Bool {
                self.firstLineAsTitle = firstLineAsTitle
            } else {
                self.firstLineAsTitle = UserDefaultsManagement.firstLineAsTitle
            }

            return
        }

        self.firstLineAsTitle = UserDefaultsManagement.firstLineAsTitle

        if label == "Welcome" {
            sortBy = .title
            sortDirection = .asc
        }
    }

    public func getRelativePath() -> String? {
        if let iCloudRoot =  FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents").resolvingSymlinksInPath() {
            return url.path.replacingOccurrences(of: iCloudRoot.path, with: "")
        }

        return nil
    }

    public func getGitPath() -> String? {
        if isArchive || parent == nil {
            return nil
        }

        let parentURL = getParent().url
        let relative = url.path.replacingOccurrences(of: parentURL.path, with: "")
        
        if relative.first == "/" {
            return String(relative.dropFirst())
        }

        if relative == "" {
            return nil
        }

        return relative
    }

    public func createDirectory() {
        do {
            try FileManager.default.createDirectory(at: url.appendingPathComponent("i"), withIntermediateDirectories: true, attributes: nil)
        } catch {
            print(error)
        }
    }

    public func remove() {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print(error)
        }
    }

    public func create() {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print(error)
        }
    }

    public func getShortSign() -> String {
        return String(getParent().url.path.md5.prefix(4))
    }

    public func getAllTags() -> [String] {
        let notes = Storage.sharedInstance().noteList.filter({ $0.project == self })

        var tags = [String]()
        for note in notes {
            for tag in note.tags {
                if !tags.contains(tag) {
                    tags.append(tag)
                }
            }
        }

        return tags
    }
}
