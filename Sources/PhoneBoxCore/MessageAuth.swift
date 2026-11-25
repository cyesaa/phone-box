import CryptoKit
import Foundation

/// HMAC-SHA256 signatures of the WebSocket protocol (design §5). The phone signs with the same key in
/// `Resources/web/sha256.js`; the key itself never travels.
public enum MessageAuth {
    public static func hmacHex(key: Data, message: String) -> String {
        let code = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: key))
        return Hex.encode(Data(code))
    }

    /// What the phone signs to prove it holds the key: `auth:<nonce>`.
    public static func authMessage(nonce: String) -> String {
        "auth:" + nonce
    }

    /// What the phone signs for a command: `cmd:<nonce>:<seq>:<name>:<args>`, with `args` exactly as sent.
    public static func commandMessage(nonce: String, seq: Int, name: String, args: String) -> String {
        "cmd:\(nonce):\(seq):\(name):\(args)"
    }

    /// Compares in constant time. False for anything that is not 64 hex digits.
    public static func isValid(signature: String, key: Data, message: String) -> Bool {
        guard let tag = Hex.decode(signature), tag.count == 32 else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(tag, authenticating: Data(message.utf8), using: SymmetricKey(data: key))
    }
}
