import Foundation

public enum NoteText {
    /// UTF-8 first, then GB18030, which covers the GBK and GB2312 notes older
    /// Chinese editors wrote. A UTF-8-only read left those notes on the
    /// loading skeleton for good. Saving writes UTF-8, as every MiaoYan note is.
    public static func decode(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        return String(data: data, encoding: gb18030)
    }
}

/// Search reads local files in chunks so cancellation can stop disk work.
/// Matching still receives the full UTF-8 text, including chunk boundaries.
public enum NoteSearchReader {
    public static func read(_ url: URL) throws -> String {
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        try Task.checkCancellation()
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }
}
