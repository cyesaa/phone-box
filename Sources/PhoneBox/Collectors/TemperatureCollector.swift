import Foundation
import PhoneBoxCore

/// Chip temperature from the HID temperature sensors (`IOHIDEventSystemClient`, private; spike 6).
///
/// Every sensor read is a call into the HID system, and reading all 44 sensors each second cost about 3 % CPU on an
/// M4. So it reads only the chip sensors, every 5 seconds (temperature changes slowly), and looks the sensor list up
/// again once a minute.
final class TemperatureCollector {
    private typealias ClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias ClientSetMatching = @convention(c) (CFTypeRef, CFDictionary) -> Int32
    private typealias ClientCopyServices = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias ServiceCopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias ServiceCopyEvent = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias EventGetFloatValue = @convention(c) (CFTypeRef, Int32) -> Double

    static let readInterval: TimeInterval = 5
    static let sensorListInterval: TimeInterval = 60
    private static let temperatureEvent: Int64 = 15  // kIOHIDEventTypeTemperature

    private let copyServices: ClientCopyServices?
    private let copyProperty: ServiceCopyProperty?
    private let copyEvent: ServiceCopyEvent?
    private let floatValue: EventGetFloatValue?
    private let client: CFTypeRef?
    private var sensors: [(name: String, service: CFTypeRef)] = []
    private var sensorsTime: TimeInterval = -.infinity
    private var last: TemperatureSample?
    private var lastTime: TimeInterval = -.infinity

    init() {
        let library = PrivateSymbols.iokit
        let create = PrivateSymbols.function(library, "IOHIDEventSystemClientCreate", as: ClientCreate.self)
        let setMatching = PrivateSymbols.function(library, "IOHIDEventSystemClientSetMatching", as: ClientSetMatching.self)
        copyServices = PrivateSymbols.function(library, "IOHIDEventSystemClientCopyServices", as: ClientCopyServices.self)
        copyProperty = PrivateSymbols.function(library, "IOHIDServiceClientCopyProperty", as: ServiceCopyProperty.self)
        copyEvent = PrivateSymbols.function(library, "IOHIDServiceClientCopyEvent", as: ServiceCopyEvent.self)
        floatValue = PrivateSymbols.function(library, "IOHIDEventGetFloatValue", as: EventGetFloatValue.self)
        client = create?(kCFAllocatorDefault)?.takeRetainedValue()
        if let client, let setMatching {
            _ = setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        }
    }

    /// The last summary, read again at most every `readInterval`.
    func sample() -> TemperatureSample? {
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
        guard now - lastTime >= Self.readInterval else { return last }
        lastTime = now
        if now - sensorsTime >= Self.sensorListInterval || sensors.isEmpty {
            sensors = chipSensors()
            sensorsTime = now
        }
        guard let copyEvent, let floatValue else { return nil }
        var readings: [(name: String, celsius: Double)] = []
        for sensor in sensors {
            guard let event = copyEvent(sensor.service, Self.temperatureEvent, 0, 0)?.takeRetainedValue(),
                  let celsius = floatValue(event, Int32(Self.temperatureEvent << 16)).finiteOrNil
            else { continue }
            readings.append((sensor.name, celsius))
        }
        last = Temperatures.summary(readings)
        return last
    }

    private func chipSensors() -> [(name: String, service: CFTypeRef)] {
        guard let client, let copyServices, let copyProperty,
              let services = copyServices(client)?.takeRetainedValue() as? [CFTypeRef]
        else { return [] }
        let named = services.compactMap { service -> (name: String, service: CFTypeRef)? in
            guard let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String else { return nil }
            return (name, service)
        }
        let chosen = Temperatures.chipSensors(named.map(\.name))
        return named.filter { chosen.contains($0.name) }
    }
}
