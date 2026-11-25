import Foundation
import IOKit

/// Which network interfaces are an iPhone's USB link (design §4). When a trusted iPhone is plugged in, macOS
/// gets one or more USB NCM interfaces from it (`anri*`, `en*`; spike); a connection that arrives on one of
/// them can only come from that cable. Names change from one plug-in to the next, so this asks IOKit each time.
enum USBLinks {
    static let appleVendorID = 0x05AC

    /// BSD names of the Ethernet interfaces that sit on an Apple USB device named iPhone or iPad.
    static func iPhoneInterfaceNames() -> Set<String> {
        var names = Set<String>()
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOEthernetInterface"), &iterator)
                == KERN_SUCCESS
        else { return names }
        defer { IOObjectRelease(iterator) }
        while case let interface = IOIteratorNext(iterator), interface != 0 {
            defer { IOObjectRelease(interface) }
            guard let name = property(interface, "BSD Name") as? String else { continue }
            if isOnIPhone(interface) { names.insert(name) }
        }
        return names
    }

    private static func isOnIPhone(_ interface: io_registry_entry_t) -> Bool {
        var current = interface
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }
        for _ in 0..<12 {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { return false }
            IOObjectRelease(current)
            current = parent
            if IOObjectConformsTo(current, "IOUSBHostDevice") != 0 {
                let vendor = property(current, "idVendor") as? Int ?? 0
                let product = property(current, "USB Product Name") as? String ?? ""
                return vendor == appleVendorID && (product.contains("iPhone") || product.contains("iPad"))
            }
        }
        return false
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
