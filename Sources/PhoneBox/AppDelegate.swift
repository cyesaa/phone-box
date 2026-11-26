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
    private var settingsModel: SettingsModel!
    private var settingsWindow: SettingsWindowController!
    private var phones = PhoneCounts()
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
        let claudeFailure = resumeClaudeSessions()
        menuBar = MenuBarController(updates: updates)
        settingsModel = SettingsModel(mode: settings.mode, lockAndMusic: settings.lockAndMusicOverWiFi, port: settings.port,
                                      link: settings.personalURL(key: key), claudeOn: settings.claudeSessions,
                                      version: version, checksAutomatically: updates.checksAutomatically)
        settingsModel.claudeFailure = claudeFailure
        settingsModel.actions = makeSettingsActions()
        settingsWindow = SettingsWindowController(model: settingsModel)
        // Open at Login and the Claude Code settings file tell nobody when they change: read each time the window
        // comes to the front.
        settingsWindow.onShow = { [weak self] in
            self?.showValue(\.loginItem, LoginItem.state)
            self?.refreshClaudeFile()
        }

        hub.onStreamingChange = { [weak self] streaming in self?.sampler.setRunning(streaming) }
        hub.onClientsChange = { [weak self] counts in
            self?.phones = counts
            self?.refreshStatus()
        }
        hub.onAuthenticated = { [weak self] in self?.settings.hasEverPaired = true }
        sampler.onSnapshot = { [weak self] snapshot in self?.hub.broadcast(snapshot) }
        sampler.claudeSessions = { [weak self] in
            guard let self, settings.claudeSessions else { return nil }
            return claudeMonitor.sessions
        }
        claudeMonitor.onChange = { [weak self] in self?.refreshClaudeSessions() }
        updates.onChange = { [weak self] in self?.refreshUpdate() }
        server.onStateChange = { [weak self] _ in self?.refreshStatus() }

        menuBar.onShowSettings = { [weak self] in self?.settingsWindow.show() }
        menuBar.onShowQR = { [weak self] in self?.showQR() }

        usbWatcher.onChange = { [weak self] pluggedIn in self?.iPhoneChanged(pluggedIn: pluggedIn) }
        usbWatcher.onAvailabilityChange = { [weak self] _ in self?.refreshStatus() }
        usbWatcher.start()
        server.start(port: settings.port)
        updates.start()
        refreshClaudeSessions()
        refreshUpdate()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampler.resetAfterWake() }
        }
    }

    /// Opening PhoneBox again while it runs (Finder, Launchpad, `open`) shows the settings window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
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
    /// still there (a test copy) and a file PhoneBox cannot read are left as they are. Returns why installing them again
    /// failed, for the settings window.
    private func resumeClaudeSessions() -> String? {
        guard settings.claudeSessions else { return nil }
        let executable = Bundle.main.executablePath!
        var failure: String?
        switch claudeHooks.launchCheck(executable: executable) {
        case .removed:
            settings.claudeSessions = false
            return nil
        case .unreadable:
            Log.app.error("Could not read the Claude Code settings, or there are none; the hooks are left as they are")
        case .reinstall:
            do {
                try claudeHooks.install(executable: executable)
            } catch {
                failure = Self.reason(error)
                Log.app.error("Could not install the Claude Code hooks again: \(Self.reason(error), privacy: .public)")
            }
        case .otherCopy:
            Log.app.notice("The Claude Code hooks run another PhoneBox; they are left to it")
        case .current:
            break
        }
        claudeMonitor.start()
        return failure
    }

    /// From the settings window. On: the hooks first, and only if they are in place the feature. Off: the feature stops
    /// even when the hooks cannot be removed. Returns whether the feature is on, and why the file was left alone.
    private func setClaudeSessions(_ on: Bool) -> (on: Bool, failure: String?) {
        var failure: String?
        if on {
            do {
                try claudeHooks.install(executable: Bundle.main.executablePath!)
                settings.claudeSessions = true
                claudeMonitor.start()
            } catch {
                failure = Self.reason(error)
                showClaudeSettingsFailure(error)
            }
        } else {
            settings.claudeSessions = false
            claudeMonitor.stop()
            do {
                try claudeHooks.remove()
            } catch {
                failure = Self.reason(error)
                showClaudeSettingsFailure(error)
            }
        }
        refreshClaudeFile()
        return (settings.claudeSessions, failure)
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

    /// The flows behind the settings window's controls (they were the menu's until 0.4.0).
    private func makeSettingsActions() -> SettingsActions {
        var actions = SettingsActions()
        actions.applyMode = { [weak self] mode in
            self?.settings.mode = mode
            self?.hub.mode = mode
        }
        actions.confirmLockAndMusic = { SettingsDialogs.confirmLockAndMusic() }
        actions.applyLockAndMusic = { [weak self] on in
            self?.settings.lockAndMusicOverWiFi = on
            self?.hub.lockAndMusicOverWiFi = on
        }
        actions.confirmClaudeSessions = { SettingsDialogs.confirmClaudeSessions() }
        actions.changeClaudeSessions = { [weak self] on in self?.setClaudeSessions(on) ?? (on: false, failure: nil) }
        actions.revealClaudeSettings = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.activateFileViewerSelecting([claudeHooks.realURL()])
        }
        actions.askPort = { SettingsDialogs.askPort(current: $0) }
        actions.movePort = { [weak self] port, completion in self?.movePort(to: port, completion: completion) }
        actions.confirmReset = { SettingsDialogs.confirmReset() }
        actions.resetPairing = { [weak self] in self?.resetPairing() ?? "" }
        actions.copyLink = { link in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link, forType: .string)
        }
        actions.showQR = { [weak self] in self?.showQR() }
        actions.toggleLaunchAtLogin = { LoginItem.toggle() }
        actions.openLoginItems = { LoginItem.openSystemSettings() }
        actions.checkForUpdates = { [weak self] in self?.updates.check(userInitiated: true) }
        actions.installUpdate = { [weak self] in self?.updates.installWithConfirmation() }
        actions.openRepository = { NSWorkspace.shared.open(UpdateCheck.repositoryURL) }
        actions.openLicenses = { Self.openLicenses() }
        return actions
    }

    /// Saved only once the new port listens: a port in use leaves PhoneBox, and its phones, on the old one.
    private func movePort(to port: UInt16, completion: @escaping @MainActor (String?) -> Void) {
        server.move(to: port) { [weak self] moved in
            guard let self else { return }
            guard moved else {
                portInUse(port)
                return completion(nil)
            }
            settings.port = port
            completion(settings.personalURL(key: key))
            // The phone's link names the port: it has to scan the new code.
            showQR()
        }
    }

    /// A new pairing key: every phone has to scan the new QR code. Returns the new link.
    private func resetPairing() -> String {
        key = PairingStore.reset()
        settings.hasEverPaired = false
        hub.replaceKey(key)
        showQR()
        return settings.personalURL(key: key)
    }

    /// The bundled licence and notices, in TextEdit (a .md file may have no app of its own).
    private static func openLicenses() {
        let files = ["LICENSE", "THIRD_PARTY_NOTICES.md"].compactMap { Bundle.main.url(forResource: $0, withExtension: nil) }
        guard !files.isEmpty else { return }
        let workspace = NSWorkspace.shared
        if let textEdit = workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            workspace.open(files, withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        } else {
            workspace.activateFileViewerSelecting(files)
        }
    }

    /// The port chosen in the settings is taken; PhoneBox stays where it is.
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

    /// The menu's status line and the settings window's status row.
    private func refreshStatus() {
        var portInUse: UInt16?
        if case let .failed(port, _) = server.state { portInUse = port }
        let status = ConnectionStatus.decide(portInUse: portInUse, phones: phones, usbAvailable: usbWatcher.isAvailable)
        menuBar.update(status: SettingsText.menuLine(status), active: status.isActive)
        showValue(\.status, status)
        showValue(\.phones, phones)
    }

    private func refreshClaudeSessions() {
        let on = settings.claudeSessions
        showValue(\.claudeSessions, on ? claudeMonitor.sessionCount : 0)
        showValue(\.claudeWaiting, on ? claudeMonitor.waitingCount : 0)
    }

    /// Whether PhoneBox's hooks are in ~/.claude/settings.json, and whether the file is there at all.
    private func refreshClaudeFile() {
        showValue(\.claudeHooksInstalled, !claudeHooks.installedCommands().isEmpty)
        showValue(\.claudeSettingsExists, FileManager.default.fileExists(atPath: claudeHooks.realURL().path))
    }

    private func refreshUpdate() {
        showValue(\.update, updates.status)
        showValue(\.availableUpdate, updates.availableRelease?.version.description)
        showValue(\.lastChecked, updates.lastChecked)
    }

    /// Sets what the settings window shows only when it changed: every set redraws the window.
    private func showValue<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<SettingsModel, Value>, _ value: Value) {
        guard let settingsModel, settingsModel[keyPath: keyPath] != value else { return }
        settingsModel[keyPath: keyPath] = value
    }
}
