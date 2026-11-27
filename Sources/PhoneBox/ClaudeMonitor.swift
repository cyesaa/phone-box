import Darwin
import Foundation
import PhoneBoxCore

/// Follows the Mac's Claude Code sessions while "Claude Code Sessions" is on (design §14): listens on a Unix socket for
/// the events `PhoneBox --claude-hook` hands over, keeps `ClaudeSessions` up to date, reads each session's title and
/// model from its file, drops a session whose process has ended, sees a command the user approved start, and keeps the
/// sessions in a file across a restart.
@MainActor
final class ClaudeMonitor {
    typealias Tail = (data: Data, startsAtBeginning: Bool)

    /// One connection carries one event of a few hundred bytes.
    nonisolated static let maxConnectionBytes = 64 * 1024
    nonisolated static let tailBytes = 256 * 1024
    /// A session's file is read again on its next event once this many milliseconds have passed.
    static let detailsEvery: Int64 = 10_000
    static let livenessEvery: TimeInterval = 5
    /// While a session waits for permission to run a command, its process's children are looked at this often.
    static let commandsEvery: TimeInterval = 1

    /// Called on the main thread after the sessions changed.
    var onChange: (() -> Void)?
    var sessions: [ClaudeSession] { state.list }
    /// Every open session, also beyond the ones listed; the settings window counts them.
    var sessionCount: Int { state.count }
    /// The sessions waiting for the user (the list has those first).
    var waitingCount: Int { state.list.filter { $0.state == .waiting }.count }
    var isRunning: Bool { source != nil }
    /// Some session waits for permission to run a command: its process's children are looked at every second.
    var checksCommands: Bool { commandTimer != nil }

    private let socketPath: String
    /// Where the sessions are kept across a restart; nil keeps them nowhere.
    private let sessionsFile: URL?
    private let clock: () -> Int64
    private let isAlive: (Int32) -> Bool
    private let readTail: @Sendable (String) -> Tail?
    /// How long after a change the sessions are saved, at most.
    private let saveDelay: TimeInterval
    /// When a process started (µs since 1970).
    private let processStart: (Int32) -> Int64?
    private let children: (Int32) -> [ClaudeSessions.ChildProcess]
    private var state = ClaudeSessions()
    /// When each session's file was last read (by `clock`).
    private var detailsReadAt: [String: Int64] = [:]
    private var source: DispatchSourceRead?
    /// The socket file this monitor made, as it was right after `bind`: `stop()` removes that file and no other.
    private var socketFile: FileID?
    private var livenessTimer: Timer?
    private var commandTimer: Timer?
    private var saveTimer: Timer?
    /// The sessions changed since they were last saved.
    private var unsaved = false
    /// Bumped by `stop()`: events and details still on their way from before are dropped.
    private var generation = 0
    private let socketQueue = DispatchQueue(label: "PhoneBox Claude socket")
    private let fileQueue = DispatchQueue(label: "PhoneBox Claude files", qos: .utility)

    init(socketPath: String = ClaudePaths.socket, sessionsFile: URL? = ClaudePaths.sessions,
         clock: @escaping () -> Int64 = ClaudeMonitor.now,
         isAlive: @escaping (Int32) -> Bool = ClaudeMonitor.processIsAlive,
         readTail: @escaping @Sendable (String) -> Tail? = { ClaudeMonitor.readTail($0) },
         saveDelay: TimeInterval = 2,
         processStart: @escaping (Int32) -> Int64? = { ClaudeHookForwarder.startTime(of: $0) },
         children: @escaping (Int32) -> [ClaudeSessions.ChildProcess] = { ClaudeMonitor.children(of: $0) }) {
        self.socketPath = socketPath
        self.sessionsFile = sessionsFile
        self.clock = clock
        self.isAlive = isAlive
        self.readTail = readTail
        self.saveDelay = saveDelay
        self.processStart = processStart
        self.children = children
    }

    /// Listens on the socket. If it cannot be made, PhoneBox logs it and stays stopped: sessions then simply do not
    /// show up.
    func start() {
        guard source == nil else { return }
        let folder = (socketPath as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: folder) {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
        }
        let descriptor: Int32
        switch Self.listen(at: socketPath) {
        case let .success(listening):
            descriptor = listening.descriptor
            socketFile = listening.file
        case .failure(.taken):
            Log.app.notice("Another PhoneBox is listening for Claude Code at \(self.socketPath, privacy: .public); this one stays out of it")
            return
        case let .failure(.system(error)):
            Log.app.error("Could not listen for Claude Code at \(self.socketPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        let generation = self.generation
        let source = Self.makeSource(descriptor, on: socketQueue) { [weak self] events in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.received(events, generation: generation) }
            }
        }
        source.resume()
        self.source = source
        // Before the first event, which comes in through the main queue.
        restore()
        let timer = Timer(timeInterval: Self.livenessEvery, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkProcesses() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        livenessTimer = timer
    }

    /// Saves the sessions, closes the socket, removes its file (if it is still the one this monitor made) and forgets
    /// every session.
    func stop() {
        generation += 1
        livenessTimer?.invalidate()
        livenessTimer = nil
        commandTimer?.invalidate()
        commandTimer = nil
        // For the next start: after an update, PhoneBox shows the sessions again.
        if unsaved { save() }
        if let source {
            source.cancel()
            self.source = nil
            // Another PhoneBox may have its own socket at the path by now.
            if let socketFile, Self.fileID(socketPath) == socketFile { unlink(socketPath) }
            socketFile = nil
        }
        state = ClaudeSessions()
        detailsReadAt = [:]
        onChange?()
    }

    /// Drops the sessions whose `claude` process has ended (every `livenessEvery` seconds).
    func checkProcesses() {
        let before = state.count
        state.removeSessions(whosePIDIsDead: { [isAlive] in !isAlive($0) })
        guard state.count != before else { return }
        let ids = state.ids
        detailsReadAt = detailsReadAt.filter { ids.contains($0.key) }
        changed()
    }

    /// Looks for the shell of a command the user approved among the children of each process whose session waits for
    /// permission to run one (every `commandsEvery` seconds while one does; `ClaudeSessions.applyApprovals`).
    func checkCommands() {
        var any = false
        for pid in state.pidsWaitingToRunACommand where state.applyApprovals(pid: pid, children: children(pid), now: clock()) {
            any = true
        }
        if any { changed() }
    }

    /// After the sessions changed: saves them soon, looks for approved commands while some session waits to run one,
    /// and tells `onChange`.
    private func changed() {
        unsaved = true
        if sessionsFile != nil, saveTimer == nil {
            let timer = Timer(timeInterval: saveDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.save() }
            }
            RunLoop.main.add(timer, forMode: .common)
            saveTimer = timer
        }
        let checking = source != nil && !state.pidsWaitingToRunACommand.isEmpty
        if checking, commandTimer == nil {
            let timer = Timer(timeInterval: Self.commandsEvery, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkCommands() }
            }
            timer.tolerance = 0.2
            RunLoop.main.add(timer, forMode: .common)
            commandTimer = timer
        } else if !checking, let commandTimer {
            commandTimer.invalidate()
            self.commandTimer = nil
        }
        onChange?()
    }

    /// The sessions saved before PhoneBox last stopped, those whose `claude` still runs: alive, and started before the
    /// session's last event (a pid can be another process's after a restart of the Mac).
    private func restore() {
        guard let sessionsFile, let data = try? Data(contentsOf: sessionsFile) else { return }
        let isAlive = self.isAlive, processStart = self.processStart
        guard let saved = ClaudeSessions(saved: data, now: clock(), keep: { pid, at in
            isAlive(pid) && (processStart(pid).map { $0 <= at } ?? false)
        }), saved.count > 0 else { return }
        state = saved
        changed()
    }

    private func save() {
        saveTimer?.invalidate()
        saveTimer = nil
        unsaved = false
        guard let sessionsFile else { return }
        do {
            try Self.write(state.saved(now: clock()), replacing: sessionsFile)
        } catch {
            Log.app.error("Could not save the Claude Code sessions: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `data` in place of the file at `url`, readable and writable by this user only: written to a new file next to it,
    /// then renamed over it.
    nonisolated static func write(_ data: Data, replacing url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(getpid()).tmp").path
        unlink(temporary)
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var failure: Int32 = 0
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count, let base = bytes.baseAddress {
                let written = Darwin.write(descriptor, base + offset, bytes.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    failure = errno
                    return
                }
                offset += written
            }
        }
        if failure == 0, fchmod(descriptor, 0o600) != 0 { failure = errno }
        if close(descriptor) != 0, failure == 0 { failure = errno }
        if failure == 0, rename(temporary, url.path) != 0 { failure = errno }
        guard failure == 0 else {
            unlink(temporary)
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
    }

    private func received(_ events: [ClaudeEvent], generation: Int) {
        guard generation == self.generation else { return }
        let now = clock()
        for event in events {
            state.apply(event, now: now)
            if event.kind == .sessionEnd {
                detailsReadAt[event.session] = nil
            } else {
                readDetailsIfDue(event, now: now)
            }
        }
        changed()
    }

    /// A new session's file is read at once; a known one's at most every `detailsEvery` ms, so a title the user
    /// changes shows up with the session's next event.
    private func readDetailsIfDue(_ event: ClaudeEvent, now: Int64) {
        guard let path = event.transcript, state.ids.contains(event.session) else { return }
        if let last = detailsReadAt[event.session], now - last <= Self.detailsEvery { return }
        detailsReadAt[event.session] = now
        let readTail = self.readTail, session = event.session, generation = self.generation
        fileQueue.async { [weak self] in
            guard let tail = readTail(path) else { return }
            let details = ClaudeTranscript.details(fromTail: tail.data, startsAtBeginning: tail.startsAtBeginning)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, generation == self.generation else { return }
                    self.state.setDetails(session: session, title: details.title, model: details.model)
                    self.changed()
                }
            }
        }
    }

    nonisolated static func now() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    /// `kill(pid, 0)` succeeds, or fails only for lack of permission. 0 (PhoneBox's own process group) and 1 (launchd,
    /// the parent of a hook whose session is gone) are never a session's process.
    nonisolated static func processIsAlive(_ pid: Int32) -> Bool {
        guard pid > 1 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// The child processes of `pid` with their start times (libproc) and arguments; none when they cannot be read.
    nonisolated static func children(of pid: Int32) -> [ClaudeSessions.ChildProcess] {
        var pids = [pid_t](repeating: 0, count: 256)
        let count = pids.withUnsafeMutableBytes { proc_listchildpids(pid, $0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return [] }
        return pids.prefix(min(Int(count), pids.count)).compactMap { child in
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            // The child may have ended since it was listed, and its pid gone to another process.
            guard child > 0, proc_pidinfo(child, PROC_PIDTBSDINFO, 0, &info, size) == size,
                  info.pbi_ppid == UInt32(bitPattern: pid), let arguments = arguments(of: child)
            else { return nil }
            return ClaudeSessions.ChildProcess(pid: child,
                                               start: Int64(info.pbi_start_tvsec) * 1_000_000 + Int64(info.pbi_start_tvusec),
                                               arguments: arguments)
        }
    }

    /// The most bytes a process's arguments and environment take (`kern.argmax`).
    private nonisolated static let argumentsSize: Int = {
        var name: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctl(&name, u_int(name.count), &value, &size, nil, 0) == 0 && value > 0 ? Int(value) : 1 << 20
    }()

    /// The arguments `pid` was started with, its executable first (`sysctl` `KERN_PROCARGS2`); nil when they cannot be
    /// read (the process ended, or is another user's). Looked at, never stored or logged: a shell's arguments hold its
    /// command.
    nonisolated static func arguments(of pid: Int32) -> [String]? {
        var name: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var buffer = [UInt8](repeating: 0, count: argumentsSize)
        var size = buffer.count
        guard pid > 0, sysctl(&name, u_int(name.count), &buffer, &size, nil, 0) == 0 else { return nil }
        return arguments(fromProcArgs: Data(buffer.prefix(min(size, buffer.count))))
    }

    /// The arguments in `KERN_PROCARGS2`'s layout: their count (a 32-bit integer), the executable's path and the NULs
    /// after it, then each argument ending in a NUL, then the environment. Nil when it holds fewer.
    nonisolated static func arguments(fromProcArgs data: Data) -> [String]? {
        guard data.count >= 4 else { return nil }
        let count = data.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard count >= 0, var index = data.dropFirst(4).firstIndex(of: 0) else { return nil }
        while index < data.endIndex, data[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < Int(count) {
            guard let end = data[index...].firstIndex(of: 0) else { return nil }
            arguments.append(String(decoding: data[index..<end], as: UTF8.self))
            index = end + 1
        }
        return arguments
    }

    /// The last `tailBytes` of a regular file.
    nonisolated static func readTail(_ path: String) -> Tail? {
        guard (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeRegular,
              let handle = FileHandle(forReadingAtPath: path)
        else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.read(upToCount: tailBytes) else { return nil }
        return (data, start == 0)
    }

    // MARK: The socket, on `socketQueue`

    /// A file, whatever path it is reached by.
    struct FileID: Equatable, Sendable {
        var device: dev_t
        var inode: ino_t
    }

    enum ListenFailure: Error {
        /// Another PhoneBox (a test copy next to the installed one) accepts on the socket; it keeps it.
        case taken
        case system(POSIXError)
    }

    /// The file at `path` itself (a link is not followed); nil when there is none.
    nonisolated static func fileID(_ path: String) -> FileID? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return FileID(device: info.st_dev, inode: info.st_ino)
    }

    /// A listening, non-blocking socket at `path`, readable and writable by this user only, and its file. A socket
    /// file at the path that nobody accepts on (a PhoneBox that crashed left it) is replaced; one that someone accepts
    /// on, and any other file, is not.
    private nonisolated static func listen(at path: String) -> Result<(descriptor: Int32, file: FileID?), ListenFailure> {
        func failure(_ code: Int32) -> Result<(descriptor: Int32, file: FileID?), ListenFailure> {
            .failure(.system(POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)))
        }
        guard var address = ClaudePaths.address(path) else { return failure(ENAMETOOLONG) }
        var info = stat()
        if lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK {
            switch connectError(to: &address) {
            case 0: return .failure(.taken)
            case ECONNREFUSED: unlink(path)
            // Anything else (another user's socket, say) stays; `bind` then says what is wrong.
            default: break
            }
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return failure(errno) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        guard bound else {
            let code = errno
            close(descriptor)
            return failure(code)
        }
        let file = fileID(path)
        guard chmod(path, 0o600) == 0, Darwin.listen(descriptor, 64) == 0,
              fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK) == 0
        else {
            let code = errno
            close(descriptor)
            unlink(path)
            return failure(code)
        }
        return .success((descriptor, file))
    }

    /// 0 when someone accepts a connection to `address`, else why not (`ECONNREFUSED`: nobody listens there).
    private nonisolated static func connectError(to address: inout sockaddr_un) -> Int32 {
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { return errno }
        defer { close(probe) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        return connected ? 0 : errno
    }

    /// Accepts every waiting connection when the socket is readable; `deliver` gets the events of each batch in the
    /// order they came.
    private nonisolated static func makeSource(_ descriptor: Int32, on queue: DispatchQueue,
                                               deliver: @escaping @Sendable ([ClaudeEvent]) -> Void) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler {
            var events: [ClaudeEvent] = []
            while true {
                let client = accept(descriptor, nil, nil)
                if client < 0 {
                    if errno == EINTR { continue }
                    break
                }
                events += readEvents(client)
                close(client)
            }
            if !events.isEmpty { deliver(events) }
        }
        source.setCancelHandler { close(descriptor) }
        return source
    }

    /// The events of one connection, read to its end: at most `maxConnectionBytes`, and for at most two seconds.
    private nonisolated static func readEvents(_ client: Int32) -> [ClaudeEvent] {
        // A connection accepted from a non-blocking socket is non-blocking too; this one waits, but not for long.
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let deadline = Date().addingTimeInterval(2)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            let count = read(client, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                break
            }
            data.append(buffer, count: count)
            if data.count > maxConnectionBytes { return [] }
        }
        return data.split(separator: 0x0A).compactMap { ClaudeEvent.decode(line: Data($0)) }
    }
}
