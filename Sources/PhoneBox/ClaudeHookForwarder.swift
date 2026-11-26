import Darwin
import Foundation
import PhoneBoxCore

/// `PhoneBox --claude-hook` (design §14 "Olaylar nasıl gelir"): Claude Code runs it for each hook event, with the
/// event's JSON on stdin. It hands the event to the running PhoneBox over a Unix socket and exits. Whatever goes wrong
/// (PhoneBox not running, the feature off, input it does not follow), it gives up without a word: the exit status is
/// always 0 and nothing is printed, so a session never shows an error for PhoneBox. It is gone within five seconds, even
/// when its input never ends: `readTimeout`, then at most a second for the socket.
enum ClaudeHookForwarder {
    /// Hook input is a few kilobytes; more than this is not worth reading.
    static let maxInput = 1 << 20
    /// Claude Code writes the input at once and closes it; the helper does not wait longer than this for its end.
    static let readTimeout: TimeInterval = 4

    static func run(socketPath: String = ClaudePaths.socket) {
        guard let input = read(from: .standardInput),
              let event = ClaudeEvent.parse(hookInput: input, parentPID: getppid(), at: startTime() ?? now())
        else { return }
        _ = send(event.line(), to: socketPath)
    }

    /// When the process `pid` started, in microseconds since 1970 (the kernel's `p_starttime`); nil when it cannot be
    /// read. For the helper this is when Claude Code ran the hook: each hook gets its own process, in the order Claude
    /// Code ran them, while their events may reach PhoneBox in another.
    static func startTime(of pid: pid_t = getpid()) -> Int64? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Int64(start.tv_sec) * 1_000_000 + Int64(start.tv_usec)
    }

    /// Microseconds since 1970.
    static func now() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000_000)
    }

    /// Everything up to the end of `handle`; nil when that is more than `maxInput` bytes, reading fails, or the end has
    /// not come within `timeout` seconds. A device (`poll` cannot wait on one on macOS) is read without a deadline:
    /// /dev/null ends at once, and a terminal is a person trying the helper out.
    static func read(from handle: FileHandle, timeout: TimeInterval = readTimeout) -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var waits = true
        while true {
            if waits {
                let left = deadline.timeIntervalSinceNow
                guard left > 0 else { return nil }
                var ready = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
                let result = poll(&ready, 1, Int32((left * 1000).rounded(.up)))
                if result == 0 { return nil }
                if result < 0 {
                    if errno == EINTR { continue }
                    return nil
                }
                if ready.revents & Int16(POLLNVAL) != 0 { waits = false }
            }
            let count = Darwin.read(handle.fileDescriptor, &buffer, buffer.count)
            if count == 0 { return data }
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            data.append(buffer, count: count)
            if data.count > maxInput { return nil }
        }
    }

    /// Writes `line` to the Unix socket at `path`; false when nobody listens there or the write fails or takes more than a
    /// second.
    static func send(_ line: Data, to path: String) -> Bool {
        guard var address = ClaudePaths.address(path) else { return false }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        // The helper runs before PhoneBoxApp ignores SIGPIPE: a listener that goes away must not kill it.
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        guard connected else { return false }
        return line.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return true }
            var offset = 0
            while offset < bytes.count {
                let written = write(descriptor, base + offset, bytes.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += written
            }
            return true
        }
    }
}
