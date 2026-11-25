import Darwin
import Foundation
import PhoneBoxCore
import SystemConfiguration

/// Download and upload speed of the primary network interface. Uses the 64-bit counters from
/// `sysctl(NET_RT_IFLIST2)`; the 32-bit ones in `getifaddrs` wrap every 4 GB.
final class NetworkCollector {
    private var interface: String?
    private var received = CounterRate()
    private var sent = CounterRate()

    func reset() {
        received.reset()
        sent.reset()
    }

    func sample() -> NetworkSample? {
        guard let name = Self.primaryInterface(), let counters = Self.counters(for: name) else { return nil }
        if name != interface {
            interface = name
            reset()
        }
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
        guard let rx = received.rate(value: counters.rx, at: now), let tx = sent.rate(value: counters.tx, at: now)
        else { return nil }
        return NetworkSample(rx: rx, tx: tx, iface: name)
    }

    /// The interface macOS uses for the default route, e.g. `en0` (Wi-Fi).
    static func primaryInterface() -> String? {
        let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        return global?["PrimaryInterface"] as? String
    }

    static func counters(for name: String) -> (rx: UInt64, tx: UInt64)? {
        let index = if_nametoindex(name)
        guard index != 0 else { return nil }
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return nil }
        return buffer.withUnsafeBytes { raw -> (rx: UInt64, tx: UInt64)? in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { return nil }
                if Int32(header.ifm_type) == RTM_IFINFO2, header.ifm_index == UInt16(index),
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    return (message.ifm_data.ifi_ibytes, message.ifm_data.ifi_obytes)
                }
                offset += Int(header.ifm_msglen)
            }
            return nil
        }
    }
}
