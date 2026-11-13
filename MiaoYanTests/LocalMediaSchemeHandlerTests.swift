import AppKit
import WebKit
import XCTest

@testable import MiaoYan

/// The preview reads local images and videos through the app (#578): the
/// App Store build is sandboxed, its page could not read the notes folder
/// through `file://`, and every local image came out blank with no
/// "image not found".
final class LocalMediaSchemeHandlerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiaoYan Local Media \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func png(width: Int, height: Int, at url: URL) throws {
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    /// The page may read only its own folder, as the sandboxed build's page
    /// in effect could, and the note's image sits elsewhere. The image the
    /// preview pipeline writes still loads; it did not through `file://`.
    @MainActor
    func testANoteImageOutsideThePageFolderLoads() async throws {
        let notes = directory.appendingPathComponent("Notes #1", isDirectory: true)
        try png(width: 40, height: 20, at: notes.appendingPathComponent("i/a b.png"))
        let html = try XCTUnwrap(renderMarkdownHTML(markdown: "![](/i/a%20b.png)", useGithubLineBreak: false))
        let body = HtmlManager.processImages(in: html, imagesStorage: notes)
        XCTAssertTrue(body.contains("src=\"\(HtmlManager.localMediaScheme)://"), body)

        let pageFolder = directory.appendingPathComponent("page", isDirectory: true)
        try FileManager.default.createDirectory(at: pageFolder, withIntermediateDirectories: true)
        let page = pageFolder.appendingPathComponent("index.html")
        try "<!doctype html><html><body>\(body)</body></html>".write(to: page, atomically: true, encoding: .utf8)

        let configuration = WKWebViewConfiguration()
        LocalMediaSchemeHandler.install(on: configuration)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
        webView.loadFileURL(page, allowingReadAccessTo: pageFolder)

        var width = 0
        for _ in 0..<100 {
            try await Task.sleep(nanoseconds: 50_000_000)
            let state = "(() => { const i = document.images[0]; return i && i.complete ? i.naturalWidth : -1 })()"
            width = (try? await webView.evaluateJavaScript(state) as? Int) ?? -1
            if width >= 0 { break }
        }
        XCTAssertEqual(width, 40, "the image loaded through the app's scheme")
    }

    /// With read access to `/`, a sandboxed build's network process was
    /// refused the preview page itself and every note came out blank. Both
    /// web views read only the page's folder.
    func testNoWebViewAsksToReadTheWholeDisk() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for file in ["Views/MPreviewView.swift", "Helpers/PdfExportController.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            XCTAssertTrue(source.contains("loadFileURL("), file)
            XCTAssertFalse(source.contains("allowingReadAccessTo: URL(fileURLWithPath: \"/\")"), file)
        }
    }

    func testAWholeFileIsServedWithItsType() async throws {
        let file = directory.appendingPathComponent("a.png")
        try png(width: 4, height: 2, at: file)
        let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int)

        let reply = await LocalMediaSchemeHandler.reply(to: URL(string: HtmlManager.localMediaURL(forPath: file.path)), range: nil)

        guard case .file(let status, let headers, let data) = reply else { return XCTFail("\(reply)") }
        XCTAssertEqual(status, 200)
        XCTAssertEqual(headers["Content-Type"], "image/png")
        XCTAssertEqual(data.count, size)
    }

    func testARangeIsServedAsPartialContent() async throws {
        let file = directory.appendingPathComponent("clip.mp4")
        try Data((0..<100).map { UInt8($0) }).write(to: file)
        let url = URL(string: HtmlManager.localMediaURL(forPath: file.path))

        let reply = await LocalMediaSchemeHandler.reply(to: url, range: "bytes=10-19")
        guard case .file(let status, let headers, let data) = reply else { return XCTFail("\(reply)") }
        XCTAssertEqual(status, 206)
        XCTAssertEqual(headers["Content-Range"], "bytes 10-19/100")
        XCTAssertEqual(headers["Content-Type"], "video/mp4")
        XCTAssertEqual(Array(data), Array(10..<20).map { UInt8($0) })

        let past = await LocalMediaSchemeHandler.reply(to: url, range: "bytes=200-")
        guard case .file(let pastStatus, let pastHeaders, _) = past else { return XCTFail("\(past)") }
        XCTAssertEqual(pastStatus, 416)
        XCTAssertEqual(pastHeaders["Content-Range"], "bytes */100")
    }

    func testRangeHeaderForms() {
        XCTAssertEqual(LocalMediaSchemeHandler.byteRange("bytes=0-1", size: 100), 0..<2)
        XCTAssertEqual(LocalMediaSchemeHandler.byteRange("bytes=90-", size: 100), 90..<100)
        XCTAssertEqual(LocalMediaSchemeHandler.byteRange("bytes=-10", size: 100), 90..<100)
        XCTAssertEqual(LocalMediaSchemeHandler.byteRange("bytes=-500", size: 100), 0..<100)
        XCTAssertEqual(LocalMediaSchemeHandler.byteRange("bytes=50-5000", size: 100), 50..<100)
        XCTAssertNil(LocalMediaSchemeHandler.byteRange("bytes=100-", size: 100))
        XCTAssertNil(LocalMediaSchemeHandler.byteRange("bytes=20-10", size: 100))
        XCTAssertNil(LocalMediaSchemeHandler.byteRange("items=0-1", size: 100))
    }

    /// Markup in a note cannot read an arbitrary file through the scheme.
    func testOnlyMediaFilesAreServed() async throws {
        let text = directory.appendingPathComponent("secret.txt")
        try "secret".write(to: text, atomically: true, encoding: .utf8)
        let missing = directory.appendingPathComponent("gone.png")

        let refused = await LocalMediaSchemeHandler.reply(to: URL(string: HtmlManager.localMediaURL(forPath: text.path)), range: nil)
        XCTAssertEqual(refused, .failure(.noPermissionsToReadFile))
        let gone = await LocalMediaSchemeHandler.reply(to: URL(string: HtmlManager.localMediaURL(forPath: missing.path)), range: nil)
        XCTAssertEqual(gone, .failure(.fileDoesNotExist))
        let other = await LocalMediaSchemeHandler.reply(to: URL(fileURLWithPath: text.path), range: nil)
        XCTAssertEqual(other, .failure(.unsupportedURL))
    }

    func testTheAddressKeepsEveryCharacterOfThePath() throws {
        for path in ["/a/Mobile Documents/i/x#1?.png", "/a/笔记/i/图 1.jpg", "/a/100%.png", "/a/Tom's & Jerry.png"] {
            let url = try XCTUnwrap(URL(string: HtmlManager.localMediaURL(forPath: path)))
            XCTAssertEqual(url.scheme, HtmlManager.localMediaScheme)
            XCTAssertEqual(url.path, path)
        }
    }
}
