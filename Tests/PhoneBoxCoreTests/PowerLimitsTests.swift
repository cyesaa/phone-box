import Testing
@testable import PhoneBoxCore

struct PowerLimitsTests {
    @Test func picksLimitsByChipFamily() {
        #expect(PowerLimits.forChip("Apple M4", wholeMac: true) == PowerLimits(start: 15, full: 35))
        #expect(PowerLimits.forChip("Apple M4 Pro", wholeMac: true) == PowerLimits(start: 25, full: 60))
        #expect(PowerLimits.forChip("Apple M2 Max", wholeMac: true) == PowerLimits(start: 35, full: 100))
        #expect(PowerLimits.forChip("Apple M3 Ultra", wholeMac: true) == PowerLimits(start: 50, full: 160))
    }

    @Test func desktopMacsGetGPULimits() {
        #expect(PowerLimits.forChip("Apple M4", wholeMac: false) == PowerLimits(start: 5, full: 15))
        #expect(PowerLimits.forChip("Apple M4 Pro", wholeMac: false) == PowerLimits(start: 10, full: 30))
        #expect(PowerLimits.forChip("Apple M2 Max", wholeMac: false) == PowerLimits(start: 20, full: 60))
        #expect(PowerLimits.forChip("Apple M2 Ultra", wholeMac: false) == PowerLimits(start: 30, full: 90))
    }

    @Test func anUnknownChipGetsTheStandardLimits() {
        #expect(PowerLimits.forChip("", wholeMac: true) == .standard)
        #expect(PowerLimits.forChip("Apple M9 Hyper", wholeMac: true) == .standard)
    }
}
