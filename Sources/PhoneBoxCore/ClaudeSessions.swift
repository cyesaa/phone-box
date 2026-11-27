import Foundation

/// One Claude Code session as the phone shows it (design §14 "Ne gösterir"). In the snapshot's `claude` array.
public struct ClaudeSession: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case ready, working, waiting }
    /// Why a session waits; only while `waiting`.
    public enum Reason: String, Codable, Sendable { case question, permission, turn }
    /// What a session does; only while `working`.
    public enum Activity: String, Codable, Sendable { case think, command, edit, read, web, agent, tool, background }

    public var id: String
    public var title: String
    /// The name of the session's folder.
    public var project: String
    /// "Opus 5.5"; nil while not known.
    public var model: String?
    public var state: State
    public var reason: Reason?
    public var activity: Activity?
    /// Milliseconds since 1970 when the state (or the reason for waiting) began.
    public var since: Int64

    public init(id: String, title: String, project: String, model: String?, state: State, reason: Reason?,
                activity: Activity?, since: Int64) {
        self.id = id
        self.title = title
        self.project = project
        self.model = model
        self.state = state
        self.reason = reason
        self.activity = activity
        self.since = since
    }
}

/// Every open session, kept up to date from hook events (design §14 "Olay → durum").
public struct ClaudeSessions: Sendable {
    public static let maxListed = 12
    /// How long an ended session is remembered (ms), so that its late events do not bring it back.
    public static let endMemory: Int64 = 60_000
    /// A list saved longer ago than this (ms) is not used: the sessions have changed in ways no event will tell (the
    /// feature was off, or PhoneBox did not run).
    public static let savedLife: Int64 = 10 * 60_000

    /// A child process of a session's `claude`.
    public struct ChildProcess: Equatable, Sendable {
        public var pid: Int32
        /// When it started, in microseconds since 1970: the clock of an event's `at`.
        public var start: Int64
        /// What it was started with, its executable first; empty when they cannot be read.
        public var arguments: [String]

        public init(pid: Int32, start: Int64, arguments: [String]) {
            self.pid = pid
            self.start = start
            self.arguments = arguments
        }
    }

    /// A command shell that starts within this many microseconds of an event may be that event's own command (another
    /// agent's tool).
    public static let eventStartMargin: Int64 = 500_000
    /// A child counts once it has run this many microseconds: an event of its time may still be on its way.
    public static let childSettling: Int64 = 250_000
    /// In an argument of every shell Claude Code runs a command of its Bash tool in: the user's shell (zsh or bash)
    /// first reads Claude Code's snapshot of the user's shell settings (`zsh -c source
    /// ~/.claude/shell-snapshots/snapshot-zsh-….sh … && …`, seen with 2.1.330 on 2026-11-27). Hooks and the status line
    /// run in a plain `sh -c` (bash on macOS) or as themselves, and the `git`, `security` and `caffeinate` that `claude`
    /// starts at any time without it.
    static let commandShellMark = "/.claude/shell-snapshots/snapshot-"

    /// What a session does apart from its agents' waits: ready, working, or waiting for its turn.
    private struct Mode: Codable, Sendable {
        var state: ClaudeSession.State
        var reason: ClaudeSession.Reason?
        var activity: ClaudeSession.Activity?
    }

    /// An agent waiting for the user.
    private struct Wait: Codable, Sendable {
        var reason: ClaudeSession.Reason
        /// When it began (`now`, ms).
        var since: Int64
        /// The tool that asked for permission.
        var tool: String?

        var isForACommand: Bool { reason == .permission && tool == "Bash" }
    }

    private struct Entry: Codable, Sendable {
        /// As listed: the oldest of `waits`, or else `mode`.
        var session: ClaudeSession
        var pid: Int32
        /// The end-of-turn box asked a question: the turn's stop waits with `question`.
        var questionAtEnd = false
        /// The `at` of the last event applied, or the start of a command seen approved.
        var at: Int64
        var mode: Mode
        /// Each agent's wait, by `agent` ("" for the main agent).
        var waits: [String: Wait] = [:]
        /// The `at` of each agent's last own event (`AgentEffect`) since `allAgentsAt`, or the start of its command
        /// seen approved.
        var agentsAt: [String: Int64] = [:]
        /// The `at` of the last event that ended every agent's wait: a prompt, the end of the turn.
        var allAgentsAt: Int64 = .min

        /// An event of `agent` older than this is old news for it.
        func lastAt(of agent: String) -> Int64 { agentsAt[agent] ?? allAgentsAt }
    }

    /// What an event of one agent's own says about that agent's wait.
    private enum AgentEffect {
        case wait(ClaudeSession.Reason)
        case end
    }

    private struct End: Sendable {
        /// The SessionEnd's `at`.
        var at: Int64
        /// When it came in (`now`, ms).
        var received: Int64
    }

    private struct Saved: Codable {
        /// When it was saved (ms).
        var saved: Int64
        var entries: [String: Entry]
    }

    private var entries: [String: Entry] = [:]
    private var ended: [String: End] = [:]

    public init() {}

    /// The sessions `saved(now:)` gave at most `savedLife` ago, those for which `keep(pid, at)` holds. `at` is the
    /// session's last event, a hook its process ran: a process with that pid that started later is another one. Nil
    /// for anything else.
    public init?(saved data: Data, now: Int64, keep: (_ pid: Int32, _ at: Int64) -> Bool) {
        guard let saved = try? JSONDecoder().decode(Saved.self, from: data), now - saved.saved <= Self.savedLife
        else { return nil }
        entries = saved.entries.filter { keep($0.value.pid, $0.value.at) }
    }

    /// Every session, with its agents' waits and the order of its events, for after a restart (`now`, ms).
    public func saved(now: Int64) -> Data {
        (try? JSONEncoder().encode(Saved(saved: now, entries: entries))) ?? Data()
    }

    /// Waiting sessions (the one waiting longest first), then working, then ready ones; at most `maxListed`.
    public var list: [ClaudeSession] {
        func rank(_ state: ClaudeSession.State) -> Int {
            switch state {
            case .waiting: return 0
            case .working: return 1
            case .ready: return 2
            }
        }
        let sorted = entries.values.map(\.session).sorted { a, b in
            if a.state != b.state { return rank(a.state) < rank(b.state) }
            if a.since != b.since { return a.since < b.since }
            return a.id < b.id
        }
        return Array(sorted.prefix(Self.maxListed))
    }

    public var count: Int { entries.count }

    /// Every session's id, listed or not.
    public var ids: Set<String> { Set(entries.keys) }

    /// The processes with a session one of whose agents waits for permission to run a command (`Bash`).
    public var pidsWaitingToRunACommand: Set<Int32> {
        Set(entries.values.filter { $0.waits.values.contains(where: \.isForACommand) }.map(\.pid))
    }

    /// Applies one event at `now` (ms). Hooks run as separate processes and can come in out of order: an event that ran
    /// before the session's last one, or no later than its end, is old news (design §14), except for what an agent's own
    /// event says about that agent's wait (`applyToItsAgent`). Each agent of the session ("" the main one) waits on its
    /// own: the session waits while any of them does.
    public mutating func apply(_ event: ClaudeEvent, now: Int64) {
        if !ended.isEmpty { ended = ended.filter { now - $0.value.received <= Self.endMemory } }
        // A subagent's stop ends only its own wait; it makes no session.
        if event.kind == .stop, event.subagent, entries[event.session] == nil { return }
        // `at` is wall-clock time (the helper's start time): if the Mac's clock steps back, the events of a known session
        // are ignored until the clock passes the last `at` applied.
        if let end = ended[event.session] {
            // A session can start again after its end (`claude --resume`).
            guard event.at > end.at else { return }
            ended[event.session] = nil
        }
        if let known = entries[event.session], event.at < known.at { return applyToItsAgent(event, now: now) }
        if event.kind == .sessionEnd {
            entries[event.session] = nil
            ended[event.session] = End(at: event.at, received: now)
            return
        }
        var entry = entries[event.session] ?? Self.newEntry(for: event, now: now)
        entry.pid = event.pid
        entry.at = event.at
        if Self.agentEffect(of: event) != nil { entry.agentsAt[event.agent] = event.at }
        switch event.kind {
        case .sessionStart:
            entries[event.session] = entry
            setDetails(session: event.session, title: event.title,
                       model: event.model.flatMap(ClaudeTranscript.modelName))
            return
        case .prompt:
            entry.questionAtEnd = false
            entry.waits = [:]
            entry.agentsAt = [:]
            entry.allAgentsAt = event.at
            entry.mode = Mode(state: .working, activity: .think)
            Self.show(&entry, now: now)
            // A new turn: its time starts now even when the last one was still running.
            entry.session.since = now
            entries[event.session] = entry
            return
        case .toolStart:
            switch event.tool {
            case ClaudeEvent.questionTool:
                Self.wait(&entry, agent: event.agent, reason: .question, tool: event.tool, now: now)
            case "ExitPlanMode":
                Self.wait(&entry, agent: event.agent, reason: .permission, tool: event.tool, now: now)
            default:
                entry.waits[event.agent] = nil
                if event.tool == ClaudeEvent.wrapUpTool, event.asks { entry.questionAtEnd = true }
                entry.mode = Mode(state: .working, activity: event.tool.map(Self.activity(forTool:)) ?? .tool)
            }
        case .toolEnd:
            entry.waits[event.agent] = nil
            entry.mode = Mode(state: .working, activity: .think)
        case .permission:
            Self.wait(&entry, agent: event.agent, reason: .permission, tool: event.tool, now: now)
        case .permissionPrompt:
            // The dialog's notification may not say which agent asked: it stands for a permission wait already known.
            if !entry.waits.values.contains(where: { $0.reason == .permission }) {
                Self.wait(&entry, agent: event.agent, reason: .permission, tool: nil, now: now)
            }
        case .stop:
            if event.subagent {
                entry.waits[event.agent] = nil
            } else {
                if event.background {
                    // The background tasks' agents may still wait.
                    entry.waits[""] = nil
                    entry.agentsAt[""] = event.at
                    entry.mode = Mode(state: .working, activity: .background)
                } else {
                    entry.waits = [:]
                    entry.agentsAt = [:]
                    entry.allAgentsAt = event.at
                    entry.mode = Mode(state: .waiting, reason: entry.questionAtEnd ? .question : .turn)
                }
                entry.questionAtEnd = false
            }
        case .idle:
            // A turn that ended without a Stop (Esc, or StopFailure where it is not hooked) ends here.
            if entry.mode.state == .working, entry.mode.activity != .background {
                entry.mode = Mode(state: .waiting, reason: entry.questionAtEnd ? .question : .turn)
                entry.questionAtEnd = false
            }
        case .sessionEnd:
            return
        }
        Self.show(&entry, now: now)
        entries[event.session] = entry
    }

    /// An event that ran before its session's last one: each agent's hooks run in order, but another agent's later event
    /// may have come in first. An agent's own event that ran no earlier than that agent's last one and the last end of
    /// every wait still starts or ends that agent's wait; the rest stays as the later events made it.
    private mutating func applyToItsAgent(_ event: ClaudeEvent, now: Int64) {
        guard var entry = entries[event.session], let effect = Self.agentEffect(of: event),
              event.at >= entry.lastAt(of: event.agent)
        else { return }
        switch effect {
        case let .wait(reason): Self.wait(&entry, agent: event.agent, reason: reason, tool: event.tool, now: now)
        case .end: entry.waits[event.agent] = nil
        }
        entry.agentsAt[event.agent] = event.at
        Self.show(&entry, now: now)
        entries[event.session] = entry
    }

    /// Nil for an event that is no single agent's own: a prompt, the main agent's Stop, a notification, the session's
    /// start or end.
    private static func agentEffect(of event: ClaudeEvent) -> AgentEffect? {
        switch event.kind {
        case .toolStart:
            switch event.tool {
            case ClaudeEvent.questionTool: return .wait(.question)
            case "ExitPlanMode": return .wait(.permission)
            default: return .end
            }
        case .permission: return .wait(.permission)
        case .toolEnd: return .end
        case .stop: return event.subagent ? .end : nil
        case .sessionStart, .prompt, .permissionPrompt, .idle, .sessionEnd: return nil
        }
    }

    /// The first command shell of Claude Code (`commandShellMark`) among `children` that started more than
    /// `eventStartMargin` after `lastEvent` and no later than `startedBy` (µs): the command the user approved, as the
    /// command of no event since is one. Nil when there is none.
    public static func approvedCommand(lastEvent: Int64, children: [ChildProcess], startedBy: Int64) -> ChildProcess? {
        children.filter { child in
            child.start > lastEvent + eventStartMargin && child.start <= startedBy
                && child.arguments.contains { $0.contains(commandShellMark) }
        }.min { ($0.start, $0.pid) < ($1.start, $1.pid) }
    }

    /// No hook says that the user approved a command; its shell starting as a child of the session's process does
    /// (design §14). With `children` of the process `pid` at `now` (ms): the agent of its sessions that asked first to
    /// run one works on it. True when that changed a session.
    @discardableResult
    public mutating func applyApprovals(pid: Int32, children: [ChildProcess], now: Int64) -> Bool {
        let process = entries.filter { $0.value.pid == pid }
        guard let lastEvent = process.values.map(\.at).max() else { return false }
        let asking = process.flatMap { id, entry in
            entry.waits.filter { $0.value.isForACommand }.map { (since: $0.value.since, id: id, agent: $0.key) }
        }
        guard let first = asking.min(by: { ($0.since, $0.id, $0.agent) < ($1.since, $1.id, $1.agent) }),
              let command = Self.approvedCommand(lastEvent: lastEvent, children: children,
                                                 startedBy: now * 1_000 - Self.childSettling),
              var entry = entries[first.id]
        else { return false }
        entry.waits[first.agent] = nil
        entry.mode = Mode(state: .working, activity: .command)
        // Like an event of that agent at the command's start: what ran before it (the dialog's late notification) is
        // old news.
        entry.at = command.start
        entry.agentsAt[first.agent] = command.start
        Self.show(&entry, now: now)
        entries[first.id] = entry
        return true
    }

    /// The title and the model from the session's file. Nil (and an empty title) changes nothing.
    public mutating func setDetails(session: String, title: String?, model: String?) {
        guard var entry = entries[session] else { return }
        if let title = ClaudeTranscript.cleanTitle(title) { entry.session.title = title }
        if let model { entry.session.model = model }
        entries[session] = entry
    }

    public mutating func removeSessions(whosePIDIsDead isDead: (Int32) -> Bool) {
        entries = entries.filter { !isDead($0.value.pid) }
    }

    public static func activity(forTool name: String) -> ClaudeSession.Activity {
        switch name {
        case "Bash", "BashOutput", "KillShell": return .command
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return .edit
        case "Read", "Grep", "Glob", "LS": return .read
        case "WebFetch", "WebSearch": return .web
        case "Agent", "Task": return .agent
        default: return .tool
        }
    }

    private static func newEntry(for event: ClaudeEvent, now: Int64) -> Entry {
        let folder = event.cwd.split(separator: "/").last.map(String.init) ?? ""
        let name = folder.isEmpty ? "Claude" : folder
        return Entry(session: ClaudeSession(id: event.session, title: name, project: name, model: nil, state: .ready,
                                            reason: nil, activity: nil, since: now),
                     pid: event.pid, at: event.at, mode: Mode(state: .ready))
    }

    /// `agent` waits for `reason`; a wait for the same reason goes on from when it began.
    private static func wait(_ entry: inout Entry, agent: String, reason: ClaudeSession.Reason, tool: String?, now: Int64) {
        let since = entry.waits[agent].flatMap { $0.reason == reason ? $0.since : nil } ?? now
        entry.waits[agent] = Wait(reason: reason, since: since, tool: tool)
    }

    /// The session as listed: waiting with the reason and the time of its oldest wait, or else its mode, whose time
    /// restarts when the state or the reason changes.
    private static func show(_ entry: inout Entry, now: Int64) {
        let shown: Mode
        if let oldest = entry.waits.min(by: { ($0.value.since, $0.key) < ($1.value.since, $1.key) })?.value {
            shown = Mode(state: .waiting, reason: oldest.reason)
            entry.session.since = oldest.since
        } else {
            shown = entry.mode
            if entry.session.state != shown.state || entry.session.reason != shown.reason { entry.session.since = now }
        }
        entry.session.state = shown.state
        // `reason` only while waiting, `activity` only while working.
        entry.session.reason = shown.state == .waiting ? shown.reason : nil
        entry.session.activity = shown.state == .working ? shown.activity : nil
    }
}
