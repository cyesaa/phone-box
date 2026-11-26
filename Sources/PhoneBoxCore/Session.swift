import Foundation

/// The protocol state of one WebSocket connection (design §5): authentication, command signatures,
/// increasing sequence numbers and the rate limit. Pure, so every rule is unit-tested.
public struct Session: Sendable {
    public static let authFailedCode: UInt16 = 4001
    /// No auth message within the timeout: the page retries instead of reporting a wrong key.
    public static let authTimeoutCode: UInt16 = 4003
    public static let policyViolationCode: UInt16 = 1008
    public static let maxCommandsPerSecond = 10

    public let nonce: String
    public private(set) var isAuthenticated = false
    private var lastSeq = 0
    private var recentCommands: [Date] = []

    public init(nonce: String) {
        self.nonce = nonce
    }

    /// 16 random bytes as 32 hex digits.
    public static func makeNonce() -> String {
        var generator = SystemRandomNumberGenerator()
        return Hex.encode((0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    public enum Outcome: Equatable, Sendable {
        /// The phone proved it holds the key.
        case authenticated
        /// A signed, fresh, allowed and well-formed command the caller should run, then answer with an `ack`.
        case command(seq: Int, command: Command)
        /// Send this and keep the connection.
        case reply(ServerMessage)
        /// Close the connection with this WebSocket close code.
        case close(code: UInt16, reason: String)
    }

    /// `allowedCommands` is the phone's `Access.commands`: a signed, fresh command outside it is answered with
    /// `not-allowed` before its arguments are looked at.
    public mutating func receive(_ text: String, key: PairingKey, allowedCommands: [String], now: Date) -> Outcome {
        guard let message = ClientMessage.parse(text) else {
            return .close(code: Self.policyViolationCode, reason: "bad message")
        }
        switch message {
        case let .auth(mac):
            guard !isAuthenticated else { return .close(code: Self.policyViolationCode, reason: "already authenticated") }
            guard MessageAuth.isValid(signature: mac, key: key.bytes, message: MessageAuth.authMessage(nonce: nonce)) else {
                return .close(code: Self.authFailedCode, reason: "bad key")
            }
            isAuthenticated = true
            return .authenticated

        case let .command(seq, name, args, mac):
            guard isAuthenticated else { return .close(code: Self.authFailedCode, reason: "not authenticated") }
            let signed = MessageAuth.commandMessage(nonce: nonce, seq: seq, name: name, args: args)
            guard MessageAuth.isValid(signature: mac, key: key.bytes, message: signed) else {
                return .close(code: Self.policyViolationCode, reason: "bad signature")
            }
            guard seq > lastSeq else { return .close(code: Self.policyViolationCode, reason: "old sequence number") }
            lastSeq = seq
            recentCommands = recentCommands.filter { now.timeIntervalSince($0) < 1 }
            guard recentCommands.count < Self.maxCommandsPerSecond else {
                return .close(code: Self.policyViolationCode, reason: "too many commands")
            }
            recentCommands.append(now)
            guard allowedCommands.contains(name) else { return .reply(.ack(seq: seq, result: .failed(.notAllowed))) }
            guard let command = Command.parse(name: name, args: args) else {
                return .reply(.ack(seq: seq, result: .failed(.unsupported)))
            }
            return .command(seq: seq, command: command)
        }
    }
}
