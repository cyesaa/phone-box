import Foundation

/// The battery of the iPhone plugged into the Mac (design §6 `phone`). Safari gives a page no battery information,
/// so the Mac reads it over USB.
public struct PhoneBatterySample: Equatable, Codable, Sendable {
    public var percent: Int
    public var charging: Bool
    /// On a power source; on the Mac's cable this is normally true.
    public var plugged: Bool
    public init(percent: Int, charging: Bool, plugged: Bool) {
        self.percent = percent
        self.charging = charging
        self.plugged = plugged
    }
}

public enum PhoneBatteryInfo {
    /// From the phone's `com.apple.mobile.battery` values: `BatteryCurrentCapacity` (a number, 0…100),
    /// `BatteryIsCharging` and `ExternalConnected` (booleans). Nil without a usable capacity.
    public static func sample(capacity: Any?, charging: Any?, external: Any?) -> PhoneBatterySample? {
        guard let percent = JSONValue.integer(capacity), (0...100).contains(percent) else { return nil }
        return PhoneBatterySample(percent: percent, charging: JSONValue.bool(charging) ?? false,
                                  plugged: JSONValue.bool(external) ?? false)
    }
}

/// Keeps the last good reading for a while, so one failed read (the phone busy, or locked) does not make the
/// page's battery icon blink.
public struct PhoneBatteryMemory: Sendable {
    /// A reading older than this is dropped and the page hides the icon.
    public static let keepFor: TimeInterval = 300
    private var last: PhoneBatterySample?
    private var readAt = Date.distantPast

    public init() {}

    public mutating func remember(_ sample: PhoneBatterySample, at date: Date) {
        last = sample
        readAt = date
    }

    /// The phone was unplugged, or a second one was plugged in: the reading no longer belongs to "the" phone.
    public mutating func forget() {
        last = nil
    }

    public func current(at date: Date) -> PhoneBatterySample? {
        date.timeIntervalSince(readAt) <= Self.keepFor ? last : nil
    }
}
