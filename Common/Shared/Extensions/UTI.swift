import Foundation
#if os(OSX)
import CoreServices
#elseif os(iOS)
import MobileCoreServices
#endif

public extension String {
    func tag(withClass: CFString) -> String? {
        UTTypeCopyPreferredTagWithClass(self as CFString, withClass)?.takeRetainedValue() as String?
    }

    func uti(withClass: CFString) -> String? {
        UTTypeCreatePreferredIdentifierForTag(withClass, self as CFString, nil)?.takeRetainedValue() as String?
    }

    var utiMimeType: String? {
        tag(withClass: kUTTagClassMIMEType)
    }

    var utiFileExtension: String? {
        tag(withClass: kUTTagClassFilenameExtension)
    }

    var mimeTypeUTI: String? {
        uti(withClass: kUTTagClassMIMEType)
    }

    var fileExtensionUTI: String? {
        uti(withClass: kUTTagClassFilenameExtension)
    }
}
