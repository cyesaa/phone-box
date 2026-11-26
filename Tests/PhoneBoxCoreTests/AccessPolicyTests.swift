import Testing
@testable import PhoneBoxCore

struct AccessPolicyTests {
    @Test func cableModeAllowsOnlyClientsOnTheUSBLink() {
        for setting in [false, true] {
            #expect(AccessPolicy.decide(mode: .cable, lockAndMusicOverWiFi: setting, clientOnUSB: true, authenticated: true)
                == .onCable)
            #expect(AccessPolicy.decide(mode: .cable, lockAndMusicOverWiFi: setting, clientOnUSB: false, authenticated: true)
                == .notOnCable)
        }
    }

    @Test func alwaysModeStreamsToEveryoneButTakesCommandsOnlyFromTheCable() {
        #expect(AccessPolicy.decide(mode: .always, lockAndMusicOverWiFi: false, clientOnUSB: true, authenticated: true)
            == .onCable)
        let wifi = AccessPolicy.decide(mode: .always, lockAndMusicOverWiFi: false, clientOnUSB: false, authenticated: true)
        #expect(wifi == .overWiFi)
        #expect(wifi.streaming && wifi.commands.isEmpty && !wifi.cable)
    }

    @Test func lockAndMusicOverWiFiOpensOnlyThoseToWiFiPhonesInAlwaysMode() {
        let wifi = AccessPolicy.decide(mode: .always, lockAndMusicOverWiFi: true, clientOnUSB: false, authenticated: true)
        #expect(wifi == .overWiFiWithLockAndMusic)
        #expect(wifi.streaming && wifi.commands == ["media", "lock"] && !wifi.cable && wifi.reason == "ok")
        #expect(AccessPolicy.decide(mode: .always, lockAndMusicOverWiFi: true, clientOnUSB: true, authenticated: true)
            == .onCable)
    }

    @Test func theCableMaySendEveryCommand() {
        for mode in AccessMode.allCases {
            for setting in [false, true] {
                #expect(AccessPolicy.decide(mode: mode, lockAndMusicOverWiFi: setting, clientOnUSB: true, authenticated: true)
                    .commands == Command.allNames)
            }
        }
    }

    @Test func wiFiNeverGetsMoreThanLockAndMusic() {
        for mode in AccessMode.allCases {
            for setting in [false, true] {
                for authenticated in [true, false] {
                    let commands = AccessPolicy.decide(mode: mode, lockAndMusicOverWiFi: setting, clientOnUSB: false,
                                                       authenticated: authenticated).commands
                    #expect(Set(commands).isSubset(of: ["media", "lock"]), "\(mode) \(setting) \(authenticated)")
                    #expect(commands.isEmpty == !(mode == .always && setting && authenticated), "\(mode) \(setting) \(authenticated)")
                }
            }
        }
    }

    @Test func unauthenticatedClientsGetNothingInAnyMode() {
        for mode in AccessMode.allCases {
            for setting in [false, true] {
                for onUSB in [true, false] {
                    let access = AccessPolicy.decide(mode: mode, lockAndMusicOverWiFi: setting, clientOnUSB: onUSB,
                                                     authenticated: false)
                    #expect(access == .unauthenticated)
                    #expect(!access.streaming && access.commands.isEmpty)
                }
            }
        }
    }

    @Test func reasonsMatchTheProtocol() {
        #expect(Access.onCable.reason == "ok")
        #expect(Access.overWiFi.reason == "ok")
        #expect(Access.overWiFiWithLockAndMusic.reason == "ok")
        #expect(Access.notOnCable.reason == "not-on-cable")
    }
}
