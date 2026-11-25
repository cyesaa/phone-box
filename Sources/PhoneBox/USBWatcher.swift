import Foundation

/// Listens to usbmuxd for iPhones plugged in and out (design §4; spike 5). PhoneBox uses it to open the QR
/// window the first time a phone is plugged in and to move Wi-Fi clients over to the cable; access itself
/// depends on the client's interface (`USBLinks`).
@MainActor
final class USBWatcher {
    /// Called on the main thread with `true` when an iPhone was just plugged in.
    var onChange: ((_ pluggedIn: Bool) -> Void)?
    /// Called on the main thread when usbmuxd becomes reachable or goes away.
    var onAvailabilityChange: ((Bool) -> Void)?
    private(set) var isAvailable = false
    private(set) var attachedDevices: Set<Int> = []

    var hasIPhone: Bool { !attachedDevices.isEmpty }

    func start() {
        let thread = Thread { [weak self] in Self.run(watcher: self) }
        thread.name = "PhoneBox usbmuxd"
        thread.start()
    }

    private func handle(_ message: [String: Any]) {
        let deviceID = message["DeviceID"] as? Int ?? -1
        switch message["MessageType"] as? String {
        case "Attached":
            let properties = message["Properties"] as? [String: Any] ?? [:]
            guard properties["ConnectionType"] as? String == "USB" else { return }
            attachedDevices.insert(deviceID)
            onChange?(true)
        case "Detached":
            guard attachedDevices.remove(deviceID) != nil else { return }
            onChange?(false)
        default:
            break
        }
    }

    private func setAvailable(_ available: Bool) {
        let changed = isAvailable != available
        isAvailable = available
        if !available, !attachedDevices.isEmpty {
            attachedDevices.removeAll()
            onChange?(false)
        }
        if changed { onAvailabilityChange?(available) }
    }

    // MARK: usbmuxd, on a background thread

    private nonisolated static func run(watcher: USBWatcher?) {
        while true {
            let fd = connect()
            if fd >= 0 {
                send(fd, ["MessageType": "Listen", "ClientVersionString": "PhoneBox", "ProgName": "PhoneBox"])
                DispatchQueue.main.async { MainActor.assumeIsolated { watcher?.setAvailable(true) } }
                while let message = read(fd) {
                    DispatchQueue.main.async { MainActor.assumeIsolated { watcher?.handle(message) } }
                }
                close(fd)
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { watcher?.setAvailable(false) } }
            Thread.sleep(forTimeInterval: 5)
        }
    }

    private nonisolated static func connect() -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array("/var/run/usbmuxd".utf8) + [0]
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            close(fd)
            return -1
        }
        return fd
    }

    /// 16-byte little-endian header (length, version 1, message 8 = plist, tag) + XML plist.
    private nonisolated static func send(_ fd: Int32, _ message: [String: Any]) {
        guard let body = try? PropertyListSerialization.data(fromPropertyList: message, format: .xml, options: 0) else { return }
        var packet = Data()
        for value in [UInt32(16 + body.count), 1, 8, 1] {
            withUnsafeBytes(of: value.littleEndian) { packet.append(contentsOf: $0) }
        }
        packet.append(body)
        _ = packet.withUnsafeBytes { write(fd, $0.baseAddress, packet.count) }
    }

    private nonisolated static func read(_ fd: Int32) -> [String: Any]? {
        guard let header = readExactly(fd, 16) else { return nil }
        let length = Int(UInt32(littleEndian: header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
        guard length >= 16, length < 1 << 20, let body = readExactly(fd, length - 16) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: body, format: nil)) as? [String: Any] ?? [:]
    }

    private nonisolated static func readExactly(_ fd: Int32, _ count: Int) -> Data? {
        var data = Data(count: count)
        var received = 0
        while received < count {
            let n = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress! + received, count - received) }
            if n <= 0 { return nil }
            received += n
        }
        return data
    }
}
