import Foundation

/// Messages from the Mac to the phone (design §5). Every message carries `"v":1`.
public enum ServerMessage: Equatable, Sendable {
    case hello(nonce: String, app: String)
    case ready(mode: AccessMode, host: String, access: Access)
    case access(Access)
    case snapshot(Snapshot)
    case ack(seq: Int, ok: Bool, error: String?)

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    /// Compact JSON with sorted keys. Never crashes: a snapshot that cannot be encoded (a non-finite number that
    /// slipped past a collector) is sent with its timestamp only: for one second the phone keeps its CPU and RAM values and shows "—" for the
    /// other rows.
    public func json() -> String {
        if let data = try? Self.encoder.encode(self) { return String(decoding: data, as: UTF8.self) }
        if case let .snapshot(snapshot) = self, snapshot != Snapshot(t: snapshot.t) {
            return ServerMessage.snapshot(Snapshot(t: snapshot.t)).json()
        }
        return #"{"type":"error","v":1}"#
    }
}

extension ServerMessage: Encodable {
    private enum Keys: String, CodingKey {
        case v, type, nonce, app, mode, host, access, streaming, commands, cable, reason, t, cpu, mem, gpu, temp, power, net, disk,
             battery, apps, seq, ok, error
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(1, forKey: .v)
        switch self {
        case let .hello(nonce, app):
            try container.encode("hello", forKey: .type)
            try container.encode(nonce, forKey: .nonce)
            try container.encode(app, forKey: .app)
        case let .ready(mode, host, access):
            try container.encode("ready", forKey: .type)
            try container.encode(mode, forKey: .mode)
            try container.encode(host, forKey: .host)
            try container.encode(access, forKey: .access)
        case let .access(access):
            try container.encode("access", forKey: .type)
            try container.encode(access.streaming, forKey: .streaming)
            try container.encode(access.commands, forKey: .commands)
            try container.encode(access.cable, forKey: .cable)
            try container.encode(access.reason, forKey: .reason)
        case let .snapshot(snapshot):
            try container.encode("snapshot", forKey: .type)
            try container.encode(snapshot.t, forKey: .t)
            try container.encodeIfPresent(snapshot.cpu, forKey: .cpu)
            try container.encodeIfPresent(snapshot.mem, forKey: .mem)
            try container.encodeIfPresent(snapshot.gpu, forKey: .gpu)
            try container.encodeIfPresent(snapshot.temp, forKey: .temp)
            try container.encodeIfPresent(snapshot.power, forKey: .power)
            try container.encodeIfPresent(snapshot.net, forKey: .net)
            try container.encodeIfPresent(snapshot.disk, forKey: .disk)
            try container.encodeIfPresent(snapshot.battery, forKey: .battery)
            try container.encodeIfPresent(snapshot.apps, forKey: .apps)
        case let .ack(seq, ok, error):
            try container.encode("ack", forKey: .type)
            try container.encode(seq, forKey: .seq)
            try container.encode(ok, forKey: .ok)
            try container.encodeIfPresent(error, forKey: .error)
        }
    }
}

extension ServerMessage {
    /// The `ack` for a command's result.
    public static func ack(seq: Int, result: CommandResult) -> ServerMessage {
        switch result {
        case .ok: return .ack(seq: seq, ok: true, error: nil)
        case let .failed(failure): return .ack(seq: seq, ok: false, error: failure.rawValue)
        }
    }
}

/// Messages from the phone to the Mac.
public enum ClientMessage: Equatable, Sendable {
    case auth(mac: String)
    /// `args` is the JSON text exactly as the phone signed it.
    case command(seq: Int, name: String, args: String, mac: String)

    /// Nil for anything that is not a well-formed version 1 message. `v` must be the integer 1 and `seq` a
    /// positive integer: `true`, `1.0` or a negative number is not accepted (design §5).
    public static func parse(_ text: String) -> ClientMessage? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              JSONValue.integer(object["v"]) == 1
        else { return nil }
        switch object["type"] as? String {
        case "auth":
            guard let mac = object["mac"] as? String else { return nil }
            return .auth(mac: mac)
        case "cmd":
            guard let seq = JSONValue.integer(object["seq"]), seq > 0, let name = object["name"] as? String,
                  let args = object["args"] as? String, let mac = object["mac"] as? String
            else { return nil }
            return .command(seq: seq, name: name, args: args, mac: mac)
        default:
            return nil
        }
    }
}
