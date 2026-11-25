import Foundation
import Testing
@testable import PhoneBoxCore

struct CounterRateTests {
    @Test func firstReadingHasNoRate() {
        var rate = CounterRate()
        #expect(rate.rate(value: 1_000, at: 10) == nil)
    }

    @Test func computesBytesPerSecondRounded() {
        var rate = CounterRate()
        _ = rate.rate(value: 1_000, at: 10)
        #expect(rate.rate(value: 4_000, at: 12) == 1_500)
        #expect(rate.rate(value: 4_001, at: 15) == 0)
    }

    @Test func startsOverWhenTheCounterGoesBackOrTimeStands() {
        var rate = CounterRate()
        _ = rate.rate(value: 5_000, at: 10)
        #expect(rate.rate(value: 100, at: 11) == nil)
        #expect(rate.rate(value: 600, at: 12) == 500)
        #expect(rate.rate(value: 700, at: 12) == nil)
    }

    @Test func resetForgetsTheLastReading() {
        var rate = CounterRate()
        _ = rate.rate(value: 5_000, at: 10)
        rate.reset()
        #expect(rate.rate(value: 6_000, at: 11) == nil)
    }
}

struct TemperaturesTests {
    @Test func summarisesTheDieSensors() {
        let readings: [(name: String, celsius: Double)] = [
            ("PMU tdie1", 50), ("PMU tdie2", 54), ("PMU2 tdie1", 46), ("PMU tdev1", 80),
            ("gas gauge battery", 31), ("NAND CH0 temp", 43),
        ]
        #expect(Temperatures.summary(readings) == TemperatureSample(avg: 50, max: 54))
    }

    @Test func fallsBackToOtherPMUSensorsButNotCalibration() {
        let readings: [(name: String, celsius: Double)] = [("PMU tdev1", 40), ("PMU tdev2", 44), ("PMU tcal", 90)]
        #expect(Temperatures.summary(readings) == TemperatureSample(avg: 42, max: 44))
    }

    @Test func choosesTheChipSensorsByName() {
        #expect(Temperatures.chipSensors(["PMU tdie1", "PMU2 tdie3", "PMU tdev1", "NAND CH0 temp"]) == ["PMU tdie1", "PMU2 tdie3"])
        #expect(Temperatures.chipSensors(["PMU tdev1", "PMU tcal", "gas gauge battery"]) == ["PMU tdev1"])
        #expect(Temperatures.chipSensors(["gas gauge battery"]).isEmpty)
    }

    @Test func ignoresImpossibleValuesAndEmptyInput() {
        #expect(Temperatures.summary([("PMU tdie1", -1), ("PMU tdie2", 500)]) == nil)
        #expect(Temperatures.summary([]) == nil)
        #expect(Temperatures.summary([("gas gauge battery", 31)]) == nil)
    }
}

struct EnergyRateTests {
    @Test func convertsEachUnitToWatts() {
        #expect(EnergyRate.watts(energy: 2_000, unit: "mJ", seconds: 1) == 2)
        #expect(EnergyRate.watts(energy: 500_000, unit: "uJ", seconds: 0.5) == 1)
        #expect(EnergyRate.watts(energy: 510_018_661, unit: "nJ", seconds: 2) == 0.26)
        #expect(EnergyRate.watts(energy: 1_000_000, unit: " µJ ", seconds: 1) == 1)
    }

    @Test func refusesUnknownUnitsAndBadIntervals() {
        #expect(EnergyRate.watts(energy: 1, unit: "W", seconds: 1) == nil)
        #expect(EnergyRate.watts(energy: 1, unit: "mJ", seconds: 0) == nil)
        #expect(EnergyRate.watts(energy: -1, unit: "mJ", seconds: 1) == nil)
    }
}

struct BatteryInfoTests {
    @Test func readsADischargingBattery() {
        let description: [String: Any] = ["Type": "InternalBattery", "Current Capacity": 86, "Max Capacity": 100,
                                          "Is Charging": false, "Time to Empty": 312, "Time to Full Charge": -1]
        #expect(BatteryInfo.sample(from: description) == BatterySample(percent: 86, charging: false, minutesLeft: 312))
    }

    @Test func readsAChargingBatteryAndAnUnknownEstimate() {
        let description: [String: Any] = ["Type": "InternalBattery", "Current Capacity": 40, "Max Capacity": 100,
                                          "Is Charging": true, "Time to Full Charge": -1]
        #expect(BatteryInfo.sample(from: description) == BatterySample(percent: 40, charging: true, minutesLeft: nil))
    }

    @Test func ignoresUPSesAndBrokenDescriptions() {
        #expect(BatteryInfo.sample(from: ["Type": "UPS", "Current Capacity": 50, "Max Capacity": 100]) == nil)
        #expect(BatteryInfo.sample(from: ["Type": "InternalBattery", "Current Capacity": 50, "Max Capacity": 0]) == nil)
        #expect(BatteryInfo.sample(from: [:]) == nil)
    }

    @Test func keepsThePercentInRange() {
        let description: [String: Any] = ["Type": "InternalBattery", "Current Capacity": 120, "Max Capacity": 100]
        #expect(BatteryInfo.sample(from: description)?.percent == 100)
    }
}

struct FiniteTests {
    @Test func dropsNaNAndInfinity() {
        #expect(1.5.finiteOrNil == 1.5)
        #expect(Double.nan.finiteOrNil == nil)
        #expect(Double.infinity.finiteOrNil == nil)
    }
}
