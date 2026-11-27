import Foundation
import Testing
@testable import PhoneBoxCore

/// The state of every session, event by event (design §14 "Olay → durum").
struct ClaudeSessionsTests {
    static func event(_ kind: ClaudeEvent.Kind, _ session: String = "s1", tool: String? = nil, asks: Bool = false,
                      background: Bool = false, agent: String = "", cwd: String = "/Users/me/Code/PhoneBox",
                      pid: Int32 = 100, title: String? = nil, model: String? = nil, at: Int64 = 0) -> ClaudeEvent {
        ClaudeEvent(session: session, kind: kind, tool: tool, asks: asks, background: background, agent: agent,
                    cwd: cwd, transcript: "/t/\(session).jsonl", pid: pid, title: title, model: model, at: at)
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
        #expect(Self.state([Self.event(.prompt), Self.event(.toolStart, tool: "Agent"), Self.event(.stop, agent: "a1")])
            == (.working, nil, .agent))
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.stop, agent: "a1"), now: 1)
        #expect(sessions.count == 0)
    }

    @Test func aSubagentsToolsCountAsTheSessions() {
        #expect(Self.state([Self.event(.prompt), Self.event(.toolStart, tool: "Agent"), Self.event(.toolStart, tool: "Grep", agent: "a1")])
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

    // MARK: A turn that ends without a Stop

    /// Esc, or a turn that dies on an API error (StopFailure, which is a stop): the idle prompt's notification about a
    /// minute later ends the turn.
    @Test func theIdlePromptEndsAWorkingTurn() {
        #expect(Self.state([Self.event(.prompt), Self.event(.toolStart, tool: "Bash"), Self.event(.idle)]) == (.waiting, .turn, nil))
        #expect(Self.state([Self.event(.prompt), Self.event(.idle)]) == (.waiting, .turn, nil))
        // With a question in the end-of-turn box.
        #expect(Self.state([Self.event(.prompt), Self.event(.toolStart, tool: ClaudeEvent.wrapUpTool, asks: true), Self.event(.idle)])
            == (.waiting, .question, nil))
        #expect(Self.state([Self.event(.prompt), Self.event(.toolStart, tool: ClaudeEvent.wrapUpTool, asks: true), Self.event(.idle),
                            Self.event(.prompt), Self.event(.idle)]) == (.waiting, .turn, nil))
        #expect(Self.run([Self.event(.prompt), Self.event(.idle)])?.since == 2_000)
    }

    @Test func theIdlePromptChangesNothingElse() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.prompt), now: 1)
        sessions.apply(Self.event(.stop), now: 2)
        sessions.apply(Self.event(.idle), now: 62)
        #expect(sessions.list.first?.state == .waiting)
        #expect(sessions.list.first?.reason == .turn)
        #expect(sessions.list.first?.since == 2)
        #expect(Self.state([Self.event(.sessionStart), Self.event(.idle)]) == (.ready, nil, nil))
        #expect(Self.state([Self.event(.prompt), Self.event(.toolStart, tool: "AskUserQuestion", asks: true), Self.event(.idle)])
            == (.waiting, .question, nil))
        #expect(Self.state([Self.event(.prompt), Self.event(.permission, tool: "Bash"), Self.event(.idle)]) == (.waiting, .permission, nil))
        // A turn that ended with background tasks still running keeps working.
        #expect(Self.state([Self.event(.prompt), Self.event(.stop, background: true), Self.event(.idle)]) == (.working, nil, .background))
    }

    // MARK: Agents

    /// Subagent A asks for permission while subagent B and the main agent work on (bughunt #2): A's wait shows until
    /// A's own next event.
    @Test func oneAgentsWaitIsNotHiddenByAnothersEvents() {
        var sessions = ClaudeSessions()
        func shown() -> (ClaudeSession.State?, ClaudeSession.Reason?, Int64?) {
            (sessions.list.first?.state, sessions.list.first?.reason, sessions.list.first?.since)
        }
        sessions.apply(Self.event(.prompt), now: 1)
        sessions.apply(Self.event(.toolStart, tool: "Agent"), now: 2)
        sessions.apply(Self.event(.toolStart, tool: "Bash", agent: "A"), now: 3)
        sessions.apply(Self.event(.permission, tool: "Bash", agent: "A"), now: 4)
        #expect(shown() == (.waiting, .permission, 4))
        sessions.apply(Self.event(.toolStart, tool: "Read", agent: "B"), now: 5)
        #expect(shown() == (.waiting, .permission, 4))
        // The dialog's notification, which does not say whose it is.
        sessions.apply(Self.event(.permissionPrompt), now: 10)
        #expect(shown() == (.waiting, .permission, 4))
        sessions.apply(Self.event(.toolEnd, tool: "Read", agent: "B"), now: 11)
        sessions.apply(Self.event(.toolStart, tool: "Grep"), now: 12)
        #expect(shown() == (.waiting, .permission, 4))
        #expect(sessions.list.first?.activity == nil)
        // Approved and run: A's command ends.
        sessions.apply(Self.event(.toolEnd, tool: "Bash", agent: "A"), now: 20)
        #expect(shown() == (.working, nil, 20))
        #expect(sessions.list.first?.activity == .think)
    }

    /// The main agent's question while a background agent works on.
    @Test func aQuestionWaitsWhileAnotherAgentWorks() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.prompt), now: 1)
        sessions.apply(Self.event(.toolStart, tool: "Agent"), now: 2)
        sessions.apply(Self.event(.toolEnd, tool: "Agent"), now: 3)
        sessions.apply(Self.event(.toolStart, tool: "AskUserQuestion", asks: true), now: 4)
        for (index, event) in [Self.event(.toolStart, tool: "Bash", agent: "bg"), Self.event(.toolEnd, tool: "Bash", agent: "bg"),
                               Self.event(.toolStart, tool: "Read", agent: "bg")].enumerated() {
            sessions.apply(event, now: 5 + Int64(index))
            #expect(sessions.list.first?.state == .waiting)
            #expect(sessions.list.first?.reason == .question)
            #expect(sessions.list.first?.since == 4)
        }
        sessions.apply(Self.event(.toolEnd, tool: "AskUserQuestion"), now: 9)
        #expect(sessions.list.first?.state == .working)
        #expect(sessions.list.first?.since == 9)
    }

    /// While several agents wait, the session shows the one that has waited longest.
    @Test func theOldestWaitShows() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.prompt), now: 1)
        sessions.apply(Self.event(.permission, tool: "Bash", agent: "A"), now: 2)
        sessions.apply(Self.event(.toolStart, tool: "AskUserQuestion", asks: true, agent: "B"), now: 3)
        #expect(sessions.list.first?.reason == .permission)
        #expect(sessions.list.first?.since == 2)
        sessions.apply(Self.event(.toolEnd, tool: "Bash", agent: "A"), now: 4)
        #expect(sessions.list.first?.reason == .question)
        #expect(sessions.list.first?.since == 3)
        sessions.apply(Self.event(.toolEnd, tool: "AskUserQuestion", agent: "B"), now: 5)
        #expect(sessions.list.first?.state == .working)
        #expect(sessions.list.first?.since == 5)
    }

    @Test func aWaitEndsWithItsAgentsNextToolItsEndAPromptOrTheTurnsEnd() {
        // The agent does something else (the permission was refused).
        #expect(Self.state([Self.event(.prompt), Self.event(.permission, tool: "Bash", agent: "A"),
                            Self.event(.toolStart, tool: "Read", agent: "A")]) == (.working, nil, .read))
        // It ends (SubagentStop).
        #expect(Self.state([Self.event(.prompt), Self.event(.toolStart, tool: "Agent"), Self.event(.permission, tool: "Bash", agent: "A"),
                            Self.event(.stop, agent: "A")]) == (.working, nil, .agent))
        // A prompt ends every wait.
        #expect(Self.state([Self.event(.prompt), Self.event(.permission, tool: "Bash", agent: "A"),
                            Self.event(.toolStart, tool: "AskUserQuestion", asks: true, agent: "B"), Self.event(.prompt)])
            == (.working, nil, .think))
        // So does the end of the turn, unless background tasks run on: their agents may still wait.
        #expect(Self.state([Self.event(.prompt), Self.event(.permission, tool: "Bash", agent: "A"), Self.event(.stop)])
            == (.waiting, .turn, nil))
        #expect(Self.state([Self.event(.prompt), Self.event(.permission, tool: "Bash", agent: "bg"),
                            Self.event(.stop, background: true)]) == (.waiting, .permission, nil))
        #expect(Self.state([Self.event(.prompt), Self.event(.permission, tool: "Bash"), Self.event(.stop, background: true)])
            == (.working, nil, .background))
    }

    /// The dialog's notification comes a few seconds after the request: it starts a wait only when none is known
    /// (PhoneBox was turned on in the meantime).
    @Test func thePermissionNotificationStartsAWaitOnlyWhenNoneIsKnown() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.prompt), now: 1)
        sessions.apply(Self.event(.permissionPrompt), now: 5)
        #expect(sessions.list.first?.state == .waiting)
        #expect(sessions.list.first?.reason == .permission)
        #expect(sessions.list.first?.since == 5)
        sessions.apply(Self.event(.toolEnd, tool: "Bash"), now: 6)
        #expect(sessions.list.first?.state == .working)
        // A question is not a permission.
        sessions.apply(Self.event(.toolStart, tool: "AskUserQuestion", asks: true, agent: "A"), now: 7)
        sessions.apply(Self.event(.permissionPrompt), now: 8)
        sessions.apply(Self.event(.toolEnd, tool: "AskUserQuestion", agent: "A"), now: 9)
        #expect(sessions.list.first?.reason == .permission)
        #expect(sessions.list.first?.since == 8)
    }

    // MARK: An approved command

    static func child(_ pid: Int32 = 900, start: Int64, path: String = "/bin/zsh") -> ClaudeSessions.ChildProcess {
        ClaudeSessions.ChildProcess(pid: pid, start: start, path: path)
    }

    /// `applyApprovals` outside `#expect`, which cannot hold a mutating call.
    func approve(_ sessions: inout ClaudeSessions, pid: Int32, children: [ClaudeSessions.ChildProcess], now: Int64) -> Bool {
        sessions.applyApprovals(pid: pid, children: children, now: now)
    }

    /// No hook says that the user approved a command (bughunt #3): its shell starting as a child of the session's
    /// process does. Hooks start with their event, so only a child that started well after the session's last event
    /// counts, and only once it has run a moment (an event of its time may still be on its way).
    @Test func aShellStartedAfterTheLastEventIsTheApprovedCommand() {
        let last: Int64 = 10_000_000
        func found(_ children: [ClaudeSessions.ChildProcess], settled: Int64 = 60_000_000) -> Int32? {
            ClaudeSessions.approvedCommand(lastEvent: last, children: children, startedBy: settled)?.pid
        }
        #expect(found([Self.child(start: last + 600_000)]) == 900)
        #expect(found([Self.child(start: last + 400_000)]) == nil)
        #expect(found([Self.child(start: last - 5_000_000)]) == nil)
        #expect(found([Self.child(start: last + 600_000)], settled: last + 550_000) == nil)
        #expect(found([Self.child(start: last + 600_000)], settled: last + 600_000) == 900)
        // The command runs in the user's shell. Claude Code also starts git, security (the keychain) and caffeinate
        // at any time, and hooks with their events: PhoneBox's helper, a script, or `sh` running a longer command.
        for path in ["/bin/bash", "/opt/homebrew/bin/bash", "/usr/local/bin/zsh"] {
            #expect(found([Self.child(start: last + 600_000, path: path)]) == 900, "\(path)")
        }
        for path in ["/Applications/PhoneBox.app/Contents/MacOS/PhoneBox", "/usr/bin/caffeinate", "/usr/bin/git",
                     "/usr/bin/security", "/bin/sh", "/usr/local/bin/node", "", "zsh-x"] {
            #expect(found([Self.child(start: last + 600_000, path: path)]) == nil, "\(path)")
        }
        // The first of several.
        #expect(found([Self.child(901, start: last + 900_000), Self.child(902, start: last + 700_000),
                       Self.child(903, start: last + 650_000, path: "/usr/bin/caffeinate")]) == 902)
    }

    @Test func anApprovedCommandWorks() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.prompt, at: 1_000_000), now: 1_000)
        sessions.apply(Self.event(.toolStart, tool: "Bash", at: 2_000_000), now: 2_000)
        #expect(sessions.pidsWaitingToRunACommand.isEmpty)
        sessions.apply(Self.event(.permission, tool: "Bash", at: 2_100_000), now: 2_100)
        #expect(sessions.pidsWaitingToRunACommand == [100])
        // An MCP server from the session's start, another process's child.
        #expect(!approve(&sessions, pid: 100, children: [Self.child(start: 500_000)], now: 10_000))
        #expect(!approve(&sessions, pid: 101, children: [Self.child(start: 5_000_000)], now: 10_000))
        #expect(sessions.list.first?.state == .waiting)
        #expect(approve(&sessions, pid: 100, children: [Self.child(start: 5_000_000)], now: 10_000))
        #expect(sessions.list.first?.state == .working)
        #expect(sessions.list.first?.activity == .command)
        #expect(sessions.list.first?.since == 10_000)
        #expect(sessions.pidsWaitingToRunACommand.isEmpty)
        // The dialog's notification, sent before the approval but come in late, is old news.
        sessions.apply(Self.event(.permissionPrompt, at: 4_900_000), now: 10_001)
        #expect(sessions.list.first?.state == .working)
        sessions.apply(Self.event(.toolEnd, tool: "Bash", at: 20_000_000), now: 20_000)
        #expect(sessions.list.first?.activity == .think)
    }

    @Test func onlyACommandsPermissionIsApprovedThisWay() {
        for wait in [Self.event(.toolStart, tool: "ExitPlanMode", at: 1), Self.event(.permission, tool: "Edit", at: 1),
                     Self.event(.permissionPrompt, at: 1), Self.event(.toolStart, tool: "AskUserQuestion", asks: true, at: 1)] {
            var sessions = ClaudeSessions()
            sessions.apply(wait, now: 1)
            #expect(sessions.pidsWaitingToRunACommand.isEmpty)
            #expect(!approve(&sessions, pid: 100, children: [Self.child(start: 5_000_000)], now: 10_000))
            #expect(sessions.list.first?.state == .waiting)
        }
    }

    /// Every event of the process's sessions moves the time the command's shell must come after: another agent's tool
    /// and the hooks of the dialog's notification start their own children.
    @Test func childrenOfLaterEventsAreNotTheApproval() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.permission, tool: "Bash", agent: "A", at: 2_000_000), now: 2_000)
        sessions.apply(Self.event(.toolStart, tool: "Bash", agent: "B", at: 6_000_000), now: 6_000)
        // Another session in the same process.
        sessions.apply(Self.event(.prompt, "s2", at: 8_000_000), now: 8_000)
        #expect(!approve(&sessions, pid: 100, children: [Self.child(start: 6_010_000), Self.child(start: 8_100_000)], now: 20_000))
        #expect(sessions.list.first?.state == .waiting)
        #expect(approve(&sessions, pid: 100, children: [Self.child(start: 8_600_000)], now: 20_000))
        #expect(sessions.list.first(where: { $0.id == "s1" })?.state == .working)
    }

    /// Two agents wait to run a command: one shell is one approval, for the one that asked first.
    @Test func oneShellApprovesOneCommand() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.permission, tool: "Bash", agent: "A", at: 2_000_000), now: 2_000)
        sessions.apply(Self.event(.permission, tool: "Bash", agent: "B", at: 3_000_000), now: 3_000)
        #expect(approve(&sessions, pid: 100, children: [Self.child(start: 4_000_000)], now: 10_000))
        #expect(sessions.list.first?.state == .waiting)
        #expect(sessions.list.first?.since == 3_000)
        // B's own end then shows A's approval.
        sessions.apply(Self.event(.toolEnd, tool: "Bash", agent: "B", at: 5_000_000), now: 10_001)
        #expect(sessions.list.first?.state == .working)
    }

    // MARK: Saved across a restart

    @Test func savedSessionsComeBackWhileTheirProcessRuns() throws {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.prompt, "a", pid: 10, at: 100), now: 1)
        sessions.apply(Self.event(.permission, "a", tool: "Bash", agent: "A", pid: 10, at: 200), now: 2)
        sessions.apply(Self.event(.sessionStart, "b", pid: 20, at: 300), now: 3)
        sessions.setDetails(session: "b", title: "Named", model: "Opus 5.5")
        sessions.apply(Self.event(.prompt, "c", pid: 30, at: 400), now: 4)
        sessions.apply(Self.event(.sessionEnd, "d", pid: 40, at: 500), now: 5)
        let saved = sessions.saved(now: 6)
        var asked: [String] = []
        var restored = try #require(ClaudeSessions(saved: saved, now: 7, keep: { pid, at in
            asked.append("\(pid)@\(at)")
            return pid != 30
        }))
        #expect(asked.sorted() == ["10@200", "20@300", "30@400"])
        #expect(restored.list == sessions.list.filter { $0.id != "c" })
        // The agents' waits and the order of events come back too.
        restored.apply(Self.event(.stop, "b", pid: 20, at: 250), now: 8)
        #expect(restored.list.first(where: { $0.id == "b" })?.state == .ready)
        restored.apply(Self.event(.toolEnd, "a", tool: "Bash", pid: 10, at: 600), now: 9)
        #expect(restored.list.first(where: { $0.id == "a" })?.state == .waiting)
        restored.apply(Self.event(.toolEnd, "a", tool: "Bash", agent: "A", pid: 10, at: 700), now: 10)
        #expect(restored.list.first(where: { $0.id == "a" })?.state == .working)
        #expect(restored.pidsWaitingToRunACommand.isEmpty)
        #expect(sessions.pidsWaitingToRunACommand == [10])
    }

    /// A list saved long ago says little about the sessions now (the feature was off in between); junk says nothing.
    @Test func anOldOrBrokenSaveIsNotUsed() throws {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.prompt), now: 1)
        let saved = sessions.saved(now: 1_000)
        #expect(try #require(ClaudeSessions(saved: saved, now: 1_000 + ClaudeSessions.savedLife, keep: { _, _ in true })).count == 1)
        #expect(ClaudeSessions(saved: saved, now: 1_001 + ClaudeSessions.savedLife, keep: { _, _ in true }) == nil)
        #expect(ClaudeSessions(saved: Data("junk".utf8), now: 1_000, keep: { _, _ in true }) == nil)
        #expect(ClaudeSessions(saved: Data(), now: 1_000, keep: { _, _ in true }) == nil)
        #expect(ClaudeSessions(saved: ClaudeSessions().saved(now: 5), now: 6, keep: { _, _ in true })?.count == 0)
    }

    // MARK: Order

    /// Each hook runs as its own process: the PermissionRequest can come in before its PreToolUse.
    @Test func anEventThatRanBeforeTheLastOneIsIgnored() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.prompt, at: 100), now: 1)
        sessions.apply(Self.event(.permission, tool: "Bash", at: 300), now: 2)
        sessions.apply(Self.event(.toolStart, tool: "Bash", at: 200), now: 3)
        #expect(sessions.list.first?.state == .waiting)
        #expect(sessions.list.first?.reason == .permission)
        #expect(sessions.list.first?.since == 2)
        // The answer comes later than both.
        sessions.apply(Self.event(.toolEnd, tool: "Bash", at: 400), now: 4)
        #expect(sessions.list.first?.state == .working)
    }

    /// Events of the same microsecond keep the order they came in.
    @Test func anEventOfTheSameTimeIsApplied() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.prompt, at: 100), now: 1)
        sessions.apply(Self.event(.toolStart, tool: "Bash", at: 100), now: 2)
        #expect(sessions.list.first?.activity == .command)
        sessions.apply(Self.event(.toolEnd, tool: "Bash", at: 100), now: 3)
        #expect(sessions.list.first?.activity == .think)
    }

    @Test func theOrderIsKeptForEachSession() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.prompt, "a", at: 500), now: 1)
        sessions.apply(Self.event(.prompt, "b", at: 100), now: 2)
        #expect(sessions.list.map(\.id).sorted() == ["a", "b"])
    }

    /// A Stop that comes in after its SessionEnd does not bring the closed session back.
    @Test func anEventOfAnEndedSessionIsIgnored() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.prompt, at: 100), now: 1_000)
        sessions.apply(Self.event(.sessionEnd, at: 300), now: 1_001)
        sessions.apply(Self.event(.stop, at: 200), now: 1_002)
        #expect(sessions.count == 0)
        sessions.apply(Self.event(.toolEnd, at: 300), now: 1_003)
        #expect(sessions.count == 0)
        // Even when the session had already been dropped or never been seen.
        sessions.apply(Self.event(.sessionEnd, "x", at: 50), now: 1_004)
        sessions.apply(Self.event(.stop, "x", at: 40), now: 1_005)
        #expect(sessions.count == 0)
    }

    /// `claude --resume` opens the same session again.
    @Test func aSessionThatStartsAgainAfterItsEndIsAccepted() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.prompt, at: 100), now: 1_000)
        sessions.apply(Self.event(.sessionEnd, at: 300), now: 1_001)
        sessions.apply(Self.event(.sessionStart, at: 301), now: 5_000)
        #expect(sessions.list.first?.state == .ready)
        #expect(sessions.list.first?.since == 5_000)
        sessions.apply(Self.event(.prompt, at: 302), now: 5_001)
        #expect(sessions.list.first?.state == .working)
    }

    /// An ended session is remembered for a minute.
    @Test func anEndIsForgottenAfterAMinute() {
        var sessions = ClaudeSessions()
        sessions.apply(Self.event(.sessionEnd, at: 300), now: 1_000)
        sessions.apply(Self.event(.stop, at: 200), now: 61_000)
        #expect(sessions.count == 0)
        sessions.apply(Self.event(.stop, at: 200), now: 61_001)
        #expect(sessions.list.first?.state == .waiting)
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
