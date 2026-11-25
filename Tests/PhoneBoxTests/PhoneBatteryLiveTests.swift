import Foundation
import Testing
@testable import PhoneBox
import PhoneBoxCore

/// Reads the battery of the iPhone plugged into this Mac, so it runs only on request and with one trusted iPhone on
/// the cable: `PHONEBOX_LIVE=1 make test FILTER=PhoneBatteryLiveTests`.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PHONEBOX_LIVE"] == "1"))
struct PhoneBatteryLiveTests {
    @Test func readsThePluggedInPhone() async throws {
        #expect(MobileDeviceAPI.load() != nil)
        let reader = PhoneBatteryReader()
        reader.start()
        defer { reader.stop() }
        var sample: PhoneBatterySample?
        for _ in 0..<40 where sample == nil {
            try await Task.sleep(for: .milliseconds(250))
            sample = reader.latest
        }
        let battery = try #require(sample, "no iPhone battery within 10 s: is one trusted iPhone plugged in?")
        #expect((0...100).contains(battery.percent))
        #expect(battery.plugged)
    }
}
