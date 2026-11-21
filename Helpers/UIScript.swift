#if DEBUG || MIAOYAN_SCRIPT
    import AppKit
    import Carbon.HIToolbox
    import WebKit

    /// Drives the app from a line-per-command script and captures the window
    /// without the mouse, the keyboard focus or the screen. Compiled into Debug
    /// builds, and into a Release build only when it is built with the
    /// `MIAOYAN_SCRIPT` condition for timing (`scripts/ui_scripts/README.md`);
    /// shipped builds never hold it. A build launched with `-MiaoYanScript <file> -MiaoYanShots <folder>` (plus
    /// `-storageUrl <scratch library>`, never the real one) runs the script once
    /// a window holds the editor, then quits. `scripts/ui_script.py` launches it
    /// in the background on a copy of a library and compares two builds'
    /// captures pixel by pixel. Taken from quiet-md's harness (2026-11-21).
    ///
    /// Commands, one per line, `#` starting a comment:
    ///   wait <ms>                 let the run loop turn
    ///   open <title>              open a note by title, as a wikilink does
    ///   type <text>               insert text at the selection
    ///   key <name>                return, tab, shift-return, shift-tab, backspace, escape
    ///   select <location> <length>, caret start|end
    ///   menu <selector>           send a menu action, e.g. togglePreview:
    ///   resize <width> <height>   the window's content size
    ///   scroll <points>           scroll the editor down (or up, negative)
    ///   shot <name>               <shots>/<name>.png, the preview's web view included
    ///   bench <n> <command>       run a command n times, drawing after each, and log p50/p95/max
    ///   quit
    @MainActor
    enum UIScript {
        static func startIfRequested() {
            guard let path = UserDefaults.standard.string(forKey: "MiaoYanScript") else { return }
            let shots = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "MiaoYanShots") ?? NSTemporaryDirectory())
            try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
            let runner = Runner(script: URL(fileURLWithPath: path), shots: shots)
            Task { @MainActor in await runner.run() }
        }

        @MainActor
        final class Runner {
            let script: URL
            let shots: URL
            private var log: [String] = []

            init(script: URL, shots: URL) {
                self.script = script
                self.shots = shots
            }

            func run() async {
                defer { finish() }
                guard let text = try? String(contentsOf: script, encoding: .utf8) else {
                    record("error cannot read \(script.path)")
                    return
                }
                // The window opens, loads the library and fades in; wait for an
                // editor in it, up to 20 seconds.
                for _ in 0..<200 where editor == nil { await pause(100) }
                guard let window = editor?.window else {
                    record("error no editor window")
                    return
                }
                window.orderBack(nil)
                for raw in text.components(separatedBy: .newlines) {
                    let line = raw.trimmingCharacters(in: .whitespaces)
                    guard !line.isEmpty, !line.hasPrefix("#") else { continue }
                    record("> \(line)")
                    if line == "quit" { return }
                    await perform(line)
                }
            }

            private var window: NSWindow? { editor?.window }

            /// The main window's editor, in the storyboard window or the shell.
            private var editor: EditTextView? {
                for window in NSApp.windows where window.isVisible || window.alphaValue == 0 {
                    if let found = Self.find(EditTextView.self, in: window.contentView) { return found }
                }
                return nil
            }

            private static func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
                guard let view else { return nil }
                if let match = view as? T { return match }
                for child in view.subviews {
                    if let match = find(type, in: child) { return match }
                }
                return nil
            }

            private static func all<T: NSView>(_ type: T.Type, in view: NSView?) -> [T] {
                guard let view else { return [] }
                return (view as? T).map { [$0] } ?? [] + view.subviews.flatMap { all(type, in: $0) }
            }

            private func perform(_ line: String) async {
                let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
                let command = parts[0]
                let argument = parts.count > 1 ? parts[1] : ""
                switch command {
                case "wait":
                    await pause(Int(argument) ?? 0)
                case "open":
                    let encoded = argument.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? argument
                    if let url = URL(string: "miaoyan://goto/\(encoded)") {
                        (NSApp.delegate as? AppDelegate)?.RouteMiaoYanGoto(url)
                    }
                    await pause(400)
                case "type":
                    guard let editor else { return record("error no editor") }
                    editor.insertText(argument, replacementRange: editor.selectedRange())
                case "key":
                    key(argument)
                case "select":
                    let numbers = argument.split(separator: " ").compactMap { Int($0) }
                    guard let editor, numbers.count == 2 else { return record("error select needs a location and a length") }
                    let length = (editor.string as NSString).length
                    let start = min(numbers[0], length)
                    editor.setSelectedRange(NSRange(location: start, length: min(numbers[1], length - start)))
                case "caret":
                    guard let editor else { return }
                    let at = argument == "start" ? 0 : (editor.string as NSString).length
                    editor.setSelectedRange(NSRange(location: at, length: 0))
                case "menu":
                    menu(argument)
                case "resize":
                    let numbers = argument.split(separator: " ").compactMap { Double($0) }
                    guard numbers.count == 2, let window else { return record("error resize needs a width and a height") }
                    window.setContentSize(NSSize(width: numbers[0], height: numbers[1]))
                    await pause(200)
                case "scroll":
                    guard let clip = editor?.enclosingScrollView?.contentView, let points = Double(argument) else {
                        return record("error scroll needs points and an editor")
                    }
                    let limit = max(0, (clip.documentView?.frame.height ?? 0) - clip.bounds.height)
                    clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: min(limit, max(0, clip.bounds.origin.y + points))))
                    editor?.enclosingScrollView?.reflectScrolledClipView(clip)
                case "shot":
                    await shot(argument)
                case "bench":
                    await bench(argument)
                default:
                    record("error unknown command \(command)")
                }
            }

            private func key(_ name: String) {
                guard let editor else { return record("error no editor") }
                if name == "backspace" {
                    editor.deleteBackward(nil)
                    return
                }
                let shift = name.hasPrefix("shift-")
                let codes: [String: (Int, String)] = ["return": (kVK_Return, "\r"), "tab": (kVK_Tab, "\t"), "escape": (kVK_Escape, "\u{1B}")]
                guard let (code, characters) = codes[shift ? String(name.dropFirst(6)) : name],
                    let event = NSEvent.keyEvent(
                        with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: editor.window?.windowNumber ?? 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                        isARepeat: false, keyCode: UInt16(code))
                else { return record("error unknown key \(name)") }
                editor.keyDown(with: event)
            }

            /// Sends a menu action to the first object along the editor's chain
            /// that takes it, without needing the window to be key.
            private func menu(_ name: String) {
                let action = Selector(name)
                let candidates: [AnyObject?] = [
                    editor, editor?.window?.firstResponder, window?.contentViewController, window?.windowController,
                    window?.delegate as AnyObject?, NSApp.delegate as AnyObject?,
                ]
                for case let target? in candidates where target.responds(to: action) {
                    NSApp.sendAction(action, to: target, from: nil)
                    return
                }
                record("error nobody takes \(name)")
            }

            private func shot(_ name: String) async {
                guard let view = window?.contentView else { return record("error no window") }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return record("error no bitmap") }
                view.cacheDisplay(in: view.bounds, to: rep)
                // A web view draws in another process, so the cached bitmap
                // holds it blank: its own snapshot goes over that spot.
                for webView in Self.all(WKWebView.self, in: view) where !webView.isHiddenOrHasHiddenAncestor && webView.bounds.width > 0 {
                    guard let image = try? await webView.takeSnapshot(configuration: nil) else { continue }
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                    image.draw(in: webView.convert(webView.bounds, to: view))
                    NSGraphicsContext.restoreGraphicsState()
                }
                let url = shots.appendingPathComponent(name + ".png")
                do {
                    try rep.representation(using: .png, properties: [:])?.write(to: url)
                } catch {
                    record("error \(error.localizedDescription)")
                }
            }

            private func bench(_ argument: String) async {
                let parts = argument.split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count == 2, let times = Int(parts[0]), times > 0 else { return record("error bench needs a count and a command") }
                var samples: [Double] = []
                for _ in 0..<times {
                    let start = CFAbsoluteTimeGetCurrent()
                    await perform(parts[1])
                    window?.contentView?.layoutSubtreeIfNeeded()
                    window?.displayIfNeeded()
                    samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
                }
                samples.sort()
                func at(_ q: Double) -> Double { samples[min(samples.count - 1, Int(Double(samples.count - 1) * q + 0.5))] }
                record(String(format: "bench \"%@\" x%d: p50 %.2f p95 %.2f max %.2f ms", parts[1], times, at(0.5), at(0.95), samples.last ?? 0))
            }

            private func pause(_ milliseconds: Int) async {
                try? await Task.sleep(nanoseconds: UInt64(max(0, milliseconds)) * 1_000_000)
            }

            private func record(_ line: String) {
                log.append(line)
                print("[UIScript] \(line)")
            }

            private func finish() {
                let text = log.joined(separator: "\n") + "\n"
                try? text.write(to: shots.appendingPathComponent("script.log"), atomically: true, encoding: .utf8)
                // Quitting through the app saves the notes as a normal quit does.
                NSApp.terminate(nil)
            }
        }
    }
#endif
