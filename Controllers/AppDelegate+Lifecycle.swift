import Cocoa

extension AppDelegate {
    static func relaunchApp() {
        let appURL = Bundle.main.bundleURL
        // Prefer robust shell launch to avoid API quirks and ensure new instance
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", appURL.path]

        DispatchQueue.main.async {
            // Try to close preference windows or sheets to avoid edge-case crashes
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.prefsWindowController?.close()
            }
            for window in NSApp.windows {
                if let sheet = window.attachedSheet {
                    window.endSheet(sheet)
                }
            }
            try? task.run()
            // Give the launcher a moment to spawn, then terminate current app
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NSApp.terminate(nil)
            }
        }
    }
}
