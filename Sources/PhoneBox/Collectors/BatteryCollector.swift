import IOKit.ps
import PhoneBoxCore

/// The internal battery from the power sources API; nil on Macs without one.
final class BatteryCollector {
    /// True on a Mac with an internal battery, even when its values cannot be read right now: decides whether the
    /// power figure is the whole Mac's or only the GPU's (design §6).
    static func hasInternalBattery() -> Bool {
        internalBattery() != nil
    }

    func sample() -> BatterySample? {
        Self.internalBattery().flatMap(BatteryInfo.sample)
    }

    /// The internal battery's description from `IOPSGetPowerSourceDescription`; nil without one.
    private static func internalBattery() -> [String: Any]? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
               description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                return description
            }
        }
        return nil
    }
}
