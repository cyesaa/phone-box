import Darwin
import PhoneBoxCore

/// Reads per-core tick counters and turns two readings into a `CPUSample` (design §6).
final class CPUCollector {
    private var previous: [CPUTicks]?

    /// Forget the last reading, e.g. after the Mac wakes: the next sample is nil instead of a jump.
    func reset() {
        previous = nil
    }

    func sample() -> CPUSample? {
        guard let current = Self.readTicks() else { return nil }
        defer { previous = current }
        guard let previous, let usage = CPULoad.usage(from: previous, to: current) else { return nil }
        return CPUSample(total: usage.total, cores: usage.cores, pCores: Self.performanceCores, load: Self.loadAverage())
    }

    static func readTicks() -> [CPUTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info
        else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        return (0..<Int(cpuCount)).map { core in
            let base = core * Int(CPU_STATE_MAX)
            func ticks(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[base + Int(state)])) }
            return CPUTicks(user: ticks(CPU_STATE_USER), system: ticks(CPU_STATE_SYSTEM),
                            idle: ticks(CPU_STATE_IDLE), nice: ticks(CPU_STATE_NICE))
        }
    }

    static let performanceCores: Int = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.perflevel0.logicalcpu", &value, &size, nil, 0) == 0 ? Int(value) : 0
    }()

    static func loadAverage() -> [Double] {
        var load = [Double](repeating: 0, count: 3)
        guard getloadavg(&load, 3) == 3 else { return [] }
        return load.map(CPULoad.rounded)
    }
}
