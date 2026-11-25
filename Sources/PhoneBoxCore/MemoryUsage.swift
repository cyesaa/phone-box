/// The page counts from `host_statistics64(HOST_VM_INFO64)` that "Memory Used" is built from.
public struct VMPageCounts: Equatable, Sendable {
    public var pageSize: UInt64
    /// `internal_page_count`: anonymous memory of apps.
    public var internalPages: UInt64
    /// `purgeable_count`: memory apps said the system may throw away.
    public var purgeable: UInt64
    /// `wire_count`
    public var wired: UInt64
    /// `compressor_page_count`: pages the compressor holds.
    public var compressed: UInt64

    public init(pageSize: UInt64, internalPages: UInt64, purgeable: UInt64, wired: UInt64, compressed: UInt64) {
        self.pageSize = pageSize
        self.internalPages = internalPages
        self.purgeable = purgeable
        self.wired = wired
        self.compressed = compressed
    }
}

/// The `mem` field of a snapshot (design §6). Bytes.
public struct MemorySample: Equatable, Codable, Sendable {
    public var used: UInt64
    public var total: UInt64
    public var app: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var swapUsed: UInt64
    /// `normal`, `warn` or `critical`.
    public var pressure: String

    public init(used: UInt64, total: UInt64, app: UInt64, wired: UInt64, compressed: UInt64, swapUsed: UInt64, pressure: String) {
        self.used = used
        self.total = total
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.swapUsed = swapUsed
        self.pressure = pressure
    }
}

public enum MemoryUsage {
    /// "Memory Used" the way Activity Monitor counts it: app memory + wired + compressed.
    public static func sample(counts: VMPageCounts, totalBytes: UInt64, swapUsedBytes: UInt64, pressureLevel: Int) -> MemorySample {
        let appPages = counts.internalPages > counts.purgeable ? counts.internalPages - counts.purgeable : 0
        let app = appPages * counts.pageSize
        let wired = counts.wired * counts.pageSize
        let compressed = counts.compressed * counts.pageSize
        return MemorySample(
            used: min(app + wired + compressed, totalBytes), total: totalBytes, app: app, wired: wired,
            compressed: compressed, swapUsed: swapUsedBytes, pressure: pressureName(pressureLevel))
    }

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    public static func pressureName(_ level: Int) -> String {
        switch level {
        case 4: "critical"
        case 2: "warn"
        default: "normal"
        }
    }
}
