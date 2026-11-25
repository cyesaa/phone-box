import Foundation
import Network
import PhoneBoxCore

/// One TCP connection from a browser: an HTTP request for a dashboard file, or a WebSocket at `/ws`
/// (design §4 "Server"). Everything runs on the main queue.
@MainActor
final class ClientConnection {
    let connection: NWConnection
    /// The network interface the connection arrived on, e.g. `en8` for the iPhone's USB link or `en0` for Wi-Fi.
    private(set) var interfaceName: String?
    private(set) var isWebSocket = false

    /// Seconds a connection may take to become a WebSocket before it is dropped.
    static let headTimeout: TimeInterval = 10
    /// Seconds a closing connection may take to finish before it is cancelled.
    static let closeTimeout: TimeInterval = 2

    private let webDirectory: URL
    private weak var hub: DashboardHub?
    private var head = Data()
    private var decoder = WebSocketDecoder()
    private var closed = false

    init(connection: NWConnection, webDirectory: URL, hub: DashboardHub) {
        self.connection = connection
        self.webDirectory = webDirectory
        self.hub = hub
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    self.interfaceName = Self.interfaceName(of: self.connection)
                    self.readHead()
                case .failed, .waiting:
                    self.cancel()
                case .cancelled:
                    self.finish()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.headTimeout) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isWebSocket, !self.closed else { return }
                self.cancel()
            }
        }
    }

    /// The interface of the local end. Link-local IPv6 addresses carry it (`fe80::…%en8`); otherwise the interface
    /// that owns the local address is looked up. Unknown means nil: the hub then treats the client as not on USB.
    static func interfaceName(of connection: NWConnection) -> String? {
        guard case let .hostPort(host, _)? = connection.currentPath?.localEndpoint else { return nil }
        let bytes: [UInt8]
        switch host {
        case let .ipv6(address):
            if let name = address.interface?.name { return name }
            bytes = Array(address.rawValue)
        case let .ipv4(address):
            if let name = address.interface?.name { return name }
            bytes = Array(address.rawValue)
        default:
            return nil
        }
        return InterfaceAddress.owner(of: bytes, among: localAddresses())
    }

    /// Every IPv4 and IPv6 address of this Mac with its interface name, from `getifaddrs`.
    private static func localAddresses() -> [(name: String, address: [UInt8])] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var result: [(name: String, address: [UInt8])] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let addr = entry.pointee.ifa_addr else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            switch Int32(addr.pointee.sa_family) {
            case AF_INET:
                let bytes = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    withUnsafeBytes(of: $0.pointee.sin_addr) { Array($0) }
                }
                result.append((name, bytes))
            case AF_INET6:
                let bytes = addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                    withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) }
                }
                result.append((name, bytes))
            default:
                break
            }
        }
        return result
    }

    // MARK: HTTP

    private func readHead() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let data { self.head.append(data) }
                switch HTTPRequestParser.parse(self.head) {
                case .incomplete:
                    if isComplete || error != nil { self.cancel() } else { self.readHead() }
                case .tls:
                    self.cancel()
                case .invalid:
                    self.respond(HTTPResponse.badRequest)
                case let .complete(request):
                    self.route(request)
                }
            }
        }
    }

    private func route(_ request: HTTPRequestHead) {
        guard request.method == "GET" else { return respond(HTTPResponse.badRequest) }
        if request.path == "/ws" {
            guard request.headers["upgrade"]?.lowercased() == "websocket", let key = request.headers["sec-websocket-key"]
            else { return respond(HTTPResponse.badRequest) }
            guard let hub, hub.canAccept else { return respond(HTTPResponse.busy) }
            isWebSocket = true
            connection.send(content: WebSocketHandshake.response(for: key), completion: .contentProcessed { _ in })
            hub.opened(self)
            readFrames()
        } else {
            respond(fileResponse(path: request.path, range: request.headers["range"]))
        }
    }

    private func fileResponse(path: String, range: String?) -> Data {
        let name = path == "/" ? "index.html" : String(path.dropFirst())
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix("."),
              let body = try? Data(contentsOf: webDirectory.appendingPathComponent(name))
        else { return HTTPResponse.notFound }
        return HTTPResponse.file(body, name: name, range: range)
    }

    private func respond(_ response: Data) {
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        })
    }

    // MARK: WebSocket

    private func readFrames() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                do {
                    for frame in try self.decoder.append(data ?? Data()) {
                        self.handle(frame)
                        if self.closed { return }
                    }
                } catch {
                    return self.close(code: Session.policyViolationCode, reason: "bad frame")
                }
                if isComplete || error != nil { self.cancel() } else { self.readFrames() }
            }
        }
    }

    private func handle(_ frame: WebSocketFrame) {
        switch WebSocketOpcode(rawValue: frame.opcode) {
        case .text:
            guard let text = frame.text else { return close(code: Session.policyViolationCode, reason: "bad text") }
            hub?.received(text, from: self)
        case .ping:
            connection.send(content: WebSocketCodec.encode(.pong, frame.payload), completion: .contentProcessed { _ in })
        case .close:
            close(code: 1000, reason: "")
        default:
            break
        }
    }

    func send(_ message: ServerMessage) {
        guard isWebSocket, !closed else { return }
        connection.send(content: WebSocketCodec.text(message.json()), completion: .contentProcessed { _ in })
    }

    /// Sends a close frame, then drops the connection.
    func close(code: UInt16, reason: String) {
        guard !closed else { return }
        connection.send(content: WebSocketCodec.close(code: code, reason: reason), completion: .contentProcessed { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        })
        closed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeTimeout) { [weak self] in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    func cancel() {
        connection.cancel()
        finish()
    }

    private func finish() {
        closed = true
        hub?.closed(self)
    }
}
