import CryptoKit
import Foundation

/// RFC 6455, just what the dashboard needs: text frames, ping/pong and close; no fragmentation, no extensions.
public enum WebSocketHandshake {
    public static func acceptValue(for key: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))
        return Data(digest).base64EncodedString()
    }

    public static func response(for key: String) -> Data {
        Data(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
              + "Sec-WebSocket-Accept: \(acceptValue(for: key))\r\n\r\n").utf8)
    }
}

public enum WebSocketOpcode: UInt8, Sendable {
    case continuation = 0x0, text = 0x1, binary = 0x2, close = 0x8, ping = 0x9, pong = 0xA
}

public struct WebSocketFrame: Equatable, Sendable {
    public var opcode: UInt8
    public var payload: Data

    public init(opcode: UInt8, payload: Data) {
        self.opcode = opcode
        self.payload = payload
    }

    public var text: String? {
        opcode == WebSocketOpcode.text.rawValue ? String(data: payload, encoding: .utf8) : nil
    }
}

public enum WebSocketCodec {
    /// A server frame: final, unmasked.
    public static func encode(_ opcode: WebSocketOpcode, _ payload: Data) -> Data {
        var frame = Data([0x80 | opcode.rawValue])
        switch payload.count {
        case ..<126:
            frame.append(UInt8(payload.count))
        case ..<65_536:
            frame.append(126)
            frame.append(contentsOf: [UInt8(payload.count >> 8), UInt8(payload.count & 0xff)])
        default:
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) { frame.append(UInt8((payload.count >> shift) & 0xff)) }
        }
        return frame + payload
    }

    public static func text(_ string: String) -> Data {
        encode(.text, Data(string.utf8))
    }

    public static func close(code: UInt16, reason: String) -> Data {
        encode(.close, Data([UInt8(code >> 8), UInt8(code & 0xff)]) + Data(reason.utf8.prefix(120)))
    }
}

/// Turns the bytes a browser sends into frames. Browsers always mask their frames; an unmasked or
/// fragmented frame, one over 64 KB, a malformed control frame, reserved bits or a reserved opcode is a
/// protocol error and the connection is closed.
public struct WebSocketDecoder: Sendable {
    public static let maxPayload = 65_536

    public enum DecodeError: Error, Equatable, Sendable {
        case unmasked, fragmented, tooLarge, badControlFrame, reservedBits, reservedOpcode
    }

    private var buffer: [UInt8] = []

    public init() {}

    public mutating func append(_ data: Data) throws -> [WebSocketFrame] {
        buffer.append(contentsOf: data)
        var frames: [WebSocketFrame] = []
        var read = 0
        // One compaction at the end keeps this linear in the bytes appended, also when the frames come in the
        // thousands (and when an error is thrown, the connection is closed anyway).
        defer { if read > 0 { buffer.removeFirst(read) } }
        while buffer.count - read >= 2 {
            let first = buffer[read]
            let second = buffer[read + 1]
            let final = first & 0x80 != 0
            let opcode = first & 0x0f
            guard first & 0x70 == 0 else { throw DecodeError.reservedBits }
            guard (0x3...0x7).contains(opcode) == false, opcode < 0xB else { throw DecodeError.reservedOpcode }
            guard second & 0x80 != 0 else { throw DecodeError.unmasked }
            let isControl = opcode >= 0x8
            if isControl {
                guard final, second & 0x7f <= 125 else { throw DecodeError.badControlFrame }
            }
            var length = Int(second & 0x7f)
            var offset = 2
            if length == 126 {
                guard buffer.count - read >= 4 else { break }
                length = Int(buffer[read + 2]) << 8 | Int(buffer[read + 3])
                offset = 4
            } else if length == 127 {
                guard buffer.count - read >= 10 else { break }
                guard buffer[read + 2] & 0x80 == 0 else { throw DecodeError.tooLarge }
                length = buffer[(read + 2)..<(read + 10)].reduce(0) { $0 << 8 | Int($1) }
                offset = 10
            }
            guard length >= 0, length <= Self.maxPayload else { throw DecodeError.tooLarge }
            guard final, opcode != WebSocketOpcode.continuation.rawValue else { throw DecodeError.fragmented }
            guard buffer.count - read >= offset + 4 + length else { break }
            let maskStart = read + offset
            let start = maskStart + 4
            var payload = Array(buffer[start..<(start + length)])
            for index in payload.indices { payload[index] ^= buffer[maskStart + index % 4] }
            frames.append(WebSocketFrame(opcode: opcode, payload: Data(payload)))
            read = start + length
        }
        return frames
    }
}
