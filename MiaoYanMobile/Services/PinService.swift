import Foundation

/// Note pinning for the iOS app. Mirrors the macOS app exactly: a note is
/// pinned by writing a one-byte boolean into the extended attribute
/// `com.tw93.miaoyan.pin` on the file (see `Business/Note.swift` addPin /
/// removePin). The filename never changes, so the note's URL / identity
/// stays stable across a pin toggle — selection, caches and snapshots all
/// keep working.
///
/// iCloud Drive does not reliably propagate custom extended attributes, so
/// a pin is device-local. That matches what the macOS app already does and
/// is intentional: a filename-prefix scheme would sync across devices but
/// would also leak the prefix into note titles on Mac and have the two
/// platforms fight over the file.
enum PinService {
    /// Must match macOS `AppIdentifier.pinKey`, which resolves to
    /// `"<bundleID>.pin"`. Hardcoded to the macOS app bundle id rather than
    /// derived from the iOS app's own bundle id so a note pinned on Mac and
    /// read on iOS resolves the identical xattr name.
    static let pinKey = "com.tw93.miaoyan.pin"

    /// Read the pin xattr. Matches the macOS reader: the attribute stores a
    /// one-byte `Bool`, and a missing attribute means "not pinned". A note
    /// unpinned on Mac keeps the attribute present with a `false` byte, so
    /// checking the value (not mere existence) is required.
    static func isPinned(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { rawPath -> Bool in
            guard let rawPath else { return false }
            guard getxattr(rawPath, pinKey, nil, 0, 0, 0) > 0 else { return false }
            var byte: UInt8 = 0
            let read = withUnsafeMutablePointer(to: &byte) {
                getxattr(rawPath, pinKey, $0, 1, 0, 0)
            }
            return read == 1 && byte != 0
        }
    }

    /// Write the pin xattr. Mirrors macOS `removePin`, which writes a
    /// `false` byte rather than deleting the attribute when unpinning.
    static func setPinned(_ pinned: Bool, for url: URL) throws {
        try url.withUnsafeFileSystemRepresentation { rawPath in
            guard let rawPath else { throw CocoaError(.fileNoSuchFile) }
            var value: UInt8 = pinned ? 1 : 0
            let result = withUnsafePointer(to: &value) {
                setxattr(rawPath, pinKey, $0, 1, 0, 0)
            }
            guard result == 0 else {
                throw NSError(
                    domain: NSPOSIXErrorDomain, code: Int(errno),
                    userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
            }
        }
    }
}
