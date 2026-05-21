import Foundation
import os.log

/// Application-level diagnostics sink.
///
/// Release builds previously dropped every `AppDelegate.trackError` call on the
/// floor (the old `#if DEBUG print` was a no-op outside Xcode). When users
/// reported "my note vanished" there was no breadcrumb to follow. This sink
/// fixes that without pulling in a third-party crash SDK: structured os_log
/// for live `log show` inspection plus a JSON-line ring buffer at
/// `~/Library/Logs/MiaoYan/diagnostics.log` that users can attach to feedback.
@MainActor
enum Diagnostics {

    private static let subsystem = AppIdentifier.bundleID
    private static let log = OSLog(subsystem: subsystem, category: "diagnostics")

    /// Sandbox-aware log path under the user's Library/Logs (mapped into the
    /// container for sandboxed builds). Returns nil only if the directory
    /// cannot be created at all, in which case callers degrade to os_log.
    private static var logFileURL: URL? {
        let fm = FileManager.default
        guard let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = library.appendingPathComponent("Logs/MiaoYan")
        guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        return dir.appendingPathComponent("diagnostics.log")
    }

    /// Cap the ring buffer at 50 lines. Picked to fit a typical pasteable
    /// diagnostics block without truncating a fresh incident, and small enough
    /// that the file never grows past ~50 KB.
    private static let ringBufferLimit = 50

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func record(error: Error, context: String) {
        let nsError = error as NSError
        let payload: [String: String] = [
            "ts": isoFormatter.string(from: Date()),
            "ctx": context,
            "domain": nsError.domain,
            "code": String(nsError.code),
            "desc": nsError.localizedDescription,
        ]

        os_log(
            "%{public}@: %{public}@ (%{public}@#%{public}d)",
            log: log,
            type: .fault,
            context,
            nsError.localizedDescription,
            nsError.domain,
            nsError.code)

        appendRingBufferLine(payload)
    }

    private static func appendRingBufferLine(_ payload: [String: String]) {
        guard let logFileURL,
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
            var line = String(data: data, encoding: .utf8)
        else {
            return
        }
        line.append("\n")

        let fm = FileManager.default
        if !fm.fileExists(atPath: logFileURL.path) {
            try? line.write(to: logFileURL, atomically: true, encoding: .utf8)
            return
        }

        if let existing = try? String(contentsOf: logFileURL, encoding: .utf8) {
            var lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines.last == "" {
                lines.removeLast()
            }
            lines.append(line.trimmingCharacters(in: .newlines))
            if lines.count > ringBufferLimit {
                lines = Array(lines.suffix(ringBufferLimit))
            }
            let joined = lines.joined(separator: "\n") + "\n"
            try? joined.write(to: logFileURL, atomically: true, encoding: .utf8)
        } else {
            try? line.write(to: logFileURL, atomically: true, encoding: .utf8)
        }
    }

}
