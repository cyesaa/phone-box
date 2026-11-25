import IOKit
import PhoneBoxCore

/// GPU busy percentage from the accelerator's `PerformanceStatistics` (public IOKit; spike 6).
final class GPUCollector {
    func sample() -> GPUSample? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString,
                                                           kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let utilisation = stats["Device Utilization %"] as? Int {
                return GPUSample(util: Double(min(100, max(0, utilisation))))
            }
        }
        return nil
    }
}
