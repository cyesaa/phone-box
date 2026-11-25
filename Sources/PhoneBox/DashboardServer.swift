import Foundation
import Network

/// Listens on one TCP port (4747 by default) on every interface: Wi-Fi and the iPhone's USB link (design §4).
@MainActor
final class DashboardServer {
    enum State: Equatable {
        case stopped
        case listening(UInt16)
        case failed(port: UInt16, message: String)
    }

    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .stopped {
        didSet { onStateChange?(state) }
    }

    private let webDirectory: URL
    private let hub: DashboardHub
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: ClientConnection] = [:]

    init(webDirectory: URL, hub: DashboardHub) {
        self.webDirectory = webDirectory
        self.hub = hub
        hub.onConnectionClosed = { [weak self] connection in self?.connections[ObjectIdentifier(connection)] = nil }
    }

    func start(port: UInt16) {
        stop()
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: endpointPort)
        } catch {
            state = .failed(port: port, message: error.localizedDescription)
            return
        }
        listener.stateUpdateHandler = { [weak self] newState in
            MainActor.assumeIsolated {
                switch newState {
                case .ready:
                    Log.server.info("Listening on port \(port)")
                    self?.state = .listening(port)
                case let .failed(error):
                    Log.server.error("Listener failed: \(error.localizedDescription, privacy: .public)")
                    self?.state = .failed(port: port, message: error.localizedDescription)
                default:
                    break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        state = .stopped
    }

    private func accept(_ connection: NWConnection) {
        let client = ClientConnection(connection: connection, webDirectory: webDirectory, hub: hub)
        connections[ObjectIdentifier(client)] = client
        client.start()
    }
}
