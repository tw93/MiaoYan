import Foundation
/**
 * PARAM: id: is an id number that the os uses to differentiate between events.
 * PARAM: path: is the path the change took place. its formated like so: Users/John/Desktop/test/text.txt
 * PARAM: flag: pertains to the file event type.
 * EXAMPLE: let url = NSURL(fileURLWithPath: event.path)//<--formats paths to: file:///Users/John/Desktop/test/text.txt
 * EXAMPLE: Swift.print("fileWatcherEvent.fileChange: " + "\(event.fileChange)")
 * EXAMPLE: Swift.print("fileWatcherEvent.fileModified: " + "\(event.fileModified)")
 * EXAMPLE: Swift.print("\t eventId: \(event.id) - eventFlags:  \(event.flags) - eventPath:  \(event.path)")
 */
class FileWatcherEvent{
    var id:FSEventStreamEventId
    var path:String
    var flags: FSEventStreamEventFlags
    init(_ eventId:FSEventStreamEventId, _ eventPath: String, _ eventFlags: FSEventStreamEventFlags){
        self.id = eventId
        self.path = eventPath
        self.flags = eventFlags
    }
}
/**
 * The following code is to differentiate between the FSEvent flag types (aka file event types)
 * NOTE: Be aware that .DS_STORE changes frequently when other files change
 */
extension FileWatcherEvent{
    /*general*/
    var fileChange:Bool {return (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile)) != 0}
    var dirChange:Bool {return (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir)) != 0}
    /*CRUD*/
    var created:Bool {return (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)) != 0}
    var removed:Bool {return (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)) != 0}
    var renamed:Bool {return (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)) != 0}
    var modified:Bool {return (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)) != 0}
}
/**
 * Convenince
 */
extension FileWatcherEvent{
    /*File*/
    var fileCreated:Bool {return fileChange && created}
    var fileRemoved:Bool {return fileChange && removed}
    var fileRenamed:Bool {return fileChange && renamed}
    var fileModified:Bool {return fileChange && modified}
    /*Directory*/
    var dirCreated:Bool {return dirChange && created}
    var dirRemoved:Bool {return dirChange && removed}
    var dirRenamed:Bool {return dirChange && renamed}
    var dirModified:Bool {return dirChange && modified}
}
/**
 * Simplifies debugging
 * EXAMPLE: Swift.print(event.description)//Outputs: The file /Users/John/Desktop/test/text.txt was modified
 */
extension FileWatcherEvent{
    var description:String {
        var result = "The \(fileChange ? "file":"directory") \(self.path) was"
        if self.created {
            result += " created"
        }
        if self.removed {
            result += " removed"
        }
        if self.renamed {
            result += " renamed"
        }
        if self.modified {
            result += " modified"
        }
        return result
    }
}
