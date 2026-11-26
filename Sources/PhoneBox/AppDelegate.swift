import AppKit
import PhoneBoxCore

/// Wires the parts together (design §4).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let sampler = Sampler()
    private let usbWatcher = USBWatcher()
    private let qrWindow = QRWindowController()
    private let updates = UpdateService()
    private lazy var commandRunner = CommandRunner(nowPlaying: sampler.nowPlaying)
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
        // A Mac with a battery reports its whole power draw; a desktop Mac only the GPU's.
        let powerLimits = PowerLimits.forChip(Settings.chipName(), wholeMac: BatteryCollector.hasInternalBattery())
        let webDirectory = Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true)
        hub = DashboardHub(mode: settings.mode, key: key, appName: "PhoneBox \(version)", hostName: Settings.computerName(),
                           powerLimits: powerLimits, build: Self.webBuild(webDirectory), commands: commandRunner)
        server = DashboardServer(webDirectory: webDirectory, hub: hub)
        menuBar = MenuBarController(mode: settings.mode, port: settings.port, updates: updates)

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
        menuBar.onPortChange = { [weak self] port in
            guard let self else { return }
            settings.port = port
            menuBar.port = port
            server.start(port: port)
            // The phone's link names the port: it has to scan the new code.
            showQR()
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
        updates.start()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampler.resetAfterWake() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stops the sampler and with it the media adapter's child process, which would otherwise outlive the app
        // until its next write.
        sampler.setRunning(false)
    }

    /// The name of the dashboard files in `directory` (`WebBuild`): an update changes it, and a page left open reloads.
    private static func webBuild(_ directory: URL) -> String {
        var files: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  let data = try? Data(contentsOf: url)
            else { continue }
            files[String(url.path.dropFirst(directory.path.count))] = data
        }
        return WebBuild.fingerprint(files)
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
