import IOKit.ps
import PhoneBoxCore

/// The internal battery from the power sources API; nil on Macs without one.
final class BatteryCollector {
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
