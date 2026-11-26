import Foundation
import Testing
@testable import PhoneBoxCore

struct WiFiCommandLimitTests {
    let start = Date(timeIntervalSince1970: 1_000)

    /// `#expect` cannot call a mutating member directly.
    func ask(_ limit: inout WiFiCommandLimit, _ command: Command, _ now: Date) -> Bool {
        limit.allows(command, now: now)
    }

    @Test func aSecondLockWithin30SecondsIsRefused() {
        var limit = WiFiCommandLimit()
        #expect(ask(&limit, .lock, start))
        #expect(!ask(&limit, .lock, start.addingTimeInterval(0.1)))
        #expect(!ask(&limit, .lock, start.addingTimeInterval(29.9)))
        #expect(ask(&limit, .lock, start.addingTimeInterval(30)))
    }

    @Test func aRefusedLockDoesNotExtendTheWait() {
        var limit = WiFiCommandLimit()
        #expect(ask(&limit, .lock, start))
        #expect(!ask(&limit, .lock, start.addingTimeInterval(20)))
        #expect(ask(&limit, .lock, start.addingTimeInterval(30)))
    }

    @Test func theFourthMediaCommandWithinASecondIsRefused() {
        var limit = WiFiCommandLimit()
        for offset in [0.0, 0.2, 0.4] {
            #expect(ask(&limit, .media(.next), start.addingTimeInterval(offset)))
        }
        #expect(!ask(&limit, .media(.next), start.addingTimeInterval(0.6)))
        #expect(!ask(&limit, .media(.playPause), start.addingTimeInterval(0.99)))
        // The first one has left the 1 s window.
        #expect(ask(&limit, .media(.previous), start.addingTimeInterval(1.0)))
    }

    @Test func theTwoLimitsAreIndependent() {
        var limit = WiFiCommandLimit()
        #expect(ask(&limit, .lock, start))
        #expect(ask(&limit, .media(.next), start))
        #expect(ask(&limit, .media(.next), start))
        #expect(ask(&limit, .media(.next), start))
        #expect(!ask(&limit, .media(.next), start))
        #expect(!ask(&limit, .lock, start.addingTimeInterval(1)))
        #expect(ask(&limit, .media(.next), start.addingTimeInterval(1)))
    }

    @Test func otherCommandsAreNotCountedHere() {
        var limit = WiFiCommandLimit()
        for _ in 0..<5 { #expect(ask(&limit, .mute(on: true), start)) }
    }
}
