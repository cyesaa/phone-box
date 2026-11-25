import Foundation
import Testing
@testable import PhoneBoxCore

struct PhoneBatteryTests {
    @Test func readsTheValuesThePhoneGives() {
        let sample = PhoneBatteryInfo.sample(capacity: NSNumber(value: 76), charging: kCFBooleanTrue, external: kCFBooleanTrue)
        #expect(sample == PhoneBatterySample(percent: 76, charging: true, plugged: true))
        #expect(PhoneBatteryInfo.sample(capacity: NSNumber(value: 100), charging: kCFBooleanFalse, external: nil)
            == PhoneBatterySample(percent: 100, charging: false, plugged: false))
    }

    @Test func refusesAMissingOrOddCapacity() {
        #expect(PhoneBatteryInfo.sample(capacity: nil, charging: kCFBooleanTrue, external: kCFBooleanTrue) == nil)
        #expect(PhoneBatteryInfo.sample(capacity: kCFBooleanTrue, charging: nil, external: nil) == nil)
        #expect(PhoneBatteryInfo.sample(capacity: NSNumber(value: 101), charging: nil, external: nil) == nil)
        #expect(PhoneBatteryInfo.sample(capacity: NSNumber(value: -1), charging: nil, external: nil) == nil)
        #expect(PhoneBatteryInfo.sample(capacity: "76", charging: nil, external: nil) == nil)
    }

    @Test func keepsAReadingForFiveMinutes() {
        var memory = PhoneBatteryMemory()
        let start = Date(timeIntervalSince1970: 1_000)
        let sample = PhoneBatterySample(percent: 50, charging: true, plugged: true)
        #expect(memory.current(at: start) == nil)
        memory.remember(sample, at: start)
        #expect(memory.current(at: start.addingTimeInterval(300)) == sample)
        #expect(memory.current(at: start.addingTimeInterval(301)) == nil)
    }

    @Test func forgetsAtOnceWhenThePhoneGoes() {
        var memory = PhoneBatteryMemory()
        let start = Date(timeIntervalSince1970: 1_000)
        memory.remember(PhoneBatterySample(percent: 50, charging: false, plugged: true), at: start)
        memory.forget()
        #expect(memory.current(at: start) == nil)
    }
}
