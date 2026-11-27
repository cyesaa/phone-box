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

    /// Most connections held at once that are not phones yet (a file request, a socket still waiting for its key), in
    /// all and from one address; further ones are refused. Authenticated phones have their own limit (the hub's), and a
    /// connection over the iPhone's USB link is always taken (design §9).
    static let maxConnections = 32
    static let maxConnectionsPerAddress = 16

    private let webDirectory: URL
    private let hub: DashboardHub
    private let localHostName: @MainActor () -> String
    /// Seconds between tries of a port that could not be opened (design §9 "Port dolu").
    private let retryDelay: TimeInterval
    private var listener: NWListener?
    /// The listener `move(to:)` is starting; it takes over from `listener` once it is ready.
    private var pendingListener: NWListener?
    /// The next try of the port in a failed `state`.
    private var retry: DispatchWorkItem?
    /// One connection with the listener that accepted it (moving to another port closes the old port's), whether it
    /// came over the iPhone's USB link and the address it came from.
    private struct Entry {
        let client: ClientConnection
        let listener: NWListener
        let cable: Bool
        let address: String?
    }

    private var connections: [ObjectIdentifier: Entry] = [:]

    init(webDirectory: URL, hub: DashboardHub, retryDelay: TimeInterval = 30,
         localHostName: @escaping @MainActor () -> String = Settings.localHostName) {
        self.webDirectory = webDirectory
        self.hub = hub
        self.retryDelay = retryDelay
        self.localHostName = localHostName
        hub.onConnectionClosed = { [weak self] connection in self?.connections[ObjectIdentifier(connection)] = nil }
    }

    /// Listens on `port`. While it cannot (another program holds it at launch), it is tried again every `retryDelay`
    /// seconds, so PhoneBox comes back to the port in every saved link once it is free.
    func start(port: UInt16) {
        stop()
        listen(on: port)
    }

    private func listen(on port: UInt16) {
        guard let listener = makeListener(port: port, moved: nil) else { return }
        self.listener = listener
        listener.start(queue: .main)
    }

    /// The current listener cannot listen on `port`: `state` says so, and `retryDelay` later the port is tried again.
    private func failed(port: UInt16, message: String) {
        listener?.cancel()
        listener = nil
        state = .failed(port: port, message: message)
        retry?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, case let .failed(failedPort, message) = self.state, failedPort == port else { return }
                // A move under way decides first; if it fails too, the port is tried again later.
                guard self.pendingListener == nil else { return self.failed(port: port, message: message) }
                Log.server.info("Trying port \(port) again")
                self.listen(on: port)
            }
        }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: work)
    }

    /// Listens on `port` instead, keeping the current port until the new one works (design §9 "Port dolu"). Once the
    /// new listener is ready the old one stops, the phones it accepted are closed and `completion` gets true. When
    /// `port` cannot be used only the new listener goes: the old one, its phones and `state` stay, and `completion`
    /// gets false. A later `move(to:)`, `start(port:)` or `stop()` drops a move still under way without calling its
    /// `completion`.
    func move(to port: UInt16, completion: @escaping @MainActor (Bool) -> Void) {
        pendingListener?.cancel()
        pendingListener = nil
        guard let listener = makeListener(port: port, moved: completion) else { return completion(false) }
        pendingListener = listener
        listener.start(queue: .main)
    }

    func stop() {
        retry?.cancel()
        retry = nil
        listener?.cancel()
        listener = nil
        pendingListener?.cancel()
        pendingListener = nil
        state = .stopped
    }

    /// A listener on `port` that is not started yet; `moved` is set when it is to replace the current one. Nil (and,
    /// without `moved`, a failed `state`) when it cannot be made.
    private func makeListener(port: UInt16, moved: (@MainActor (Bool) -> Void)?) -> NWListener? {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return nil }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: endpointPort)
        } catch {
            Log.server.error("Cannot listen on port \(port): \(error.localizedDescription, privacy: .public)")
            if moved == nil { failed(port: port, message: error.localizedDescription) }
            return nil
        }
        listener.stateUpdateHandler = { [weak self, weak listener] newState in
            MainActor.assumeIsolated {
                // A listener replaced by a newer one (another port) may still report; only the current one and the
                // one being moved to count.
                guard let self, let listener else { return }
                if self.listener === listener {
                    switch newState {
                    case .ready:
                        Log.server.info("Listening on port \(port)")
                        self.state = .listening(port)
                    case let .failed(error):
                        Log.server.error("Listener failed: \(error.localizedDescription, privacy: .public)")
                        self.failed(port: port, message: error.localizedDescription)
                    default:
                        break
                    }
                } else if self.pendingListener === listener, let moved {
                    switch newState {
                    case .ready:
                        self.takeOver(listener, port: port)
                        moved(true)
                    case let .failed(error), let .waiting(error):
                        // `.waiting` (the port is taken, for one) would otherwise leave the move hanging.
                        Log.server.error("Cannot move to port \(port): \(error.localizedDescription, privacy: .public)")
                        listener.cancel()
                        self.pendingListener = nil
                        moved(false)
                    default:
                        break
                    }
                }
            }
        }
        listener.newConnectionHandler = { [weak self, weak listener] connection in
            MainActor.assumeIsolated {
                guard let self, let listener else { return connection.cancel() }
                self.accept(connection, from: listener)
            }
        }
        return listener
    }

    /// The listener that `move(to:)` started is ready: it replaces the current one, whose phones are closed (their
    /// page reconnects to the port in its address, which is gone; they have to scan the new QR code).
    private func takeOver(_ newListener: NWListener, port: UInt16) {
        retry?.cancel()
        retry = nil
        let oldListener = listener
        oldListener?.cancel()
        listener = newListener
        pendingListener = nil
        for entry in connections.values where entry.listener === oldListener {
            // Only a WebSocket can take a close frame; a plain HTTP request is simply dropped.
            if entry.client.isWebSocket {
                entry.client.close(code: 1001, reason: "port changed")
            } else {
                entry.client.cancel()
            }
        }
        Log.server.info("Listening on port \(port)")
        state = .listening(port)
    }

    private func accept(_ connection: NWConnection, from listener: NWListener) {
        // A replaced listener's late connection is refused, like its late state.
        guard listener === self.listener || listener === pendingListener else { return connection.cancel() }
        let cable = arrivesOverUSB(connection)
        let address = ClientConnection.remoteAddress(of: connection)
        if !cable {
            let held = connections.values.filter { !$0.cable && !$0.client.isAuthenticated }
            guard held.count < Self.maxConnections,
                  held.filter({ $0.address == address }).count < Self.maxConnectionsPerAddress
            else { return connection.cancel() }
        }
        let client = ClientConnection(connection: connection, webDirectory: webDirectory, hub: hub,
                                      localHostName: localHostName)
        connections[ObjectIdentifier(client)] = Entry(client: client, listener: listener, cable: cable, address: address)
        client.start()
    }

    /// From a scoped IPv6 link-local address on the iPhone's USB link: only the plugged-in phone can be there.
    private func arrivesOverUSB(_ connection: NWConnection) -> Bool {
        guard case let .hostPort(host, _) = connection.endpoint, case let .ipv6(address) = host, address.isLinkLocal,
              let name = address.interface?.name
        else { return false }
        return hub.isUSBLink(name)
    }
}
