import Foundation

class NameHelper {
    /// A free file URL for `name` in the project. On a clash a trailing
    /// ` <number>` counts up (`Note` to `Note 1`, `Note 12` to `Note 13`);
    /// a number inside the name (`Meeting 3 notes`) is part of the name and
    /// gets its own suffix (`Meeting 3 notes 1`).
    public static func getUniqueFileName(name: String, project: Project, ext: String) -> URL {
        var name =
            name
            .trimmingCharacters(in: CharacterSet.whitespaces)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: ":")

        if name.isEmpty {
            name = UUID().uuidString
        }

        let fileManager = FileManager.default
        func url(for candidate: String) -> URL {
            project.url.appendingPathComponent(candidate).appendingPathExtension(ext)
        }

        var candidate = url(for: name)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let (base, counted) = splitTrailingNumber(name)
        var number = counted ?? 0
        repeat {
            number += 1
            candidate = url(for: "\(base) \(number)")
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }

    /// `Note 12` is `("Note", 12)`; a name without a trailing number, or one
    /// that is only a number, keeps its whole text as the base.
    static func splitTrailingNumber(_ name: String) -> (base: String, number: Int?) {
        guard let match = trailingNumberRegex?.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
            let baseRange = Range(match.range(at: 1), in: name),
            let numberRange = Range(match.range(at: 2), in: name),
            let number = Int(name[numberRange])
        else {
            return (name, nil)
        }
        return (String(name[baseRange]), number)
    }

    private static let trailingNumberRegex = try? NSRegularExpression(pattern: #"^(.*\S)\s+(\d{1,9})$"#)
}
