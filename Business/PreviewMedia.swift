import Foundation
import ImageIO

/// What a rendered note needs to keep its images and videos in place while
/// they load: each image's pixel size from its file's header (local files,
/// and remote ones through `RemoteImageProbe`), the tag attributes that hold
/// the box, and videos held to `preload="none"` until the page is up. It
/// imports Foundation and ImageIO only, so the iPhone and iPad reader in
/// MiaoYan-Pro compiles this same file; keep AppKit and WebKit out of it.
enum PreviewMedia {
    private static let videoTagRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "<video\\b[^>]*>", options: [.caseInsensitive])
    }()

    /// Whether the tag already fixes its box: both `width` and `height`.
    /// One alone is not enough. Weekly notes write `<img width="800">`, and
    /// with only a width the 1px placeholder's square ratio drew an 800 by
    /// 800 box for a landscape photo.
    static func hasSize(_ tag: String) -> Bool {
        hasAttribute("width", in: tag) && hasAttribute("height", in: tag)
    }

    private static func hasAttribute(_ name: String, in tag: String) -> Bool {
        tag.range(of: #"\s"# + name + "=", options: .regularExpression) != nil
    }

    /// `placeholder` is the Mac preview's case, where a lazy image's `src` is
    /// a 1px GIF whose own square ratio beats the attributes' ratio, so the
    /// box is held by a plain `aspect-ratio`, written fresh on every render. A tag that loads its real file at once (the iPhone
    /// reader) takes `auto` instead, so the picture's own ratio wins once it
    /// arrives, even when its file changed after the HTML was cached. A width
    /// or height the note wrote stays; the image's own ratio sets the other
    /// side.
    static func sized(_ tag: String, _ size: (width: Int, height: Int), original: String, placeholder: Bool = true) -> String {
        let ratio = placeholder ? "\(size.width) / \(size.height)" : "auto \(size.width) / \(size.height)"
        let style = original.contains("style=") ? "" : " style=\"aspect-ratio: \(ratio)\""
        let written = hasAttribute("width", in: original) || hasAttribute("height", in: original)
        let attributes = written ? "" : " width=\"\(size.width)\" height=\"\(size.height)\""
        return tag.replacingOccurrences(of: "<img ", with: "<img\(attributes)\(style) ")
    }

    /// The image's displayed size in pixels, from its header alone. An iCloud
    /// file that has not been downloaded is skipped rather than fetched to
    /// read it; that image simply loads without a reserved box.
    static func pixelSize(atPath path: String) -> (width: Int, height: Int)? {
        var info = stat()
        guard stat(path, &info) == 0, info.st_flags & UInt32(SF_DATALESS) == 0 else { return nil }
        // Split view renders on every keystroke; a file whose date and length
        // are unchanged keeps the size read last time.
        let stamp = PixelSizeCache.Stamp(seconds: info.st_mtimespec.tv_sec, nanoseconds: info.st_mtimespec.tv_nsec, length: info.st_size)
        if let known = PixelSizeCache.shared.size(for: path, stamp: stamp) { return known }
        let size = readPixelSize(atPath: path)
        if let size { PixelSizeCache.shared.store(size, for: path, stamp: stamp) }
        return size
    }

    private static func readPixelSize(atPath path: String) -> (width: Int, height: Int)? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, options) else { return nil }
        if let size = pixelSize(of: source) { return size }
        guard path.lowercased().hasSuffix(".webp"), let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        return extendedWebPSize((try? handle.read(upToCount: 30)) ?? Data())
    }

    /// The displayed size from the first bytes of an image file, or nil while
    /// they do not reach the size yet. ImageIO's incremental source gives no
    /// properties for a JPEG cut short, so this is a whole source each time.
    static func pixelSize(fromHeader data: Data) -> (width: Int, height: Int)? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return extendedWebPSize(data) }
        return pixelSize(of: source) ?? extendedWebPSize(data)
    }

    /// The canvas of an extended WebP (an animated one, or one with alpha or
    /// metadata), from its `VP8X` chunk: ImageIO reports no size for an
    /// animated WebP, not even for the whole file.
    static func extendedWebPSize(_ data: Data) -> (width: Int, height: Int)? {
        let bytes = [UInt8](data.prefix(30))
        guard bytes.count == 30, bytes[0..<4] == [0x52, 0x49, 0x46, 0x46], bytes[8..<12] == [0x57, 0x45, 0x42, 0x50],
            bytes[12..<16] == [0x56, 0x50, 0x38, 0x58]
        else { return nil }
        let side = { (at: Int) in 1 + (Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16) }
        return (side(24), side(27))
    }

    private static func pixelSize(of source: CGImageSource) -> (width: Int, height: Int)? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { return nil }
        // EXIF orientations 5 to 8 turn the picture a quarter, and the page
        // shows it turned (`image-orientation: from-image`).
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 && orientation <= 8 ? (height, width) : (width, height)
    }

    /// Every video starts with `preload="none"`: a video that loads anything
    /// holds back the page's load event, and the app shows a note only after
    /// it, so one slow server kept the whole note hidden. `data-preload`
    /// marks the ones MiaoYan held back, and `MiaoYanCommon.prepareVideos`
    /// loads their metadata and first frame once the page is up, so the
    /// player shows a picture instead of an empty box. A video the note
    /// itself set to `preload="none"` is left as written.
    static func deferredVideoTags(_ html: String) -> String {
        guard let regex = videoTagRegex else { return html }
        var result = html
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let tag = String(result[range])
            if tag.range(of: #"\bpreload\s*=\s*["']?none\b"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            if tag.contains("data-preload=") { continue }
            let bare =
                tag
                .replacingOccurrences(of: #"\s+preload\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#, with: "", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: #"\s+preload(?=[\s/>])"#, with: "", options: [.regularExpression, .caseInsensitive])
            let open = bare.prefix(6)
            result.replaceSubrange(range, with: open + " preload=\"none\" data-preload=\"metadata\"" + bare.dropFirst(6))
        }
        return result
    }
}

/// Image sizes already read, keyed by path and checked against the file's
/// modification date and length. Renders run on detached tasks, so it locks.
final class PixelSizeCache: @unchecked Sendable {
    struct Stamp: Equatable {
        let seconds: Int
        let nanoseconds: Int
        let length: Int64
    }

    static let shared = PixelSizeCache()
    private let lock = NSLock()
    private struct Entry {
        let stamp: Stamp
        let width: Int
        let height: Int
    }

    private var entries: [String: Entry] = [:]
    private let limit = 4096

    func size(for path: String, stamp: Stamp) -> (width: Int, height: Int)? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[path], entry.stamp == stamp else { return nil }
        return (entry.width, entry.height)
    }

    func store(_ size: (width: Int, height: Int), for path: String, stamp: Stamp) {
        lock.lock()
        defer { lock.unlock() }
        if entries.count >= limit { entries.removeAll(keepingCapacity: true) }
        entries[path] = Entry(stamp: stamp, width: size.width, height: size.height)
    }
}

/// Sizes of remote images, kept in the app's caches folder so a note opened
/// again reserves each image's box before it downloads. They come from the
/// file's header (`RemoteImageProbe`) and from the preview once the image
/// has loaded, which has the last word.
final class RemoteImageSizes: @unchecked Sendable {
    static let shared = RemoteImageSizes()
    private let lock = NSLock()
    private var entries: [String: [Int]]?
    private var saveScheduled = false
    private let limit = 4000
    private let queue = DispatchQueue(label: "com.tw93.miaoyan.remote-image-sizes", qos: .utility)
    private let fileURL: URL?

    init(fileURL: URL? = RemoteImageSizes.defaultFileURL) {
        self.fileURL = fileURL
    }

    static let defaultFileURL: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "MiaoYan", isDirectory: true)
        .appendingPathComponent("remote-image-sizes.json")

    func size(for url: String) -> (width: Int, height: Int)? {
        lock.lock()
        defer { lock.unlock() }
        guard let size = loadedEntries()[url], size.count == 2 else { return nil }
        return (size[0], size[1])
    }

    func record(url: String, width: Int, height: Int) {
        guard url.hasPrefix("http://") || url.hasPrefix("https://"), url.count < 4096,
            (1...100_000).contains(width), (1...100_000).contains(height)
        else { return }
        lock.lock()
        var current = loadedEntries()
        guard current[url] != [width, height] else {
            lock.unlock()
            return
        }
        if current.count >= limit { current.removeAll(keepingCapacity: true) }
        current[url] = [width, height]
        entries = current
        let shouldSchedule = !saveScheduled && fileURL != nil
        if shouldSchedule { saveScheduled = true }
        lock.unlock()
        if shouldSchedule {
            queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.save() }
        }
    }

    /// Caller holds the lock.
    private func loadedEntries() -> [String: [Int]] {
        if let entries { return entries }
        var loaded: [String: [Int]] = [:]
        if let fileURL, let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([String: [Int]].self, from: data)
        {
            loaded = decoded
        }
        entries = loaded
        return loaded
    }

    private func save() {
        lock.lock()
        let snapshot = entries ?? [:]
        saveScheduled = false
        lock.unlock()
        guard let fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Reads a remote image's pixel size from the start of the file, so a note
/// opened for the first time holds each image's box at the picture's own
/// ratio while the file is still on its way. A 2 MB photo can take seconds
/// to arrive, and until then a width-only tag drew a square; its size sits in
/// the first kilobytes (a PNG's in 1 KB, an iPhone JPEG's at about 8 KB,
/// after its EXIF). Each request asks for that range only and stops reading
/// once the size is known. It goes to the same URL the preview loads, so no
/// server is contacted that the note does not already show.
actor RemoteImageProbe {
    typealias Size = (width: Int, height: Int)
    /// A read either finds the size, finds there is none to find (an error
    /// status, or no size within the range), or cannot tell (offline, a
    /// timeout); only the first two are kept, so a dropped connection does
    /// not stop the next render from asking again.
    private enum Answer {
        case size(Size)
        case none
        case unknown
    }

    static let shared = RemoteImageProbe()
    static let maxBytes = 262_144
    private static let maxRunning = 4

    private let session: URLSession
    private let sizes: RemoteImageSizes
    private var inFlight: [String: Task<Answer, Never>] = [:]
    private var failed: Set<String> = []
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(configuration: URLSessionConfiguration = RemoteImageProbe.defaultConfiguration, sizes: RemoteImageSizes = .shared) {
        session = URLSession(configuration: configuration)
        self.sizes = sizes
    }

    static var defaultConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = maxRunning
        return configuration
    }

    func size(of urlString: String) async -> Size? {
        if let known = sizes.size(for: urlString) { return known }
        guard !failed.contains(urlString), let url = URL(string: urlString),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        let task: Task<Answer, Never>
        if let running = inFlight[urlString] {
            task = running
        } else {
            let session = session
            task = Task {
                await acquire()
                let answer = await Self.read(url, session: session)
                release()
                return answer
            }
            inFlight[urlString] = task
        }
        let answer = await task.value
        inFlight[urlString] = nil
        switch answer {
        case .size(let size) where (1...100_000).contains(size.width) && (1...100_000).contains(size.height):
            // The page's own measurement, once the image has loaded, wins.
            if let measured = sizes.size(for: urlString) { return measured }
            sizes.record(url: urlString, width: size.width, height: size.height)
            return size
        case .size, .none:
            if failed.count < 4000 { failed.insert(urlString) }
            return nil
        case .unknown:
            return nil
        }
    }

    private func acquire() async {
        if running < Self.maxRunning {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }

    private static func read(_ url: URL, session: URLSession) async -> Answer {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-\(maxBytes - 1)", forHTTPHeaderField: "Range")
        guard let (bytes, response) = try? await session.bytes(for: request) else { return .unknown }
        // Whatever the answer, the rest of the body is not wanted: an error
        // page, or the whole file from a server that ignores the range.
        defer { bytes.task.cancel() }
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200...299).contains(status) else { return .none }
        var data = Data()
        data.reserveCapacity(16_384)
        var nextCheck = 1024
        do {
            for try await byte in bytes {
                data.append(byte)
                guard data.count >= nextCheck else { continue }
                if let size = PreviewMedia.pixelSize(fromHeader: data) { return .size(size) }
                if data.count >= maxBytes { return .none }
                nextCheck = min(nextCheck * 2, maxBytes)
            }
        } catch {
            return .unknown
        }
        return PreviewMedia.pixelSize(fromHeader: data).map { .size($0) } ?? .none
    }
}
