import Cocoa

extension AppDelegate {
    static func relaunchApp() {
        let appURL = Bundle.main.bundleURL
        func shellQuoted(_ value: String) -> String {
            return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        // Launch a fresh instance after a short delay so the current process can terminate first.
        let task = Process()
        task.launchPath = "/bin/sh"
        let quotedAppPath = shellQuoted(appURL.path)
        task.arguments = [
            "-c",
            "sleep 0.7; /usr/bin/open -n -a \(quotedAppPath)",
        ]

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
            // Give the launcher a moment to start, then terminate current app
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.terminate(nil)
            }
        }
    }
}
