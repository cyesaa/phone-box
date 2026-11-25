import Testing
@testable import PhoneBoxCore

struct AccessPolicyTests {
    @Test func cableModeAllowsOnlyClientsOnTheUSBLink() {
        #expect(AccessPolicy.decide(mode: .cable, clientOnUSB: true, authenticated: true) == .onCable)
        #expect(AccessPolicy.decide(mode: .cable, clientOnUSB: false, authenticated: true) == .notOnCable)
    }

    @Test func alwaysModeStreamsToEveryoneButTakesCommandsOnlyFromTheCable() {
        #expect(AccessPolicy.decide(mode: .always, clientOnUSB: true, authenticated: true) == .onCable)
        let wifi = AccessPolicy.decide(mode: .always, clientOnUSB: false, authenticated: true)
        #expect(wifi == .overWiFi)
        #expect(wifi.streaming && !wifi.commands && !wifi.cable)
    }

    @Test func commandsNeverComeFromOffTheCable() {
        for mode in AccessMode.allCases {
            for authenticated in [true, false] {
                #expect(!AccessPolicy.decide(mode: mode, clientOnUSB: false, authenticated: authenticated).commands)
            }
        }
    }

    @Test func unauthenticatedClientsGetNothingInAnyMode() {
        for mode in AccessMode.allCases {
            for onUSB in [true, false] {
                let access = AccessPolicy.decide(mode: mode, clientOnUSB: onUSB, authenticated: false)
                #expect(access == .unauthenticated)
                #expect(!access.streaming && !access.commands)
            }
        }
    }

    @Test func reasonsMatchTheProtocol() {
        #expect(Access.onCable.reason == "ok")
        #expect(Access.overWiFi.reason == "ok")
        #expect(Access.notOnCable.reason == "not-on-cable")
    }
}
