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
                #expect(groups[0]["matcher"] as? String == (event == "Notification" ? "permission_prompt" : nil))
            }
        }
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
        "SubagentStop": [{"hooks": [{"type": "command", "command": "say done"}]}]
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
        #expect(hooks["SubagentStop"]?.count == 1)
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
        let text = #"{"hooks":{"SubagentStop":"custom"}}"#
        let installed = try Self.install(text)
        #expect(try Self.object(installed)["hooks"].flatMap { ($0 as? NSDictionary)?["SubagentStop"] as? String } == "custom")
        #expect(try Self.object(try ClaudeHooks.remove(from: installed)) == Self.object(Data(text.utf8)))
    }
}
