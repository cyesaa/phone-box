import Darwin
import Foundation
import PhoneBoxCore

/// Follows the Mac's Claude Code sessions while "Claude Code Sessions" is on (design §14): listens on a Unix socket for
/// the events `PhoneBox --claude-hook` hands over, keeps `ClaudeSessions` up to date, reads each session's title and
/// model from its file and drops a session whose process has ended.
@MainActor
final class ClaudeMonitor {
    typealias Tail = (data: Data, startsAtBeginning: Bool)

    /// One connection carries one event of a few hundred bytes.
    nonisolated static let maxConnectionBytes = 64 * 1024
    nonisolated static let tailBytes = 256 * 1024
    /// A session's file is read again on its next event once this many milliseconds have passed.
    static let detailsEvery: Int64 = 10_000
    static let livenessEvery: TimeInterval = 5

    /// Called on the main thread after the sessions changed.
    var onChange: (() -> Void)?
    var sessions: [ClaudeSession] { state.list }
    var isRunning: Bool { source != nil }

    private let socketPath: String
    private let clock: () -> Int64
    private let isAlive: (Int32) -> Bool
    private let readTail: @Sendable (String) -> Tail?
    private var state = ClaudeSessions()
    /// When each session's file was last read (by `clock`).
    private var detailsReadAt: [String: Int64] = [:]
    private var source: DispatchSourceRead?
    /// The socket file this monitor made, as it was right after `bind`: `stop()` removes that file and no other.
    private var socketFile: FileID?
    private var livenessTimer: Timer?
    /// Bumped by `stop()`: events and details still on their way from before are dropped.
    private var generation = 0
    private let socketQueue = DispatchQueue(label: "PhoneBox Claude socket")
    private let fileQueue = DispatchQueue(label: "PhoneBox Claude files", qos: .utility)

    init(socketPath: String = ClaudePaths.socket, clock: @escaping () -> Int64 = ClaudeMonitor.now,
         isAlive: @escaping (Int32) -> Bool = ClaudeMonitor.processIsAlive,
         readTail: @escaping @Sendable (String) -> Tail? = { ClaudeMonitor.readTail($0) }) {
        self.socketPath = socketPath
        self.clock = clock
        self.isAlive = isAlive
        self.readTail = readTail
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
        let timer = Timer(timeInterval: Self.livenessEvery, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkProcesses() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        livenessTimer = timer
    }

    /// Closes the socket, removes its file (if it is still the one this monitor made) and forgets every session.
    func stop() {
        generation += 1
        livenessTimer?.invalidate()
        livenessTimer = nil
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
        onChange?()
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
        onChange?()
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
                    self.onChange?()
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
