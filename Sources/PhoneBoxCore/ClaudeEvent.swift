import Foundation

/// What one Claude Code hook call tells PhoneBox (design §14 "Olaylar nasıl gelir"). Claude Code runs
/// `PhoneBox --claude-hook` with the hook's JSON on stdin; the helper turns it into one of these and hands it to the app
/// as a line on a Unix socket. Every text of the conversation (`prompt`, `last_assistant_message`, `tool_input`,
/// `tool_response`, `message`) is dropped here and never copied anywhere.
public struct ClaudeEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case sessionStart, prompt, toolStart, toolEnd, permission, stop, sessionEnd
    }

    public var session: String
    public var kind: Kind
    /// The tool's name, only when it is a plain identifier.
    public var tool: String?
    /// A tool start that puts a question to the user: `AskUserQuestion`, or the end-of-turn box with a question.
    public var asks: Bool
    /// A stop while background tasks still run.
    public var background: Bool
    /// The event came from a subagent of the session.
    public var subagent: Bool
    public var cwd: String
    /// The session's file, read for its title and model.
    public var transcript: String?
    /// The session's `claude` process: the hook's parent.
    public var pid: Int32
    /// `session_title` and `model` of a SessionStart, when given; the title as short as one from the session's file.
    public var title: String?
    public var model: String?
    /// When Claude Code ran the hook, in microseconds since 1970: the helper's own start time. Each hook runs as its own
    /// process, so two events a few milliseconds apart can reach PhoneBox the other way round; this puts them back in
    /// order (`ClaudeSessions.apply`).
    public var at: Int64

    public init(session: String, kind: Kind, tool: String?, asks: Bool, background: Bool, subagent: Bool, cwd: String,
                transcript: String?, pid: Int32, title: String?, model: String?, at: Int64) {
        self.session = session
        self.kind = kind
        self.tool = tool
        self.asks = asks
        self.background = background
        self.subagent = subagent
        self.cwd = cwd
        self.transcript = transcript
        self.pid = pid
        self.title = title
        self.model = model
        self.at = at
    }

    /// The end-of-turn box of the Claude desktop app; with a non-empty `ask` it ends the turn with a question.
    public static let wrapUpTool = "mcp__ccd_turn__wrap_up"
    public static let questionTool = "AskUserQuestion"

    /// Nil for an event PhoneBox does not follow, a Notification other than a permission prompt, or input without a
    /// session. `at` is when the hook ran (µs since 1970).
    public static func parse(hookInput: Data, parentPID: Int32, at: Int64) -> ClaudeEvent? {
        guard let object = (try? JSONSerialization.jsonObject(with: hookInput)) as? [String: Any],
              let session = object["session_id"] as? String, !session.isEmpty
        else { return nil }
        let kind: Kind
        switch object["hook_event_name"] as? String {
        case "SessionStart": kind = .sessionStart
        case "UserPromptSubmit": kind = .prompt
        case "PreToolUse": kind = .toolStart
        case "PostToolUse", "PostToolUseFailure", "PermissionDenied": kind = .toolEnd
        case "PermissionRequest": kind = .permission
        case "Notification":
            guard object["notification_type"] as? String == "permission_prompt" else { return nil }
            kind = .permission
        case "Stop": kind = .stop
        case "SessionEnd": kind = .sessionEnd
        default: return nil
        }
        let tool = (object["tool_name"] as? String).flatMap { isPlainName($0) ? $0 : nil }
        var asks = false
        if kind == .toolStart {
            if tool == questionTool {
                asks = true
            } else if tool == wrapUpTool, let input = object["tool_input"] as? [String: Any],
                      let ask = input["ask"] as? String {
                asks = !ask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
        let background = kind == .stop && !((object["background_tasks"] as? [Any]) ?? []).isEmpty
        let subagent = !((object["agent_id"] as? String) ?? "").isEmpty
        let transcript = (object["transcript_path"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return ClaudeEvent(session: session, kind: kind, tool: tool, asks: asks, background: background,
                           subagent: subagent, cwd: object["cwd"] as? String ?? "", transcript: transcript,
                           pid: parentPID,
                           title: kind == .sessionStart ? ClaudeTranscript.cleanTitle(object["session_title"]) : nil,
                           model: kind == .sessionStart ? trimmed(object["model"]) : nil, at: at)
    }

    /// Compact JSON and a newline.
    public func line() -> Data {
        var data = (try? JSONEncoder().encode(self)) ?? Data()
        data.append(0x0A)
        return data
    }

    public static func decode(line: Data) -> ClaudeEvent? {
        var line = line
        while let last = line.last, last == 0x0A || last == 0x0D { line.removeLast() }
        guard let event = try? JSONDecoder().decode(ClaudeEvent.self, from: line), !event.session.isEmpty else { return nil }
        return event
    }

    /// `^[A-Za-z0-9_.-]{1,128}$`
    static func isPlainName(_ name: String) -> Bool {
        let bytes = name.utf8
        guard (1...128).contains(bytes.count) else { return false }
        return bytes.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: "-"):
                return true
            default:
                return false
            }
        }
    }

    private static func trimmed(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
