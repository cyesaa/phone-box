/// "Kablo takılıyken" (cable) or "Her zaman" (always), chosen in the menu bar (design §5).
public enum AccessMode: String, Codable, Sendable, CaseIterable {
    case cable
    case always

    /// "Lock and Music over Wi-Fi" changes something only in "always" mode: in cable mode a phone on Wi-Fi gets no data
    /// at all, so the settings window dims the switch.
    public var offersLockAndMusicOverWiFi: Bool { self == .always }
}

/// What one phone may do right now.
public struct Access: Equatable, Codable, Sendable {
    public var streaming: Bool
    /// The commands (`Command.allNames`) the phone may send; empty when it may send none.
    public var commands: [String]
    /// The phone is connected over the iPhone's USB link; the page shows "kablo" or "Wi-Fi".
    public var cable: Bool
    /// `ok`, `not-on-cable`, or `unauthenticated` (never sent: such clients get no messages).
    public var reason: String

    public init(streaming: Bool, commands: [String], cable: Bool, reason: String) {
        self.streaming = streaming
        self.commands = commands
        self.cable = cable
        self.reason = reason
    }

    public static let onCable = Access(streaming: true, commands: Command.allNames, cable: true, reason: "ok")
    public static let overWiFi = Access(streaming: true, commands: [], cable: false, reason: "ok")
    /// Over Wi-Fi with "Lock and Music over Wi-Fi" on.
    public static let overWiFiWithLockAndMusic = Access(streaming: true, commands: Command.wifiNames, cable: false, reason: "ok")
    public static let notOnCable = Access(streaming: false, commands: [], cable: false, reason: "not-on-cable")
    public static let unauthenticated = Access(streaming: false, commands: [], cable: false, reason: "unauthenticated")
}

/// Design §5 "AccessPolicy". A connection on the iPhone's USB link can only come from a phone that is
/// plugged into this Mac and trusts it: it may send every command, in both modes. The page is served over plain HTTP,
/// so an active attacker on the same Wi-Fi could serve a modified page: a phone on Wi-Fi gets only the harmless
/// `Command.wifiNames`, and only in "always" mode with `lockAndMusicOverWiFi` on (the user's choice, 2026-11-26).
public enum AccessPolicy {
    public static func decide(mode: AccessMode, lockAndMusicOverWiFi: Bool, clientOnUSB: Bool, authenticated: Bool) -> Access {
        guard authenticated else { return .unauthenticated }
        if clientOnUSB { return .onCable }
        switch mode {
        case .always: return lockAndMusicOverWiFi ? .overWiFiWithLockAndMusic : .overWiFi
        case .cable: return .notOnCable
        }
    }
}
