import Foundation
import PhoneBoxCore

/// What the hub needs from one phone's WebSocket: `ClientConnection` in the app, a fake in the tests.
@MainActor
protocol PhoneConnection: AnyObject {
    /// The network interface the connection arrived on, e.g. `en8` (the iPhone's USB link) or `en0` (Wi-Fi).
    var interfaceName: String? { get }
    /// True when the local end is a scoped IPv6 link-local address, which is how the iPhone's USB link looks.
    var arrivedOnScopedLinkLocal: Bool { get }
    /// When the last frame of any kind arrived.
    var lastInboundAt: Date { get }
    func send(_ message: ServerMessage)
    func sendPing()
    func markAuthenticated()
    func close(code: UInt16, reason: String)
    func cancel()
}

/// Runs a command on the Mac (design §7): `CommandRunner` in the app, a fake in the tests. `completion` is
/// called once, on the main actor.
@MainActor
protocol CommandRunning: AnyObject {
    func run(_ command: Command, completion: @escaping @MainActor (CommandResult) -> Void)
}

/// Keeps track of the phones connected over WebSocket (design §5): the protocol session of each, whether it
/// came in over the iPhone's USB link, what it may do, who gets the snapshots, and the commands they send.
@MainActor
final class DashboardHub {
    static let maxClients = 4
    static let authTimeout: TimeInterval = 5
    /// Close code that tells the page to reconnect at once (to come back over the cable).
    static let reconnectCode: UInt16 = 4002
    /// Seconds between liveness pings, and how long a phone may stay silent before it is dropped.
    static let pingInterval: TimeInterval = 15
    static let silenceLimit: TimeInterval = 45

    private struct Client {
        let connection: any PhoneConnection
        var session: Session
        let onUSB: Bool
        var access: Access
    }

    var mode: AccessMode {
        didSet { if mode != oldValue { refreshAccess() } }
    }
    private var key: PairingKey
    private let appName: String
    /// The Mac's name, shown in the page's status line.
    private let hostName: String
    private let commands: any CommandRunning
    private let usbInterfaces: () -> Set<String>
    private var clients: [ObjectIdentifier: Client] = [:]
    private var livenessTimer: Timer?

    /// True while at least one phone may receive snapshots: the sampler runs only then.
    var onStreamingChange: ((Bool) -> Void)?
    /// Counts for the menu bar: phones receiving data, phones waiting for the cable.
    var onClientsChange: ((_ streaming: Int, _ waitingForCable: Int) -> Void)?
    /// A phone authenticated for the first time with this key.
    var onAuthenticated: (() -> Void)?
    var onConnectionClosed: ((any PhoneConnection) -> Void)?

    init(mode: AccessMode, key: PairingKey, appName: String, hostName: String, commands: any CommandRunning,
         usbInterfaces: @escaping () -> Set<String> = USBLinks.iPhoneInterfaceNames) {
        self.mode = mode
        self.key = key
        self.appName = appName
        self.hostName = hostName
        self.commands = commands
        self.usbInterfaces = usbInterfaces
        let timer = Timer(timeInterval: Self.pingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkLiveness() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        livenessTimer = timer
    }

    /// Pings every authenticated phone and drops the ones that have been silent for too long.
    private func checkLiveness() {
        let now = Date()
        for client in clients.values where client.session.isAuthenticated {
            if now.timeIntervalSince(client.connection.lastInboundAt) > Self.silenceLimit {
                Log.server.notice("Dropping a silent phone")
                client.connection.cancel()
            } else {
                client.connection.sendPing()
            }
        }
    }

    /// Cancels USB phones whose interface is gone (the cable was unplugged).
    func dropVanishedUSBClients() {
        let present = usbInterfaces()
        for client in clients.values where client.session.isAuthenticated && client.onUSB {
            guard let name = client.connection.interfaceName, present.contains(name) else {
                Log.server.notice("Dropping a phone whose USB link is gone")
                client.connection.cancel()
                continue
            }
        }
    }

    var canAccept: Bool { clients.count < Self.maxClients }
    private var isStreaming: Bool { clients.values.contains { $0.access.streaming } }

    func opened(_ connection: any PhoneConnection) {
        let onUSB = connection.arrivedOnScopedLinkLocal && (connection.interfaceName.map(usbInterfaces().contains) ?? false)
        let session = Session(nonce: Session.makeNonce())
        clients[ObjectIdentifier(connection)] = Client(connection: connection, session: session, onUSB: onUSB, access: .unauthenticated)
        Log.server.info("Phone connected on \(connection.interfaceName ?? "?", privacy: .public) (scoped link-local: \(connection.arrivedOnScopedLinkLocal), USB: \(onUSB))")
        connection.send(.hello(nonce: session.nonce, app: appName))
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.authTimeout) { [weak self, weak connection] in
            MainActor.assumeIsolated {
                guard let self, let connection, let client = self.clients[ObjectIdentifier(connection)],
                      !client.session.isAuthenticated
                else { return }
                connection.close(code: Session.authTimeoutCode, reason: "no auth")
            }
        }
    }

    func received(_ text: String, from connection: any PhoneConnection) {
        let id = ObjectIdentifier(connection)
        guard var client = clients[id] else { return }
        let outcome = client.session.receive(text, key: key, commandsAllowed: client.access.commands, now: Date())
        clients[id] = client
        switch outcome {
        case .authenticated:
            let wasStreaming = isStreaming
            connection.markAuthenticated()
            client.access = AccessPolicy.decide(mode: mode, clientOnUSB: client.onUSB, authenticated: true)
            clients[id] = client
            connection.send(.ready(mode: mode, host: hostName, access: client.access))
            onAuthenticated?()
            changed(wasStreaming: wasStreaming)
        case let .command(seq, command):
            Log.server.info("Running \(command.name, privacy: .public) from the phone")
            commands.run(command) { [weak self, weak connection] result in
                // The phone may have gone (or been dropped) while the command ran.
                guard let self, let connection, self.clients[ObjectIdentifier(connection)] != nil else { return }
                if case let .failed(failure) = result {
                    Log.server.notice("\(command.name, privacy: .public) failed: \(failure.rawValue, privacy: .public)")
                }
                connection.send(.ack(seq: seq, result: result))
            }
        case let .reply(message):
            connection.send(message)
        case let .close(code, reason):
            Log.server.notice("Closing a phone: \(reason, privacy: .public)")
            connection.close(code: code, reason: reason)
        }
    }

    func closed(_ connection: any PhoneConnection) {
        let wasStreaming = isStreaming
        if clients.removeValue(forKey: ObjectIdentifier(connection)) != nil {
            changed(wasStreaming: wasStreaming)
        }
        onConnectionClosed?(connection)
    }

    func broadcast(_ snapshot: Snapshot) {
        let message = ServerMessage.snapshot(snapshot)
        for client in clients.values where client.access.streaming {
            client.connection.send(message)
        }
    }

    /// A new pairing key: every phone has to scan the new QR code.
    func replaceKey(_ newKey: PairingKey) {
        key = newKey
        for client in clients.values {
            client.connection.close(code: Session.authFailedCode, reason: "pairing reset")
        }
    }

    /// An iPhone was just plugged in. In cable mode, phones that are connected over Wi-Fi are asked to
    /// reconnect so that they come back over the cable.
    func iPhonePluggedIn() {
        guard mode == .cable, !usbInterfaces().isEmpty else { return }
        for client in clients.values where client.session.isAuthenticated && !client.onUSB {
            client.connection.close(code: Self.reconnectCode, reason: "use the cable")
        }
    }

    private func refreshAccess() {
        let wasStreaming = isStreaming
        for (id, var client) in clients where client.session.isAuthenticated {
            let access = AccessPolicy.decide(mode: mode, clientOnUSB: client.onUSB, authenticated: true)
            guard access != client.access else { continue }
            client.access = access
            clients[id] = client
            client.connection.send(.access(access))
        }
        changed(wasStreaming: wasStreaming)
    }

    private func changed(wasStreaming: Bool) {
        if isStreaming != wasStreaming { onStreamingChange?(isStreaming) }
        let streaming = clients.values.filter { $0.access.streaming }.count
        let waiting = clients.values.filter { $0.access.reason == Access.notOnCable.reason }.count
        onClientsChange?(streaming, waiting)
    }
}
