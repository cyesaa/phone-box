import Foundation

/// A session's title and model from the end of its file (design §14). The JSONL format is not documented, so
/// anything unexpected is skipped: no title means the folder's name stays, no model means none is shown.
public enum ClaudeTranscript {
    public static let maxTitleLength = 120

    /// `data` is the file's last bytes; unless it `startsAtBeginning`, its first line is probably cut and is skipped.
    /// Title: `customTitle` of the last `custom-title` line (the desktop app writes one when the session is named).
    /// Model: of the last `assistant` line whose `message.model` has a name.
    public static func details(fromTail data: Data, startsAtBeginning: Bool) -> (title: String?, model: String?) {
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        if !startsAtBeginning, !lines.isEmpty { lines.removeFirst() }
        let titleMark = Data(#""custom-title""#.utf8)
        let modelMark = Data(#""model""#.utf8)
        var title: String?
        var model: String?
        for line in lines.reversed() {
            if title != nil, model != nil { break }
            let mayHaveTitle = title == nil && line.range(of: titleMark) != nil
            let mayHaveModel = model == nil && line.range(of: modelMark) != nil
            guard mayHaveTitle || mayHaveModel,
                  let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
            else { continue }
            switch object["type"] as? String {
            case "custom-title" where mayHaveTitle:
                title = cleanTitle(object["customTitle"])
            case "assistant" where mayHaveModel:
                model = ((object["message"] as? [String: Any])?["model"] as? String).flatMap(modelName)
            default:
                break
            }
        }
        return (title, model)
    }

    /// "Opus 5.5" for `claude-opus-5-5`, `claude-opus-5-5-20261001` or `claude-opus-5-5[1m]`; "Opus 4" for
    /// `claude-opus-4`. Nil for any other shape, the old `claude-3-5-sonnet-…` ids among them.
    public static func modelName(_ id: String) -> String? {
        var id = Substring(id)
        if let bracket = id.firstIndex(of: "[") { id = id[..<bracket] }
        let parts = id.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.count <= 5, parts[0] == "claude",
              let family = parts[1].first.map({ String($0).uppercased() + parts[1].dropFirst() }),
              parts[1].allSatisfy({ $0.isASCII && $0.isLetter }),
              isNumber(parts[2], digits: 1...2)
        else { return nil }
        var version = String(parts[2])
        var rest = parts.dropFirst(3)
        if let minor = rest.first, isNumber(minor, digits: 1...2) {
            version += "." + minor
            rest = rest.dropFirst()
        }
        if let date = rest.first, isNumber(date, digits: 8...8) { rest = rest.dropFirst() }
        guard rest.isEmpty else { return nil }
        return "\(family) \(version)"
    }

    private static func isNumber(_ text: Substring, digits: ClosedRange<Int>) -> Bool {
        digits.contains(text.count) && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// A session's title as the phone shows it, wherever it comes from (the session's file, a SessionStart): trimmed,
    /// at most `maxTitleLength` characters; nil when nothing is left.
    public static func cleanTitle(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return String(text.prefix(maxTitleLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
