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
                case .failed, .cancelled:
                    self.finish()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }

    /// The interface of the local end: link-local IPv6 addresses carry it (`fe80::…%en8`); otherwise the path's.
    static func interfaceName(of connection: NWConnection) -> String? {
        if case let .hostPort(host, _)? = connection.currentPath?.localEndpoint {
            switch host {
            case let .ipv6(address): if let name = address.interface?.name { return name }
            case let .ipv4(address): if let name = address.interface?.name { return name }
            default: break
            }
        }
        return connection.currentPath?.availableInterfaces.first { $0.type != .loopback }?.name
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
