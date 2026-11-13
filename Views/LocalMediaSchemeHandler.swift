import UniformTypeIdentifiers
import WebKit

/// Serves a note's local images, videos and audio to the preview from the
/// app's own process, at `HtmlManager.localMediaURL(forPath:)` (#578).
///
/// The page is a file in a temporary folder and used to reach the notes
/// through `file://`, with read access to `/`. The App Store build is
/// sandboxed, and its web content process got no access to the notes folder
/// that way: every local image came out blank, with no "image not found",
/// while the iPhone showed the same notes. The app itself holds the folder's
/// access (its container, its iCloud container or the folder the user
/// granted), so it reads the file and hands the bytes over, in the GitHub
/// build too, so both take one path.
///
/// Only files whose type is an image or audiovisual content are served, so
/// markup in a note cannot read any other file this way. Byte ranges are
/// honoured, which a video needs to start and seek.
@MainActor
final class LocalMediaSchemeHandler: NSObject, WKURLSchemeHandler {
    static let shared = LocalMediaSchemeHandler()

    static func install(on configuration: WKWebViewConfiguration) {
        configuration.setURLSchemeHandler(shared, forURLScheme: HtmlManager.localMediaScheme)
    }

    /// Tasks WebKit has not stopped. A file read finishing after the page
    /// moved on must not answer, since a stopped task throws on any call.
    private var running = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        running.insert(id)
        let request = urlSchemeTask.request
        Task { @MainActor in
            let reply = await Self.reply(to: request.url, range: request.value(forHTTPHeaderField: "Range"))
            guard running.remove(id) != nil, let url = request.url else { return }
            switch reply {
            case .file(let status, let headers, let data):
                guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
                    urlSchemeTask.didFailWithError(URLError(.cannotParseResponse))
                    return
                }
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            case .failure(let code):
                urlSchemeTask.didFailWithError(URLError(code))
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        running.remove(ObjectIdentifier(urlSchemeTask))
    }

    enum Reply: Sendable, Equatable {
        case file(status: Int, headers: [String: String], data: Data)
        case failure(URLError.Code)
    }

    /// Reads the file `url` names, off the main thread: the whole file, or
    /// the part a `Range: bytes=…` header asks for.
    nonisolated static func reply(to url: URL?, range: String?) async -> Reply {
        guard let url, url.scheme == HtmlManager.localMediaScheme else { return .failure(.unsupportedURL) }
        let fileURL = URL(fileURLWithPath: url.path)
        guard let type = UTType(filenameExtension: fileURL.pathExtension),
            type.conforms(to: .image) || type.conforms(to: .audiovisualContent)
        else { return .failure(.noPermissionsToReadFile) }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return .failure(.fileDoesNotExist) }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return .failure(.cannotOpenFile) }

        var headers = [
            "Content-Type": type.preferredMIMEType ?? "application/octet-stream",
            "Accept-Ranges": "bytes",
        ]
        let requested = range.flatMap { byteRange($0, size: size) }
        if range != nil, requested == nil {
            headers["Content-Range"] = "bytes */\(size)"
            return .file(status: 416, headers: headers, data: Data())
        }
        let bytes = requested ?? (0..<size)
        do {
            try handle.seek(toOffset: bytes.lowerBound)
            let data = try handle.read(upToCount: Int(bytes.count)) ?? Data()
            headers["Content-Length"] = String(data.count)
            guard requested != nil else { return .file(status: 200, headers: headers, data: data) }
            headers["Content-Range"] = "bytes \(bytes.lowerBound)-\(bytes.lowerBound + UInt64(data.count) - 1)/\(size)"
            return .file(status: 206, headers: headers, data: data)
        } catch {
            return .failure(.cannotOpenFile)
        }
    }

    /// The bytes one `bytes=start-end`, `bytes=start-` or `bytes=-suffix`
    /// range asks for within a file of `size` bytes, or nil when it asks for
    /// none of them. Only the first range of a list is read; WebKit's media
    /// loader asks for one at a time.
    nonisolated static func byteRange(_ header: String, size: UInt64) -> Range<UInt64>? {
        guard header.hasPrefix("bytes="), size > 0 else { return nil }
        let spec = header.dropFirst("bytes=".count).split(separator: ",").first.map(String.init) ?? ""
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty {
            guard let suffix = UInt64(parts[1]), suffix > 0 else { return nil }
            return (size - min(suffix, size))..<size
        }
        guard let start = UInt64(parts[0]), start < size else { return nil }
        if parts[1].isEmpty { return start..<size }
        guard let end = UInt64(parts[1]), end >= start else { return nil }
        return start..<(min(end, size - 1) + 1)
    }
}
