// Spike 6: can we read temperatures, power and GPU use without sudo on Apple silicon?
// Run: swift spike/sensors.swift
import Foundation
import IOKit

func symbol<T>(_ library: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T {
    guard let pointer = dlsym(library, name) else { fatalError("missing symbol \(name)") }
    return unsafeBitCast(pointer, to: type)
}

// MARK: Temperatures: IOHIDEventSystemClient (private API in IOKit)

let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
let hidClientCreate = symbol(iokit, "IOHIDEventSystemClientCreate",
                             as: (@convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?).self)
let hidClientSetMatching = symbol(iokit, "IOHIDEventSystemClientSetMatching",
                                  as: (@convention(c) (CFTypeRef, CFDictionary) -> Int32).self)
let hidClientCopyServices = symbol(iokit, "IOHIDEventSystemClientCopyServices",
                                   as: (@convention(c) (CFTypeRef) -> Unmanaged<CFArray>?).self)
let hidServiceCopyProperty = symbol(iokit, "IOHIDServiceClientCopyProperty",
                                    as: (@convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?).self)
let hidServiceCopyEvent = symbol(iokit, "IOHIDServiceClientCopyEvent",
                                 as: (@convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?).self)
let hidEventGetFloatValue = symbol(iokit, "IOHIDEventGetFloatValue",
                                   as: (@convention(c) (CFTypeRef, Int32) -> Double).self)

let temperatureEventType: Int64 = 15  // kIOHIDEventTypeTemperature

func readTemperatures() -> [(name: String, celsius: Double)] {
    guard let client = hidClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { return [] }
    let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
    _ = hidClientSetMatching(client, matching)
    guard let services = hidClientCopyServices(client)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
    var readings: [(name: String, celsius: Double)] = []
    for service in services {
        let name = hidServiceCopyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String ?? "?"
        guard let event = hidServiceCopyEvent(service, temperatureEventType, 0, 0)?.takeRetainedValue() else { continue }
        let celsius = hidEventGetFloatValue(event, Int32(temperatureEventType << 16))
        if celsius > 0 && celsius < 150 { readings.append((name, celsius)) }
    }
    return readings.sorted { $0.name < $1.name }
}

// MARK: Power: IOReport "Energy Model" channels (private library)

let ioReport = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW)
let reportCopyChannelsInGroup = symbol(ioReport, "IOReportCopyChannelsInGroup",
    as: (@convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?).self)
let reportCreateSubscription = symbol(ioReport, "IOReportCreateSubscription",
    as: (@convention(c) (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>,
                         UInt64, CFTypeRef?) -> Unmanaged<CFTypeRef>?).self)
let reportCreateSamples = symbol(ioReport, "IOReportCreateSamples",
    as: (@convention(c) (CFTypeRef, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?).self)
let reportCreateSamplesDelta = symbol(ioReport, "IOReportCreateSamplesDelta",
    as: (@convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?).self)
let reportChannelGetChannelName = symbol(ioReport, "IOReportChannelGetChannelName",
    as: (@convention(c) (CFDictionary) -> Unmanaged<CFString>?).self)
let reportChannelGetUnitLabel = symbol(ioReport, "IOReportChannelGetUnitLabel",
    as: (@convention(c) (CFDictionary) -> Unmanaged<CFString>?).self)
let reportSimpleGetIntegerValue = symbol(ioReport, "IOReportSimpleGetIntegerValue",
    as: (@convention(c) (CFDictionary, Int32) -> Int64).self)

func readPower(over interval: TimeInterval) -> [(name: String, watts: Double)] {
    guard let channels = reportCopyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue(),
          let mutableChannels = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, CFDictionaryGetCount(channels), channels)
    else { return [] }
    var subscribed: Unmanaged<CFMutableDictionary>?
    guard let subscription = reportCreateSubscription(nil, mutableChannels, &subscribed, 0, nil)?.takeRetainedValue(),
          let subscribedChannels = subscribed?.takeUnretainedValue(),
          let first = reportCreateSamples(subscription, subscribedChannels, nil)?.takeRetainedValue()
    else { return [] }
    Thread.sleep(forTimeInterval: interval)
    guard let second = reportCreateSamples(subscription, subscribedChannels, nil)?.takeRetainedValue(),
          let delta = reportCreateSamplesDelta(first, second, nil)?.takeRetainedValue(),
          let items = (delta as NSDictionary)["IOReportChannels"] as? [NSDictionary]
    else { return [] }
    var readings: [(name: String, watts: Double)] = []
    for item in items {
        let channel = item as CFDictionary
        let name = reportChannelGetChannelName(channel)?.takeUnretainedValue() as String? ?? "?"
        let unit = (reportChannelGetUnitLabel(channel)?.takeUnretainedValue() as String? ?? "")
            .trimmingCharacters(in: .whitespaces)
        let value = Double(reportSimpleGetIntegerValue(channel, 0))
        let divisor: Double
        switch unit {
        case "mJ": divisor = 1e3
        case "uJ", "µJ": divisor = 1e6
        case "nJ": divisor = 1e9
        default: continue
        }
        let watts = value / divisor / interval
        if watts > 0.001 { readings.append((name, watts)) }
    }
    return readings
}

// MARK: Total system power (MacBook only): AppleSmartBattery telemetry, public IOKit

func readSystemPowerWatts() -> Double? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    guard let telemetry = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString,
                                                         kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
          let milliwatts = telemetry["SystemPowerIn"] as? Int
    else { return nil }
    return Double(milliwatts) / 1000
}

// MARK: GPU utilisation: IOAccelerator "PerformanceStatistics", public IOKit

func readGPUUtilisation() -> Int? {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
    else { return nil }
    defer { IOObjectRelease(iterator) }
    while case let service = IOIteratorNext(iterator), service != 0 {
        defer { IOObjectRelease(service) }
        if let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString,
                                                       kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
           let utilisation = stats["Device Utilization %"] as? Int {
            return utilisation
        }
    }
    return nil
}

// MARK: Report

let temperatures = readTemperatures()
print("Temperatures: \(temperatures.count) sensors")
for t in temperatures { print(String(format: "  %-24@ %6.1f °C", t.name as NSString, t.celsius)) }

let power = readPower(over: 1)
print("Power (Energy Model, over 1 s): \(power.count) channels")
for p in power.sorted(by: { $0.watts > $1.watts }).prefix(15) {
    print(String(format: "  %-24@ %7.3f W", p.name as NSString, p.watts))
}
for wanted in ["CPU Energy", "GPU Energy"] {
    let found = power.first { $0.name == wanted }
    print("  -> \(wanted): \(found.map { String(format: "%.3f W", $0.watts) } ?? "not found")")
}
let ane = power.filter { $0.name.hasPrefix("ANE") }.reduce(0) { $0 + $1.watts }
print(String(format: "  -> ANE (sum of ANE* channels): %.3f W", ane))

print("System power (battery telemetry): \(readSystemPowerWatts().map { String(format: "%.2f W", $0) } ?? "not available")")
print("GPU utilisation: \(readGPUUtilisation().map { "\($0) %" } ?? "not available")")
