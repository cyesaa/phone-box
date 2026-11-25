import Foundation
import IOKit
import PhoneBoxCore

/// Free and total space of the startup volume (refreshed every 10 s; it is slow to compute) and the read/write
/// speed of all block storage drivers.
final class DiskCollector {
    private static let capacityInterval: TimeInterval = 10
    private var capacity: (free: UInt64, total: UInt64)?
    private var capacityTime: TimeInterval = -.infinity
    private var reads = CounterRate()
    private var writes = CounterRate()

    func reset() {
        reads.reset()
        writes.reset()
    }

    func sample() -> DiskSample? {
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
        if now - capacityTime >= Self.capacityInterval {
            capacity = Self.readCapacity()
            capacityTime = now
        }
        guard let capacity else { return nil }
        let bytes = Self.readBytes()
        return DiskSample(free: capacity.free, total: capacity.total,
                          read: bytes.flatMap { reads.rate(value: $0.read, at: now) },
                          write: bytes.flatMap { writes.rate(value: $0.written, at: now) })
    }

    static func readCapacity() -> (free: UInt64, total: UInt64)? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0,
              let free = values.volumeAvailableCapacityForImportantUsage, free >= 0
        else { return nil }
        return (UInt64(free), UInt64(total))
    }

    /// Bytes read and written since boot, summed over every `IOBlockStorageDriver`.
    static func readBytes() -> (read: UInt64, written: UInt64)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator)
                == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0
        var written: UInt64 = 0
        var found = false
        while case let driver = IOIteratorNext(iterator), driver != 0 {
            defer { IOObjectRelease(driver) }
            guard let statistics = IORegistryEntryCreateCFProperty(driver, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any]
            else { continue }
            read += UInt64(max(0, statistics["Bytes (Read)"] as? Int ?? 0))
            written += UInt64(max(0, statistics["Bytes (Write)"] as? Int ?? 0))
            found = true
        }
        return found ? (read, written) : nil
    }
}
