import Foundation

/// The 32-byte secret shared with paired phones (design §5). It reaches the phone only inside the QR code's
/// URL fragment (`#k=`), which browsers never send to the server.
public struct PairingKey: Equatable, Sendable {
    public let bytes: Data

    public init?(bytes: Data) {
        guard bytes.count == 32 else { return nil }
        self.bytes = bytes
    }

    /// 32 bytes from the system's cryptographically secure generator.
    public static func generate() -> PairingKey {
        var generator = SystemRandomNumberGenerator()
        return PairingKey(bytes: Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))!
    }

    /// Base64url without padding: safe in a URL fragment and in a file.
    public var base64URL: String {
        bytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public init?(base64URL text: String) {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        self.init(bytes: data)
    }
}
