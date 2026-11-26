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

    private struct Entry: Sendable {
        var session: ClaudeSession
        var pid: Int32
        /// The end-of-turn box asked a question: the turn's stop waits with `question`.
        var questionAtEnd = false
        /// The `at` of the last event applied.
        var at: Int64
    }

    private struct End: Sendable {
        /// The SessionEnd's `at`.
        var at: Int64
        /// When it came in (`now`, ms).
        var received: Int64
    }

    private var entries: [String: Entry] = [:]
    private var ended: [String: End] = [:]

    public init() {}

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

    /// Applies one event at `now` (ms). Hooks run as separate processes and can come in out of order: an event that ran
    /// before the session's last one, or no later than its end, is old news and changes nothing (design §14).
    public mutating func apply(_ event: ClaudeEvent, now: Int64) {
        if !ended.isEmpty { ended = ended.filter { now - $0.value.received <= Self.endMemory } }
        // A subagent's stop ends only its own work; the session goes on.
        if event.kind == .stop, event.subagent { return }
        if let end = ended[event.session] {
            // A session can start again after its end (`claude --resume`).
            guard event.at > end.at else { return }
            ended[event.session] = nil
        }
        if let known = entries[event.session], event.at < known.at { return }
        if event.kind == .sessionEnd {
            entries[event.session] = nil
            ended[event.session] = End(at: event.at, received: now)
            return
        }
        var entry = entries[event.session] ?? Self.newEntry(for: event, now: now)
        entry.pid = event.pid
        entry.at = event.at
        switch event.kind {
        case .sessionStart:
            entries[event.session] = entry
            setDetails(session: event.session, title: event.title,
                       model: event.model.flatMap(ClaudeTranscript.modelName))
            return
        case .prompt:
            entry.questionAtEnd = false
            Self.set(&entry.session, .working, activity: .think, now: now)
            // A new turn: its time starts now even when the last one was still running.
            entry.session.since = now
        case .toolStart:
            switch event.tool {
            case ClaudeEvent.questionTool:
                Self.set(&entry.session, .waiting, reason: .question, now: now)
            case "ExitPlanMode":
                Self.set(&entry.session, .waiting, reason: .permission, now: now)
            default:
                if event.tool == ClaudeEvent.wrapUpTool, event.asks { entry.questionAtEnd = true }
                Self.set(&entry.session, .working, activity: event.tool.map(Self.activity(forTool:)) ?? .tool, now: now)
            }
        case .toolEnd:
            Self.set(&entry.session, .working, activity: .think, now: now)
        case .permission:
            Self.set(&entry.session, .waiting, reason: .permission, now: now)
        case .stop:
            if event.background {
                Self.set(&entry.session, .working, activity: .background, now: now)
            } else {
                Self.set(&entry.session, .waiting, reason: entry.questionAtEnd ? .question : .turn, now: now)
            }
            entry.questionAtEnd = false
        case .sessionEnd:
            return
        }
        entries[event.session] = entry
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
                     pid: event.pid, at: event.at)
    }

    /// `reason` only while waiting, `activity` only while working; the time restarts when the state or the reason
    /// changes.
    private static func set(_ session: inout ClaudeSession, _ state: ClaudeSession.State, reason: ClaudeSession.Reason? = nil,
                            activity: ClaudeSession.Activity? = nil, now: Int64) {
        let reason = state == .waiting ? reason : nil
        if session.state != state || session.reason != reason { session.since = now }
        session.state = state
        session.reason = reason
        session.activity = state == .working ? activity : nil
    }
}
