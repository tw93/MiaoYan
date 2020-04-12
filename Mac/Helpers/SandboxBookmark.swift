//
//  SandboxBookmark.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 8/6/17.
//  Copyright © 2017 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

class SandboxBookmark {
    static var instance: SandboxBookmark? = nil
    var bookmarks = [URL: Data]()
    var successfullyRestored = [URL]()
    
    public static func sharedInstance() -> SandboxBookmark {
        guard let sandbox = self.instance else {
            self.instance = SandboxBookmark()
            return self.instance!
        }
        return sandbox
    }
    
    func bookmarkPath() -> String {
        var url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        url = url.appendingPathComponent("Bookmarks.dict")
        
        return url.path
    }
    
    func load() -> [URL] {
        let path = bookmarkPath()

        if FileManager.default.fileExists(atPath: path), let bookmarks = NSKeyedUnarchiver.unarchiveObject(withFile: path) as? [URL: Data] {
            self.bookmarks = bookmarks

            for bookmark in bookmarks {
                _ = restore(bookmark)
            }
        }
        
        return successfullyRestored
    }
    
    func save() {
        let path = bookmarkPath()
        NSKeyedArchiver.archiveRootObject(bookmarks, toFile: path)
    }
    
    func store(url: URL) {
        #if os(OSX)
        do {
            let data = try url.bookmarkData(options: NSURL.BookmarkCreationOptions.withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            bookmarks[url] = data
        } catch {
            Swift.print(error)
            Swift.print("Error storing bookmarks")
        }
        #endif
    }
    
    func restore(_ bookmark: (key: URL, value: Data)) -> Bool {
        #if os(OSX)
        let restoredUrl: URL?
        var isStale = false
        
        do {
            restoredUrl = try URL.init(resolvingBookmarkData: bookmark.value, options: NSURL.BookmarkResolutionOptions.withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
        } catch {
            Swift.print("Error restoring bookmarks")
            restoredUrl = nil
        }

        guard let url = restoredUrl else { return false }

        if isStale {
            Swift.print("URL is stale")
            return false
        }

        if url.startAccessingSecurityScopedResource() {
            print("Bookmark restored: \(url.path)")
            successfullyRestored.append(url)
            return true
        }

        Swift.print("Couldn't access: \(url.path)")
        #endif

        return false
    }
    
    func remove(url: URL) {
        bookmarks.removeValue(forKey: url)
    }
    
    func removeBy(_ url: URL) {
        _ = load()
        bookmarks.removeValue(forKey: url)
        save()
    }
    
    func rename(url: URL, new: URL) {
        let value = bookmarks[url]
        bookmarks[new] = value
        save()
    }
    
    public func save(url: URL) {
        let path = bookmarkPath()

        if self.bookmarks.isEmpty,
            FileManager.default.fileExists(atPath: path),
            let bookmarks = NSKeyedUnarchiver.unarchiveObject(withFile: path) as? [URL: Data]
        {
            self.bookmarks = bookmarks
        }
        
        self.store(url: url)
        self.save()
    }
}
