import Foundation
import Testing
@testable import PhoneBoxCore

/// The state of every session, event by event (design §14 "Olay → durum").
struct ClaudeSessionsTests {
    static func event(_ kind: ClaudeEvent.Kind, _ session: String = "s1", tool: String? = nil, asks: Bool = false,
                      background: Bool = false, subagent: Bool = false, cwd: String = "/Users/me/Code/PhoneBox",
                      pid: Int32 = 100, title: String? = nil, model: String? = nil) -> ClaudeEvent {
        ClaudeEvent(session: session, kind: kind, tool: tool, asks: asks, background: background, subagent: subagent,
                    cwd: cwd, transcript: "/t/\(session).jsonl", pid: pid, title: title, model: model)
    }

    /// `events` applied one second apart, starting at 1000 ms; the one session that results.
    static func run(_ events: [ClaudeEvent]) -> ClaudeSession? {
        var sessions = ClaudeSessions()
        for (index, event) in events.enumerated() { sessions.apply(event, now: 1_000 * Int64(index + 1)) }
        return sessions.list.first
    }

    static func state(_ events: [ClaudeEvent]) -> (ClaudeSession.State?, ClaudeSession.Reason?, ClaudeSession.Activity?) {
        let session = run(events)
        return (session?.state, session?.reason, session?.activity)
    }

    // MARK: The table

    @Test func aNewSessionIsReadyAndNamedAfterItsFolder() throws {
        let session = try #require(Self.run([Self.event(.sessionStart)]))
        #expect(session == ClaudeSession(id: "s1", title: "PhoneBox", project: "PhoneBox", model: nil, state: .ready,
                                         reason: nil, activity: nil, since: 1_000))
    }

    @Test func aSessionWithoutAFolderIsCalledClaude() throws {
        #expect(Self.run([Self.event(.sessionStart, cwd: "")])?.title == "Claude")
        #expect(Self.run([Self.event(.sessionStart, cwd: "/")])?.project == "Claude")
        #expect(Self.run([Self.event(.sessionStart, cwd: "/Users/me/Code/web/")])?.project == "web")
    }

    @Test func sessionStartKeepsTheStateOfAKnownSession() {
        // `/clear` and compaction start the session again.
        let session = Self.run([Self.event(.sessionStart), Self.event(.prompt), Self.event(.sessionStart)])
        #expect(session?.state == .working)
        #expect(session?.activity == .think)
        #expect(session?.since == 2_000)
    }

    @Test func aPromptStartsWorkingAndThinking() {
        #expect(Self.state([Self.event(.sessionStart), Self.event(.prompt)]) == (.working, nil, .think))
    }

    @Test func aQuestionWaits() {
        #expect(Self.state([Self.event(.prompt), Self.event(.toolStart, tool: "AskUserQuestion", asks: true)])
            == (.waiting, .question, nil))
    }

    @Test func leavingPlanModeWaitsForPermission() {
        #expect(Self.state([Self.event(.prompt), Self.event(.toolStart, tool: "ExitPlanMode")]) == (.waiting, .permission, nil))
    }

    @Test func otherToolsWorkWithTheirKind() {
        let cases: [(String?, ClaudeSession.Activity)] = [
            ("Bash", .command), ("BashOutput", .command), ("KillShell", .command), ("Edit", .edit), ("Write", .edit),
            ("MultiEdit", .edit), ("NotebookEdit", .edit), ("Read", .read), ("Grep", .read), ("Glob", .read), ("LS", .read),
            ("WebFetch", .web), ("WebSearch", .web), ("Agent", .agent), ("Task", .agent), ("mcp__x__y", .tool),
            (nil, .tool), (ClaudeEvent.wrapUpTool, .tool),
        ]
        for (tool, activity) in cases {
            #expect(Self.state([Self.event(.prompt), Self.event(.toolStart, tool: tool)]) == (.working, nil, activity),
                    "\(tool ?? "nil")")
        }
    }

    @Test func permissionWaits() {
        #expect(Self.state([Self.event(.prompt), Self.event(.toolStart, tool: "Bash"), Self.event(.permission, tool: "Bash")])
            == (.waiting, .permission, nil))
    }

    @Test func theEndOfAToolGoesBackToThinking() {
        #expect(Self.state([Self.event(.prompt), Self.event(.toolStart, tool: "Bash"), Self.event(.toolEnd, tool: "Bash")])
            == (.working, nil, .think))
        // Answered: the question's or the permission's tool ends.
        #expect(Self.state([Self.event(.prompt), Self.event(.toolStart, tool: "AskUserQuestion", asks: true),
                            Self.event(.toolEnd, tool: "AskUserQuestion")]) == (.working, nil, .think))
        #expect(Self.state([Self.event(.prompt), Self.event(.permission, tool: "Bash"), Self.event(.toolEnd, tool: "Bash")])
            == (.working, nil, .think))
        #expect(Self.state([Self.event(.sessionStart), Self.event(.toolEnd)]) == (.working, nil, .think))
    }

    @Test func aStopWaitsForTheUser() {
        #expect(Self.state([Self.event(.prompt), Self.event(.stop)]) == (.waiting, .turn, nil))
    }

    @Test func aStopWithBackgroundTasksKeepsWorking() {
        #expect(Self.state([Self.event(.prompt), Self.event(.stop, background: true)]) == (.working, nil, .background))
    }

    @Test func aWrapUpWithAQuestionMakesTheStopAQuestion() {
        let wrapUp = Self.event(.toolStart, tool: ClaudeEvent.wrapUpTool, asks: true)
        #expect(Self.state([Self.event(.prompt), wrapUp]) == (.working, nil, .tool))
        #expect(Self.state([Self.event(.prompt), wrapUp, Self.event(.toolEnd, tool: ClaudeEvent.wrapUpTool), Self.event(.stop)])
            == (.waiting, .question, nil))
        // Without a question it is an ordinary end of the turn.
        #expect(Self.state([Self.event(.prompt), Self.event(.toolStart, tool: ClaudeEvent.wrapUpTool), Self.event(.stop)])
            == (.waiting, .turn, nil))
    }

    @Test func theQuestionMarkLastsOneTurn() {
        let wrapUp = Self.event(.toolStart, tool: ClaudeEvent.wrapUpTool, asks: true)
        // A stop clears it.
        #expect(Self.state([Self.event(.prompt), wrapUp, Self.event(.stop), Self.event(.prompt), Self.event(.stop)])
            == (.waiting, .turn, nil))
        // So does a prompt.
        #expect(Self.state([Self.event(.prompt), wrapUp, Self.event(.prompt), Self.event(.stop)]) == (.waiting, .turn, nil))
    }

    @Test func aSubagentsStopIsIgnored() {
        #expect(Self.state([Self.event(.prompt), Self.event(.toolStart, tool: "Agent"), Self.event(.stop, subagent: true)])
            == (.working, nil, .agent))
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.stop, subagent: true), now: 1)
        #expect(sessions.count == 0)
    }

    @Test func aSubagentsToolsCountAsTheSessions() {
        #expect(Self.state([Self.event(.prompt), Self.event(.toolStart, tool: "Agent"), Self.event(.toolStart, tool: "Grep", subagent: true)])
            == (.working, nil, .read))
    }

    @Test func sessionEndRemovesTheSession() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.sessionStart, "a"), now: 1)
        sessions.apply(Self.event(.sessionStart, "b"), now: 2)
        sessions.apply(Self.event(.sessionEnd, "a"), now: 3)
        #expect(sessions.list.map(\.id) == ["b"])
        // An unknown session's end adds nothing.
        sessions.apply(Self.event(.sessionEnd, "c"), now: 4)
        #expect(sessions.count == 1)
    }

    @Test func anEventForAnUnknownSessionCreatesIt() throws {
        // PhoneBox was turned on in the middle of a session.
        let session = try #require(Self.run([Self.event(.toolStart, tool: "Edit", cwd: "/Users/me/notes")]))
        #expect(session.title == "notes")
        #expect(session.project == "notes")
        #expect(session.state == .working)
        #expect(session.activity == .edit)
        #expect(session.since == 1_000)
    }

    // MARK: Time

    @Test func theTimeRestartsOnlyWhenTheStateOrTheReasonChanges() {
        var sessions = ClaudeSessions()
        func since() -> Int64? { sessions.list.first?.since }
        sessions.apply(Self.event(.sessionStart), now: 1)
        sessions.apply(Self.event(.sessionStart), now: 2)
        #expect(since() == 1)
        sessions.apply(Self.event(.prompt), now: 10)
        #expect(since() == 10)
        // Tools of the same turn keep it.
        sessions.apply(Self.event(.toolStart, tool: "Bash"), now: 11)
        sessions.apply(Self.event(.toolEnd, tool: "Bash"), now: 12)
        sessions.apply(Self.event(.toolStart, tool: "Read"), now: 13)
        sessions.apply(Self.event(.stop, background: true), now: 14)
        #expect(since() == 10)
        sessions.apply(Self.event(.permission, tool: "Bash"), now: 20)
        #expect(since() == 20)
        // The permission's notification arrives a few seconds after the request.
        sessions.apply(Self.event(.permission), now: 26)
        #expect(since() == 20)
        sessions.apply(Self.event(.toolStart, tool: "AskUserQuestion", asks: true), now: 30)
        #expect(since() == 30)
        sessions.apply(Self.event(.toolEnd, tool: "AskUserQuestion"), now: 40)
        #expect(since() == 40)
        sessions.apply(Self.event(.stop), now: 50)
        #expect(since() == 50)
        sessions.apply(Self.event(.stop), now: 51)
        #expect(since() == 50)
    }

    @Test func aPromptAlwaysRestartsTheTime() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.prompt), now: 1)
        sessions.apply(Self.event(.prompt), now: 5)
        #expect(sessions.list.first?.since == 5)
    }

    // MARK: The list

    @Test func listsWaitingThenWorkingThenReadyOldestFirst() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.sessionStart, "ready-old"), now: 1)
        sessions.apply(Self.event(.prompt, "work-old"), now: 2)
        sessions.apply(Self.event(.stop, "wait-new"), now: 9)
        sessions.apply(Self.event(.sessionStart, "ready-new"), now: 4)
        sessions.apply(Self.event(.prompt, "work-new"), now: 5)
        sessions.apply(Self.event(.permission, "wait-old"), now: 6)
        #expect(sessions.list.map(\.id) == ["wait-old", "wait-new", "work-old", "work-new", "ready-old", "ready-new"])
        #expect(sessions.count == 6)
    }

    @Test func listsAtMostTwelve() {
        var sessions = ClaudeSessions()
        for index in 0..<15 { sessions.apply(Self.event(.sessionStart, "s\(index)"), now: Int64(index)) }
        sessions.apply(Self.event(.stop, "s14"), now: 100)
        #expect(ClaudeSessions.maxListed == 12)
        #expect(sessions.count == 15)
        #expect(sessions.list.count == 12)
        // The waiting one is never the one left out.
        #expect(sessions.list.first?.id == "s14")
        #expect(sessions.list.last?.id == "s10")
        #expect(sessions.ids == Set((0..<15).map { "s\($0)" }))
    }

    @Test func removesSessionsWhoseProcessEnded() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.sessionStart, "a", pid: 10), now: 1)
        sessions.apply(Self.event(.sessionStart, "b", pid: 20), now: 2)
        sessions.apply(Self.event(.sessionStart, "c", pid: 30), now: 3)
        // Every event says which process the session is in now (`claude --resume` in another terminal).
        sessions.apply(Self.event(.prompt, "c", pid: 31), now: 4)
        sessions.removeSessions(whosePIDIsDead: { $0 == 10 || $0 == 30 })
        #expect(sessions.list.map(\.id).sorted() == ["b", "c"])
        sessions.removeSessions(whosePIDIsDead: { $0 == 31 })
        #expect(sessions.list.map(\.id) == ["b"])
    }

    // MARK: Details

    @Test func setDetailsReplacesTheTitleAndTheModel() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.sessionStart), now: 1)
        sessions.setDetails(session: "s1", title: "Menu fix", model: "Opus 5.5")
        #expect(sessions.list.first?.title == "Menu fix")
        #expect(sessions.list.first?.model == "Opus 5.5")
        #expect(sessions.list.first?.project == "PhoneBox")
        sessions.setDetails(session: "s1", title: nil, model: nil)
        sessions.setDetails(session: "s1", title: "", model: nil)
        sessions.setDetails(session: "s1", title: "   ", model: nil)
        #expect(sessions.list.first?.title == "Menu fix")
        #expect(sessions.list.first?.model == "Opus 5.5")
        sessions.setDetails(session: "s1", title: "Other", model: "Sonnet 4.5")
        #expect(sessions.list.first?.title == "Other")
        #expect(sessions.list.first?.model == "Sonnet 4.5")
        // An unknown session is not created.
        sessions.setDetails(session: "s2", title: "Ghost", model: nil)
        #expect(sessions.count == 1)
    }

    @Test func sessionStartAppliesItsTitleAndModel() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.sessionStart, title: "Named", model: "claude-sonnet-4-5-20250929"), now: 1)
        #expect(sessions.list.first?.title == "Named")
        #expect(sessions.list.first?.model == "Sonnet 4.5")
        // A model id without a name is not shown.
        sessions.apply(Self.event(.sessionStart, model: "gpt-4"), now: 2)
        #expect(sessions.list.first?.model == "Sonnet 4.5")
        #expect(sessions.list.first?.title == "Named")
    }

    // MARK: JSON

    @Test func encodesASessionWithoutEmptyFields() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let ready = ClaudeSession(id: "s", title: "T", project: "P", model: nil, state: .ready, reason: nil, activity: nil, since: 5)
        #expect(String(decoding: try encoder.encode(ready), as: UTF8.self)
            == #"{"id":"s","project":"P","since":5,"state":"ready","title":"T"}"#)
        let waiting = ClaudeSession(id: "s", title: "T", project: "P", model: "Opus 5.5", state: .waiting, reason: .question,
                                    activity: nil, since: 5)
        #expect(String(decoding: try encoder.encode(waiting), as: UTF8.self)
            == #"{"id":"s","model":"Opus 5.5","project":"P","reason":"question","since":5,"state":"waiting","title":"T"}"#)
        let working = ClaudeSession(id: "s", title: "T", project: "P", model: nil, state: .working, reason: nil,
                                    activity: .background, since: 5)
        #expect(String(decoding: try encoder.encode(working), as: UTF8.self)
            == #"{"activity":"background","id":"s","project":"P","since":5,"state":"working","title":"T"}"#)
    }
}
