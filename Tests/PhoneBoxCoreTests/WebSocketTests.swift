import Foundation
import Testing
@testable import PhoneBoxCore

struct WebSocketTests {
    /// A frame as a browser sends it: final, masked.
    func clientFrame(_ opcode: UInt8, _ payload: [UInt8], mask: [UInt8] = [0x11, 0x22, 0x33, 0x44]) -> Data {
        var frame: [UInt8] = [0x80 | opcode]
        if payload.count < 126 {
            frame.append(0x80 | UInt8(payload.count))
        } else {
            frame.append(0x80 | 126)
            frame += [UInt8(payload.count >> 8), UInt8(payload.count & 0xff)]
        }
        frame += mask
        frame += payload.enumerated().map { $0.element ^ mask[$0.offset % 4] }
        return Data(frame)
    }

    /// The example in RFC 6455 section 1.3.
    @Test func computesTheAcceptValue() {
        #expect(WebSocketHandshake.acceptValue(for: "dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    @Test func encodesShortAndMediumTextFrames() {
        #expect(WebSocketCodec.text("Hi") == Data([0x81, 0x02, 0x48, 0x69]))
        let medium = WebSocketCodec.text(String(repeating: "a", count: 300))
        #expect(Array(medium.prefix(4)) == [0x81, 126, 0x01, 0x2c])
        #expect(medium.count == 304)
    }

    @Test func encodesCloseWithCode() {
        #expect(WebSocketCodec.close(code: 4001, reason: "x") == Data([0x88, 0x03, 0x0f, 0xa1, 0x78]))
    }

    @Test func decodesMaskedTextFrames() throws {
        var decoder = WebSocketDecoder()
        let frames = try decoder.append(clientFrame(0x1, Array("hello".utf8)))
        #expect(frames.map(\.text) == ["hello"])
    }

    @Test func waitsForAFrameThatArrivesInPieces() throws {
        var decoder = WebSocketDecoder()
        let frame = clientFrame(0x1, Array(String(repeating: "b", count: 200).utf8))
        #expect(try decoder.append(frame.prefix(3)).isEmpty)
        #expect(try decoder.append(frame.dropFirst(3).prefix(50)).isEmpty)
        let frames = try decoder.append(frame.dropFirst(53))
        #expect(frames.first?.text == String(repeating: "b", count: 200))
    }

    @Test func decodesSeveralFramesInOneRead() throws {
        var decoder = WebSocketDecoder()
        let frames = try decoder.append(clientFrame(0x1, Array("a".utf8)) + clientFrame(0x9, [1, 2]))
        #expect(frames.map(\.opcode) == [0x1, 0x9])
        #expect(frames[1].payload == Data([1, 2]))
    }

    @Test func rejectsUnmaskedFragmentedAndHugeFrames() {
        var unmasked = WebSocketDecoder()
        #expect(throws: WebSocketDecoder.DecodeError.unmasked) { try unmasked.append(Data([0x81, 0x01, 0x41])) }

        var fragmented = WebSocketDecoder()
        var first = clientFrame(0x1, [0x41])
        first[0] = 0x01
        #expect(throws: WebSocketDecoder.DecodeError.fragmented) { try fragmented.append(first) }

        var huge = WebSocketDecoder()
        let header = Data([0x81, 0x80 | 127, 0, 0, 0, 0, 0, 0x10, 0, 0])
        #expect(throws: WebSocketDecoder.DecodeError.tooLarge) { try huge.append(header) }
    }
}
