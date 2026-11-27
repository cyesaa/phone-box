import Darwin
import Foundation

/// Where the Claude Code sessions feature keeps its files (design §14).
enum ClaudePaths {
    /// `~/Library/Application Support/PhoneBox/claude.sock`: `PhoneBox --claude-hook` writes each event here.
    static var socket: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhoneBox", isDirectory: true)
            .appendingPathComponent("claude.sock").path
    }

    /// `~/Library/Application Support/PhoneBox/claude-sessions.json`: the sessions, kept across a restart (an update).
    static var sessions: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhoneBox", isDirectory: true)
            .appendingPathComponent("claude-sessions.json")
    }

    /// `~/.claude/settings.json`, where Claude Code reads the user's hooks.
    static var settings: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    /// The Unix socket address of `path`; nil when it does not fit (`sun_path` holds 104 bytes with the final zero).
    static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard !bytes.isEmpty, bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }
}
