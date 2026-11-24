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

    /// A weekly issue's cover is a raw `<img src=… width="800" />` on its own
    /// lines, which cmark leaves outside any paragraph, so it took no reserved
    /// box and its 1px placeholder held it as tall as it is wide: every cover
    /// opened as a square and jumped to its real height (maintainer,
    /// 2026-11-22). It now holds the 16:9 box an image alone in a paragraph
    /// does; one beside text stays inline.
    @MainActor
    func testARawImageOnItsOwnLinesReservesTheBoxAParagraphImageDoes() async throws {
        let bundle = try XCTUnwrap(Bundle.main.url(forResource: "DownView", withExtension: "bundle"))
        let page = """
            <!doctype html><html><head><meta charset="utf-8">
            <link rel="stylesheet" href="\(bundle.appendingPathComponent("css/base.css").absoluteString)">
            <link rel="stylesheet" href="\(bundle.appendingPathComponent("css/theme-light.css").absoluteString)">
            </head><body>
            <div class="markdown-body heti" id="write" style="width: 640px">
            <img id="cover" class="lazy-image" data-measure="1" width="800" src="\(Self.placeholder)" data-src="http://127.0.0.1:9/cover.jpg" />
            <p><small>Caption.</small></p>
            <div>Text <img id="inline" class="lazy-image" data-measure="1" width="200" src="\(Self.placeholder)" data-src="http://127.0.0.1:9/i.png"> more.</div>
            <div align="center">
            <img id="pairA" class="lazy-image" data-measure="1" src="\(Self.placeholder)" data-src="http://127.0.0.1:9/a.png">
            <img id="pairB" class="lazy-image" data-measure="1" src="\(Self.placeholder)" data-src="http://127.0.0.1:9/b.png">
            </div>
            </div>
            <script src="\(bundle.appendingPathComponent("js/common.js").absoluteString)"></script>
            <script>
            MiaoYanCommon.optimizeImages();
            (function() {
                var cover = document.getElementById('cover');
                var box = cover.getBoundingClientRect();
                window.__state = {
                    reserved: cover.classList.contains('media-reserve'),
                    width: box.width,
                    height: box.height,
                    inlineReserved: document.getElementById('inline').classList.contains('media-reserve'),
                    pairReserved: ['pairA', 'pairB'].some(function (id) { return document.getElementById(id).classList.contains('media-reserve'); })
                };
            })();
            </script>
            </body></html>
            """
        let url = directory.appendingPathComponent("cover.html")
        try page.write(to: url, atomically: true, encoding: .utf8)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 700, height: 900))
        webView.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        var state: [String: Any] = [:]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let read = try? await webView.evaluateJavaScript("window.__state || null") as? [String: Any] {
                state = read
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(state["reserved"] as? Bool, true, "\(state)")
        XCTAssertEqual(state["width"] as? Double, 640)
        XCTAssertEqual(state["height"] as? Double, 360, "16:9, not a square")
        XCTAssertEqual(state["inlineReserved"] as? Bool, false, "an image beside text stays inline")
        XCTAssertEqual(state["pairReserved"] as? Bool, false, "two images on consecutive lines sit side by side")
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
            <table><tr><td><img id="unpainted" data-measure="1" width="400" data-src="http://127.0.0.1:9/w.png"></td></tr></table>
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
                    spinner: pending.backgroundImage,
                    reserved: img.classList.contains('media-reserve'),
                    width: box.width,
                    height: box.height,
                    tint: getComputedStyle(img).backgroundColor,
                    tintAnimation: getComputedStyle(img).animationName,
                    tintDelay: getComputedStyle(img).animationDelay,
                    videoTint: getComputedStyle(document.querySelector('video')).backgroundColor
                };
                // The answer lands while the reader is further down. A test
                // webview has no window and never anchors the scroll itself,
                // so this checks the page's own compensation, which older
                // WebKit (CI's macOS 15) relies on; newer WebKit anchors too,
                // and applyImageSize only adds what it did not. The text is
                // read in the same turn, before a failed image above it can
                // fold and move it for a reason of its own.
                // The second table image has nothing painted yet, as a lazy
                // placeholder can be on older WebKit: it is 0 tall in a row
                // still one line high, so the row grows less than the image.
                window.scrollTo(0, 1500);
                var markerTop = marker.getBoundingClientRect().top;
                MiaoYanCommon.applyImageSize('http://127.0.0.1:9/y.png', 1536, 2048);
                var sized = widthOnly.getBoundingClientRect();
                window.__before.sizedWidth = sized.width;
                window.__before.sizedHeight = sized.height;
                window.__before.moved = marker.getBoundingClientRect().top - markerTop;
                markerTop = marker.getBoundingClientRect().top;
                MiaoYanCommon.applyImageSize('http://127.0.0.1:9/w.png', 1536, 2048);
                window.__before.movedInRow = marker.getBoundingClientRect().top - markerTop;
                window.__before.unpaintedHeight = document.getElementById('unpainted').getBoundingClientRect().height;
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
        // The tint waits 0.2s, so an image WebKit's cache hands over a few
        // frames after the page never flashes grey (maintainer 2026-11-24).
        XCTAssertEqual(before["tint"] as? String, transparent, "no tint at once: \(before)")
        XCTAssertEqual(before["tintAnimation"] as? String, "media-tint", "a lazy image takes the tint later")
        XCTAssertEqual(before["tintDelay"] as? String, "0.2s")
        XCTAssertNotEqual(before["videoTint"] as? String, transparent, "a video shows a tinted box")
        XCTAssertEqual(before["sizedWidth"] as? Double, 400)
        XCTAssertEqual(try XCTUnwrap(before["sizedHeight"] as? Double), 533.33, accuracy: 0.5, "the header's size gives it the picture's ratio")
        XCTAssertEqual(before["styledHeight"] as? Double, 200, "a ratio the note set is kept")
        // How tall the box was before the answer depends on the engine: the
        // 1px placeholder had decoded to a square on macOS 27's WebKit and
        // not yet on CI's macOS 15. What must hold is the text in view.
        XCTAssertEqual(try XCTUnwrap(before["moved"] as? Double), 0, accuracy: 1, "a box above the view grows without moving the text")
        XCTAssertEqual(try XCTUnwrap(before["unpaintedHeight"] as? Double), 533.33, accuracy: 0.5, "an image with nothing painted takes the answer too")
        XCTAssertEqual(try XCTUnwrap(before["movedInRow"] as? Double), 0, accuracy: 1, "a row that grows less than its image still leaves the text in place")
        // Under Reduce Motion the pulse is off by design.
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertEqual(
                before["pulse"] as? String, "media-tint, media-pulse, media-spinner",
                "a loading image takes the tint, breathes it and shows a turning arc")
            XCTAssertEqual(before["pulseDelay"] as? String, "0.2s, 0.45s, 0.45s", "after a moment, so a quick one never flashes either")
            XCTAssertTrue((before["spinner"] as? String)?.contains("animateTransform") == true, "the arc turns: \(before)")
        }

        XCTAssertEqual(result["lazyLoaded"] as? Bool, true, "\(result)")
        XCTAssertEqual(result["lazyPending"] as? Bool, false, "\(result)")
        XCTAssertEqual(result["lazyTint"] as? String, transparent, "the tint goes once the image has loaded")
        XCTAssertEqual(result["videoMarked"] as? Bool, false, "\(result)")
        XCTAssertEqual(result["videoPreload"] as? String, "metadata", "the video loads its first frame after the page")
    }

    /// A live update rendered the note's media only when it had an image, so
    /// a note with a local video and no image swapped in the raw tag on its
    /// first edit, its path relative to the cache page, and lost the player.
    func testALiveUpdateResolvesALocalVideoInANoteWithoutImages() throws {
        try Data([0, 0, 0, 0]).write(to: directory.appendingPathComponent("clip.mp4"))
        let html = try XCTUnwrap(
            MPreviewView.previewHTML(
                markdown: "Text.\n\n<video src=\"clip.mp4\" controls></video>\n", useGithubLineBreak: false, imagesStorage: directory))
        XCTAssertTrue(html.contains("src=\"\(HtmlManager.localMediaURL(forPath: directory.appendingPathComponent("clip.mp4").path))\""), html)
        XCTAssertTrue(html.contains("data-preload=\"metadata\""), html)

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Views/MPreviewView.swift"), encoding: .utf8)
        XCTAssertNil(source.range(of: "contains(\"<img\")"), "no path skips media for notes without images")
        XCTAssertEqual(source.components(separatedBy: "Self.previewHTML(markdown:").count - 1, 3, "load, in-place switch and live update")
    }

    /// A YouTube iframe framed the player straight from the local page, which
    /// YouTube answers with Error 153 (no Referer), and a `watch` address is
    /// never framed at all. It now goes through the relay on cdn.miaoyan.app,
    /// which ships in the bundle at the same path.
    func testYouTubeFramesGoThroughTheRelay() throws {
        let markdown = #"<div class="video-container" style="margin-top:-12px"><iframe src="https://www.youtube.com/watch?v=FCKJL-mTncY&t=90s" width="800" height="450" allowfullscreen></iframe></div>"#
        let html = try XCTUnwrap(MPreviewView.previewHTML(markdown: markdown + "\n\n```\n<iframe src=\"https://youtu.be/FCKJL-mTncY\"></iframe>\n```", useGithubLineBreak: false, imagesStorage: directory))
        XCTAssertTrue(html.contains(#"<iframe src="https://cdn.miaoyan.app/Resources/DownView.bundle/youtube.html?v=FCKJL-mTncY&amp;start=90" width="800""#), html)
        XCTAssertTrue(html.contains("&lt;iframe src=&quot;https://youtu.be/FCKJL-mTncY"), "a frame in a code block is text")

        for (address, start) in [
            ("https://youtu.be/FCKJL-mTncY?t=1m5s", 65),
            ("//www.youtube-nocookie.com/embed/FCKJL-mTncY?start=12", 12),
            ("https://m.youtube.com/shorts/FCKJL-mTncY", nil),
            ("https://www.youtube.com/watch?feature=share&amp;v=FCKJL-mTncY", nil),
        ] as [(String, Int?)] {
            let video = try XCTUnwrap(PreviewMedia.youTubeVideo(address), address)
            XCTAssertEqual(video.id, "FCKJL-mTncY", address)
            XCTAssertEqual(video.start, start, address)
        }
        // A start this long overflowed the sum and crashed the render.
        for address in ["https://youtu.be/FCKJL-mTncY?t=9999999999999999h", "https://youtu.be/FCKJL-mTncY?t=99999999999999999999s"] {
            XCTAssertNil(try XCTUnwrap(PreviewMedia.youTubeVideo(address)).start, address)
        }
        for address in [
            "https://www.youtube.com/watch?v=short", "https://player.bilibili.com/player.html?bvid=BV1", "https://example.com/embed/FCKJL-mTncY",
            "https://www.youtube.com/embed/videoseries?list=PL1", "https://www.youtube.com/embed/live_stream?channel=UC1",
        ] {
            XCTAssertNil(PreviewMedia.youTubeVideo(address), address)
        }
        let other = #"<iframe src="https://player.bilibili.com/player.html?bvid=BV1"></iframe>"#
        XCTAssertEqual(PreviewMedia.relayedYouTubeFrames(other), other)

        let bundle = try XCTUnwrap(Bundle.main.url(forResource: "DownView", withExtension: "bundle"))
        let relay = try String(contentsOf: bundle.appendingPathComponent("youtube.html"), encoding: .utf8)
        XCTAssertTrue(PreviewMedia.youTubeRelay.hasSuffix("/DownView.bundle/youtube.html"))
        XCTAssertTrue(relay.contains("https://www.youtube-nocookie.com/embed/"))
    }

    /// Slides render the raw markdown in the page, so their frames go through
    /// the relay from `js/youtube-relay.js`, which must read an address the
    /// way `PreviewMedia.youTubeVideo` does or a slide and the preview of the
    /// same note play different things.
    @MainActor
    func testTheSlidesRelayReadsAddressesAsThePreviewDoes() async throws {
        let bundle = try XCTUnwrap(Bundle.main.url(forResource: "DownView", withExtension: "bundle"))
        let script = try String(contentsOf: bundle.appendingPathComponent("js/youtube-relay.js"), encoding: .utf8)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        webView.loadHTMLString("<html><body><script>\(script)</script></body></html>", baseURL: nil)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, (try? await webView.evaluateJavaScript("typeof MiaoYanYouTubeRelay === 'object'") as? Bool) != true {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let addresses = [
            "https://www.youtube.com/watch?v=FCKJL-mTncY&t=90s", "https://youtu.be/FCKJL-mTncY?t=1m5s",
            "//www.youtube-nocookie.com/embed/FCKJL-mTncY?start=12", "https://m.youtube.com/shorts/FCKJL-mTncY",
            "https://www.youtube.com/watch?feature=share&amp;v=FCKJL-mTncY", "https://www.youtube.com/live/FCKJL-mTncY?t=1h2m3s",
            "https://youtube.com/v/FCKJL-mTncY?start=0", "https://youtu.be/FCKJL-mTncY?t=-5", "https://youtu.be/FCKJL-mTncY?t=90x",
            "https://youtu.be/FCKJL-mTncY?t=9999999999999999h", "https://www.youtube.com/watch?v=short",
            "https://player.bilibili.com/player.html?bvid=BV1", "https://example.com/embed/FCKJL-mTncY",
            "https://www.youtube.com/embed/videoseries?list=PL1", "https://www.youtube.com/embed/live_stream?channel=UC1",
            "youtube.com/embed/FCKJL-mTncY", "  https://www.youtube.com/embed/FCKJL-mTncY  ", "",
        ]
        for address in addresses {
            let expected = PreviewMedia.youTubeVideo(address).map { video in
                "\(PreviewMedia.youTubeRelay)?v=\(video.id)" + (video.start.map { "&start=\($0)" } ?? "")
            }
            let call = "MiaoYanYouTubeRelay.relayed(\(HtmlManager.jsStringLiteral(address)))"
            let actual = try await webView.evaluateJavaScript("\(call) || ''") as? String
            XCTAssertEqual(actual, expected ?? "", address)
        }
        let relay = try await webView.evaluateJavaScript("MiaoYanYouTubeRelay.relay") as? String
        XCTAssertEqual(relay, PreviewMedia.youTubeRelay)
    }
}
