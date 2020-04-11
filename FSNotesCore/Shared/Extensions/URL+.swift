//
//  URL+.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 3/22/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

#if os(iOS)
    import MobileCoreServices
#else
    import CoreServices
#endif

public extension URL {
    /// Get extended attribute.
    func extendedAttribute(forName name: String) throws -> Data {
        return try self.withUnsafeFileSystemRepresentation { fileSystemPath -> Data in

            // Determine attribute size:
            let length = getxattr(fileSystemPath, name, nil, 0, 0, 0)
            guard length >= 0 else { throw URL.posixError(errno) }

            // Create buffer with required size:
            var data = Data(count: length)
            let count = data.count

            // Retrieve attribute:
            let result = data.withUnsafeMutableBytes {
                getxattr(fileSystemPath, name, $0.baseAddress, count, 0, 0)
            }
            guard result >= 0 else { throw URL.posixError(errno) }
            return data
        }
    }

    /// Set extended attribute.
    func setExtendedAttribute(data: Data, forName name: String) throws {

        try self.withUnsafeFileSystemRepresentation { fileSystemPath in
            let result = data.withUnsafeBytes {
                setxattr(fileSystemPath, name, $0.baseAddress, data.count, 0, 0)
            }
            guard result == 0 else { throw URL.posixError(errno) }
        }
    }

    /// Remove extended attribute.
    func removeExtendedAttribute(forName name: String) throws {

        try self.withUnsafeFileSystemRepresentation { fileSystemPath in
            let result = removexattr(fileSystemPath, name, 0)
            guard result == 0 else { throw URL.posixError(errno) }
        }
    }

    /// Get list of all extended attributes.
    func listExtendedAttributes() throws -> [String] {
        let list = try self.withUnsafeFileSystemRepresentation { fileSystemPath -> [String] in
            let length = listxattr(fileSystemPath, nil, 0, 0)
            guard length >= 0 else { throw URL.posixError(errno) }

            // Create buffer with required size:
            var namebuf = [CChar](repeating: 0, count: length)

            // Retrieve attribute list:
            let result = listxattr(fileSystemPath, &namebuf, namebuf.count, 0)
            guard result >= 0 else { throw URL.posixError(errno) }

            // Extract attribute names:
            let list = namebuf.split(separator: 0).compactMap {
                $0.withUnsafeBufferPointer {
                    $0.withMemoryRebound(to: UInt8.self) {
                        String(bytes: $0, encoding: .utf8)
                    }
                }
            }
            return list
        }
        return list
    }

    /// Helper function to create an NSError from a Unix errno.
    private static func posixError(_ err: Int32) -> NSError {
        return NSError(domain: NSPOSIXErrorDomain, code: Int(err),
                       userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(err))])
    }

    // Access the URL parameters eg nv://make?title=blah&txt=body like so:
    // let titleStr = myURL['title']
    subscript(queryParam: String) -> String? {
        guard let url = URLComponents(string: self.absoluteString) else { return nil }
        return url.queryItems?.first(where: { $0.name == queryParam })?.value
    }

    func isRemote() -> Bool {
        return (self.absoluteString.starts(with: "http://") || self.absoluteString.starts(with: "https://"))
    }

    var attributes: [FileAttributeKey: Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: path)
        } catch let error as NSError {
            print("FileAttribute error: \(error)")
        }
        return nil
    }

    var fileSize: UInt64 {
        return attributes?[.size] as? UInt64 ?? UInt64(0)
    }

    func removingFragment() -> URL {
        var string = self.absoluteString
        if let query = query {
            string = string.replacingOccurrences(of: "?\(query)", with: "")
        }

        if let fragment = fragment {
            string = string.replacingOccurrences(of: "#\(fragment)", with: "")
        }

        return URL(string: string) ?? self
    }

    var typeIdentifier: String? {
        return (try? resourceValues(forKeys: [.typeIdentifierKey]))?.typeIdentifier
    }

    var fileUTType: CFString? {
        let unmanagedFileUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExtension as CFString, nil)
        return unmanagedFileUTI?.takeRetainedValue()
    }

    var isVideo: Bool {
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

    var isImage: Bool {
        guard let fileUTI = fileUTType else { return false }

        return UTTypeConformsTo(fileUTI, kUTTypeImage)
    }
}
