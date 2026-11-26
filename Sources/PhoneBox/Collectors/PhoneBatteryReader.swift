import Foundation
import PhoneBoxCore

/// An iPhone as MobileDevice hands it out (`am_device *`).
struct DeviceRef: @unchecked Sendable, Equatable {
    let pointer: UnsafeMutableRawPointer
}

/// The few functions of the private MobileDevice framework that reading a phone's battery needs (2026-11-26:
/// works without root on macOS 27; the phone only has to trust this Mac). Nil if the framework or a function is
/// missing.
struct MobileDeviceAPI: @unchecked Sendable {
    typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    typealias Subscribe = @convention(c) (Callback, UInt32, UInt32, UnsafeMutableRawPointer?,
                                          UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    typealias Unsubscribe = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias Retain = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
    typealias Release = @convention(c) (UnsafeMutableRawPointer) -> Void
    typealias Call = @convention(c) (UnsafeMutableRawPointer) -> Int32
    typealias CopyValue = @convention(c) (UnsafeMutableRawPointer, CFString?, CFString?) -> Unmanaged<CFTypeRef>?

    /// `msg` values of `am_device_notification_callback_info`.
    static let connected: UInt32 = 1
    static let disconnected: UInt32 = 2
    /// `AMDeviceGetInterfaceType`: 1 is USB, 2 is the network (Wi-Fi sync).
    static let usb: Int32 = 1

    let subscribe: Subscribe
    let unsubscribe: Unsubscribe
    let retain: Retain
    let release: Release
    let interfaceType: Call
    let connect: Call
    let disconnect: Call
    let validatePairing: Call
    let startSession: Call
    let stopSession: Call
    let copyValue: CopyValue

    /// Loaded on first use (the framework is not opened at launch); nil if it is missing.
    static let shared = load()

    static func load() -> MobileDeviceAPI? {
        let library = PrivateSymbols.mobileDevice
        func function<T>(_ name: String, _ type: T.Type) -> T? { PrivateSymbols.function(library, name, as: type) }
        guard let subscribe = function("AMDeviceNotificationSubscribe", Subscribe.self),
              let unsubscribe = function("AMDeviceNotificationUnsubscribe", Unsubscribe.self),
              let retain = function("AMDeviceRetain", Retain.self),
              let release = function("AMDeviceRelease", Release.self),
              let interfaceType = function("AMDeviceGetInterfaceType", Call.self),
              let connect = function("AMDeviceConnect", Call.self),
              let disconnect = function("AMDeviceDisconnect", Call.self),
              let validatePairing = function("AMDeviceValidatePairing", Call.self),
              let startSession = function("AMDeviceStartSession", Call.self),
              let stopSession = function("AMDeviceStopSession", Call.self),
              let copyValue = function("AMDeviceCopyValue", CopyValue.self)
        else { return nil }
        return MobileDeviceAPI(subscribe: subscribe, unsubscribe: unsubscribe, retain: retain, release: release,
                               interfaceType: interfaceType, connect: connect, disconnect: disconnect,
                               validatePairing: validatePairing, startSession: startSession, stopSession: stopSession,
                               copyValue: copyValue)
    }

    /// Connects, starts a session, reads the battery values and closes again (~150 ms). Blocks: call it off the
    /// main thread.
    func readBattery(_ device: DeviceRef) -> PhoneBatterySample? {
        let pointer = device.pointer
        guard connect(pointer) == 0 else { return nil }
        defer { _ = disconnect(pointer) }
        guard validatePairing(pointer) == 0, startSession(pointer) == 0 else { return nil }
        defer { _ = stopSession(pointer) }
        func value(_ key: String) -> Any? {
            copyValue(pointer, "com.apple.mobile.battery" as CFString, key as CFString)?.takeRetainedValue()
        }
        return PhoneBatteryInfo.sample(capacity: value("BatteryCurrentCapacity"), charging: value("BatteryIsCharging"),
                                       external: value("ExternalConnected"))
    }
}

/// Reads the battery of the iPhone plugged in over USB (design §6 `phone`): a moment after it is plugged in and
/// then once a minute, only between `start()` and `stop()` (while the sampler runs). A failed read (the phone still
/// waking, or asking whether to trust this Mac) is tried again after 10 s, up to 3 times. Reads run on their own
/// queue, one at a time, so they never hold up a snapshot. With two iPhones plugged in there is no "the" phone and
/// `latest` is nil; unplugging one reads the other.
@MainActor
final class PhoneBatteryReader {
    static let interval: TimeInterval = 60
    /// The phone needs a moment after usbmuxd reports it before it answers.
    static let settleDelay: TimeInterval = 2
    static let retryDelay: TimeInterval = 10
    static let maxRetries = 3

    private var api: MobileDeviceAPI? { MobileDeviceAPI.shared }
    private let queue = DispatchQueue(label: "com.phonebox.PhoneBox.phone-battery", qos: .utility)
    private var subscription: UnsafeMutableRawPointer?
    private var devices: [DeviceRef] = []
    private var memory = PhoneBatteryMemory()
    private var timer: Timer?
    private var reading = false
    /// Failed reads in a row since the last good one or the last plug-in.
    private var retries = 0
    /// True while `subscribe` runs: phones already plugged in may be reported before it returns.
    private var subscribing = false

    /// The last good reading of the one iPhone on USB, at most 5 minutes old.
    var latest: PhoneBatterySample? { memory.current(at: Date()) }

    func start() {
        guard let api, subscription == nil else { return }
        // Called on the main thread, which is where MobileDevice delivers its notifications; phones already plugged
        // in are reported right away.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: MobileDeviceAPI.Callback = { info, context in
            guard let info, let context else { return }
            // struct am_device_notification_callback_info { am_device *dev; unsigned int msg; }
            let device = DeviceRef(pointer: info.load(as: UnsafeMutableRawPointer.self))
            let message = info.load(fromByteOffset: MemoryLayout<UnsafeMutableRawPointer>.size, as: UInt32.self)
            let reader = Unmanaged<PhoneBatteryReader>.fromOpaque(context).takeUnretainedValue()
            if Thread.isMainThread {
                MainActor.assumeIsolated { reader.deviceChanged(device, message: message) }
                return
            }
            // Not the main thread after all: keep the device alive until the main thread has seen it.
            guard let api = MobileDeviceAPI.shared else { return }
            _ = api.retain(device.pointer)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { reader.deviceChanged(device, message: message) }
                api.release(device.pointer)
            }
        }
        var subscription: UnsafeMutableRawPointer?
        subscribing = true
        defer { subscribing = false }
        guard api.subscribe(callback, 0, 0, context, &subscription) == 0 else {
            Log.app.notice("Cannot watch iPhones for their battery")
            return
        }
        self.subscription = subscription
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        guard let api, let subscription else { return }
        _ = api.unsubscribe(subscription)
        self.subscription = nil
        for device in devices { api.release(device.pointer) }
        devices.removeAll()
        memory.forget()
    }

    private func deviceChanged(_ device: DeviceRef, message: UInt32) {
        guard let api, subscription != nil || subscribing else { return }
        switch message {
        case MobileDeviceAPI.connected where api.interfaceType(device.pointer) == MobileDeviceAPI.usb:
            guard !devices.contains(device) else { return }
            _ = api.retain(device.pointer)
            devices.append(device)
            memory.forget()
            retries = 0
            read(after: Self.settleDelay)
        case MobileDeviceAPI.disconnected:
            guard let index = devices.firstIndex(of: device) else { return }
            api.release(devices.remove(at: index).pointer)
            memory.forget()
            // Two phones were plugged in and one is left: it is "the" phone now.
            if devices.count == 1 {
                retries = 0
                read(after: Self.settleDelay)
            }
        default:
            break
        }
    }

    private func read(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.read() }
        }
    }

    private func read() {
        guard let api, devices.count == 1, let device = devices.first, !reading else { return }
        reading = true
        _ = api.retain(device.pointer)
        queue.async { [weak self] in
            let sample = api.readBattery(device)
            api.release(device.pointer)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.finished(device, sample) }
            }
        }
    }

    private func finished(_ device: DeviceRef, _ sample: PhoneBatterySample?) {
        reading = false
        // The phone may have been unplugged, or another one plugged in, while it was read.
        guard subscription != nil, devices == [device] else { return }
        guard let sample else {
            guard retries < Self.maxRetries else { return }
            retries += 1
            read(after: Self.retryDelay)
            return
        }
        retries = 0
        memory.remember(sample, at: Date())
    }
}
