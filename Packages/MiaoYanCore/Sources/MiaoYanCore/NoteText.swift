import Foundation

public enum NoteText {
    /// UTF-8 first, then an encoding Foundation detects without loss (UTF-16,
    /// Big5, Windows-1252), then GB18030, which covers the GBK and GB2312 notes
    /// older Chinese editors wrote. A UTF-8-only read left those notes on the
    /// loading skeleton for good, and accepting a lossy guess turned GBK or Big5
    /// notes into mojibake that the next save wrote back. Saving writes UTF-8,
    /// as every MiaoYan note is.
    ///
    /// Detection alone reads a mostly English GBK, Big5 or EUC-KR note with a
    /// few CJK characters as a Western or Cyrillic code page. When the guess
    /// holds no CJK text and the user reads Chinese, Japanese or Korean, it is
    /// detected again with that language's encodings suggested, and kept only
    /// if that finds CJK text. Hinting every file instead read Shift-JIS and
    /// EUC-KR notes as Chinese.
    public static func decode(_ data: Data) -> String? {
        decode(data, preferredLanguages: Locale.preferredLanguages)
    }

    public static func decode(_ data: Data, preferredLanguages: [String]) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }
        if let first = detect(data, options: [.allowLossyKey: false]) {
            if containsCJK(first) { return first }
            if let hint = cjkHint(for: preferredLanguages),
                let second = detect(
                    data,
                    options: [.allowLossyKey: false, .likelyLanguageKey: hint.language, .suggestedEncodingsKey: hint.encodings]),
                containsCJK(second)
            {
                return second
            }
            return first
        }
        return String(data: data, encoding: encoding(.GB_18030_2000))
    }

    private static func detect(_ data: Data, options: [StringEncodingDetectionOptionsKey: Any]) -> String? {
        var converted: NSString?
        var lossy: ObjCBool = false
        let detected = NSString.stringEncoding(
            for: data, encodingOptions: options, convertedString: &converted, usedLossyConversion: &lossy)
        guard detected != 0, !lossy.boolValue else { return nil }
        return converted as String?
    }

    private static func cjkHint(for languages: [String]) -> (language: String, encodings: [UInt])? {
        for language in languages {
            switch language.prefix(2) {
            case "zh": return ("zh", [encoding(.GB_18030_2000).rawValue, encoding(.big5).rawValue])
            case "ja": return ("ja", [String.Encoding.shiftJIS.rawValue, String.Encoding.japaneseEUC.rawValue])
            case "ko": return ("ko", [encoding(.EUC_KR).rawValue])
            default: continue
            }
        }
        return nil
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            switch $0.value {
            case 0x1100...0x11FF, 0x3000...0x30FF, 0x3400...0x9FFF, 0xAC00...0xD7AF, 0xFF00...0xFFEF: return true
            default: return false
            }
        }
    }

    private static func encoding(_ cf: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue)))
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
