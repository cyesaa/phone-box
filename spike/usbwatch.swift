// Spike 5: does usbmuxd tell us when an iPhone is plugged in or out, without Xcode?
// Run: swift spike/usbwatch.swift      (stop with Ctrl-C)
import Foundation

let socketPath = "/var/run/usbmuxd"

func stamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f.string(from: Date())
}

func connectToUsbmuxd() -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { fatalError("socket() failed: errno \(errno)") }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let path = Array(socketPath.utf8) + [0]
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: path) }
    let result = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else { fatalError("connect(\(socketPath)) failed: errno \(errno)") }
    return fd
}

/// usbmuxd packet: 16-byte little-endian header (length, version 1, message 8 = plist, tag) + XML plist.
func sendPlist(_ fd: Int32, _ message: [String: Any], tag: UInt32) {
    let body = try! PropertyListSerialization.data(fromPropertyList: message, format: .xml, options: 0)
    var packet = Data()
    for value in [UInt32(16 + body.count), 1, 8, tag] {
        withUnsafeBytes(of: value.littleEndian) { packet.append(contentsOf: $0) }
    }
    packet.append(body)
    _ = packet.withUnsafeBytes { write(fd, $0.baseAddress, packet.count) }
}

func readExactly(_ fd: Int32, _ count: Int) -> Data? {
    var data = Data(count: count)
    var received = 0
    while received < count {
        let n = data.withUnsafeMutableBytes { read(fd, $0.baseAddress! + received, count - received) }
        if n <= 0 { return nil }
        received += n
    }
    return data
}

func readPlist(_ fd: Int32) -> [String: Any]? {
    guard let header = readExactly(fd, 16) else { return nil }
    let length = Int(UInt32(littleEndian: header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
    guard length >= 16, let body = readExactly(fd, length - 16) else { return nil }
    return (try? PropertyListSerialization.propertyList(from: body, format: nil)) as? [String: Any]
}

setvbuf(stdout, nil, _IOLBF, 0)
let fd = connectToUsbmuxd()
sendPlist(fd, ["MessageType": "Listen", "ClientVersionString": "phonebox-spike", "ProgName": "phonebox-spike"], tag: 1)
print("\(stamp()) listening on \(socketPath): plug an iPhone in and out")

var connectionTypes: [Int: String] = [:]
while let message = readPlist(fd) {
    let deviceID = message["DeviceID"] as? Int ?? -1
    switch message["MessageType"] as? String {
    case "Result":
        print("\(stamp()) Listen result: \(message["Number"] ?? "?") (0 means OK)")
    case "Attached":
        let properties = message["Properties"] as? [String: Any] ?? [:]
        let type = properties["ConnectionType"] as? String ?? "?"
        let serial = properties["SerialNumber"] as? String ?? "?"
        connectionTypes[deviceID] = type
        print("\(stamp()) ATTACHED id=\(deviceID) type=\(type) product=\(properties["ProductID"] ?? "?") serial=\(serial.prefix(8))…")
    case "Detached":
        print("\(stamp()) DETACHED id=\(deviceID) type=\(connectionTypes.removeValue(forKey: deviceID) ?? "?")")
    default:
        print("\(stamp()) other message: \(message)")
    }
}
print("\(stamp()) usbmuxd closed the connection")
