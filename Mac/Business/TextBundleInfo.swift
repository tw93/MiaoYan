import Foundation

struct TextBundleInfo: Decodable {
    let version: Int
    let type: String
    let flatExtension: String?
}
