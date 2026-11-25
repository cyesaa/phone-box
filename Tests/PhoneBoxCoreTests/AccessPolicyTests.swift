import Testing
@testable import PhoneBoxCore

struct AccessPolicyTests {
    @Test func cableModeAllowsOnlyClientsOnTheUSBLink() {
        #expect(AccessPolicy.decide(mode: .cable, clientOnUSB: true, authenticated: true) == .granted)
        #expect(AccessPolicy.decide(mode: .cable, clientOnUSB: false, authenticated: true) == .notOnCable)
    }

    @Test func alwaysModeAllowsEveryAuthenticatedClient() {
        #expect(AccessPolicy.decide(mode: .always, clientOnUSB: true, authenticated: true) == .granted)
        #expect(AccessPolicy.decide(mode: .always, clientOnUSB: false, authenticated: true) == .granted)
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
        #expect(Access.granted.reason == "ok")
        #expect(Access.notOnCable.reason == "not-on-cable")
    }
}
