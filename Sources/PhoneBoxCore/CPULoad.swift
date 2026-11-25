/// One core's tick counters as `host_processor_info` reports them.
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    var busy: UInt64 { user + system + nice }
    var total: UInt64 { busy + idle }
}

/// The `cpu` field of a snapshot (design §6).
public struct CPUSample: Equatable, Codable, Sendable {
    /// Busy percentage of all cores together, 0…100.
    public var total: Double
    /// Busy percentage of each core, in the order macOS numbers them.
    public var cores: [Double]
    /// How many performance cores the Mac has (`hw.perflevel0.logicalcpu`); 0 when macOS does not say.
    public var pCores: Int
    /// Load average over 1, 5 and 15 minutes.
    public var load: [Double]

    public init(total: Double, cores: [Double], pCores: Int, load: [Double]) {
        self.total = total
        self.cores = cores
        self.pCores = pCores
        self.load = load
    }
}

public enum CPULoad {
    /// Busy percentages between two readings. Nil when the core count changed or a counter went backwards
    /// (after sleep or a counter wrap), so the caller starts again from the new reading.
    public static func usage(from previous: [CPUTicks], to current: [CPUTicks]) -> (total: Double, cores: [Double])? {
        guard !current.isEmpty, previous.count == current.count else { return nil }
        var cores: [Double] = []
        var busySum: UInt64 = 0
        var totalSum: UInt64 = 0
        for (old, new) in zip(previous, current) {
            guard new.user >= old.user, new.system >= old.system, new.idle >= old.idle, new.nice >= old.nice
            else { return nil }
            let busy = new.busy - old.busy
            let total = new.total - old.total
            cores.append(percent(busy, of: total))
            busySum += busy
            totalSum += total
        }
        return (percent(busySum, of: totalSum), cores)
    }

    private static func percent(_ part: UInt64, of whole: UInt64) -> Double {
        whole == 0 ? 0 : rounded(Double(part) / Double(whole) * 100)
    }

    /// One decimal place: enough for the dashboard and keeps the JSON short.
    public static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
