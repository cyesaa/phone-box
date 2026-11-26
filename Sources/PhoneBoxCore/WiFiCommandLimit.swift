import Foundation

/// How often phones on Wi-Fi may lock the Mac and change the music (design §5, §7). Someone who stole the key could
/// otherwise keep the Mac locked or start helper processes in a loop, so the promise "at worst someone locks the
/// screen or skips a song" needs a limit. Counted for all Wi-Fi phones together, not per connection; phones on the
/// cable never ask. Pure, so the rules are unit-tested.
public struct WiFiCommandLimit: Sendable {
    /// `lock`: at most once in this many seconds.
    public static let lockInterval: TimeInterval = 30
    /// `media`: at most this many in any window of `mediaWindow` seconds.
    public static let maxMediaPerWindow = 3
    public static let mediaWindow: TimeInterval = 1

    private var lastLock: Date?
    private var recentMedia: [Date] = []

    public init() {}

    /// True when the command may run now; the command is then counted. A refused command is not counted, so
    /// hammering `lock` does not extend the wait. Commands other than `lock` and `media` are not limited here
    /// (a Wi-Fi phone may not send them at all).
    public mutating func allows(_ command: Command, now: Date) -> Bool {
        switch command {
        case .lock:
            if let lastLock, now.timeIntervalSince(lastLock) < Self.lockInterval { return false }
            lastLock = now
            return true
        case .media:
            recentMedia = recentMedia.filter { now.timeIntervalSince($0) < Self.mediaWindow }
            guard recentMedia.count < Self.maxMediaPerWindow else { return false }
            recentMedia.append(now)
            return true
        default:
            return true
        }
    }
}
