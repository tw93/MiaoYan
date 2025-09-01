import Foundation

/// PARAM: id: is an id number that the os uses to differentiate between events.
/// PARAM: path: is the path the change took place. its formatted like so: Users/John/Desktop/test/text.txt
/// PARAM: flag: pertains to the file event type.
/// EXAMPLE: let url = NSURL(fileURLWithPath: event.path)//<--formats paths to: file:///Users/John/Desktop/test/text.txt
/// EXAMPLE: Swift.print("fileWatcherEvent.fileChange: " + "\(event.fileChange)")
/// EXAMPLE: Swift.print("fileWatcherEvent.fileModified: " + "\(event.fileModified)")
/// EXAMPLE: Swift.print("\t eventId: \(event.id) - eventFlags:  \(event.flags) - eventPath:  \(event.path)")
class FileWatcherEvent {
    var id: FSEventStreamEventId
    var path: String
    var flags: FSEventStreamEventFlags

    init(_ eventId: FSEventStreamEventId, _ eventPath: String, _ eventFlags: FSEventStreamEventFlags) {
        id = eventId
        path = eventPath
        flags = eventFlags
    }
}

/// The following code is to differentiate between the FSEvent flag types (aka file event types)
/// NOTE: Be aware that .DS_STORE changes frequently when other files change
extension FileWatcherEvent {
    /* general */
    var fileChange: Bool { (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile)) != 0 }
    var dirChange: Bool { (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir)) != 0 }
    /* CRUD */
    var created: Bool { (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)) != 0 }
    var removed: Bool { (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)) != 0 }
    var renamed: Bool { (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)) != 0 }
    var modified: Bool { (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)) != 0 }
}

/// Convenience
extension FileWatcherEvent {
    /* File */
    var fileCreated: Bool { fileChange && created }
    var fileRemoved: Bool { fileChange && removed }
    var fileRenamed: Bool { fileChange && renamed }
    var fileModified: Bool { fileChange && modified }
    /* Directory */
    var dirCreated: Bool { dirChange && created }
    var dirRemoved: Bool { dirChange && removed }
    var dirRenamed: Bool { dirChange && renamed }
    var dirModified: Bool { dirChange && modified }
}

/// Simplifies debugging
/// EXAMPLE: Swift.print(event.description)//Outputs: The file /Users/John/Desktop/test/text.txt was modified
extension FileWatcherEvent {
    var description: String {
        var result = "The \(fileChange ? "file" : "directory") \(path) was"
        if created {
            result += " created"
        }
        if removed {
            result += " removed"
        }
        if renamed {
            result += " renamed"
        }
        if modified {
            result += " modified"
        }
        return result
    }
}
