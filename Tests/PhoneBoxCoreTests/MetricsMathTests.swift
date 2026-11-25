import Testing
@testable import PhoneBoxCore

struct CPULoadTests {
    @Test func computesPerCoreAndTotalBusyPercent() {
        let before = [CPUTicks(user: 100, system: 50, idle: 850, nice: 0), CPUTicks(user: 0, system: 0, idle: 1000, nice: 0)]
        let after = [CPUTicks(user: 150, system: 75, idle: 875, nice: 0), CPUTicks(user: 10, system: 0, idle: 1090, nice: 0)]
        let usage = CPULoad.usage(from: before, to: after)
        #expect(usage?.cores == [75, 10])
        #expect(usage?.total == 42.5)
    }

    @Test func countsNiceAsBusy() {
        let usage = CPULoad.usage(from: [CPUTicks(user: 0, system: 0, idle: 0, nice: 0)],
                                  to: [CPUTicks(user: 0, system: 0, idle: 50, nice: 50)])
        #expect(usage?.total == 50)
    }

    @Test func noTicksMeansZeroNotNaN() {
        let ticks = [CPUTicks(user: 5, system: 5, idle: 5, nice: 0)]
        #expect(CPULoad.usage(from: ticks, to: ticks)?.total == 0)
    }

    @Test func startsAgainWhenCountersGoBackwardsOrCoresChange() {
        let high = [CPUTicks(user: 100, system: 100, idle: 100, nice: 0)]
        let low = [CPUTicks(user: 1, system: 1, idle: 1, nice: 0)]
        #expect(CPULoad.usage(from: high, to: low) == nil)
        #expect(CPULoad.usage(from: high, to: high + high) == nil)
        #expect(CPULoad.usage(from: [], to: []) == nil)
    }

    @Test func roundsToOneDecimal() {
        #expect(CPULoad.rounded(33.333) == 33.3)
        #expect(CPULoad.rounded(66.666) == 66.7)
    }
}

struct MemoryUsageTests {
    @Test func usedIsAppPlusWiredPlusCompressed() {
        let counts = VMPageCounts(pageSize: 16_384, internalPages: 300_000, purgeable: 20_000, wired: 100_000, compressed: 50_000)
        let sample = MemoryUsage.sample(counts: counts, totalBytes: 17_179_869_184, swapUsedBytes: 1_024, pressureLevel: 1)
        #expect(sample.app == 280_000 * 16_384)
        #expect(sample.wired == 100_000 * 16_384)
        #expect(sample.compressed == 50_000 * 16_384)
        #expect(sample.used == 430_000 * 16_384)
        #expect(sample.swapUsed == 1_024)
        #expect(sample.pressure == "normal")
    }

    @Test func neverReportsMoreThanTheMacHas() {
        let counts = VMPageCounts(pageSize: 16_384, internalPages: 2_000_000, purgeable: 0, wired: 0, compressed: 0)
        #expect(MemoryUsage.sample(counts: counts, totalBytes: 1_000, swapUsedBytes: 0, pressureLevel: 1).used == 1_000)
    }

    @Test func purgeableLargerThanInternalCountsAsZero() {
        let counts = VMPageCounts(pageSize: 4_096, internalPages: 10, purgeable: 20, wired: 0, compressed: 0)
        #expect(MemoryUsage.sample(counts: counts, totalBytes: 1 << 30, swapUsedBytes: 0, pressureLevel: 1).app == 0)
    }

    @Test func namesThePressureLevels() {
        #expect(MemoryUsage.pressureName(1) == "normal")
        #expect(MemoryUsage.pressureName(2) == "warn")
        #expect(MemoryUsage.pressureName(4) == "critical")
        #expect(MemoryUsage.pressureName(0) == "normal")
    }
}
