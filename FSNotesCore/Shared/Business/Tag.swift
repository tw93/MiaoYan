//
//  Tag.swift
//  FSNotes
//
//  Created by Олександр Глущенко on 14.10.2019.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

class Tag {
    private var name: String
    private var child = [Tag]()
    private var parent: Tag?

    init(name: String, parent: Tag? = nil) {
        self.name = name
        self.parent = parent

        let tags = name.components(separatedBy: "/")
        if tags.count > 1, let parent = tags.first {
            addChild(name: tags.dropFirst().joined(separator: "/"), completion: {(_, _) in })
            self.name = parent
            return
        }
    }

    public func appendChild(tag: Tag) {
        child.append(tag)
    }

    public func isExpandable() -> Bool {
        return child.count > 0
    }

    public func addChild(name: String, completion: (_ tag: Tag, _ isExist: Bool) -> Void) {
        let tags = name.components(separatedBy: "/")

        if tags.count > 1, let parent = tags.first {
            if let tag = child.first(where: { $0.name == parent }) {
                completion(tag, true)
            } else {
                let tagObject = Tag(name: name, parent: self)
                appendChild(tag: tagObject)
                completion(tagObject, false)
            }
            return
        }

        if let first = child.first(where: { $0.name == name }) {
            completion(first, true)
            return
        }

        let tag = Tag(name: name, parent: self)
        child.append(tag)
        completion(tag, false)
    }

    public func indexOf(child tag: Tag) -> Int? {
        return child.firstIndex(where: { $0 === tag })
    }

    public func remove(by index: Int) {
        child.remove(at: index)
    }

    public func removeChild(tag: Tag) {
        child.removeAll(where: { $0 === tag })
    }

    public func getChild() -> [Tag] {
        return child
    }

    public func removeParent() {
        parent = nil
    }

    public func get(name: String) -> Tag? {
        var name = name
        let tags = name.components(separatedBy: "/")

        if tags.count > 1, let parent = tags.first {
            name = parent
        }

        return child.first(where: { $0.name == name })

    }

    public func getName() -> String {
        return name
    }

    public func getFullName() -> String {
        if let parentTag = parent?.getFullName(), parentTag != "" {
            return "\(parentTag)/\(name)"
        }

        if name == "# \(NSLocalizedString("Tags", comment: "Sidebar label")))" {
            return String()
        }

        return "\(name)"
    }

    public func find(name: String) -> Tag? {
        let tags = name.components(separatedBy: "/")
        let trimmed = tags.dropFirst().joined(separator: "/")

        if let child = get(name: trimmed) {
            if child.name == trimmed {
                return child
            }

            return child.find(name: trimmed)
        }

        return nil
    }

    public func isAlone() -> Bool {
        guard let parent = parent else { return false }

        if parent.child.count == 1 {
            return true
        }

        return false
    }

    public func getParent() -> Tag? {
        return parent
    }

    public func hasOneChild() -> Bool {
        return child.count < 2
    }

    public func removeAllChild() {
        if child.count < 2 {
            child.removeAll()
        }
    }
}
