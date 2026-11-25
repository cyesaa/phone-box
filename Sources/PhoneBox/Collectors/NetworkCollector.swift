import Darwin
import Foundation
import PhoneBoxCore
import SystemConfiguration

/// Download and upload speed of the primary network interface. Uses the interface MIB
/// (`net.link.generic.ifdata.<index>.general`), whose byte counters are full 64-bit values like `netstat -ib` shows;
/// on current macOS both `getifaddrs` and `sysctl(NET_RT_IFLIST2)` return only the low 32 bits (they wrap every 4 GiB).
final class NetworkCollector {
    static let primaryInterfaceInterval: TimeInterval = 10
    private var interface: String?
    private var primaryName: String?
    private var primaryTime: UInt64 = 0
    private var received = CounterRate()
    private var sent = CounterRate()

    func reset() {
        received.reset()
        sent.reset()
    }

    func sample() -> NetworkSample? {
        let tick = DispatchTime.now().uptimeNanoseconds
        // Only a found interface is kept for the interval; a failed lookup is retried next second.
        if primaryName == nil || Double(tick &- primaryTime) / 1e9 >= Self.primaryInterfaceInterval {
            primaryName = Self.primaryInterface()
            primaryTime = tick
        }
        guard let name = primaryName else { return nil }
        guard let counters = Self.counters(for: name) else {
            primaryName = nil  // e.g. the adapter was unplugged: look the primary interface up again next second
            return nil
        }
        if name != interface {
            interface = name
            reset()
        }
        let now = Double(tick) / 1e9
        // Both counters must be read before the guard, or the first reading would leave `sent` unprimed.
        let rx = received.rate(value: counters.rx, at: now)
        let tx = sent.rate(value: counters.tx, at: now)
        guard let rx, let tx else { return nil }
        return NetworkSample(rx: rx, tx: tx, iface: name)
    }

    /// The interface macOS uses for the default route, e.g. `en0` (Wi-Fi).
    static func primaryInterface() -> String? {
        for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
            let global = SCDynamicStoreCopyValue(nil, key as CFString) as? [String: Any]
            if let name = global?["PrimaryInterface"] as? String { return name }
        }
        return nil
    }

    static func counters(for name: String) -> (rx: UInt64, tx: UInt64)? {
        let index = if_nametoindex(name)
        guard index != 0, index <= UInt32(Int32.max) else { return nil }
        var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, Int32(index), IFDATA_GENERAL]
        var data = ifmibdata()
        var length = MemoryLayout<ifmibdata>.size
        guard sysctl(&mib, 6, &data, &length, nil, 0) == 0, length == MemoryLayout<ifmibdata>.size else { return nil }
        return (data.ifmd_data.ifi_ibytes, data.ifmd_data.ifi_obytes)
    }
}
