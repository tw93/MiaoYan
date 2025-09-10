import Cocoa

class FileWatcher {
    let filePaths: [String]  // -- paths to watch - works on folders and file paths

    var callback: ((_ fileWatcherEvent: FileWatcherEvent) -> Void)?
    var queue: DispatchQueue?

    private var streamRef: FSEventStreamRef?
    private var hasStarted: Bool { streamRef != nil }

    init(_ paths: [String]) { filePaths = paths }

    /**
     * Start listening for FSEvents
     */
    func start() {
        guard !hasStarted else { return }  // -- make sure we are not already listening!

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: retainCallback, release: releaseCallback,
            copyDescription: nil
        )

        streamRef = FSEventStreamCreate(
            kCFAllocatorDefault, eventCallback, &context,
            filePaths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )

        selectStreamScheduler()
        FSEventStreamStart(streamRef!)
    }

    /**
     * Stop listening for FSEvents
     */
    func stop() {
        guard hasStarted else { return }  // -- make sure we are indeed listening!

        FSEventStreamStop(streamRef!)
        FSEventStreamInvalidate(streamRef!)
        FSEventStreamRelease(streamRef!)

        streamRef = nil
    }

    private let eventCallback: FSEventStreamCallback = {
        _, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds
        in
        let fileSystemWatcher = Unmanaged<FileWatcher>.fromOpaque(clientCallBackInfo!).takeUnretainedValue()
        let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]

        for index in 0..<numEvents {
            fileSystemWatcher.callback?(FileWatcherEvent(eventIds[index], paths[index], eventFlags[index]))
        }
    }

    private let retainCallback: CFAllocatorRetainCallBack = { (info: UnsafeRawPointer?) in
        _ = Unmanaged<FileWatcher>.fromOpaque(info!).retain()
        return info
    }

    private let releaseCallback: CFAllocatorReleaseCallBack = { (info: UnsafeRawPointer?) in
        Unmanaged<FileWatcher>.fromOpaque(info!).release()
    }

    private func selectStreamScheduler() {
        if let queue = queue {
            FSEventStreamSetDispatchQueue(streamRef!, queue)
        } else {
            FSEventStreamScheduleWithRunLoop(
                streamRef!, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue
            )
        }
    }
}

extension FileWatcher {
    convenience init(_ paths: [String], _ callback: @escaping (_ fileWatcherEvent: FileWatcherEvent) -> Void) {
        self.init(paths)
        self.callback = callback
    }
}
