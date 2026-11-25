import Foundation
import Testing
@testable import PhoneBoxCore

struct PairingKeyTests {
    @Test func hexRoundTrips() {
        let bytes = Data([0x00, 0x0f, 0xa5, 0xff])
        #expect(Hex.encode(bytes) == "000fa5ff")
        #expect(Hex.decode("000fa5ff") == bytes)
        #expect(Hex.decode("000FA5FF") == bytes)
    }

    @Test func hexRejectsOddLengthAndNonDigits() {
        #expect(Hex.decode("abc") == nil)
        #expect(Hex.decode("zz") == nil)
    }

    @Test func generatedKeysAre32BytesAndDiffer() {
        let first = PairingKey.generate()
        let second = PairingKey.generate()
        #expect(first.bytes.count == 32)
        #expect(first != second)
    }

    @Test func base64URLRoundTripsWithoutPadding() {
        let key = PairingKey(bytes: Data((0..<32).map { UInt8($0 * 8) }))!
        #expect(!key.base64URL.contains("="))
        #expect(!key.base64URL.contains("+"))
        #expect(!key.base64URL.contains("/"))
        #expect(PairingKey(base64URL: key.base64URL) == key)
    }

    @Test func rejectsWrongLengths() {
        #expect(PairingKey(bytes: Data(count: 31)) == nil)
        #expect(PairingKey(base64URL: "c2hvcnQ") == nil)
        #expect(PairingKey(base64URL: "%%%") == nil)
    }
}
