import Foundation
import Testing
@testable import PhoneBoxCore

struct SessionTests {
    let key = PairingKey.generate()
    let now = Date(timeIntervalSince1970: 1_000)

    func authMessage(_ session: Session, key: PairingKey) -> String {
        let mac = MessageAuth.hmacHex(key: key.bytes, message: MessageAuth.authMessage(nonce: session.nonce))
        return #"{"v":1,"type":"auth","mac":"\#(mac)"}"#
    }

    func commandMessage(_ session: Session, seq: Int, name: String = "mute", args: String = #"{"on":true}"#) -> String {
        let mac = MessageAuth.hmacHex(key: key.bytes,
                                      message: MessageAuth.commandMessage(nonce: session.nonce, seq: seq, name: name, args: args))
        let escapedArgs = args.replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"v":1,"type":"cmd","seq":\#(seq),"name":"\#(name)","args":"\#(escapedArgs)","mac":"\#(mac)"}"#
    }

    func authenticated() -> Session {
        var session = Session(nonce: Session.makeNonce())
        _ = session.receive(authMessage(session, key: key), key: key, commandsAllowed: true, now: now)
        return session
    }

    @Test func noncesAre32HexDigitsAndDiffer() {
        let nonce = Session.makeNonce()
        #expect(nonce.count == 32)
        #expect(Hex.decode(nonce) != nil)
        #expect(nonce != Session.makeNonce())
    }

    @Test func authenticatesWithTheRightKey() {
        var session = Session(nonce: Session.makeNonce())
        #expect(session.receive(authMessage(session, key: key), key: key, commandsAllowed: true, now: now) == .authenticated)
        #expect(session.isAuthenticated)
    }

    @Test func closesWith4001ForAWrongKey() {
        var session = Session(nonce: Session.makeNonce())
        let outcome = session.receive(authMessage(session, key: PairingKey.generate()), key: key, commandsAllowed: true, now: now)
        #expect(outcome == .close(code: 4001, reason: "bad key"))
        #expect(!session.isAuthenticated)
    }

    @Test func refusesCommandsBeforeAuthentication() {
        var session = Session(nonce: Session.makeNonce())
        #expect(session.receive(commandMessage(session, seq: 1), key: key, commandsAllowed: true, now: now)
            == .close(code: 4001, reason: "not authenticated"))
    }

    @Test func passesSignedFreshCommands() {
        var session = authenticated()
        #expect(session.receive(commandMessage(session, seq: 1), key: key, commandsAllowed: true, now: now)
            == .command(seq: 1, name: "mute", args: #"{"on":true}"#))
        #expect(session.receive(commandMessage(session, seq: 5), key: key, commandsAllowed: true, now: now)
            == .command(seq: 5, name: "mute", args: #"{"on":true}"#))
    }

    @Test func closesOnABadSignature() {
        var session = authenticated()
        let forged = commandMessage(session, seq: 1).replacingOccurrences(of: #""name":"mute""#, with: #""name":"sleep""#)
        #expect(session.receive(forged, key: key, commandsAllowed: true, now: now)
            == .close(code: 1008, reason: "bad signature"))
    }

    @Test func closesOnAReplayedOrOlderSequenceNumber() {
        var session = authenticated()
        _ = session.receive(commandMessage(session, seq: 3), key: key, commandsAllowed: true, now: now)
        #expect(session.receive(commandMessage(session, seq: 3), key: key, commandsAllowed: true, now: now)
            == .close(code: 1008, reason: "old sequence number"))
    }

    @Test func answersNotAllowedWhenAccessIsClosed() {
        var session = authenticated()
        #expect(session.receive(commandMessage(session, seq: 1), key: key, commandsAllowed: false, now: now)
            == .reply(.ack(seq: 1, ok: false, error: "not-allowed")))
    }

    @Test func closesAfterTenCommandsInOneSecond() {
        var session = authenticated()
        for seq in 1...10 {
            #expect(session.receive(commandMessage(session, seq: seq), key: key, commandsAllowed: true, now: now)
                == .command(seq: seq, name: "mute", args: #"{"on":true}"#))
        }
        #expect(session.receive(commandMessage(session, seq: 11), key: key, commandsAllowed: true, now: now)
            == .close(code: 1008, reason: "too many commands"))
    }

    @Test func theRateLimitWindowMoves() {
        var session = authenticated()
        for seq in 1...10 {
            _ = session.receive(commandMessage(session, seq: seq), key: key, commandsAllowed: true, now: now)
        }
        #expect(session.receive(commandMessage(session, seq: 11), key: key, commandsAllowed: true, now: now.addingTimeInterval(1.1))
            == .command(seq: 11, name: "mute", args: #"{"on":true}"#))
    }

    @Test func closesOnJunkAndOnASecondAuth() {
        var session = authenticated()
        #expect(session.receive("{", key: key, commandsAllowed: true, now: now) == .close(code: 1008, reason: "bad message"))
        var again = authenticated()
        #expect(again.receive(authMessage(again, key: key), key: key, commandsAllowed: true, now: now)
            == .close(code: 1008, reason: "already authenticated"))
    }

    @Test func authTimeoutHasItsOwnCloseCode() {
        #expect(Session.authTimeoutCode == 4003)
        #expect(Session.authTimeoutCode != Session.authFailedCode)
    }
}
