import Foundation

/// Messages from the Mac to the phone (design §5). Every message carries `"v":1`.
public enum ServerMessage: Equatable, Sendable {
    case hello(nonce: String, app: String)
    case ready(mode: AccessMode, access: Access)
    case access(Access)
    case snapshot(Snapshot)
    case ack(seq: Int, ok: Bool, error: String?)

    /// Compact JSON with sorted keys.
    public func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try! encoder.encode(self), as: UTF8.self)
    }
}

extension ServerMessage: Encodable {
    private enum Keys: String, CodingKey {
        case v, type, nonce, app, mode, access, streaming, commands, reason, t, cpu, mem, seq, ok, error
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(1, forKey: .v)
        switch self {
        case let .hello(nonce, app):
            try container.encode("hello", forKey: .type)
            try container.encode(nonce, forKey: .nonce)
            try container.encode(app, forKey: .app)
        case let .ready(mode, access):
            try container.encode("ready", forKey: .type)
            try container.encode(mode, forKey: .mode)
            try container.encode(access, forKey: .access)
        case let .access(access):
            try container.encode("access", forKey: .type)
            try container.encode(access.streaming, forKey: .streaming)
            try container.encode(access.commands, forKey: .commands)
            try container.encode(access.reason, forKey: .reason)
        case let .snapshot(snapshot):
            try container.encode("snapshot", forKey: .type)
            try container.encode(snapshot.t, forKey: .t)
            try container.encodeIfPresent(snapshot.cpu, forKey: .cpu)
            try container.encodeIfPresent(snapshot.mem, forKey: .mem)
        case let .ack(seq, ok, error):
            try container.encode("ack", forKey: .type)
            try container.encode(seq, forKey: .seq)
            try container.encode(ok, forKey: .ok)
            try container.encodeIfPresent(error, forKey: .error)
        }
    }
}

/// Messages from the phone to the Mac.
public enum ClientMessage: Equatable, Sendable {
    case auth(mac: String)
    /// `args` is the JSON text exactly as the phone signed it.
    case command(seq: Int, name: String, args: String, mac: String)

    /// Nil for anything that is not a well-formed version 1 message.
    public static func parse(_ text: String) -> ClientMessage? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              object["v"] as? Int == 1
        else { return nil }
        switch object["type"] as? String {
        case "auth":
            guard let mac = object["mac"] as? String else { return nil }
            return .auth(mac: mac)
        case "cmd":
            guard let seq = object["seq"] as? Int, let name = object["name"] as? String,
                  let args = object["args"] as? String, let mac = object["mac"] as? String
            else { return nil }
            return .command(seq: seq, name: name, args: args, mac: mac)
        default:
            return nil
        }
    }
}
