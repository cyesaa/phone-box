import Darwin
import Foundation
import Testing
@testable import PhoneBox
import PhoneBoxCore

/// A BSD TCP socket on every IPv4 address: port 0 lets the system pick a free port, `listening` holds the port the
/// way another app would.
final class BoundSocket {
    let descriptor: Int32
    let port: UInt16

    init?(port: UInt16, listening: Bool = false) {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_ANY)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, length) == 0 && (!listening || listen(descriptor, 1) == 0)
                    && getsockname(descriptor, $0, &length) == 0
            }
        }
        guard bound else {
            Darwin.close(descriptor)
            return nil
        }
        self.descriptor = descriptor
        self.port = UInt16(bigEndian: address.sin_port)
    }

    deinit { Darwin.close(descriptor) }

    /// A port nothing uses right now, other than `other`.
    static func freePort(other: UInt16 = 0) throws -> UInt16 {
        while true {
            let port = try #require(BoundSocket(port: 0)).port
            if port != other { return port }
        }
    }
}

/// Moving to another port (design §9 "Port dolu"): the old port keeps working until the new one does.
@MainActor
struct DashboardServerTests {
    let runner = FakeRunner()

    func makeServer(retryDelay: TimeInterval = 30,
                    usbInterfaces: @escaping () -> Set<String> = { [] }) -> DashboardServer {
        let hub = DashboardHub(mode: .cable, key: PairingKey.generate(), appName: "PhoneBox test", hostName: { "Test Mac" },
                               commands: runner, usbInterfaces: usbInterfaces)
        return DashboardServer(webDirectory: URL(fileURLWithPath: "/nonexistent"), hub: hub, retryDelay: retryDelay,
                               localHostName: { "Test-Mac" })
    }

    /// The first line of the answer to `request`, sent from 127.0.0.1.
    func statusLine(_ port: UInt16, _ request: String) async throws -> String {
        let client = try #require(TestClient(port: port))
        client.send(request)
        _ = try await client.read(until: { _ in client.ended })
        return String(decoding: client.received, as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
    }

    /// Waits until `server` reports `wanted`, for at most `seconds`.
    func reaches(_ server: DashboardServer, _ wanted: DashboardServer.State, within seconds: Double = 3) async throws -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if server.state == wanted { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return server.state == wanted
    }

    /// Starts `server` on `port` and waits for the listener's answer.
    func start(_ server: DashboardServer, port: UInt16) async -> DashboardServer.State {
        await withCheckedContinuation { continuation in
            server.onStateChange = { state in
                // start(port:) stops the server first.
                guard state != .stopped else { return }
                server.onStateChange = nil
                continuation.resume(returning: state)
            }
            server.start(port: port)
        }
    }

    func move(_ server: DashboardServer, to port: UInt16) async -> Bool {
        await withCheckedContinuation { continuation in
            server.move(to: port) { continuation.resume(returning: $0) }
        }
    }

    /// True once `port` can be bound again within `seconds` (a cancelled listener lets go of it a moment later).
    func becomesFree(_ port: UInt16, within seconds: Double = 3) async throws -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if BoundSocket(port: port) != nil { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    @Test func movesToAFreePortAndLetsGoOfTheOldOne() async throws {
        let server = makeServer()
        defer { server.stop() }
        let old = try BoundSocket.freePort()
        let new = try BoundSocket.freePort(other: old)
        #expect(await start(server, port: old) == .listening(old))
        #expect(BoundSocket(port: old) == nil)
        #expect(await move(server, to: new))
        #expect(server.state == .listening(new))
        #expect(try await becomesFree(old))
        #expect(BoundSocket(port: new) == nil)
    }

    @Test func staysOnTheOldPortWhenTheNewOneIsTaken() async throws {
        let server = makeServer()
        defer { server.stop() }
        let old = try BoundSocket.freePort()
        let taken = try #require(BoundSocket(port: try BoundSocket.freePort(other: old), listening: true))
        #expect(await start(server, port: old) == .listening(old))
        #expect(await !move(server, to: taken.port))
        #expect(server.state == .listening(old))
        #expect(BoundSocket(port: old) == nil)
    }

    /// Design §9: PhoneBox stays on the saved port at launch even when another program holds it, and takes it once it
    /// is free.
    @Test func triesTheSavedPortAgainUntilItIsFree() async throws {
        let server = makeServer(retryDelay: 0.2)
        defer { server.stop() }
        var holder = BoundSocket(port: try BoundSocket.freePort(), listening: true)
        let port = try #require(holder?.port)
        guard case .failed(port, _) = await start(server, port: port) else {
            Issue.record("a taken port should fail")
            return
        }
        try await Task.sleep(for: .milliseconds(500))
        #expect(server.state.isFailed)
        holder = nil
        #expect(try await reaches(server, .listening(port)))
    }

    /// "Change…" with the same port while it is in use runs the move to it.
    @Test func movesToTheSamePortOnceItIsFree() async throws {
        let server = makeServer()
        defer { server.stop() }
        var holder = BoundSocket(port: try BoundSocket.freePort(), listening: true)
        let port = try #require(holder?.port)
        #expect(await start(server, port: port).isFailed)
        #expect(await !move(server, to: port))
        holder = nil
        #expect(await move(server, to: port))
        #expect(server.state == .listening(port))
    }

    /// Design §5: a page elsewhere whose name points at the Mac (DNS rebinding) is refused, files and WebSocket alike.
    @Test func answersOnlyRequestsThatNameThisMac() async throws {
        let server = makeServer()
        defer { server.stop() }
        let port = try BoundSocket.freePort()
        #expect(await start(server, port: port) == .listening(port))
        // There are no files (`/nonexistent`), so a request that gets through is a 404.
        #expect(try await statusLine(port, "GET / HTTP/1.1\r\nHost: test-mac.local:\(port)\r\n\r\n") == "HTTP/1.1 404 Not Found")
        #expect(try await statusLine(port, "GET / HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n") == "HTTP/1.1 404 Not Found")
        #expect(try await statusLine(port, "GET / HTTP/1.1\r\nHost: evil.example:\(port)\r\n\r\n") == "HTTP/1.1 403 Forbidden")
        #expect(try await statusLine(port, "GET / HTTP/1.1\r\n\r\n") == "HTTP/1.1 403 Forbidden")
        let upgrade = "GET /ws HTTP/1.1\r\nHost: evil.example:\(port)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
            + "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
        #expect(try await statusLine(port, upgrade) == "HTTP/1.1 403 Forbidden")
    }

    /// Design §9: idle connections from one address cannot take every place, and the iPhone's USB link is always
    /// taken (here `lo0`, whose `fe80::1` stands in for the phone's link-local address).
    @Test func limitsIdleConnectionsPerAddressAndInAllButAlwaysTakesTheCable() async throws {
        var usb: Set<String> = []
        let server = makeServer(usbInterfaces: { usb })
        defer { server.stop() }
        let port = try BoundSocket.freePort()
        #expect(await start(server, port: port) == .listening(port))
        var held: [TestClient] = []
        for _ in 0..<DashboardServer.maxConnectionsPerAddress { held.append(try #require(TestClient(port: port))) }
        let extra = try #require(TestClient(port: port))
        #expect(try await extra.read(until: { _ in extra.ended }, within: 2))
        for _ in 0..<(DashboardServer.maxConnections - DashboardServer.maxConnectionsPerAddress) {
            held.append(try #require(TestClient(port: port, address: "::1")))
        }
        // A third address finds no place left.
        let third = try #require(TestClient(port: port, address: "fe80::1", interface: "lo0"))
        #expect(try await third.read(until: { _ in third.ended }, within: 2))
        #expect(held.allSatisfy { $0.isOpen } && !third.isOpen)

        usb = ["lo0"]
        let cable = try #require(TestClient(port: port, address: "fe80::1", interface: "lo0"))
        cable.send("GET / HTTP/1.1\r\nHost: [fe80::1%lo0]:\(port)\r\n\r\n")
        #expect(try await cable.read(until: { $0.starts(with: Data("HTTP/1.1 404".utf8)) }))
    }

    @Test func closesThePhonesOfTheOldPort() async throws {
        let server = makeServer()
        defer { server.stop() }
        let old = try BoundSocket.freePort()
        #expect(await start(server, port: old) == .listening(old))
        let phone = try #require(TestClient(port: old))
        phone.send("GET /ws HTTP/1.1\r\nHost: 127.0.0.1:\(old)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                   + "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n")
        // The hub's hello shows the old listener accepted it.
        #expect(try await phone.read(until: { $0.range(of: Data(#""type":"hello""#.utf8)) != nil }))
        #expect(await move(server, to: try BoundSocket.freePort(other: old)))
        #expect(try await phone.read(until: { _ in phone.ended }))
        #expect(phone.received.range(of: Data([0x03, 0xE9]) + Data("port changed".utf8)) != nil)
    }
}

extension DashboardServer.State {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// A TCP client on 127.0.0.1 (or an IPv6 loopback address) that reads without blocking the main thread, where the
/// server runs.
final class TestClient {
    let descriptor: Int32
    private(set) var received = Data()
    private(set) var ended = false

    init?(port: UInt16) {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        guard connected else {
            Darwin.close(descriptor)
            return nil
        }
        self.descriptor = descriptor
    }

    /// From an IPv6 address of this Mac: `::1`, or `fe80::1` with `interface` `lo0`.
    init?(port: UInt16, address text: String, interface: String? = nil) {
        let descriptor = socket(AF_INET6, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = port.bigEndian
        address.sin6_scope_id = interface.map { if_nametoindex($0) } ?? 0
        let connected = inet_pton(AF_INET6, text, &address.sin6_addr) == 1 && withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) == 0
            }
        }
        guard connected else {
            Darwin.close(descriptor)
            return nil
        }
        self.descriptor = descriptor
    }

    deinit { Darwin.close(descriptor) }

    /// One look without waiting: false once the other end has closed.
    var isOpen: Bool {
        var byte: UInt8 = 0
        let count = recv(descriptor, &byte, 1, MSG_DONTWAIT | MSG_PEEK)
        return count > 0 || (count < 0 && errno == EAGAIN)
    }

    func send(_ text: String) {
        let bytes = Array(text.utf8)
        _ = bytes.withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress, $0.count, 0) }
    }

    /// Reads what has arrived until `done` says so or `seconds` pass; the end of the stream counts as arrived.
    func read(until done: (Data) -> Bool, within seconds: Double = 3) async throws -> Bool {
        let end = Date().addingTimeInterval(seconds)
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            if done(received) { return true }
            if ended || Date() >= end { return false }
            let count = buffer.withUnsafeMutableBytes { recv(descriptor, $0.baseAddress, $0.count, MSG_DONTWAIT) }
            if count > 0 {
                received.append(contentsOf: buffer[0..<count])
            } else if count == 0 || errno != EAGAIN {
                ended = true
            } else {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
    }
}
