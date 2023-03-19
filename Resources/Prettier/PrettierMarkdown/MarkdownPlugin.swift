import Foundation

public struct MarkdownPlugin: Plugin {
    public var fileURL: URL
    public init() {
        let path = Bundle.main.path(forResource: "Prettier", ofType: ".bundle")
        let url = NSURL.fileURL(withPath: path!)
        let bundle = Bundle(url: url)
        fileURL = bundle!.url(forResource: "parser-markdown", withExtension: "js")!
    }
}
