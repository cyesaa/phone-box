/// Finds which network interface owns a local address, so a connection's interface is known exactly
/// instead of guessed (a guess could count a Wi-Fi client as being on the USB cable).
public enum InterfaceAddress {
    /// The name of the first interface whose address matches `address` byte for byte; nil when none does.
    public static func owner(of address: [UInt8], among interfaces: [(name: String, address: [UInt8])]) -> String? {
        guard !address.isEmpty else { return nil }
        return interfaces.first { $0.address == address }?.name
    }
}
