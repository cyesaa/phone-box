import Foundation
import Testing
@testable import PhoneBoxCore

/// What a hook call tells PhoneBox (design §14 "Olaylar nasıl gelir"): the kind of event and a few flags, never the
/// texts of the conversation.
struct ClaudeEventTests {
    static func parse(_ json: String, pid: Int32 = 4242) -> ClaudeEvent? {
        ClaudeEvent.parse(hookInput: Data(json.utf8), parentPID: pid)
    }

    static func input(_ event: String, _ extra: String = "") -> String {
        #"{"session_id":"s1","transcript_path":"/Users/me/.claude/projects/x/s1.jsonl","cwd":"/Users/me/Code/PhoneBox","hook_event_name":"\#(event)"\#(extra)}"#
    }

    @Test func mapsEveryEvent() {
        let kinds: [(String, ClaudeEvent.Kind)] = [
            ("SessionStart", .sessionStart), ("UserPromptSubmit", .prompt), ("PreToolUse", .toolStart),
            ("PostToolUse", .toolEnd), ("PostToolUseFailure", .toolEnd), ("PermissionDenied", .toolEnd),
            ("PermissionRequest", .permission), ("Stop", .stop), ("SessionEnd", .sessionEnd),
        ]
        for (name, kind) in kinds {
            #expect(Self.parse(Self.input(name))?.kind == kind, "\(name)")
        }
    }

    @Test func copiesTheSessionThePathsAndTheParentProcess() throws {
        let event = try #require(Self.parse(Self.input("UserPromptSubmit"), pid: 777))
        #expect(event == ClaudeEvent(session: "s1", kind: .prompt, tool: nil, asks: false, background: false, subagent: false,
                                     cwd: "/Users/me/Code/PhoneBox", transcript: "/Users/me/.claude/projects/x/s1.jsonl",
                                     pid: 777, title: nil, model: nil))
    }

    @Test func otherEventsAndOtherNotificationsAreNil() {
        #expect(Self.parse(Self.input("SubagentStop")) == nil)
        #expect(Self.parse(Self.input("PreCompact")) == nil)
        #expect(Self.parse(Self.input("Notification", #","notification_type":"idle_prompt","message":"waiting""#)) == nil)
        #expect(Self.parse(Self.input("Notification")) == nil)
        #expect(Self.parse(Self.input("Notification", #","notification_type":"permission_prompt""#))?.kind == .permission)
    }

    @Test func aMissingOrEmptySessionIsNil() {
        #expect(Self.parse(#"{"hook_event_name":"Stop","cwd":"/x"}"#) == nil)
        #expect(Self.parse(#"{"session_id":"","hook_event_name":"Stop","cwd":"/x"}"#) == nil)
        #expect(Self.parse(#"{"session_id":7,"hook_event_name":"Stop","cwd":"/x"}"#) == nil)
        #expect(Self.parse("not json") == nil)
        #expect(Self.parse("[1]") == nil)
    }

    @Test func aMissingDirectoryIsEmpty() throws {
        let event = try #require(Self.parse(#"{"session_id":"s","hook_event_name":"Stop"}"#))
        #expect(event.cwd == "")
        #expect(event.transcript == nil)
    }

    @Test func sessionStartCarriesTheTitleAndTheModelWhenGiven() throws {
        let event = try #require(Self.parse(Self.input("SessionStart",
                                                       #","source":"startup","session_title":"  Fix the menu ","model":"claude-opus-5-5""#)))
        #expect(event.title == "Fix the menu")
        #expect(event.model == "claude-opus-5-5")
        let bare = try #require(Self.parse(Self.input("SessionStart", #","session_title":"   ","model":3"#)))
        #expect(bare.title == nil)
        #expect(bare.model == nil)
        // Only SessionStart says what the session is called.
        let prompt = try #require(Self.parse(Self.input("UserPromptSubmit", #","session_title":"T","model":"claude-opus-5-5""#)))
        #expect(prompt.title == nil)
        #expect(prompt.model == nil)
    }

    @Test func keepsOnlyAPlainToolName() throws {
        #expect(Self.parse(Self.input("PreToolUse", #","tool_name":"mcp__ccd_session__mark-chapter.v2""#))?.tool
            == "mcp__ccd_session__mark-chapter.v2")
        #expect(Self.parse(Self.input("PreToolUse", #","tool_name":"Bash; rm -rf""#))?.tool == nil)
        #expect(Self.parse(Self.input("PreToolUse", #","tool_name":"""#))?.tool == nil)
        #expect(Self.parse(Self.input("PreToolUse", #","tool_name":"\#(String(repeating: "a", count: 129))""#))?.tool == nil)
        #expect(Self.parse(Self.input("PreToolUse", #","tool_name":"\#(String(repeating: "a", count: 128))""#))?.tool?.count == 128)
        #expect(Self.parse(Self.input("PreToolUse", #","tool_name":"Bäsh""#))?.tool == nil)
        let event = try #require(Self.parse(Self.input("PreToolUse", #","tool_name":"Bash""#)))
        #expect(event.tool == "Bash")
        #expect(!event.asks)
    }

    @Test func aQuestionAsks() {
        #expect(Self.parse(Self.input("PreToolUse", #","tool_name":"AskUserQuestion","tool_input":{"questions":[]}"#))?.asks == true)
        // Only before the tool runs.
        #expect(Self.parse(Self.input("PostToolUse", #","tool_name":"AskUserQuestion""#))?.asks == false)
    }

    @Test func aWrapUpAsksOnlyWithANonEmptyQuestion() {
        func wrapUp(_ input: String) -> Bool? {
            Self.parse(Self.input("PreToolUse", #","tool_name":"mcp__ccd_turn__wrap_up","tool_input":\#(input)"#))?.asks
        }
        #expect(wrapUp(#"{"recap":"Done.","ask":"Ship it?"}"#) == true)
        #expect(wrapUp(#"{"recap":"Done.","ask":""}"#) == false)
        #expect(wrapUp(#"{"recap":"Done.","ask":"  \n "}"#) == false)
        #expect(wrapUp(#"{"recap":"Done.","ask":7}"#) == false)
        #expect(wrapUp(#"{"recap":"Done."}"#) == false)
        #expect(wrapUp(#""text""#) == false)
    }

    @Test func aStopWithBackgroundTasksSaysSo() {
        #expect(Self.parse(Self.input("Stop", #","background_tasks":[{"id":"b1"}]"#))?.background == true)
        #expect(Self.parse(Self.input("Stop", #","background_tasks":[]"#))?.background == false)
        #expect(Self.parse(Self.input("Stop"))?.background == false)
        #expect(Self.parse(Self.input("Stop", #","background_tasks":"b1""#))?.background == false)
    }

    @Test func aSubagentsEventSaysSo() {
        #expect(Self.parse(Self.input("Stop", #","agent_id":"a1""#))?.subagent == true)
        #expect(Self.parse(Self.input("Stop", #","agent_id":"""#))?.subagent == false)
        #expect(Self.parse(Self.input("Stop"))?.subagent == false)
    }

    @Test func neverCopiesTheConversation() throws {
        let secret = "SECRET-7f3a"
        let inputs = [
            Self.input("UserPromptSubmit", #","prompt":"my \#(secret)""#),
            Self.input("Stop", #","last_assistant_message":"\#(secret)","stop_hook_active":false"#),
            Self.input("PreToolUse", #","tool_name":"Bash","tool_input":{"command":"echo \#(secret)"}"#),
            Self.input("PostToolUse", #","tool_name":"Bash","tool_input":{"command":"x"},"tool_response":{"stdout":"\#(secret)"}"#),
            Self.input("PreToolUse", #","tool_name":"mcp__ccd_turn__wrap_up","tool_input":{"ask":"\#(secret)?"}"#),
            Self.input("Notification", #","notification_type":"permission_prompt","message":"\#(secret)""#),
        ]
        for input in inputs {
            let line = String(decoding: try #require(Self.parse(input)).line(), as: UTF8.self)
            #expect(!line.contains(secret), "\(line)")
        }
    }

    @Test func aLineIsOneJSONObjectAndDecodesBack() throws {
        let event = try #require(Self.parse(Self.input("SessionStart", #","session_title":"Başlık","model":"claude-opus-5-5""#)))
        let line = event.line()
        #expect(line.last == 0x0A)
        #expect(line.dropLast().firstIndex(of: 0x0A) == nil)
        #expect(ClaudeEvent.decode(line: line) == event)
        #expect(ClaudeEvent.decode(line: line.dropLast()) == event)
        let stop = try #require(Self.parse(Self.input("Stop", #","background_tasks":[1],"agent_id":"a""#)))
        #expect(ClaudeEvent.decode(line: stop.line()) == stop)
    }

    @Test func decodingRejectsJunk() {
        #expect(ClaudeEvent.decode(line: Data("junk\n".utf8)) == nil)
        #expect(ClaudeEvent.decode(line: Data(#"{"session":"s"}"#.utf8)) == nil)
        #expect(ClaudeEvent.decode(line: Data()) == nil)
    }
}
