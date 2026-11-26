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
    /// True when the local end is a scoped IPv6 link-local address (`fe80::…%en8`), which is how the iPhone's
    /// USB link looks. Anything else (IPv4, unscoped IPv6, unknown) is not the cable: fail closed.
    private(set) var arrivedOnScopedLinkLocal = false
    /// When the last frame of any kind arrived; the hub drops connections that went silent.
    private(set) var lastInboundAt = Date()
    private(set) var isAuthenticated = false

    /// Seconds a connection may take to become a WebSocket before it is dropped.
    static let headTimeout: TimeInterval = 10
    /// Seconds a closing connection may take to finish before it is cancelled.
    static let closeTimeout: TimeInterval = 2
    /// Seconds a connection may stay non-viable (no route, e.g. after unplugging the cable) before it is dropped.
    static let nonViableTimeout: TimeInterval = 5
    /// Sends that have not completed yet; a peer that never reads is dropped beyond this.
    static let maxOutstandingSends = 256

    private let webDirectory: URL
    private weak var hub: DashboardHub?
    private var head = Data()
    private var decoder = WebSocketDecoder()
    private var closed = false
    private var outstandingSends = 0
    private var nonViableTimer: DispatchWorkItem?

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
                    self.arrivedOnScopedLinkLocal = Self.isScopedLinkLocal(self.connection)
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
        connection.viabilityUpdateHandler = { [weak self] viable in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.nonViableTimer?.cancel()
                self.nonViableTimer = nil
                guard !viable, !self.closed else { return }
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated { self?.cancel() }
                }
                self.nonViableTimer = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.nonViableTimeout, execute: work)
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

    /// Whether the local end is a link-local IPv6 address that carries its interface scope.
    static func isScopedLinkLocal(_ connection: NWConnection) -> Bool {
        guard case let .hostPort(host, _)? = connection.currentPath?.localEndpoint,
              case let .ipv6(address) = host else { return false }
        return address.isLinkLocal && address.interface != nil
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
            guard WebSocketOrigin.isAllowed(origin: request.headers["origin"], host: request.headers["host"]) else {
                Log.server.notice("Refusing a WebSocket from another site")
                return respond(HTTPResponse.forbidden)
            }
            guard let hub, hub.canAccept else { return respond(HTTPResponse.busy) }
            isWebSocket = true
            transmit(WebSocketHandshake.response(for: key))
            hub.opened(self)
            readFrames()
        } else {
            respond(fileResponse(path: request.path, range: request.headers["range"]))
        }
    }

    private func fileResponse(path: String, range: String?) -> Data {
        let name = path == "/" ? "index.html" : String(path.dropFirst())
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix("."),
              let file = try? Data(contentsOf: webDirectory.appendingPathComponent(name))
        else { return HTTPResponse.notFound }
        // The page reads the build it was served with from index.html (design §5).
        let body = name == "index.html" ? WebBuild.stamp(file, build: hub?.build ?? "") : file
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
                let frames: [WebSocketFrame]
                do {
                    frames = try self.decoder.append(data ?? Data())
                } catch {
                    return self.close(code: Session.policyViolationCode, reason: "bad frame")
                }
                if !frames.isEmpty { self.lastInboundAt = Date() }
                // RFC 6455 section 5.5.3: answering the last ping of a burst is enough.
                var lastPing: WebSocketFrame?
                for frame in frames {
                    if frame.opcode == WebSocketOpcode.ping.rawValue && self.isAuthenticated {
                        lastPing = frame
                        continue
                    }
                    self.handle(frame)
                    if self.closed { return }
                }
                if let lastPing { self.transmit(WebSocketCodec.encode(.pong, lastPing.payload)) }
                if isComplete || error != nil { self.cancel() } else { self.readFrames() }
            }
        }
    }

    /// Called by the hub once the phone has authenticated; until then only text frames are accepted.
    func markAuthenticated() {
        isAuthenticated = true
    }

    private func handle(_ frame: WebSocketFrame) {
        guard isAuthenticated || frame.opcode == WebSocketOpcode.text.rawValue else {
            return close(code: Session.policyViolationCode, reason: "not authenticated")
        }
        switch WebSocketOpcode(rawValue: frame.opcode) {
        case .text:
            guard let text = frame.text else { return close(code: Session.policyViolationCode, reason: "bad text") }
            hub?.received(text, from: self)
        case .ping:
            transmit(WebSocketCodec.encode(.pong, frame.payload))
        case .close:
            close(code: 1000, reason: "")
        case .binary:
            close(code: 1003, reason: "binary frames are not supported")
        default:
            break
        }
    }

    func send(_ message: ServerMessage) {
        guard isWebSocket, !closed else { return }
        transmit(WebSocketCodec.text(message.json()))
    }

    /// A ping from the hub's liveness timer; browsers answer with a pong on their own.
    func sendPing() {
        guard isWebSocket, !closed else { return }
        transmit(WebSocketCodec.encode(.ping, Data()))
    }

    /// Sends bytes and counts them until they are written; a peer that stops reading is dropped.
    private func transmit(_ data: Data) {
        outstandingSends += 1
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            MainActor.assumeIsolated { self?.outstandingSends -= 1 }
        })
        if outstandingSends > Self.maxOutstandingSends { cancel() }
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
        nonViableTimer?.cancel()
        nonViableTimer = nil
        closed = true
        hub?.closed(self)
    }
}

extension ClientConnection: PhoneConnection {}
