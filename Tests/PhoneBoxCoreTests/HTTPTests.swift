import Foundation
import Testing
@testable import PhoneBoxCore

struct HTTPRequestParserTests {
    @Test func parsesARequestHead() {
        let request = "GET /app.js?x=1 HTTP/1.1\r\nHost: mac.local:4747\r\nRange: bytes=0-1\r\n\r\n"
        #expect(HTTPRequestParser.parse(Data(request.utf8))
            == .complete(HTTPRequestHead(method: "GET", path: "/app.js", headers: ["host": "mac.local:4747", "range": "bytes=0-1"])))
    }

    @Test func waitsForTheEndOfTheHead() {
        #expect(HTTPRequestParser.parse(Data("GET / HTTP/1.1\r\nHost: x\r\n".utf8)) == .incomplete)
    }

    @Test func spotsATLSHandshake() {
        #expect(HTTPRequestParser.parse(Data([0x16, 0x03, 0x01, 0x02, 0x00])) == .tls)
    }

    @Test func rejectsJunkAndHugeHeads() {
        #expect(HTTPRequestParser.parse(Data("HELLO\r\n\r\n".utf8)) == .invalid)
        #expect(HTTPRequestParser.parse(Data("GET / HTTP/1.1\r\nno colon here\r\n\r\n".utf8)) == .invalid)
        #expect(HTTPRequestParser.parse(Data(repeating: 0x41, count: HTTPRequestParser.maxHeadBytes + 1)) == .invalid)
    }

    @Test func rejectsAnOversizedHeadEvenWithItsTerminator() {
        let big = "GET / HTTP/1.1\r\nX-Big: " + String(repeating: "a", count: 20_000) + "\r\n\r\n"
        #expect(HTTPRequestParser.parse(Data(big.utf8)) == .invalid)
        #expect(HTTPRequestParser.parse(Data("GET / HTTP/1.1\r\nHost: x\r\n\r\n".utf8))
            == .complete(HTTPRequestHead(method: "GET", path: "/", headers: ["host": "x"])))
    }
}

struct ByteRangeTests {
    @Test func resolvesTheFormsIOSSends() {
        #expect(ByteRange.resolve(header: "bytes=0-1", length: 2854) == .partial(0...1))
        #expect(ByteRange.resolve(header: "bytes=0-2853", length: 2854) == .partial(0...2853))
        #expect(ByteRange.resolve(header: "bytes=0-", length: 2854) == .partial(0...2853))
    }

    @Test func clampsTheEndAndHandlesSuffixes() {
        #expect(ByteRange.resolve(header: "bytes=10-99999", length: 100) == .partial(10...99))
        #expect(ByteRange.resolve(header: "bytes=-10", length: 100) == .partial(90...99))
        #expect(ByteRange.resolve(header: "bytes=-500", length: 100) == .partial(0...99))
    }

    @Test func refusesRangesOutsideTheBody() {
        #expect(ByteRange.resolve(header: "bytes=100-", length: 100) == .unsatisfiable)
        #expect(ByteRange.resolve(header: "bytes=50-10", length: 100) == .unsatisfiable)
        #expect(ByteRange.resolve(header: "bytes=-0", length: 100) == .unsatisfiable)
    }

    @Test func servesTheWholeBodyOtherwise() {
        #expect(ByteRange.resolve(header: nil, length: 100) == .full)
        #expect(ByteRange.resolve(header: "bytes=0-1,5-6", length: 100) == .full)
        #expect(ByteRange.resolve(header: "items=0-1", length: 100) == .full)
    }
}

struct HTTPResponseTests {
    @Test func answersARangeWith206() {
        let response = String(decoding: HTTPResponse.file(Data("abcdef".utf8), name: "v.mp4", range: "bytes=1-2"), as: UTF8.self)
        #expect(response.hasPrefix("HTTP/1.1 206 Partial Content\r\n"))
        #expect(response.contains("Content-Type: video/mp4\r\n"))
        #expect(response.contains("Content-Range: bytes 1-2/6\r\n"))
        #expect(response.contains("Content-Length: 2\r\n"))
        #expect(response.hasSuffix("\r\n\r\nbc"))
    }

    @Test func answersWithoutARangeWith200() {
        let response = String(decoding: HTTPResponse.file(Data("<p>".utf8), name: "index.html", range: nil), as: UTF8.self)
        #expect(response.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(response.contains("Content-Type: text/html; charset=utf-8\r\n"))
        #expect(response.hasSuffix("\r\n\r\n<p>"))
    }

    @Test func answersAnImpossibleRangeWith416() {
        let response = String(decoding: HTTPResponse.file(Data("ab".utf8), name: "v.mp4", range: "bytes=5-"), as: UTF8.self)
        #expect(response.hasPrefix("HTTP/1.1 416 Range Not Satisfiable\r\n"))
        #expect(response.contains("Content-Range: bytes */2\r\n"))
    }

    @Test func answersARangeOnADataSlice() {
        let body = Data("xxabcdef".utf8).dropFirst(2)
        let response = String(decoding: HTTPResponse.file(body, name: "v.mp4", range: "bytes=1-2"), as: UTF8.self)
        #expect(response.contains("Content-Range: bytes 1-2/6\r\n"))
        #expect(response.hasSuffix("\r\n\r\nbc"))
    }
}
