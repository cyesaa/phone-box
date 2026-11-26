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

    /// The executable of a command that `command(executable:)` wrote; nil for any other command.
    public static func executable(fromCommand command: String) -> String? {
        let end = "' --claude-hook"
        guard command.hasPrefix("'"), command.hasSuffix(end), command.count > end.count else { return nil }
        let path = String(command.dropFirst().dropLast(end.count)).replacingOccurrences(of: #"'\''"#, with: "'")
        guard !path.isEmpty, Self.command(executable: path) == command else { return nil }
        return path
    }

    /// What PhoneBox does with the settings file at launch while the feature is on (design §14 "Kurulum").
    public enum LaunchCheck: Equatable, Sendable {
        /// The hooks run this app, for every event: nothing to do.
        case current
        /// The file cannot be read, or there is none (no `~/.claude`): it stays as it is, and so does the feature.
        case unreadable
        /// No PhoneBox hooks: the user took them out, and the feature goes off.
        case removed
        /// The hooks run a PhoneBox that is no longer there (the app was moved), or some events have none: this app
        /// installs its own.
        case reinstall
        /// The hooks run another PhoneBox that is still there (a test copy next to the installed one): that one owns
        /// them, and the file stays as it is.
        case otherCopy
    }

    /// `settings` is the file's contents, nil when there is no file; `executable` is this app's; `exists` says whether
    /// an executable is still on disk.
    public static func launchCheck(settings: Data?, executable: String, exists: (String) -> Bool) -> LaunchCheck {
        // No file at all says nothing about the hooks (no `~/.claude` yet, or it cannot be seen): like an unreadable one.
        guard let settings else { return .unreadable }
        var byEvent: [String: Int] = [:]
        var executables: Set<String?> = []
        let hooks: [String: Any]?
        do {
            hooks = try hooksObject(of: try parse(settings))
        } catch {
            return .unreadable
        }
        for (event, groups) in hooks ?? [:] {
            for group in groups as? [Any] ?? [] {
                for entry in (group as? [String: Any])?["hooks"] as? [Any] ?? [] {
                    guard let command = phoneBoxCommand(entry) else { continue }
                    byEvent[event, default: 0] += 1
                    executables.insert(Self.executable(fromCommand: command))
                }
            }
        }
        if executables.isEmpty { return .removed }
        let gone = executables.contains { $0.map(exists) != true }
        // Hooks that all run PhoneBoxes still on disk, none of them this one, belong to those copies, whatever events
        // they miss.
        if !gone, !executables.contains(executable) { return .otherCopy }
        if gone || events.contains(where: { byEvent[$0] == nil }) { return .reinstall }
        return executables == [executable] ? .current : .otherCopy
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
