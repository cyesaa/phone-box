import Foundation
import Testing
@testable import PhoneBoxCore

struct MessageAuthTests {
    /// RFC 4231 test case 1.
    @Test func matchesRFC4231Case1() {
        let key = Data(repeating: 0x0b, count: 20)
        #expect(MessageAuth.hmacHex(key: key, message: "Hi There")
            == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
    }

    /// RFC 4231 test case 2.
    @Test func matchesRFC4231Case2() {
        #expect(MessageAuth.hmacHex(key: Data("Jefe".utf8), message: "what do ya want for nothing?")
            == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
    }

    @Test func buildsTheSignedStrings() {
        #expect(MessageAuth.authMessage(nonce: "ab12") == "auth:ab12")
        #expect(MessageAuth.commandMessage(nonce: "ab12", seq: 3, name: "mute", args: #"{"on":true}"#)
            == #"cmd:ab12:3:mute:{"on":true}"#)
    }

    @Test func validatesOnlyTheRightSignature() {
        let key = PairingKey.generate().bytes
        let good = MessageAuth.hmacHex(key: key, message: "auth:1234")
        #expect(MessageAuth.isValid(signature: good, key: key, message: "auth:1234"))
        #expect(MessageAuth.isValid(signature: good.uppercased(), key: key, message: "auth:1234"))
        #expect(!MessageAuth.isValid(signature: good, key: key, message: "auth:1235"))
        #expect(!MessageAuth.isValid(signature: String(good.dropLast(2)), key: key, message: "auth:1234"))
        #expect(!MessageAuth.isValid(signature: "not hex", key: key, message: "auth:1234"))
        #expect(!MessageAuth.isValid(signature: good, key: PairingKey.generate().bytes, message: "auth:1234"))
    }
}
