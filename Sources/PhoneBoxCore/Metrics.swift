import Foundation

// The snapshot fields that Plan 3A adds (design §6). Every value is finite; collectors pass raw numbers through
// `finiteOrNil` so a NaN from a sensor becomes a missing value instead of an encoding error.

public struct GPUSample: Equatable, Codable, Sendable {
    /// Busy percentage, 0…100.
    public var util: Double
    public init(util: Double) { self.util = util }
}

/// Chip temperature from the die sensors, °C.
public struct TemperatureSample: Equatable, Codable, Sendable {
    public var avg: Double
    public var max: Double
    public init(avg: Double, max: Double) {
        self.avg = avg
        self.max = max
    }
}

/// Watts. CPU and Neural Engine power need root on Apple silicon (spike 6), so they are not here.
public struct PowerSample: Equatable, Codable, Sendable {
    public var gpu: Double?
    /// Whole-Mac power from the battery telemetry; MacBooks only.
    public var system: Double?
    public init(gpu: Double?, system: Double?) {
        self.gpu = gpu
        self.system = system
    }
}

/// Bytes per second on the primary network interface.
public struct NetworkSample: Equatable, Codable, Sendable {
    public var rx: Double
    public var tx: Double
    public var iface: String
    public init(rx: Double, tx: Double, iface: String) {
        self.rx = rx
        self.tx = tx
        self.iface = iface
    }
}

/// The startup volume: capacity in bytes, read and write in bytes per second (nil until two readings exist).
public struct DiskSample: Equatable, Codable, Sendable {
    public var free: UInt64
    public var total: UInt64
    public var read: Double?
    public var write: Double?
    public init(free: UInt64, total: UInt64, read: Double?, write: Double?) {
        self.free = free
        self.total = total
        self.read = read
        self.write = write
    }
}

public struct BatterySample: Equatable, Codable, Sendable {
    public var percent: Int
    public var charging: Bool
    /// Minutes to empty while discharging, to full while charging; nil while macOS is still estimating.
    public var minutesLeft: Int?
    public init(percent: Int, charging: Bool, minutesLeft: Int?) {
        self.percent = percent
        self.charging = charging
        self.minutesLeft = minutesLeft
    }
}

extension Double {
    /// Nil for NaN and infinity, so an odd sensor value is left out of the snapshot instead of breaking it.
    public var finiteOrNil: Double? { isFinite ? self : nil }
}

/// Turns an ever-growing counter (bytes received, bytes read) into a per-second rate.
public struct CounterRate: Sendable {
    private var last: (value: UInt64, time: TimeInterval)?

    public init() {}

    /// Nil for the first reading, when the counter went backwards (reset, interface change) or no time passed.
    public mutating func rate(value: UInt64, at time: TimeInterval) -> Double? {
        defer { last = (value, time) }
        guard let last, value >= last.value, time > last.time else { return nil }
        return (Double(value - last.value) / (time - last.time)).rounded()
    }

    public mutating func reset() {
        last = nil
    }
}

public enum Temperatures {
    /// The sensors that describe the chip: the die sensors (`PMU tdie*`, `PMU2 tdie*`); if a chip names them
    /// differently, every `PMU` sensor except the calibration ones. Reading a sensor is a system call, so the
    /// collector asks only for these.
    public static func chipSensors(_ names: [String]) -> Set<String> {
        let die = names.filter { $0.hasPrefix("PMU tdie") || $0.hasPrefix("PMU2 tdie") }
        return Set(die.isEmpty ? names.filter { $0.hasPrefix("PMU") && !$0.contains("tcal") } : die)
    }

    /// Average and maximum of the chip sensors (see `chipSensors`). Readings outside 1…130 °C are ignored.
    public static func summary(_ readings: [(name: String, celsius: Double)]) -> TemperatureSample? {
        let chosenNames = chipSensors(readings.map(\.name))
        let chosen = readings.filter { chosenNames.contains($0.name) && $0.celsius > 0 && $0.celsius < 130 }
        guard !chosen.isEmpty else { return nil }
        let values = chosen.map(\.celsius)
        return TemperatureSample(avg: CPULoad.rounded(values.reduce(0, +) / Double(values.count)),
                                 max: CPULoad.rounded(values.max()!))
    }
}

public enum EnergyRate {
    /// Watts from an energy counter delta in IOReport's unit (`mJ`, `uJ`/`µJ` or `nJ`) over `seconds`.
    public static func watts(energy: Double, unit: String, seconds: Double) -> Double? {
        guard seconds > 0, energy >= 0 else { return nil }
        let joules: Double
        switch unit.trimmingCharacters(in: .whitespaces) {
        case "mJ": joules = energy / 1e3
        case "uJ", "µJ": joules = energy / 1e6
        case "nJ": joules = energy / 1e9
        default: return nil
        }
        return (joules / seconds * 100).rounded() / 100
    }
}

public enum BatteryInfo {
    /// Reads one power source description from `IOPSGetPowerSourceDescription`. Nil when it is not an internal
    /// battery (desktop Macs, UPSes) or has no capacity.
    public static func sample(from description: [String: Any]) -> BatterySample? {
        guard description["Type"] as? String == "InternalBattery",
              let current = description["Current Capacity"] as? Int,
              let maximum = description["Max Capacity"] as? Int, maximum > 0
        else { return nil }
        let charging = description["Is Charging"] as? Bool ?? false
        let minutes = (charging ? description["Time to Full Charge"] : description["Time to Empty"]) as? Int
        return BatterySample(percent: min(100, max(0, current * 100 / maximum)), charging: charging,
                             minutesLeft: minutes.flatMap { $0 > 0 ? $0 : nil })
    }
}
