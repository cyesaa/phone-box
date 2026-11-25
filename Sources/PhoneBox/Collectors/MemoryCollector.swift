import Darwin
import PhoneBoxCore

/// Reads the VM page counts, swap and memory pressure (design §6).
final class MemoryCollector {
    func sample() -> MemorySample? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS, Self.totalBytes > 0 else { return nil }
        let counts = VMPageCounts(
            pageSize: UInt64(vm_kernel_page_size), internalPages: UInt64(stats.internal_page_count),
            purgeable: UInt64(stats.purgeable_count), wired: UInt64(stats.wire_count),
            compressed: UInt64(stats.compressor_page_count))
        return MemoryUsage.sample(counts: counts, totalBytes: Self.totalBytes,
                                  swapUsedBytes: Self.swapUsedBytes(), pressureLevel: Self.pressureLevel())
    }

    static let totalBytes: UInt64 = {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        return sysctlbyname("hw.memsize", &value, &size, nil, 0) == 0 ? value : 0
    }()

    static func swapUsedBytes() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        return sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 ? usage.xsu_used : 0
    }

    static func pressureLevel() -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 ? Int(value) : 1
    }
}
