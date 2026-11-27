import Foundation
import Testing
@testable import PhoneBoxCore

struct SessionTests {
    let key = PairingKey.generate()
    let now = ContinuousClock.now
    /// What a phone on the cable may send, and one on Wi-Fi with "Lock and Music over Wi-Fi" on.
    let cable = Command.allNames
    let wifi = Command.wifiNames

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
        _ = session.receive(authMessage(session, key: key), key: key, allowedCommands: cable, now: now)
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
        #expect(session.receive(authMessage(session, key: key), key: key, allowedCommands: cable, now: now) == .authenticated)
        #expect(session.isAuthenticated)
    }

    @Test func closesWith4001ForAWrongKey() {
        var session = Session(nonce: Session.makeNonce())
        let outcome = session.receive(authMessage(session, key: PairingKey.generate()), key: key, allowedCommands: cable, now: now)
        #expect(outcome == .close(code: 4001, reason: "bad key"))
        #expect(!session.isAuthenticated)
    }

    @Test func refusesCommandsBeforeAuthentication() {
        var session = Session(nonce: Session.makeNonce())
        #expect(session.receive(commandMessage(session, seq: 1), key: key, allowedCommands: cable, now: now)
            == .close(code: 4001, reason: "not authenticated"))
    }

    @Test func passesSignedFreshCommands() {
        var session = authenticated()
        #expect(session.receive(commandMessage(session, seq: 1), key: key, allowedCommands: cable, now: now)
            == .command(seq: 1, command: .mute(on: true)))
        #expect(session.receive(commandMessage(session, seq: 5), key: key, allowedCommands: cable, now: now)
            == .command(seq: 5, command: .mute(on: true)))
    }

    @Test func closesOnABadSignature() {
        var session = authenticated()
        let forged = commandMessage(session, seq: 1).replacingOccurrences(of: #""name":"mute""#, with: #""name":"sleep""#)
        #expect(session.receive(forged, key: key, allowedCommands: cable, now: now)
            == .close(code: 1008, reason: "bad signature"))
    }

    @Test func closesOnAReplayedOrOlderSequenceNumber() {
        var session = authenticated()
        _ = session.receive(commandMessage(session, seq: 3), key: key, allowedCommands: cable, now: now)
        #expect(session.receive(commandMessage(session, seq: 3), key: key, allowedCommands: cable, now: now)
            == .close(code: 1008, reason: "old sequence number"))
    }

    @Test func answersNotAllowedWhenAccessIsClosed() {
        var session = authenticated()
        #expect(session.receive(commandMessage(session, seq: 1), key: key, allowedCommands: [], now: now)
            == .reply(.ack(seq: 1, ok: false, error: "not-allowed")))
    }

    @Test func closesAfterTenCommandsInOneSecond() {
        var session = authenticated()
        for seq in 1...10 {
            #expect(session.receive(commandMessage(session, seq: seq), key: key, allowedCommands: cable, now: now)
                == .command(seq: seq, command: .mute(on: true)))
        }
        #expect(session.receive(commandMessage(session, seq: 11), key: key, allowedCommands: cable, now: now)
            == .close(code: 1008, reason: "too many commands"))
    }

    @Test func theRateLimitWindowMoves() {
        var session = authenticated()
        for seq in 1...10 {
            _ = session.receive(commandMessage(session, seq: seq), key: key, allowedCommands: cable, now: now)
        }
        #expect(session.receive(commandMessage(session, seq: 11), key: key, allowedCommands: cable, now: now + .seconds(1.1))
            == .command(seq: 11, command: .mute(on: true)))
    }

    @Test func closesOnJunkAndOnASecondAuth() {
        var session = authenticated()
        #expect(session.receive("{", key: key, allowedCommands: cable, now: now) == .close(code: 1008, reason: "bad message"))
        var again = authenticated()
        #expect(again.receive(authMessage(again, key: key), key: key, allowedCommands: cable, now: now)
            == .close(code: 1008, reason: "already authenticated"))
    }

    @Test func aPhoneOnTheCableMaySendEveryCommand() {
        var session = authenticated()
        let all: [(String, String, Command)] = [
            ("quitApp", #"{"bundleId":"com.apple.Chess","force":true}"#, .quitApp(bundleId: "com.apple.Chess", force: true)),
            ("media", #"{"action":"playPause"}"#, .media(.playPause)), ("volume", #"{"level":0.5}"#, .volume(level: 0.5)),
            ("mute", #"{"on":false}"#, .mute(on: false)), ("lock", "{}", .lock), ("displaySleep", "{}", .displaySleep),
            ("sleep", "{}", .sleep),
        ]
        #expect(all.map(\.0) == Command.allNames)
        for (offset, (name, args, command)) in all.enumerated() {
            let seq = 1 + offset
            #expect(session.receive(commandMessage(session, seq: seq, name: name, args: args), key: key, allowedCommands: cable, now: now)
                == .command(seq: seq, command: command), "\(name)")
        }
    }

    @Test func aPhoneOnWiFiMaySendOnlyLockAndMusic() {
        var session = authenticated()
        #expect(session.receive(commandMessage(session, seq: 1, name: "lock", args: "{}"), key: key, allowedCommands: wifi, now: now)
            == .command(seq: 1, command: .lock))
        #expect(session.receive(commandMessage(session, seq: 2, name: "media", args: #"{"action":"next"}"#), key: key,
                                allowedCommands: wifi, now: now)
            == .command(seq: 2, command: .media(.next)))
        let refused: [(String, String)] = [("volume", #"{"level":0.5}"#), ("mute", #"{"on":true}"#), ("displaySleep", "{}"),
                                           ("quitApp", #"{"bundleId":"com.apple.Chess","force":false}"#), ("sleep", "{}")]
        for (offset, (name, args)) in refused.enumerated() {
            let seq = 3 + offset
            #expect(session.receive(commandMessage(session, seq: seq, name: name, args: args), key: key, allowedCommands: wifi, now: now)
                == .reply(.ack(seq: seq, ok: false, error: "not-allowed")), "\(name)")
        }
    }

    @Test func answersAnAllowedNameWithMalformedArgumentsWithUnsupported() {
        var session = authenticated()
        #expect(session.receive(commandMessage(session, seq: 1, name: "volume", args: #"{"level":2}"#), key: key,
                                allowedCommands: cable, now: now)
            == .reply(.ack(seq: 1, ok: false, error: "unsupported")))
        #expect(session.receive(commandMessage(session, seq: 2, name: "media", args: #"{"action":"stop"}"#), key: key,
                                allowedCommands: wifi, now: now)
            == .reply(.ack(seq: 2, ok: false, error: "unsupported")))
    }

    /// The lists hold only `Command.allNames`: a name outside them is refused even from the cable.
    @Test func answersAnUnknownNameWithNotAllowed() {
        var session = authenticated()
        #expect(session.receive(commandMessage(session, seq: 1, name: "shutdown", args: "{}"), key: key, allowedCommands: cable, now: now)
            == .reply(.ack(seq: 1, ok: false, error: "not-allowed")))
    }

    @Test func notAllowedComesBeforeParsing() {
        var session = authenticated()
        #expect(session.receive(commandMessage(session, seq: 1, name: "shutdown", args: "{}"), key: key, allowedCommands: [], now: now)
            == .reply(.ack(seq: 1, ok: false, error: "not-allowed")))
    }

    @Test func authTimeoutHasItsOwnCloseCode() {
        #expect(Session.authTimeoutCode == 4003)
        #expect(Session.authTimeoutCode != Session.authFailedCode)
    }
}
