import IOKit.ps
import PhoneBoxCore

/// The internal battery from the power sources API; nil on Macs without one.
final class BatteryCollector {
    /// True on a Mac with an internal battery, even when its values cannot be read right now: decides whether the
    /// power figure is the whole Mac's or only the GPU's (design §6).
    static func hasInternalBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }
        return sources.contains { source in
            let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            return description?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }

    func sample() -> BatterySample? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
               let sample = BatteryInfo.sample(from: description) {
                return sample
            }
        }
        return nil
    }
}
