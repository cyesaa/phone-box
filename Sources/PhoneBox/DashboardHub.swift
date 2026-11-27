import Foundation
import PhoneBoxCore

/// What the hub needs from one phone's WebSocket: `ClientConnection` in the app, a fake in the tests.
@MainActor
protocol PhoneConnection: AnyObject {
    /// The network interface the connection arrived on, e.g. `en8` (the iPhone's USB link) or `en0` (Wi-Fi).
    var interfaceName: String? { get }
    /// True when the local end is a scoped IPv6 link-local address, which is how the iPhone's USB link looks.
    var arrivedOnScopedLinkLocal: Bool { get }
    /// The address of the other end, without the port: sockets that have not authenticated are counted per address.
    var remoteAddress: String? { get }
    /// When the last frame of any kind arrived, on a monotonic clock that counts sleep.
    var lastInboundAt: ContinuousClock.Instant { get }
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

/// The authenticated phones, for the menu bar and the settings window: the ones receiving data, over the cable or over
/// Wi-Fi, and the ones on Wi-Fi waiting for the cable (cable mode).
struct PhoneCounts: Equatable {
    var onCable = 0
    var overWiFi = 0
    var waitingForCable = 0

    /// Phones receiving data.
    var streaming: Int { onCable + overWiFi }
}

/// Keeps track of the phones connected over WebSocket (design §5): the protocol session of each, whether it
/// came in over the iPhone's USB link, what it may do, who gets the snapshots, and the commands they send.
@MainActor
final class DashboardHub {
    /// Phones that have authenticated (design §9); the phone on the cable is always taken, even beyond.
    static let maxClients = 4
    /// WebSockets that have not authenticated yet, from one address and in all (one on the cable is not counted): a
    /// device without the key can hold only these, never the places of the phones that have it.
    static let maxPendingPerAddress = 2
    static let maxPending = 8
    /// Close code for a phone that authenticated while `maxClients` others had. In the app's own range (4000–4999),
    /// which every browser accepts; the page treats it like any other close and tries again later.
    static let busyCode: UInt16 = 4004
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
        /// The order in which it authenticated (1, 2, …); 0 until then.
        var authenticatedAs = 0
    }

    var mode: AccessMode {
        didSet { if mode != oldValue { refreshAccess() } }
    }
    /// "Lock and Music over Wi-Fi" (design §5): in "always" mode, phones on Wi-Fi may also lock the Mac and control
    /// the music.
    var lockAndMusicOverWiFi: Bool {
        didSet { if lockAndMusicOverWiFi != oldValue { refreshAccess() } }
    }
    private var key: PairingKey
    private let appName: String
    /// The Mac's name, shown at the top of the page's "⋯" menu. Read for each `ready`: the Mac can be renamed while
    /// PhoneBox runs.
    private let hostName: @MainActor () -> String
    /// Where the page's power tile turns red, for this Mac's chip.
    private let powerLimits: PowerLimits
    /// The dashboard files' name (`WebBuild`), sent in `ready` and stamped into the index.html that is served.
    let build: String
    private let commands: any CommandRunning
    private let usbInterfaces: () -> Set<String>
    private var clients: [ObjectIdentifier: Client] = [:]
    /// Lock and music commands from phones on Wi-Fi, all of them together (design §5).
    private var wifiLimit = WiFiCommandLimit()
    private var livenessTimer: Timer?
    /// Authentications so far, to number the phones in the order they authenticated.
    private var authentications = 0
    /// `authentications` when the last iPhone was plugged in: only phones that authenticated by then are asked to
    /// reconnect, so a phone that reconnected over Wi-Fi after the first pass is not asked again.
    private var authenticationsAtPlugIn: Int?

    /// True while at least one phone may receive snapshots: the sampler runs only then.
    var onStreamingChange: ((Bool) -> Void)?
    /// Counts for the menu bar and the settings window.
    var onClientsChange: ((PhoneCounts) -> Void)?
    /// A phone authenticated for the first time with this key.
    var onAuthenticated: (() -> Void)?
    var onConnectionClosed: ((any PhoneConnection) -> Void)?

    init(mode: AccessMode, lockAndMusicOverWiFi: Bool = false, key: PairingKey, appName: String,
         hostName: @escaping @MainActor () -> String,
         powerLimits: PowerLimits = .standard, build: String = "", commands: any CommandRunning,
         usbInterfaces: @escaping () -> Set<String> = USBLinks.iPhoneInterfaceNames) {
        self.mode = mode
        self.lockAndMusicOverWiFi = lockAndMusicOverWiFi
        self.key = key
        self.appName = appName
        self.hostName = hostName
        self.powerLimits = powerLimits
        self.build = build
        self.commands = commands
        self.usbInterfaces = usbInterfaces
        let timer = Timer(timeInterval: Self.pingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkLiveness() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        livenessTimer = timer
    }

    /// Pings every authenticated phone and drops the ones that have been silent for too long. `now` is from
    /// `ContinuousClock`, which counts time asleep: after a wake the sockets from before the sleep are dropped, and
    /// setting the Mac's clock changes nothing.
    func checkLiveness(now: ContinuousClock.Instant = .now) {
        for client in clients.values where client.session.isAuthenticated {
            if now - client.connection.lastInboundAt > .seconds(Self.silenceLimit) {
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

    /// Whether a new WebSocket may open: always over the iPhone's USB link; otherwise while fewer than `maxClients`
    /// phones have authenticated and the sockets still waiting to authenticate stay under their limits.
    func canAccept(_ connection: any PhoneConnection) -> Bool {
        if isOnUSB(connection) { return true }
        guard clients.values.filter({ $0.session.isAuthenticated }).count < Self.maxClients else { return false }
        let pending = clients.values.filter { !$0.session.isAuthenticated && !$0.onUSB }
        let fromThere = pending.filter { $0.connection.remoteAddress == connection.remoteAddress }
        return pending.count < Self.maxPending && fromThere.count < Self.maxPendingPerAddress
    }

    /// Whether `interfaceName` is the iPhone's USB link, for the server's own limits.
    func isUSBLink(_ interfaceName: String) -> Bool {
        usbInterfaces().contains(interfaceName)
    }

    /// The local end is a scoped IPv6 link-local address on an interface IOKit puts on an iPhone.
    private func isOnUSB(_ connection: any PhoneConnection) -> Bool {
        connection.arrivedOnScopedLinkLocal && (connection.interfaceName.map(isUSBLink) ?? false)
    }

    private var isStreaming: Bool { clients.values.contains { $0.access.streaming } }

    func opened(_ connection: any PhoneConnection) {
        let onUSB = isOnUSB(connection)
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
        let outcome = client.session.receive(text, key: key, allowedCommands: client.access.commands, now: .now)
        clients[id] = client
        switch outcome {
        case .authenticated:
            // Several sockets may have been waiting while fewer phones had authenticated.
            let others = clients.filter { $0.key != id && $0.value.session.isAuthenticated }.count
            if !client.onUSB, others >= Self.maxClients {
                Log.server.notice("Turning a phone away: \(Self.maxClients) phones are connected")
                clients[id] = nil
                connection.close(code: Self.busyCode, reason: "too many phones")
                return
            }
            let wasStreaming = isStreaming
            connection.markAuthenticated()
            authentications += 1
            client.authenticatedAs = authentications
            client.access = access(onUSB: client.onUSB)
            clients[id] = client
            connection.send(.ready(mode: mode, host: hostName(), powerLimits: powerLimits, access: client.access,
                                   build: build))
            onAuthenticated?()
            changed(wasStreaming: wasStreaming)
        case let .command(seq, command):
            if !client.onUSB, !wifiLimit.allows(command, now: .now) {
                Log.server.notice("Refusing \(command.name, privacy: .public) from a phone on Wi-Fi: too often")
                connection.send(.ack(seq: seq, result: .failed(.failed)))
                return
            }
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

    /// usbmuxd reports an iPhone plugged in: the phones on Wi-Fi now are the ones `moveWiFiPhonesToCable()` asks to
    /// reconnect.
    func iPhonePluggedIn() {
        authenticationsAtPlugIn = authentications
    }

    /// A pass a few seconds after `iPhonePluggedIn()`, once the USB link is up. In both modes, phones that were connected
    /// over Wi-Fi at the plug-in are asked to reconnect so that the plugged-in one comes back over the cable: only there
    /// does it get every command (and, in cable mode, data). A device that is not plugged in reconnects over Wi-Fi again,
    /// after the plug-in, so a later pass leaves it alone: it reconnects once.
    func moveWiFiPhonesToCable() {
        guard let mark = authenticationsAtPlugIn, !usbInterfaces().isEmpty else { return }
        for client in clients.values
        where client.session.isAuthenticated && !client.onUSB && client.authenticatedAs <= mark {
            client.connection.close(code: Self.reconnectCode, reason: "use the cable")
        }
    }

    /// What an authenticated phone may do under the current settings.
    private func access(onUSB: Bool) -> Access {
        AccessPolicy.decide(mode: mode, lockAndMusicOverWiFi: lockAndMusicOverWiFi, clientOnUSB: onUSB, authenticated: true)
    }

    /// After a settings change: every authenticated phone whose access changed is told.
    private func refreshAccess() {
        let wasStreaming = isStreaming
        for (id, var client) in clients where client.session.isAuthenticated {
            let access = self.access(onUSB: client.onUSB)
            guard access != client.access else { continue }
            client.access = access
            clients[id] = client
            client.connection.send(.access(access))
        }
        changed(wasStreaming: wasStreaming)
    }

    private func changed(wasStreaming: Bool) {
        if isStreaming != wasStreaming { onStreamingChange?(isStreaming) }
        var counts = PhoneCounts()
        for client in clients.values {
            if client.access.streaming {
                if client.access.cable { counts.onCable += 1 } else { counts.overWiFi += 1 }
            } else if client.access.reason == Access.notOnCable.reason {
                counts.waitingForCable += 1
            }
        }
        onClientsChange?(counts)
    }
}
