import CoreServices
import Foundation

extension String {
    public func tag(withClass: CFString) -> String? {
        UTTypeCopyPreferredTagWithClass(self as CFString, withClass)?.takeRetainedValue() as String?
    }

    public func uti(withClass: CFString) -> String? {
        UTTypeCreatePreferredIdentifierForTag(withClass, self as CFString, nil)?.takeRetainedValue() as String?
    }

    public var utiMimeType: String? {
        tag(withClass: kUTTagClassMIMEType)
    }

    public var utiFileExtension: String? {
        tag(withClass: kUTTagClassFilenameExtension)
    }

    public var mimeTypeUTI: String? {
        uti(withClass: kUTTagClassMIMEType)
    }

    public var fileExtensionUTI: String? {
        uti(withClass: kUTTagClassFilenameExtension)
    }
}
