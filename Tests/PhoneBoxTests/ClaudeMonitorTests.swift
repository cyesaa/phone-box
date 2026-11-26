import Darwin
import Foundation
import Testing
@testable import PhoneBox
import PhoneBoxCore

/// Counts calls from any thread.
final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

/// The socket between `PhoneBox --claude-hook` and the app (design §14 "Olaylar nasıl gelir"). Each test listens on
/// its own socket in /tmp: a Unix socket's path must fit in 104 bytes, and the user's own PhoneBox uses another one.
@MainActor
struct ClaudeMonitorTests {
    let socketPath = "/tmp/pbc-\(UUID().uuidString.prefix(8)).sock"

    static func event(_ kind: ClaudeEvent.Kind, session: String = "s1", tool: String? = nil, pid: Int32 = getpid(),
                      transcript: String? = nil) -> ClaudeEvent {
        ClaudeEvent(session: session, kind: kind, tool: tool, asks: false, background: false, subagent: false,
                    cwd: "/Users/me/Code/PhoneBox", transcript: transcript, pid: pid, title: nil, model: nil, at: 0)
    }

    /// True once `condition` holds, checked every 10 ms for up to `seconds`.
    func eventually(within seconds: Double = 3, _ condition: () -> Bool) async throws -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition() { return true }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    func socketExists() -> Bool {
        var info = stat()
        return lstat(socketPath, &info) == 0 && (info.st_mode & S_IFMT) == S_IFSOCK
    }

    @Test func anEventSentByTheHelperShowsUp() async throws {
        let monitor = ClaudeMonitor(socketPath: socketPath, clock: { 5_000 })
        monitor.start()
        defer { monitor.stop() }
        #expect(ClaudeHookForwarder.send(Self.event(.prompt).line(), to: socketPath))
        #expect(try await eventually { !monitor.sessions.isEmpty })
        #expect(monitor.sessions == [ClaudeSession(id: "s1", title: "PhoneBox", project: "PhoneBox", model: nil, state: .working,
                                                   reason: nil, activity: .think, since: 5_000)])
    }

    @Test func appliesEveryLineOfAConnectionInOrderAndSkipsJunk() async throws {
        let monitor = ClaudeMonitor(socketPath: socketPath)
        var changes = 0
        monitor.onChange = { changes += 1 }
        monitor.start()
        defer { monitor.stop() }
        var lines = Self.event(.prompt).line()
        lines.append(Data("junk\n{\"session\":\"\"}\n".utf8))
        lines.append(Self.event(.toolStart, tool: "Bash").line())
        #expect(ClaudeHookForwarder.send(lines, to: socketPath))
        #expect(try await eventually { monitor.sessions.first?.activity == .command })
        #expect(monitor.sessions.count == 1)
        #expect(changes >= 1)
    }

    @Test func theSocketIsOnlyForThisUser() throws {
        let monitor = ClaudeMonitor(socketPath: socketPath)
        monitor.start()
        defer { monitor.stop() }
        var info = stat()
        #expect(lstat(socketPath, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o600)
    }

    @Test func replacesAStaleSocketFile() async throws {
        // The socket file a PhoneBox that crashed leaves behind: bound, nobody listening.
        var address = try #require(ClaudePaths.address(socketPath))
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        close(descriptor)
        #expect(bound == 0)
        #expect(socketExists())
        let monitor = ClaudeMonitor(socketPath: socketPath)
        monitor.start()
        defer { monitor.stop() }
        #expect(monitor.isRunning)
        #expect(ClaudeHookForwarder.send(Self.event(.prompt).line(), to: socketPath))
        #expect(try await eventually { !monitor.sessions.isEmpty })
    }

    /// A test copy of PhoneBox (`PHONEBOX_DEST`) runs next to the installed one with the same socket path: the one that
    /// listens keeps it.
    @Test func aSecondMonitorLeavesTheListeningOneAlone() async throws {
        let first = ClaudeMonitor(socketPath: socketPath)
        first.start()
        defer { first.stop() }
        let second = ClaudeMonitor(socketPath: socketPath)
        second.start()
        #expect(!second.isRunning)
        second.stop()
        #expect(socketExists())
        #expect(ClaudeHookForwarder.send(Self.event(.prompt).line(), to: socketPath))
        #expect(try await eventually { !first.sessions.isEmpty })
    }

    /// `stop()` removes the socket file only while it is still the one this monitor made.
    @Test func stopLeavesAnotherSocketFileAtThePath() async throws {
        let first = ClaudeMonitor(socketPath: socketPath)
        first.start()
        #expect(first.isRunning)
        // Another PhoneBox took the path over.
        unlink(socketPath)
        let second = ClaudeMonitor(socketPath: socketPath)
        second.start()
        defer { second.stop() }
        #expect(second.isRunning)
        first.stop()
        #expect(socketExists())
        #expect(ClaudeHookForwarder.send(Self.event(.prompt).line(), to: socketPath))
        #expect(try await eventually { !second.sessions.isEmpty })
    }

    @Test func doesNotReplaceAFileThatIsNotASocket() throws {
        let path = "/tmp/pbc-\(UUID().uuidString.prefix(8)).txt"
        #expect(FileManager.default.createFile(atPath: path, contents: Data("keep".utf8)))
        defer { unlink(path) }
        let monitor = ClaudeMonitor(socketPath: path)
        monitor.start()
        #expect(!monitor.isRunning)
        monitor.stop()
        #expect(FileManager.default.contents(atPath: path) == Data("keep".utf8))
    }

    @Test func readsTheTitleAndTheModelFromTheSessionsFile() async throws {
        let transcript = FileManager.default.temporaryDirectory.appendingPathComponent("pbc-\(UUID().uuidString).jsonl")
        let lines = [#"{"type":"user","message":{"content":"hi"}}"#,
                     #"{"type":"custom-title","customTitle":"Mac-telefon dashboard bağlantısı","sessionId":"s1"}"#,
                     #"{"type":"assistant","message":{"model":"claude-opus-5-5","content":[]}}"#]
        try Data(lines.joined(separator: "\n").utf8).write(to: transcript)
        defer { try? FileManager.default.removeItem(at: transcript) }
        let monitor = ClaudeMonitor(socketPath: socketPath)
        monitor.start()
        defer { monitor.stop() }
        #expect(ClaudeHookForwarder.send(Self.event(.sessionStart, transcript: transcript.path).line(), to: socketPath))
        #expect(try await eventually { monitor.sessions.first?.title == "Mac-telefon dashboard bağlantısı" })
        #expect(monitor.sessions.first?.model == "Opus 5.5")
        #expect(monitor.sessions.first?.project == "PhoneBox")
    }

    @Test func readsTheLastPartOfALongFile() throws {
        let transcript = FileManager.default.temporaryDirectory.appendingPathComponent("pbc-\(UUID().uuidString).jsonl")
        var data = Data(#"{"type":"custom-title","customTitle":"Old"}"#.utf8)
        data.append(Data(repeating: 0x20, count: ClaudeMonitor.tailBytes))
        data.append(Data("\n{\"type\":\"custom-title\",\"customTitle\":\"New\"}\n".utf8))
        try data.write(to: transcript)
        defer { try? FileManager.default.removeItem(at: transcript) }
        let tail = try #require(ClaudeMonitor.readTail(transcript.path))
        #expect(tail.data.count == ClaudeMonitor.tailBytes)
        #expect(!tail.startsAtBeginning)
        #expect(ClaudeTranscript.details(fromTail: tail.data, startsAtBeginning: tail.startsAtBeginning).title == "New")
        let small = FileManager.default.temporaryDirectory.appendingPathComponent("pbc-\(UUID().uuidString).jsonl")
        try Data("{}\n".utf8).write(to: small)
        defer { try? FileManager.default.removeItem(at: small) }
        let whole = try #require(ClaudeMonitor.readTail(small.path))
        #expect(whole.data == Data("{}\n".utf8))
        #expect(whole.startsAtBeginning)
        #expect(ClaudeMonitor.readTail("/nonexistent/pbc.jsonl") == nil)
        #expect(ClaudeMonitor.readTail(FileManager.default.temporaryDirectory.path) == nil)
    }

    @Test func readsASessionsFileAgainOnlyAfterTenSeconds() async throws {
        var now: Int64 = 1_000_000
        let reads = CallCounter()
        let monitor = ClaudeMonitor(socketPath: socketPath, clock: { now }, readTail: { _ in
            reads.increment()
            return (Data(#"{"type":"custom-title","customTitle":"Named"}"#.utf8), true)
        })
        monitor.start()
        defer { monitor.stop() }
        func send(_ kind: ClaudeEvent.Kind) async throws {
            #expect(ClaudeHookForwarder.send(Self.event(kind, transcript: "/t/s1.jsonl").line(), to: socketPath))
        }
        try await send(.sessionStart)
        #expect(try await eventually { monitor.sessions.first?.title == "Named" })
        #expect(reads.value == 1)
        now += 10_000
        try await send(.prompt)
        #expect(try await eventually { monitor.sessions.first?.state == .working })
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(reads.value == 1)
        now += 1
        try await send(.stop)
        #expect(try await eventually { reads.value == 2 })
        #expect(try await eventually { monitor.sessions.first?.state == .waiting })
    }

    @Test func dropsASessionWhoseProcessEnded() async throws {
        let monitor = ClaudeMonitor(socketPath: socketPath, isAlive: { $0 != 555 })
        monitor.start()
        defer { monitor.stop() }
        #expect(ClaudeHookForwarder.send(Self.event(.prompt, session: "gone", pid: 555).line(), to: socketPath))
        #expect(ClaudeHookForwarder.send(Self.event(.prompt, session: "alive", pid: 556).line(), to: socketPath))
        #expect(try await eventually { monitor.sessions.count == 2 })
        monitor.checkProcesses()
        #expect(monitor.sessions.map(\.id) == ["alive"])
    }

    @Test func knowsWhichProcessesRun() {
        #expect(ClaudeMonitor.processIsAlive(getpid()))
        // launchd: kill() says EPERM, but it is never a session's process; nor is 0, PhoneBox's own process group.
        #expect(!ClaudeMonitor.processIsAlive(1))
        #expect(!ClaudeMonitor.processIsAlive(0))
        #expect(!ClaudeMonitor.processIsAlive(-1))
        #expect(!ClaudeMonitor.processIsAlive(99_999_999))
    }

    @Test func stopRemovesTheSocketAndForgetsEverySession() async throws {
        let monitor = ClaudeMonitor(socketPath: socketPath)
        monitor.start()
        #expect(socketExists())
        #expect(ClaudeHookForwarder.send(Self.event(.prompt).line(), to: socketPath))
        #expect(try await eventually { !monitor.sessions.isEmpty })
        monitor.stop()
        #expect(!monitor.isRunning)
        #expect(!socketExists())
        #expect(monitor.sessions.isEmpty)
        #expect(!ClaudeHookForwarder.send(Self.event(.prompt).line(), to: socketPath))
        // And it can listen again.
        monitor.start()
        defer { monitor.stop() }
        #expect(ClaudeHookForwarder.send(Self.event(.stop).line(), to: socketPath))
        #expect(try await eventually { monitor.sessions.first?.state == .waiting })
    }

    @Test func theHelperGivesUpQuietlyWithoutPhoneBox() {
        #expect(!ClaudeHookForwarder.send(Self.event(.prompt).line(), to: socketPath))
        #expect(!ClaudeHookForwarder.send(Data("x\n".utf8), to: "/tmp/" + String(repeating: "p", count: 120)))
    }

    @Test func theHelperReadsAtMostOneMegabyte() throws {
        #expect(ClaudeHookForwarder.read(from: try pipe(Data(repeating: 0x41, count: ClaudeHookForwarder.maxInput)))?.count
            == ClaudeHookForwarder.maxInput)
        #expect(ClaudeHookForwarder.read(from: try pipe(Data(repeating: 0x41, count: ClaudeHookForwarder.maxInput + 1))) == nil)
        #expect(ClaudeHookForwarder.read(from: try pipe(Data())) == Data())
    }

    /// A Claude Code that never closes the hook's input does not keep the helper running.
    @Test func theHelperStopsWaitingForItsInput() throws {
        let pipe = Pipe()
        try pipe.fileHandleForWriting.write(contentsOf: Data(#"{"session_id":"#.utf8))
        let start = Date()
        #expect(ClaudeHookForwarder.read(from: pipe.fileHandleForReading, timeout: 0.3) == nil)
        let took = Date().timeIntervalSince(start)
        #expect(took >= 0.25 && took < 2, "\(took)")
        // Within its five seconds, together with the socket's one.
        #expect(ClaudeHookForwarder.readTimeout + 1 <= 5)
        // A device has no deadline but ends at once.
        let null = try #require(FileHandle(forReadingAtPath: "/dev/null"))
        #expect(ClaudeHookForwarder.read(from: null, timeout: 0.3) == Data())
        withExtendedLifetime(pipe) {}
    }

    /// The hook's process starts when Claude Code runs the hook: that is the event's time.
    @Test func theHelperKnowsWhenItStarted() throws {
        let now = Int64(Date().timeIntervalSince1970 * 1_000_000)
        let started = try #require(ClaudeHookForwarder.startTime())
        #expect(started <= now)
        #expect(started > now - 24 * 3_600 * 1_000_000)
        // A parent starts before its child.
        #expect(try #require(ClaudeHookForwarder.startTime(of: getppid())) <= started)
        #expect(ClaudeHookForwarder.startTime(of: 99_999_999) == nil)
        #expect(abs(ClaudeHookForwarder.now() - now) < 60 * 1_000_000)
    }

    /// A pipe's reading end with `data` already written and the writing end closed; `data` is written from another
    /// thread, as a pipe holds only 64 KB.
    func pipe(_ data: Data) throws -> FileHandle {
        let pipe = Pipe()
        let writer = pipe.fileHandleForWriting
        Thread.detachNewThread {
            try? writer.write(contentsOf: data)
            try? writer.close()
        }
        return pipe.fileHandleForReading
    }
}
