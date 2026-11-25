import Testing
@testable import PhoneBoxCore

struct InterfaceAddressTests {
    private let wifi: [UInt8] = [192, 168, 1, 20]
    private let usb: [UInt8] = [169, 254, 10, 2]
    private let v6: [UInt8] = [0xfe, 0x80, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8]

    @Test func matchesAnIPv4Address() {
        let interfaces = [(name: "en0", address: wifi), (name: "en8", address: usb)]
        #expect(InterfaceAddress.owner(of: usb, among: interfaces) == "en8")
        #expect(InterfaceAddress.owner(of: wifi, among: interfaces) == "en0")
    }

    @Test func matchesAnIPv6Address() {
        let interfaces = [(name: "en0", address: wifi), (name: "en8", address: v6)]
        #expect(InterfaceAddress.owner(of: v6, among: interfaces) == "en8")
    }

    @Test func returnsNilWithoutAMatch() {
        let interfaces = [(name: "en0", address: wifi)]
        #expect(InterfaceAddress.owner(of: usb, among: interfaces) == nil)
        #expect(InterfaceAddress.owner(of: [], among: interfaces) == nil)
        #expect(InterfaceAddress.owner(of: wifi, among: []) == nil)
    }

    @Test func firstInterfaceWinsForASharedAddress() {
        let interfaces = [(name: "en3", address: usb), (name: "en8", address: usb)]
        #expect(InterfaceAddress.owner(of: usb, among: interfaces) == "en3")
    }

    @Test func differentLengthsNeverMatch() {
        let interfaces = [(name: "en0", address: [UInt8](wifi.prefix(2))), (name: "en1", address: wifi + [0])]
        #expect(InterfaceAddress.owner(of: wifi, among: interfaces) == nil)
    }
}
