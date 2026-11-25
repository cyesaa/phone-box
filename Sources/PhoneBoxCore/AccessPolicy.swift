/// "Kablo takılıyken" (cable) or "Her zaman" (always), chosen in the menu bar (design §5).
public enum AccessMode: String, Codable, Sendable, CaseIterable {
    case cable
    case always
}

/// What one phone may do right now.
public struct Access: Equatable, Codable, Sendable {
    public var streaming: Bool
    public var commands: Bool
    /// `ok`, `not-on-cable`, or `unauthenticated` (never sent: such clients get no messages).
    public var reason: String

    public init(streaming: Bool, commands: Bool, reason: String) {
        self.streaming = streaming
        self.commands = commands
        self.reason = reason
    }

    public static let granted = Access(streaming: true, commands: true, reason: "ok")
    public static let notOnCable = Access(streaming: false, commands: false, reason: "not-on-cable")
    public static let unauthenticated = Access(streaming: false, commands: false, reason: "unauthenticated")
}

/// Design §5 "AccessPolicy". A connection on the iPhone's USB link can only come from a phone that is
/// plugged into this Mac and trusts it, so in cable mode that is the test.
public enum AccessPolicy {
    public static func decide(mode: AccessMode, clientOnUSB: Bool, authenticated: Bool) -> Access {
        guard authenticated else { return .unauthenticated }
        switch mode {
        case .always: return .granted
        case .cable: return clientOnUSB ? .granted : .notOnCable
        }
    }
}
