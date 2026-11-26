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
    private let claudeMonitor = ClaudeMonitor()
    private let claudeHooks = ClaudeHooksFile()
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
        hub = DashboardHub(mode: settings.mode, lockAndMusicOverWiFi: settings.lockAndMusicOverWiFi, key: key,
                           appName: "PhoneBox \(version)", hostName: Settings.computerName(), powerLimits: powerLimits,
                           build: Self.webBuild(webDirectory), commands: commandRunner)
        server = DashboardServer(webDirectory: webDirectory, hub: hub)
        resumeClaudeSessions()
        menuBar = MenuBarController(mode: settings.mode, lockAndMusicOverWiFi: settings.lockAndMusicOverWiFi,
                                    claudeSessions: settings.claudeSessions, port: settings.port, updates: updates)

        hub.onStreamingChange = { [weak self] streaming in self?.sampler.setRunning(streaming) }
        hub.onClientsChange = { [weak self] streaming, waiting in
            self?.streamingCount = streaming
            self?.waitingForCableCount = waiting
            self?.refreshStatus()
        }
        hub.onAuthenticated = { [weak self] in self?.settings.hasEverPaired = true }
        sampler.onSnapshot = { [weak self] snapshot in self?.hub.broadcast(snapshot) }
        sampler.claudeSessions = { [weak self] in
            guard let self, settings.claudeSessions else { return nil }
            return claudeMonitor.sessions
        }
        server.onStateChange = { [weak self] _ in self?.refreshStatus() }

        menuBar.onShowQR = { [weak self] in self?.showQR() }
        menuBar.onModeChange = { [weak self] mode in
            self?.settings.mode = mode
            self?.hub.mode = mode
        }
        menuBar.onLockAndMusicChange = { [weak self] on in
            self?.settings.lockAndMusicOverWiFi = on
            self?.hub.lockAndMusicOverWiFi = on
        }
        menuBar.onClaudeSessionsChange = { [weak self] on in self?.setClaudeSessions(on) }
        menuBar.onPortChange = { [weak self] port in
            // Saved only once the new port listens: a port in use leaves PhoneBox, and its phones, on the old one.
            self?.server.move(to: port) { [weak self] moved in
                guard let self else { return }
                guard moved else { return portInUse(port) }
                settings.port = port
                menuBar.port = port
                // The phone's link names the port: it has to scan the new code.
                showQR()
            }
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
        // A hook that finds no socket gives up at once.
        claudeMonitor.stop()
    }

    /// At launch (design §14 "Kurulum"): hooks the user deleted turn the feature off; hooks that run a PhoneBox that is
    /// gone (the app was moved), or miss events, are installed again for this one. Hooks of another PhoneBox that is
    /// still there (a test copy) and a file PhoneBox cannot read are left as they are.
    private func resumeClaudeSessions() {
        guard settings.claudeSessions else { return }
        let executable = Bundle.main.executablePath!
        switch claudeHooks.launchCheck(executable: executable) {
        case .removed:
            settings.claudeSessions = false
            return
        case .unreadable:
            Log.app.error("Could not read the Claude Code settings; the hooks are left as they are")
        case .reinstall:
            do {
                try claudeHooks.install(executable: executable)
            } catch {
                Log.app.error("Could not install the Claude Code hooks again: \(Self.reason(error), privacy: .public)")
            }
        case .otherCopy:
            Log.app.notice("The Claude Code hooks run another PhoneBox; they are left to it")
        case .current:
            break
        }
        claudeMonitor.start()
    }

    /// From the menu. On: the hooks first, and only if they are in place the feature. Off: the feature stops even when
    /// the hooks cannot be removed.
    private func setClaudeSessions(_ on: Bool) {
        if on {
            do {
                try claudeHooks.install(executable: Bundle.main.executablePath!)
                settings.claudeSessions = true
                claudeMonitor.start()
            } catch {
                showClaudeSettingsFailure(error)
            }
        } else {
            settings.claudeSessions = false
            claudeMonitor.stop()
            do {
                try claudeHooks.remove()
            } catch {
                showClaudeSettingsFailure(error)
            }
        }
        menuBar.claudeSessions = settings.claudeSessions
    }

    private func showClaudeSettingsFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.claudeSettingsFailedTitle
        alert.informativeText = L10n.claudeSettingsFailedMessage(Self.reason(error))
        NSApp.activate()
        alert.runModal()
    }

    /// Why `ClaudeHooksFile` left the file alone, in a few words.
    private static func reason(_ error: Error) -> String {
        switch error {
        case ClaudeHooksFile.Failure.hooks(.notJSON): return L10n.claudeSettingsNotJSON
        case ClaudeHooksFile.Failure.hooks(.notAnObject): return L10n.claudeSettingsNotAnObject
        case ClaudeHooksFile.Failure.hooks: return L10n.claudeSettingsUnknownHooks
        case let ClaudeHooksFile.Failure.file(error): return error.localizedDescription
        default: return error.localizedDescription
        }
    }

    /// The name of the dashboard files in `directory` (`WebBuild`), keyed by their paths relative to it: an update changes it, and a page left open reloads.
    private static func webBuild(_ directory: URL) -> String {
        var files: [String: Data] = [:]
        // enumerator(atPath:) yields paths relative to `directory`, so a symlink in the bundle's own path
        // (/tmp -> /private/tmp) cannot shift the keys.
        let enumerator = FileManager.default.enumerator(atPath: directory.path)
        while let relative = enumerator?.nextObject() as? String {
            guard enumerator?.fileAttributes?[.type] as? FileAttributeType == .typeRegular,
                  let data = try? Data(contentsOf: directory.appendingPathComponent(relative))
            else { continue }
            files[relative] = data
        }
        return WebBuild.fingerprint(files)
    }

    private func showQR() {
        qrWindow.show(link: settings.personalURL(key: key))
    }

    /// The port chosen in the menu is taken; PhoneBox stays where it is.
    private func portInUse(_ port: UInt16) {
        // Shown from the run loop: run from the listener's callback (a main-queue block), a modal alert would hold up
        // every other main-queue block, the phones' connections among them, until it is closed.
        RunLoop.main.perform {
            MainActor.assumeIsolated {
                let alert = NSAlert()
                alert.messageText = L10n.portInUse(port)
                NSApp.activate()
                alert.runModal()
            }
        }
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
