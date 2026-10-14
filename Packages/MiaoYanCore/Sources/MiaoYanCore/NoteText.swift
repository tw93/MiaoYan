import Foundation

public enum NoteText {
    /// UTF-8 first, then an encoding Foundation detects without loss (UTF-16,
    /// Big5, Windows-1252), then GB18030, which covers the GBK and GB2312 notes
    /// older Chinese editors wrote. A UTF-8-only read left those notes on the
    /// loading skeleton for good, and accepting a lossy guess turned GBK or Big5
    /// notes into mojibake that the next save wrote back. Saving writes UTF-8,
    /// as every MiaoYan note is.
    public static func decode(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }
        var converted: NSString?
        var lossy: ObjCBool = false
        let encoding = NSString.stringEncoding(
            for: data, encodingOptions: [.allowLossyKey: false], convertedString: &converted, usedLossyConversion: &lossy)
        if encoding != 0, !lossy.boolValue, let text = converted as String? {
            return text
        }
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        return String(data: data, encoding: gb18030)
    }
}

/// Search reads local files in chunks so cancellation can stop disk work.
/// Matching still receives the full decoded text, including chunk boundaries.
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
        guard let text = NoteText.decode(data) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }
}
