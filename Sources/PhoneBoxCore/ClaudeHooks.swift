import Foundation

/// PhoneBox's hooks in the text of `~/.claude/settings.json` (design §14 "Kurulum"). Pure: reading and writing the
/// file is the app's job. Only PhoneBox's own entries are added or removed; every other key, hook and group stays.
public enum ClaudeHooks {
    public enum Failure: Error, Equatable {
        case notJSON
        case notAnObject
        case hooksNotAnObject
        case eventNotAnArray(String)
    }

    /// One group of PhoneBox's in each of these events' arrays.
    public static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                                "PermissionRequest", "PermissionDenied", "Notification", "Stop", "SessionEnd"]

    /// The executable quoted for `sh`, then the helper's flag.
    public static func command(executable: String) -> String {
        "'" + executable.replacingOccurrences(of: "'", with: #"'\''"#) + "' --claude-hook"
    }

    /// A hook of any PhoneBox, wherever it was installed from.
    public static func isPhoneBoxCommand(_ command: String) -> Bool {
        command.contains("PhoneBox") && command.trimmingCharacters(in: .whitespaces).hasSuffix("--claude-hook")
    }

    /// `settings` with PhoneBox's hooks running `command`; earlier PhoneBox hooks (from any path) are replaced. No
    /// file, an empty one and one with only whitespace count as `{}`.
    public static func install(into settings: Data?, command: String) throws -> Data {
        var root = try parse(settings ?? Data())
        var hooks = try hooksObject(of: root) ?? [:]
        removeEntries(from: &hooks)
        for event in events {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command, "async": true, "timeout": 10]]]
            if event == "Notification" { group["matcher"] = "permission_prompt" }
            hooks[event] = ((hooks[event] as? [Any]) ?? []) + [group]
        }
        root["hooks"] = hooks
        return try serialize(root)
    }

    /// `settings` without PhoneBox's hooks. A group, an event or `hooks` that this leaves empty goes too; one that was
    /// empty before stays.
    public static func remove(from settings: Data) throws -> Data {
        var root = try parse(settings)
        if var hooks = try hooksObject(of: root), removeEntries(from: &hooks) {
            root["hooks"] = hooks.isEmpty ? nil : hooks
        }
        return try serialize(root)
    }

    /// The commands of PhoneBox's hooks in `settings`, one per hook; none for a file PhoneBox cannot read.
    public static func installedCommands(in settings: Data) -> [String] {
        guard let root = try? parse(settings), let hooks = root["hooks"] as? [String: Any] else { return [] }
        var commands: [String] = []
        for event in hooks.keys.sorted() {
            for group in hooks[event] as? [Any] ?? [] {
                for entry in (group as? [String: Any])?["hooks"] as? [Any] ?? [] {
                    if let command = phoneBoxCommand(entry) { commands.append(command) }
                }
            }
        }
        return commands
    }

    private static func parse(_ data: Data) throws -> [String: Any] {
        if data.allSatisfy({ [0x20, 0x09, 0x0A, 0x0D].contains($0) }) { return [:] }
        guard let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw Failure.notJSON
        }
        guard let root = value as? [String: Any] else { throw Failure.notAnObject }
        return root
    }

    /// Nil when there is no `hooks`. Each of PhoneBox's events, where present, must be an array; other events are not
    /// PhoneBox's business.
    private static func hooksObject(of root: [String: Any]) throws -> [String: Any]? {
        guard let value = root["hooks"] else { return nil }
        guard let hooks = value as? [String: Any] else { throw Failure.hooksNotAnObject }
        for event in events where hooks[event] != nil && !(hooks[event] is [Any]) {
            throw Failure.eventNotAnArray(event)
        }
        return hooks
    }

    /// Takes PhoneBox's entries out of every event; true when there were any.
    @discardableResult
    private static func removeEntries(from hooks: inout [String: Any]) -> Bool {
        var removedAny = false
        for (event, value) in hooks {
            guard let groups = value as? [Any] else { continue }
            var kept: [Any] = []
            var changed = false
            for group in groups {
                guard var object = group as? [String: Any], let entries = object["hooks"] as? [Any] else {
                    kept.append(group)
                    continue
                }
                let remaining = entries.filter { phoneBoxCommand($0) == nil }
                guard remaining.count != entries.count else {
                    kept.append(group)
                    continue
                }
                changed = true
                if remaining.isEmpty { continue }
                object["hooks"] = remaining
                kept.append(object)
            }
            guard changed else { continue }
            removedAny = true
            hooks[event] = kept.isEmpty ? nil : kept
        }
        return removedAny
    }

    private static func phoneBoxCommand(_ entry: Any) -> String? {
        guard let command = (entry as? [String: Any])?["command"] as? String, isPhoneBoxCommand(command) else { return nil }
        return command
    }

    /// Sorted keys and two-space indentation, like the file Claude Code writes, and a final newline.
    private static func serialize(_ root: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }
}
