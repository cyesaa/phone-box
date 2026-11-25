import Foundation
import IOKit
import PhoneBoxCore

/// GPU watts from IOReport's "GPU Energy" counter (private) and whole-Mac watts from the battery telemetry (public).
/// CPU and Neural Engine counters do not move without root on Apple silicon (spike 6), so they are not read.
final class PowerCollector {
    private typealias CopyChannelsInGroup = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias CreateSubscription = @convention(c) (UnsafeRawPointer?, CFMutableDictionary,
        UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?) -> Unmanaged<CFTypeRef>?
    private typealias CreateSamples = @convention(c) (CFTypeRef, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateSamplesDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias ChannelString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias SimpleIntegerValue = @convention(c) (CFDictionary, Int32) -> Int64

    private let createSamples: CreateSamples?
    private let createDelta: CreateSamplesDelta?
    private let channelName: ChannelString?
    private let unitLabel: ChannelString?
    private let integerValue: SimpleIntegerValue?
    private var subscription: CFTypeRef?
    private var subscribedChannels: CFMutableDictionary?
    private var previous: (sample: CFDictionary, time: UInt64)?

    init() {
        let library = PrivateSymbols.ioReport
        createSamples = PrivateSymbols.function(library, "IOReportCreateSamples", as: CreateSamples.self)
        createDelta = PrivateSymbols.function(library, "IOReportCreateSamplesDelta", as: CreateSamplesDelta.self)
        channelName = PrivateSymbols.function(library, "IOReportChannelGetChannelName", as: ChannelString.self)
        unitLabel = PrivateSymbols.function(library, "IOReportChannelGetUnitLabel", as: ChannelString.self)
        integerValue = PrivateSymbols.function(library, "IOReportSimpleGetIntegerValue", as: SimpleIntegerValue.self)
        guard let copyChannels = PrivateSymbols.function(library, "IOReportCopyChannelsInGroup", as: CopyChannelsInGroup.self),
              let subscribe = PrivateSymbols.function(library, "IOReportCreateSubscription", as: CreateSubscription.self),
              let channels = copyChannels("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue(),
              let mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, CFDictionaryGetCount(channels), channels)
        else { return }
        var subscribed: Unmanaged<CFMutableDictionary>?
        subscription = subscribe(nil, mutable, &subscribed, 0, nil)?.takeRetainedValue()
        subscribedChannels = subscribed?.takeUnretainedValue()
    }

    /// Forget the last reading, e.g. after the Mac wakes.
    func reset() {
        previous = nil
    }

    func sample() -> PowerSample? {
        let gpu = gpuWatts()
        let system = Self.systemWatts()
        guard gpu != nil || system != nil else { return nil }
        return PowerSample(gpu: gpu, system: system)
    }

    private func gpuWatts() -> Double? {
        guard let subscription, let subscribedChannels, let createSamples, let createDelta, let channelName, let unitLabel,
              let integerValue, let current = createSamples(subscription, subscribedChannels, nil)?.takeRetainedValue()
        else { return nil }
        let now = DispatchTime.now().uptimeNanoseconds
        defer { previous = (current, now) }
        guard let previous, now > previous.time,
              let delta = createDelta(previous.sample, current, nil)?.takeRetainedValue(),
              let items = (delta as NSDictionary)["IOReportChannels"] as? [NSDictionary]
        else { return nil }
        let seconds = Double(now - previous.time) / 1e9
        for item in items {
            let channel = item as CFDictionary
            guard channelName(channel)?.takeUnretainedValue() as String? == "GPU Energy",
                  let unit = unitLabel(channel)?.takeUnretainedValue() as String?
            else { continue }
            return EnergyRate.watts(energy: Double(integerValue(channel, 0)), unit: unit, seconds: seconds)
        }
        return nil
    }

    /// `AppleSmartBattery` → `PowerTelemetryData.SystemPowerIn` (milliwatts); nil on Macs without a battery.
    static func systemWatts() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let telemetry = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
              let milliwatts = telemetry["SystemPowerIn"] as? Int, milliwatts >= 0
        else { return nil }
        return (Double(milliwatts) / 10).rounded() / 100
    }
}
