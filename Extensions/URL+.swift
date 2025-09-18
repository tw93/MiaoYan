import CoreServices
import Foundation

extension URL {
    public func extendedAttribute(forName name: String) throws -> Data {
        try withUnsafeFileSystemRepresentation { fileSystemPath -> Data in
            let length = getxattr(fileSystemPath, name, nil, 0, 0, 0)
            guard length >= 0 else { throw URL.posixError(errno) }

            var data = Data(count: length)
            let count = data.count
            let result = data.withUnsafeMutableBytes {
                getxattr(fileSystemPath, name, $0.baseAddress, count, 0, 0)
            }
            guard result >= 0 else { throw URL.posixError(errno) }
            return data
        }
    }

    public func setExtendedAttribute(data: Data, forName name: String) throws {
        try withUnsafeFileSystemRepresentation { fileSystemPath in
            let result = data.withUnsafeBytes {
                setxattr(fileSystemPath, name, $0.baseAddress, data.count, 0, 0)
            }
            guard result == 0 else { throw URL.posixError(errno) }
        }
    }

    public func removeExtendedAttribute(forName name: String) throws {
        try withUnsafeFileSystemRepresentation { fileSystemPath in
            let result = removexattr(fileSystemPath, name, 0)
            guard result == 0 else { throw URL.posixError(errno) }
        }
    }

    public func listExtendedAttributes() throws -> [String] {
        try withUnsafeFileSystemRepresentation { fileSystemPath -> [String] in
            let length = listxattr(fileSystemPath, nil, 0, 0)
            guard length >= 0 else { throw URL.posixError(errno) }

            var namebuf = [CChar](repeating: 0, count: length)
            let result = listxattr(fileSystemPath, &namebuf, namebuf.count, 0)
            guard result >= 0 else { throw URL.posixError(errno) }

            return namebuf.split(separator: 0).compactMap {
                $0.withUnsafeBufferPointer {
                    $0.withMemoryRebound(to: UInt8.self) {
                        String(bytes: $0, encoding: .utf8)
                    }
                }
            }
        }
    }

    private static func posixError(_ err: Int32) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(err),
            userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(err))]
        )
    }

    public subscript(queryParam: String) -> String? {
        guard let url = URLComponents(string: absoluteString) else { return nil }
        return url.queryItems?.first(where: { $0.name == queryParam })?.value
    }

    public func isRemote() -> Bool {
        absoluteString.hasPrefix("http://") || absoluteString.hasPrefix("https://")
    }

    public var attributes: [FileAttributeKey: Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: path)
        } catch let error as NSError {
            // hop 回主线程再打点，避免跨 actor 访问
            Task { @MainActor in
                AppDelegate.trackError(error, context: "URL+.fileAttributeError")
            }
        }
        return nil
    }

    public var fileSize: UInt64 {
        self.attributes?[.size] as? UInt64 ?? UInt64(0)
    }

    public func removingFragment() -> URL {
        var string = absoluteString

        if let query = query {
            string = string.replacingOccurrences(of: "?\(query)", with: "")
        }

        if let fragment = fragment {
            string = string.replacingOccurrences(of: "#\(fragment)", with: "")
        }

        return URL(string: string) ?? self
    }

    public var typeIdentifier: String? {
        (try? resourceValues(forKeys: [.typeIdentifierKey]))?.typeIdentifier
    }

    public var fileUTType: CFString? {
        let unmanagedFileUTI = UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassFilenameExtension,
            pathExtension as CFString,
            nil
        )
        return unmanagedFileUTI?.takeRetainedValue()
    }

    public var isVideo: Bool {
        guard let fileUTI = fileUTType else { return false }

        return UTTypeConformsTo(fileUTI, kUTTypeMovie)
            || UTTypeConformsTo(fileUTI, kUTTypeVideo)
            || UTTypeConformsTo(fileUTI, kUTTypeQuickTimeMovie)
            || UTTypeConformsTo(fileUTI, kUTTypeMPEG)
            || UTTypeConformsTo(fileUTI, kUTTypeMPEG2Video)
            || UTTypeConformsTo(fileUTI, kUTTypeMPEG2TransportStream)
            || UTTypeConformsTo(fileUTI, kUTTypeMPEG4)
            || UTTypeConformsTo(fileUTI, kUTTypeAppleProtectedMPEG4Video)
            || UTTypeConformsTo(fileUTI, kUTTypeAVIMovie)
    }

    public var isImage: Bool {
        guard let fileUTI = fileUTType else { return false }
        return UTTypeConformsTo(fileUTI, kUTTypeImage)
    }
}
