import AppKit
import PhoneBoxCore

/// Wires the parts together (design §4).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let sampler = Sampler()
    private let usbWatcher = USBWatcher()
    private let qrWindow = QRWindowController()
    private let loaded = PairingStore.loadOrCreate()
    private var key: PairingKey
    private var hub: DashboardHub!
    private var server: DashboardServer!
    private var menuBar: MenuBarController!
    private var streamingCount = 0
    private var waitingForCableCount = 0
    private var wakeObserver: NSObjectProtocol?

    override init() {
        key = loaded.key
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if loaded.created { settings.hasEverPaired = false }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        hub = DashboardHub(mode: settings.mode, key: key, appName: "PhoneBox \(version)")
        let webDirectory = Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true)
        server = DashboardServer(webDirectory: webDirectory, hub: hub)
        menuBar = MenuBarController(mode: settings.mode)

        hub.onStreamingChange = { [weak self] streaming in self?.sampler.setRunning(streaming) }
        hub.onClientsChange = { [weak self] streaming, waiting in
            self?.streamingCount = streaming
            self?.waitingForCableCount = waiting
            self?.refreshStatus()
        }
        hub.onAuthenticated = { [weak self] in self?.settings.hasEverPaired = true }
        sampler.onSnapshot = { [weak self] snapshot in self?.hub.broadcast(snapshot) }
        server.onStateChange = { [weak self] _ in self?.refreshStatus() }

        menuBar.onShowQR = { [weak self] in self?.showQR() }
        menuBar.onModeChange = { [weak self] mode in
            self?.settings.mode = mode
            self?.hub.mode = mode
        }
        menuBar.onResetPairing = { [weak self] in
            guard let self else { return }
            key = PairingStore.reset()
            settings.hasEverPaired = false
            hub.replaceKey(key)
            showQR()
        }

        usbWatcher.onChange = { [weak self] pluggedIn in self?.iPhoneChanged(pluggedIn: pluggedIn) }
        usbWatcher.onAvailabilityChange = { [weak self] _ in self?.refreshStatus() }
        usbWatcher.start()
        server.start(port: settings.port)

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampler.resetAfterWake() }
        }
    }

    private func showQR() {
        qrWindow.show(link: settings.personalURL(key: key))
    }

    private func iPhoneChanged(pluggedIn: Bool) {
        refreshStatus()
        guard pluggedIn else {
            // The interface disappears a moment after usbmuxd reports the unplug; then drop its phones.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated { self?.hub.dropVanishedUSBClients() }
            }
            return
        }
        if !settings.hasEverPaired { showQR() }
        // The USB link appears a moment after usbmuxd reports the phone; then move Wi-Fi phones to the cable.
        for delay in [3.0, 8.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.hub.iPhonePluggedIn() }
            }
        }
    }

    private func refreshStatus() {
        let status: String
        if case let .failed(port, _) = server.state {
            status = L10n.statusPortInUse(port)
        } else if streamingCount > 0 {
            status = L10n.statusStreaming(streamingCount)
        } else if waitingForCableCount > 0 {
            status = L10n.statusWaitingForCable
        } else if !usbWatcher.isAvailable {
            status = L10n.statusUSBUnavailable
        } else {
            status = L10n.statusWaiting
        }
        menuBar.update(status: status, active: streamingCount > 0)
    }
}
