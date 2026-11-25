import Foundation
import JavaScriptCore
import Testing
@testable import PhoneBoxCore

/// Runs the dashboard's `Resources/web/sha256.js` in JavaScriptCore (the engine behind Safari) and checks it
/// signs exactly like `MessageAuth`. No Node or npm needed.
struct WebCryptoTests {
    static let scriptURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/web/sha256.js")

    func context() throws -> JSContext {
        let context = try #require(JSContext())
        context.exceptionHandler = { _, exception in Issue.record("JavaScript error: \(exception?.toString() ?? "?")") }
        context.evaluateScript(try String(contentsOf: Self.scriptURL, encoding: .utf8))
        return context
    }

    func hmac(_ context: JSContext, keyHex: String, message: String) -> String? {
        let function = context.evaluateScript("(k, m) => PBCrypto.hmacHex(PBCrypto.hexToBytes(k), m)")
        return function?.call(withArguments: [keyHex, message])?.toString()
    }

    @Test func matchesRFC4231() throws {
        let context = try context()
        #expect(hmac(context, keyHex: String(repeating: "0b", count: 20), message: "Hi There")
            == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
        #expect(hmac(context, keyHex: Hex.encode(Data("Jefe".utf8)), message: "what do ya want for nothing?")
            == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
    }

    /// RFC 4231 test case 6: a key longer than the block size is hashed first.
    @Test func hashesLongKeys() throws {
        let context = try context()
        #expect(hmac(context, keyHex: String(repeating: "aa", count: 131), message: "Test Using Larger Than Block-Size Key - Hash Key First")
            == "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
    }

    @Test func signsLikeTheMacForRealKeysAndNonUTF8Text() throws {
        let context = try context()
        for message in ["auth:0123456789abcdef0123456789abcdef", #"cmd:ab:7:quitApp:{"pid":42,"bundleId":"net.whatsapp"}"#,
                        "çğıöşü ÇĞİÖŞÜ 🌹", String(repeating: "x", count: 1_000)] {
            let key = PairingKey.generate()
            #expect(hmac(context, keyHex: Hex.encode(key.bytes), message: message) == MessageAuth.hmacHex(key: key.bytes, message: message))
        }
    }

    @Test func decodesBase64URLKeysLikePairingKey() throws {
        let context = try context()
        let key = PairingKey.generate()
        let decode = context.evaluateScript("(k) => PBCrypto.hex(PBCrypto.base64UrlToBytes(k))")
        #expect(decode?.call(withArguments: [key.base64URL])?.toString() == Hex.encode(key.bytes))
    }
}
