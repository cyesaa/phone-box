/// "Kablo takılıyken" (cable) or "Her zaman" (always), chosen in the menu bar (design §5).
public enum AccessMode: String, Codable, Sendable, CaseIterable {
    case cable
    case always
}

/// What one phone may do right now.
public struct Access: Equatable, Codable, Sendable {
    public var streaming: Bool
    public var commands: Bool
    /// The phone is connected over the iPhone's USB link; the page shows "kablo" or "Wi-Fi".
    public var cable: Bool
    /// `ok`, `not-on-cable`, or `unauthenticated` (never sent: such clients get no messages).
    public var reason: String

    public init(streaming: Bool, commands: Bool, cable: Bool, reason: String) {
        self.streaming = streaming
        self.commands = commands
        self.cable = cable
        self.reason = reason
    }

    public static let onCable = Access(streaming: true, commands: true, cable: true, reason: "ok")
    public static let overWiFi = Access(streaming: true, commands: false, cable: false, reason: "ok")
    public static let notOnCable = Access(streaming: false, commands: false, cable: false, reason: "not-on-cable")
    public static let unauthenticated = Access(streaming: false, commands: false, cable: false, reason: "unauthenticated")
}

/// Design §5 "AccessPolicy". A connection on the iPhone's USB link can only come from a phone that is
/// plugged into this Mac and trusts it. Commands come only from there, in both modes: the page is served over
/// plain HTTP, so an active attacker on the same Wi-Fi could serve a modified page.
public enum AccessPolicy {
    public static func decide(mode: AccessMode, clientOnUSB: Bool, authenticated: Bool) -> Access {
        guard authenticated else { return .unauthenticated }
        if clientOnUSB { return .onCable }
        switch mode {
        case .always: return .overWiFi
        case .cable: return .notOnCable
        }
    }
}
