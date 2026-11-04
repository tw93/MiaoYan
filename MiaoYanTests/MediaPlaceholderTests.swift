import AppKit
import WebKit
import XCTest

@testable import MiaoYan

/// Media in the preview hold a visible box until they can show something:
/// a slow image used to leave blank paper and a video an empty player.
@available(macOS 12.0, *)
final class MediaPlaceholderTests: XCTestCase {
    private static let placeholder = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiaoYan Media Placeholder Tests \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    @MainActor
    func testMediaHoldATintedBoxUntilTheyCanShowSomething() async throws {
        let bundle = try XCTUnwrap(Bundle.main.url(forResource: "DownView", withExtension: "bundle"))
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 20, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = directory.appendingPathComponent("a.png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: png)

        let video = HtmlManager.deferredVideoTags("<video src=\"\(directory.appendingPathComponent("none.mp4").absoluteString)\" controls></video>")
        let page = """
            <!doctype html><html><head><meta charset="utf-8">
            <link rel="stylesheet" href="\(bundle.appendingPathComponent("css/base.css").absoluteString)">
            <link rel="stylesheet" href="\(bundle.appendingPathComponent("css/theme-light.css").absoluteString)">
            </head><body>
            <div class="markdown-body heti" id="write" style="width: 640px">
            <p><img id="unmeasured" class="lazy-image" data-measure="1" src="\(Self.placeholder)" data-src="http://127.0.0.1:9/x.png"></p>
            <p><img id="lazy" class="lazy-image" width="40" height="20" src="\(Self.placeholder)" data-src="\(png.absoluteString)"></p>
            \(video)
            </div>
            <script src="\(bundle.appendingPathComponent("js/common.js").absoluteString)"></script>
            <script>
            MiaoYanCommon.optimizeImages();
            (function() {
                var img = document.getElementById('unmeasured');
                var box = img.getBoundingClientRect();
                window.__before = {
                    reserved: img.classList.contains('media-reserve'),
                    width: box.width,
                    height: box.height,
                    tint: getComputedStyle(img).backgroundColor,
                    videoTint: getComputedStyle(document.querySelector('video')).backgroundColor
                };
            })();
            window.__ready = true;
            </script>
            </body></html>
            """
        let url = directory.appendingPathComponent("page.html")
        try page.write(to: url, atomically: true, encoding: .utf8)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 700, height: 900))
        webView.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))

        let state = """
            (function() {
                var lazy = document.getElementById('lazy');
                var video = document.querySelector('video');
                return {
                    ready: window.__ready === true && document.readyState === 'complete',
                    before: window.__before || null,
                    lazyLoaded: lazy.complete && lazy.naturalWidth === 40 && !lazy.classList.contains('lazy-image'),
                    lazyPending: lazy.classList.contains('media-pending'),
                    lazyTint: getComputedStyle(lazy).backgroundColor,
                    videoPreload: video.preload,
                    videoMarked: video.hasAttribute('data-preload')
                };
            })();
            """
        var result: [String: Any] = [:]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            result = (try? await webView.evaluateJavaScript(state) as? [String: Any]) ?? [:]
            if result["ready"] as? Bool == true, result["lazyLoaded"] as? Bool == true,
                result["lazyPending"] as? Bool == false, result["videoMarked"] as? Bool == false
            {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let transparent = "rgba(0, 0, 0, 0)"
        let before = try XCTUnwrap(result["before"] as? [String: Any], "\(result)")
        XCTAssertEqual(before["reserved"] as? Bool, true, "an unmeasured image alone in its paragraph reserves a box")
        XCTAssertEqual(before["width"] as? Double, 640)
        XCTAssertEqual(before["height"] as? Double, 360)
        XCTAssertNotEqual(before["tint"] as? String, transparent, "a lazy image shows a tinted box")
        XCTAssertNotEqual(before["videoTint"] as? String, transparent, "a video shows a tinted box")

        XCTAssertEqual(result["lazyLoaded"] as? Bool, true, "\(result)")
        XCTAssertEqual(result["lazyPending"] as? Bool, false, "\(result)")
        XCTAssertEqual(result["lazyTint"] as? String, transparent, "the tint goes once the image has loaded")
        XCTAssertEqual(result["videoMarked"] as? Bool, false, "\(result)")
        XCTAssertEqual(result["videoPreload"] as? String, "metadata", "the video loads its first frame after the page")
    }
}
