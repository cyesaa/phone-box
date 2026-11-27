import Foundation
import Testing
@testable import PhoneBoxCore

/// PhoneBox's hooks in a `~/.claude/settings.json` text (design §14 "Kurulum"): added and removed without touching
/// anything else in the file.
struct ClaudeHooksTests {
    static let command = ClaudeHooks.command(executable: "/Applications/PhoneBox.app/Contents/MacOS/PhoneBox")

    static func object(_ data: Data) throws -> NSDictionary {
        try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    static func hooks(_ data: Data) throws -> [String: [[String: Any]]] {
        try #require(try object(data)["hooks"] as? [String: [[String: Any]]])
    }

    static func install(_ text: String?) throws -> Data {
        try ClaudeHooks.install(into: text.map { Data($0.utf8) }, command: command)
    }

    @Test func quotesTheExecutableForTheShell() {
        #expect(Self.command == "'/Applications/PhoneBox.app/Contents/MacOS/PhoneBox' --claude-hook")
        #expect(ClaudeHooks.command(executable: "/Users/me/My Apps/Eren's PhoneBox.app/Contents/MacOS/PhoneBox")
            == #"'/Users/me/My Apps/Eren'\''s PhoneBox.app/Contents/MacOS/PhoneBox' --claude-hook"#)
    }

    @Test func recognisesPhoneBoxsCommands() {
        #expect(ClaudeHooks.isPhoneBoxCommand(Self.command))
        #expect(ClaudeHooks.isPhoneBoxCommand("/tmp/PhoneBox.app/Contents/MacOS/PhoneBox --claude-hook"))
        #expect(!ClaudeHooks.isPhoneBoxCommand("'/Applications/PhoneBox.app/Contents/MacOS/PhoneBox' --claude-hook --x"))
        #expect(!ClaudeHooks.isPhoneBoxCommand("notify.sh --claude-hook"))
        #expect(!ClaudeHooks.isPhoneBoxCommand("echo PhoneBox"))
    }

    @Test func installsIntoNoFileAnEmptyFileAndAnEmptyObject() throws {
        for text in [nil, "", "  \n", "{}"] {
            let hooks = try Self.hooks(try Self.install(text))
            #expect(Set(hooks.keys) == Set(ClaudeHooks.events), "\(text ?? "nil")")
            for event in ClaudeHooks.events {
                let groups = try #require(hooks[event])
                #expect(groups.count == 1)
                let entry = try #require((groups[0]["hooks"] as? [[String: Any]])?.first)
                #expect(entry["type"] as? String == "command")
                #expect(entry["command"] as? String == Self.command)
                #expect(entry["async"] as? Bool == true)
                #expect(entry["timeout"] as? Int == 10)
                #expect(groups[0]["matcher"] as? String == (event == "Notification" ? "permission_prompt|idle_prompt" : nil))
            }
        }
    }

    /// A turn that ends on an API error fires StopFailure, not Stop; an agent's end (SubagentStop) ends its waits; the
    /// idle prompt's notification ends a turn that Esc ended without either (bughunt #1, #2).
    @Test func hooksTheEndsOfTurnsAndAgents() {
        #expect(ClaudeHooks.events == ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                                       "PermissionRequest", "PermissionDenied", "Notification", "Stop", "StopFailure",
                                       "SubagentStop", "SessionEnd"])
    }

    @Test func writesSortedPrettyJSONWithANewline() throws {
        let data = try Self.install(#"{"z":1,"a":"/x/y"}"#)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasPrefix("{\n  \"a\" : \"/x/y\",\n  \"hooks\" : {\n"))
        #expect(text.hasSuffix("\n  \"z\" : 1\n}\n"))
        #expect(!text.contains(#"\/"#))
    }

    static let userFile = #"""
    {
      "model": "opus",
      "env": {"FOO": "bar"},
      "permissions": {"allow": ["Bash(ls:*)"]},
      "hooks": {
        "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "~/bin/check.sh"}]}],
        "PreCompact": [{"hooks": [{"type": "command", "command": "say done"}]}]
      }
    }
    """#

    @Test func keepsEverythingElseInTheFile() throws {
        let installed = try Self.install(Self.userFile)
        let object = try Self.object(installed)
        let original = try Self.object(Data(Self.userFile.utf8))
        #expect(object["model"] as? String == "opus")
        #expect(object["env"] as? NSDictionary == original["env"] as? NSDictionary)
        #expect(object["permissions"] as? NSDictionary == original["permissions"] as? NSDictionary)
        let hooks = try Self.hooks(installed)
        #expect(hooks["PreCompact"]?.count == 1)
        let preToolUse = try #require(hooks["PreToolUse"])
        #expect(preToolUse.count == 2)
        #expect(preToolUse[0]["matcher"] as? String == "Bash")
        #expect((preToolUse[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String == "~/bin/check.sh")
        #expect((preToolUse[1]["hooks"] as? [[String: Any]])?.first?["command"] as? String == Self.command)
    }

    @Test func reinstallingLeavesOneGroupPerEvent() throws {
        let moved = ClaudeHooks.command(executable: "/Users/me/Applications/PhoneBox.app/Contents/MacOS/PhoneBox")
        let first = try Self.install(Self.userFile)
        let again = try ClaudeHooks.install(into: try ClaudeHooks.install(into: first, command: Self.command), command: moved)
        #expect(ClaudeHooks.installedCommands(in: again) == Array(repeating: moved, count: ClaudeHooks.events.count))
        let hooks = try Self.hooks(again)
        #expect(hooks["PreToolUse"]?.count == 2)
        for event in ClaudeHooks.events where event != "PreToolUse" {
            #expect(hooks[event]?.count == 1, "\(event)")
        }
    }

    @Test func removingRestoresTheOriginal() throws {
        let original = Data(Self.userFile.utf8)
        let removed = try ClaudeHooks.remove(from: try Self.install(Self.userFile))
        #expect(try Self.object(removed) == Self.object(original))
        #expect(String(decoding: removed, as: UTF8.self).hasSuffix("}\n"))
        // A file that had no hooks gets none back.
        let plain = #"{"model":"opus"}"#
        #expect(try Self.object(try ClaudeHooks.remove(from: try Self.install(plain))) == Self.object(Data(plain.utf8)))
        #expect(try Self.object(try ClaudeHooks.remove(from: try Self.install(nil))) == NSDictionary())
    }

    @Test func removingFromAFileWithoutPhoneBoxChangesNothing() throws {
        let original = Data(Self.userFile.utf8)
        #expect(try Self.object(try ClaudeHooks.remove(from: original)) == Self.object(original))
        // Empty groups and events that were already there stay.
        let empty = #"{"hooks":{"Stop":[],"PreToolUse":[{"hooks":[]}]}}"#
        #expect(try Self.object(try ClaudeHooks.remove(from: Data(empty.utf8))) == Self.object(Data(empty.utf8)))
        #expect(try Self.object(try ClaudeHooks.remove(from: Data(#"{"hooks":{}}"#.utf8))) == ["hooks": NSDictionary()])
    }

    @Test func removesPhoneBoxsEntryFromAGroupTheUserSharesWithIt() throws {
        let shared = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say hi"},{"type":"command","command":"/x/PhoneBox --claude-hook"}]}]}}"#
        let removed = try Self.hooks(try ClaudeHooks.remove(from: Data(shared.utf8)))
        let entries = try #require(removed["Stop"]?.first?["hooks"] as? [[String: Any]])
        #expect(entries.count == 1)
        #expect(entries.first?["command"] as? String == "say hi")
    }

    @Test func listsTheInstalledCommands() throws {
        #expect(ClaudeHooks.installedCommands(in: Data(Self.userFile.utf8)) == [])
        #expect(ClaudeHooks.installedCommands(in: Data("junk".utf8)) == [])
        #expect(ClaudeHooks.installedCommands(in: try Self.install(nil)).count == ClaudeHooks.events.count)
        #expect(Set(ClaudeHooks.installedCommands(in: try Self.install(Self.userFile))) == [Self.command])
    }

    @Test func refusesFilesItDoesNotUnderstand() {
        let cases: [(String, ClaudeHooks.Failure)] = [
            ("{", .notJSON), ("// comment\n{}", .notJSON), ("[]", .notAnObject), ("\"text\"", .notAnObject), ("3", .notAnObject),
            (#"{"hooks":[]}"#, .hooksNotAnObject), (#"{"hooks":"x"}"#, .hooksNotAnObject), (#"{"hooks":null}"#, .hooksNotAnObject),
            (#"{"hooks":{"Stop":{}}}"#, .eventNotAnArray("Stop")),
            (#"{"hooks":{"PreToolUse":"x","Stop":[]}}"#, .eventNotAnArray("PreToolUse")),
        ]
        for (text, failure) in cases {
            #expect(throws: failure, "\(text)") { try ClaudeHooks.install(into: Data(text.utf8), command: Self.command) }
            #expect(throws: failure, "\(text)") { try ClaudeHooks.remove(from: Data(text.utf8)) }
        }
    }

    @Test func leavesAnotherEventItDoesNotUseAsItIs() throws {
        let text = #"{"hooks":{"PreCompact":"custom"}}"#
        let installed = try Self.install(text)
        #expect(try Self.object(installed)["hooks"].flatMap { ($0 as? NSDictionary)?["PreCompact"] as? String } == "custom")
        #expect(try Self.object(try ClaudeHooks.remove(from: installed)) == Self.object(Data(text.utf8)))
    }

    @Test func readsTheExecutableBackFromACommand() {
        for path in ["/Applications/PhoneBox.app/Contents/MacOS/PhoneBox",
                     "/Users/me/My Apps/Eren's PhoneBox.app/Contents/MacOS/PhoneBox", "/tmp/'/PhoneBox"] {
            #expect(ClaudeHooks.executable(fromCommand: ClaudeHooks.command(executable: path)) == path, "\(path)")
        }
        // Only what `command(executable:)` writes.
        #expect(ClaudeHooks.executable(fromCommand: "/tmp/PhoneBox.app/Contents/MacOS/PhoneBox --claude-hook") == nil)
        #expect(ClaudeHooks.executable(fromCommand: "'/tmp/a' '/tmp/PhoneBox' --claude-hook") == nil)
        #expect(ClaudeHooks.executable(fromCommand: "'' --claude-hook") == nil)
        #expect(ClaudeHooks.executable(fromCommand: "' --claude-hook") == nil)
    }

    // MARK: At launch, with the feature on (design §14 "Kurulum")

    static let app = "/Applications/PhoneBox.app/Contents/MacOS/PhoneBox"
    static let copy = "/tmp/pbtest/PhoneBox.app/Contents/MacOS/PhoneBox"

    static func check(_ settings: Data?, executable: String = app, existing: Set<String> = [app, copy]) -> ClaudeHooks.LaunchCheck {
        ClaudeHooks.launchCheck(settings: settings, executable: executable, exists: { existing.contains($0) })
    }

    static func installed(for executable: String, into text: String? = nil) throws -> Data {
        try ClaudeHooks.install(into: text.map { Data($0.utf8) }, command: ClaudeHooks.command(executable: executable))
    }

    @Test func atLaunchHooksOfThisAppNeedNothing() throws {
        #expect(Self.check(try Self.installed(for: Self.app)) == .current)
        #expect(Self.check(try Self.installed(for: Self.app, into: #"{"model":"opus"}"#)) == .current)
    }

    /// The user took the hooks out by hand: the feature goes off.
    @Test func atLaunchNoHooksTurnTheFeatureOff() {
        for text: String in ["", "{}", #"{"hooks":{}}"#, #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#] {
            #expect(Self.check(Data(text.utf8)) == .removed, "\(text)")
        }
    }

    /// No file at all (no `~/.claude`) is not the user taking the hooks out: it stays as it is.
    @Test func atLaunchNoFileIsLeftAlone() {
        #expect(Self.check(nil) == .unreadable)
    }

    /// A file PhoneBox cannot read says nothing about the hooks: it stays as it is, and so does the feature.
    @Test func atLaunchAFilePhoneBoxCannotReadIsLeftAlone() {
        for text in ["{ not json", "[]", #"{"hooks":[]}"#, #"{"hooks":{"Stop":{}}}"#] {
            #expect(Self.check(Data(text.utf8)) == .unreadable, "\(text)")
        }
    }

    /// The app was moved (or deleted and installed elsewhere): its old hooks run nothing.
    @Test func atLaunchHooksOfAGonePhoneBoxAreInstalledAgain() throws {
        #expect(Self.check(try Self.installed(for: "/Users/me/Downloads/PhoneBox.app/Contents/MacOS/PhoneBox")) == .reinstall)
        // A command PhoneBox did not write: it cannot tell what it runs.
        let handWritten = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/Applications/PhoneBox.app/Contents/MacOS/PhoneBox --claude-hook"}]}]}}"#
        #expect(Self.check(Data(handWritten.utf8)) == .reinstall)
    }

    @Test func atLaunchMissingEventsAreInstalledAgain() throws {
        var root = try #require(try JSONSerialization.jsonObject(with: try Self.installed(for: Self.app)) as? [String: Any])
        var hooks = try #require(root["hooks"] as? [String: Any])
        hooks["Stop"] = nil
        root["hooks"] = hooks
        #expect(Self.check(try JSONSerialization.data(withJSONObject: root)) == .reinstall)
    }

    /// The hooks 0.4.0 installed miss StopFailure and SubagentStop, and their Notification group matches only the
    /// permission prompt: the new app installs its own.
    @Test func atLaunchTheHooksOf040AreInstalledAgain() throws {
        var root = try #require(try JSONSerialization.jsonObject(with: try Self.installed(for: Self.app)) as? [String: Any])
        var hooks = try #require(root["hooks"] as? [String: Any])
        hooks["StopFailure"] = nil
        hooks["SubagentStop"] = nil
        var notification = try #require((hooks["Notification"] as? [[String: Any]])?.first)
        notification["matcher"] = "permission_prompt"
        hooks["Notification"] = [notification]
        root["hooks"] = hooks
        let old = try JSONSerialization.data(withJSONObject: root)
        #expect(Self.check(old) == .reinstall)
        let again = try Self.hooks(try ClaudeHooks.install(into: old, command: ClaudeHooks.command(executable: Self.app)))
        #expect(again["Notification"]?.count == 1)
        #expect(again["Notification"]?.first?["matcher"] as? String == "permission_prompt|idle_prompt")
        #expect(again["StopFailure"]?.count == 1)
    }

    /// A test copy (`PHONEBOX_DEST`) that is still on disk owns the hooks it installed.
    @Test func atLaunchHooksOfAnotherPhoneBoxThatIsThereAreLeftAlone() throws {
        #expect(Self.check(try Self.installed(for: Self.copy)) == .otherCopy)
        #expect(Self.check(try Self.installed(for: Self.app), executable: Self.copy) == .otherCopy)
        // A copy's hooks that miss an event are still the copy's, as long as it is there.
        var root = try #require(try JSONSerialization.jsonObject(with: try Self.installed(for: Self.copy)) as? [String: Any])
        var hooks = try #require(root["hooks"] as? [String: Any])
        hooks["Stop"] = nil
        root["hooks"] = hooks
        #expect(Self.check(try JSONSerialization.data(withJSONObject: root)) == .otherCopy)
        // Once it is gone, they are this app's again.
        #expect(Self.check(try Self.installed(for: Self.copy), existing: [Self.app]) == .reinstall)
    }
}
