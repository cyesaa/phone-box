import Darwin
import Foundation
import PhoneBoxCore

/// `PhoneBox --claude-hook` (design §14 "Olaylar nasıl gelir"): Claude Code runs it for each hook event, with the
/// event's JSON on stdin. It hands the event to the running PhoneBox over a Unix socket and exits. Whatever goes wrong
/// (PhoneBox not running, the feature off, input it does not follow), it gives up without a word: the exit status is
/// always 0 and nothing is printed, so a session never shows an error for PhoneBox.
enum ClaudeHookForwarder {
    /// Hook input is a few kilobytes; more than this is not worth reading.
    static let maxInput = 1 << 20

    static func run(socketPath: String = ClaudePaths.socket) {
        guard let input = read(from: .standardInput),
              let event = ClaudeEvent.parse(hookInput: input, parentPID: getppid())
        else { return }
        _ = send(event.line(), to: socketPath)
    }

    /// Everything up to the end of `handle`; nil when that is more than `maxInput` bytes or reading fails.
    static func read(from handle: FileHandle) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
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
