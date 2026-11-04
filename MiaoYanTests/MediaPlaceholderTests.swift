import AppKit
import WebKit
import XCTest

@testable import MiaoYan

/// Media in the preview hold a visible box until they can show something:
/// a slow image used to leave blank paper and a video an empty player. A
/// width-only remote image takes its ratio from the header the app read,
/// and one still loading after a moment breathes its tint.
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

        let video = PreviewMedia.deferredVideoTags("<video src=\"\(directory.appendingPathComponent("none.mp4").absoluteString)\" controls></video>")
        let page = """
            <!doctype html><html><head><meta charset="utf-8">
            <link rel="stylesheet" href="\(bundle.appendingPathComponent("css/base.css").absoluteString)">
            <link rel="stylesheet" href="\(bundle.appendingPathComponent("css/theme-light.css").absoluteString)">
            </head><body>
            <div class="markdown-body heti" id="write" style="width: 640px">
            <p><img id="unmeasured" class="lazy-image" data-measure="1" src="\(Self.placeholder)" data-src="http://127.0.0.1:9/x.png"></p>
            <p><img id="lazy" class="lazy-image" width="40" height="20" src="\(Self.placeholder)" data-src="\(png.absoluteString)"></p>
            <table><tr><td><img id="widthOnly" class="lazy-image" data-measure="1" width="400" src="\(Self.placeholder)" data-src="http://127.0.0.1:9/y.png"></td></tr></table>
            <p><img id="styled" class="lazy-image" data-measure="1" width="200" style="aspect-ratio: 1 / 1" src="\(Self.placeholder)" data-src="http://127.0.0.1:9/z.png"> a</p>
            <p><img id="pending" class="media-pending" width="40" height="20" src="\(Self.placeholder)"></p>
            \(video)
            <div style="height: 3000px"><p id="marker" style="margin: 1800px 0 0">m</p></div>
            </div>
            <script src="\(bundle.appendingPathComponent("js/common.js").absoluteString)"></script>
            <script>
            MiaoYanCommon.optimizeImages();
            (function() {
                var img = document.getElementById('unmeasured');
                var box = img.getBoundingClientRect();
                var widthOnly = document.getElementById('widthOnly');
                var marker = document.getElementById('marker');
                MiaoYanCommon.applyImageSize('http://127.0.0.1:9/z.png', 1536, 2048);
                var styled = document.getElementById('styled').getBoundingClientRect();
                var pending = getComputedStyle(document.getElementById('pending'));
                window.__before = {
                    styledHeight: styled.height,
                    pulse: pending.animationName,
                    pulseDelay: pending.animationDelay,
                    reserved: img.classList.contains('media-reserve'),
                    width: box.width,
                    height: box.height,
                    tint: getComputedStyle(img).backgroundColor,
                    videoTint: getComputedStyle(document.querySelector('video')).backgroundColor
                };
                // The answer lands while the reader is further down. A test
                // webview has no window and never anchors the scroll itself,
                // so this checks the page's own compensation, which older
                // WebKit (CI's macOS 15) relies on; newer WebKit anchors too,
                // and applyImageSize only adds what it did not. The text is
                // read in the same turn, before a failed image above it can
                // fold and move it for a reason of its own.
                window.scrollTo(0, 1500);
                var markerTop = marker.getBoundingClientRect().top;
                MiaoYanCommon.applyImageSize('http://127.0.0.1:9/y.png', 1536, 2048);
                var sized = widthOnly.getBoundingClientRect();
                window.__before.sizedWidth = sized.width;
                window.__before.sizedHeight = sized.height;
                window.__before.moved = marker.getBoundingClientRect().top - markerTop;
                window.scrollTo(0, 0);
                window.__ready = true;
            })();
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
        XCTAssertEqual(before["sizedWidth"] as? Double, 400)
        XCTAssertEqual(try XCTUnwrap(before["sizedHeight"] as? Double), 533.33, accuracy: 0.5, "the header's size gives it the picture's ratio")
        XCTAssertEqual(before["styledHeight"] as? Double, 200, "a ratio the note set is kept")
        // How tall the box was before the answer depends on the engine: the
        // 1px placeholder had decoded to a square on macOS 27's WebKit and
        // not yet on CI's macOS 15. What must hold is the text in view.
        XCTAssertEqual(try XCTUnwrap(before["moved"] as? Double), 0, accuracy: 1, "a box above the view grows without moving the text")
        // Under Reduce Motion the pulse is off by design.
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertEqual(before["pulse"] as? String, "media-pulse", "a loading image breathes its tint")
            XCTAssertEqual(before["pulseDelay"] as? String, "0.45s", "after a moment, so a quick one never flashes it")
        }

        XCTAssertEqual(result["lazyLoaded"] as? Bool, true, "\(result)")
        XCTAssertEqual(result["lazyPending"] as? Bool, false, "\(result)")
        XCTAssertEqual(result["lazyTint"] as? String, transparent, "the tint goes once the image has loaded")
        XCTAssertEqual(result["videoMarked"] as? Bool, false, "\(result)")
        XCTAssertEqual(result["videoPreload"] as? String, "metadata", "the video loads its first frame after the page")
    }
}
