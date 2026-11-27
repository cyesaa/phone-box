import AppKit
import PhoneBoxCore

/// The settings window's sections (design §8 "Ayarlar penceresi").
enum SettingsSection: String, CaseIterable, Identifiable {
    case connection, pairing, claude, general

    var id: Self { self }

    var title: String {
        switch self {
        case .connection: return L10n.sectionConnection
        case .pairing: return L10n.sectionPairing
        case .claude: return L10n.sectionClaude
        case .general: return L10n.sectionGeneral
        }
    }
}

/// "Open at Login" as macOS reports it (`SMAppService`).
enum LoginItemState: Equatable {
    case off, on
    /// Registered, but the user has to allow it in System Settings → General → Login Items.
    case needsApproval
}

/// What the settings window asks of the rest of the app: the flows the menu used to run, with their alerts. `AppDelegate`
/// fills it in; the defaults do nothing (the sample, the tests).
@MainActor
struct SettingsActions {
    var applyMode: @MainActor (AccessMode) -> Void = { _ in }
    /// The alert before "Lock and Music over Wi-Fi" goes on; true to go ahead.
    var confirmLockAndMusic: @MainActor () -> Bool = { true }
    var applyLockAndMusic: @MainActor (Bool) -> Void = { _ in }
    /// The alert before "Claude Code Sessions" goes on; true to go ahead.
    var confirmClaudeSessions: @MainActor () -> Bool = { true }
    /// Installs (true) or removes the hooks: whether the feature is on afterwards, and why the file was left alone.
    var changeClaudeSessions: @MainActor (Bool) -> (on: Bool, failure: String?) = { ($0, nil) }
    var revealClaudeSettings: @MainActor () -> Void = {}
    /// The port dialog: the port typed, or nil when it was cancelled.
    var askPort: @MainActor (UInt16) -> UInt16? = { _ in nil }
    /// Moves the dashboard to the port; `completion` gets the new personal link once it listens there, nil when the port
    /// is in use.
    var movePort: @MainActor (UInt16, @escaping @MainActor (String?) -> Void) -> Void = { _, completion in completion(nil) }
    /// The reset alert; true to go ahead.
    var confirmReset: @MainActor () -> Bool = { true }
    /// A new pairing key; the new personal link.
    var resetPairing: @MainActor () -> String = { "" }
    var copyLink: @MainActor (String) -> Void = { _ in }
    var showQR: @MainActor () -> Void = {}
    /// Today's "Open at Login" flow (register, unregister, or the approval alert); the state afterwards.
    var toggleLaunchAtLogin: @MainActor () -> LoginItemState = { .off }
    var openLoginItems: @MainActor () -> Void = {}
    var checkForUpdates: @MainActor () -> Void = {}
    var installUpdate: @MainActor () -> Void = {}
    var openRepository: @MainActor () -> Void = {}
    var openLicenses: @MainActor () -> Void = {}
}

/// What the settings window shows, and what its controls do (design §8 "Ayarlar penceresi"). `AppDelegate` feeds it
/// and gives it `actions`; the view reads only this.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var section: SettingsSection = .connection

    // Connection
    @Published var status: ConnectionStatus = .waiting
    @Published var phones = PhoneCounts()
    @Published var mode: AccessMode
    /// The saved setting; the switch shows it only in "always" mode.
    @Published var lockAndMusic: Bool
    @Published var port: UInt16

    // Pairing
    @Published var link: String {
        didSet {
            guard link != oldValue else { return }
            qrImage = Self.qrImage(link)
            copied = false
        }
    }
    @Published private(set) var qrImage: NSImage?
    /// "Copy Link" reads "Copied" until the link changes or the window opens again.
    @Published var copied = false

    // Claude Code
    @Published var claudeOn: Bool
    @Published var claudeHooksInstalled = false
    @Published var claudeSessions = 0
    @Published var claudeWaiting = 0
    /// Why the last install or removal left `~/.claude/settings.json` alone; nil once one worked.
    @Published var claudeFailure: String?
    @Published var claudeSettingsExists = false

    // General
    @Published var loginItem: LoginItemState = .off
    let version: String
    @Published var update: UpdateService.Status = .idle
    /// The version "Install…" installs: also while a check runs, when one was found before.
    @Published var availableUpdate: String?
    @Published var lastChecked: Date?
    let checksAutomatically: Bool

    var actions = SettingsActions()

    init(mode: AccessMode, lockAndMusic: Bool, port: UInt16, link: String, claudeOn: Bool, version: String,
         checksAutomatically: Bool) {
        self.mode = mode
        self.lockAndMusic = lockAndMusic
        self.port = port
        self.link = link
        self.claudeOn = claudeOn
        self.version = version
        self.checksAutomatically = checksAutomatically
        qrImage = Self.qrImage(link)
    }

    private static func qrImage(_ link: String) -> NSImage? {
        QRWindowController.qrImage(for: link, size: 132)
    }

    // MARK: Connection

    func setMode(_ newMode: AccessMode) {
        guard newMode != mode else { return }
        mode = newMode
        actions.applyMode(newMode)
    }

    /// The switch can be used only in "always" mode (`AccessMode.offersLockAndMusicOverWiFi`).
    var lockAndMusicEnabled: Bool { mode.offersLockAndMusicOverWiFi }
    /// In cable mode the switch shows off, whatever is saved.
    var lockAndMusicShown: Bool { lockAndMusicEnabled && lockAndMusic }

    /// Turning it on asks first (design §5); turning it off asks nothing.
    func setLockAndMusic(_ on: Bool) {
        guard lockAndMusicEnabled, on != lockAndMusic else { return }
        if on, !actions.confirmLockAndMusic() { return }
        lockAndMusic = on
        actions.applyLockAndMusic(on)
    }

    /// The port dialog; the port is saved, and the link changes, only once the dashboard listens there. The same port
    /// moves nothing, unless it is in use: then it is tried again (design §9).
    func changePort() {
        guard let chosen = actions.askPort(port), chosen != port || status == .portInUse(chosen) else { return }
        actions.movePort(chosen) { [weak self] newLink in
            guard let self, let newLink else { return }
            port = chosen
            link = newLink
        }
    }

    // MARK: Pairing

    func copyLink() {
        actions.copyLink(link)
        copied = true
    }

    func showQR() { actions.showQR() }

    func resetPairing() {
        guard actions.confirmReset() else { return }
        link = actions.resetPairing()
    }

    // MARK: Claude Code

    /// Turning it on asks first and installs the hooks (design §14 "Kurulum"); turning it off removes them.
    func setClaudeSessions(_ on: Bool) {
        guard on != claudeOn else { return }
        if on, !actions.confirmClaudeSessions() { return }
        let outcome = actions.changeClaudeSessions(on)
        claudeFailure = outcome.failure
        claudeOn = outcome.on
    }

    var claudeStatusText: String {
        SettingsText.claudeStatus(on: claudeOn, hooksInstalled: claudeHooksInstalled, sessions: claudeSessions,
                                  waiting: claudeWaiting)
    }

    var claudeFailureText: String? { claudeFailure.map(SettingsText.claudeFailure) }

    func revealClaudeSettings() { actions.revealClaudeSettings() }

    // MARK: General

    var launchAtLogin: Bool { loginItem != .off }

    func setLaunchAtLogin(_ on: Bool) {
        guard on != launchAtLogin else { return }
        loginItem = actions.toggleLaunchAtLogin()
    }

    func openLoginItems() { actions.openLoginItems() }

    func updateText(now: Date) -> String {
        SettingsText.update(status: update, lastChecked: lastChecked, now: now, automatic: checksAutomatically)
    }

    /// Off while the installer runs.
    var canCheckForUpdates: Bool { update != .installing }

    func checkForUpdates() { actions.checkForUpdates() }
    func installUpdate() { actions.installUpdate() }
    func openRepository() { actions.openRepository() }
    func openLicenses() { actions.openLicenses() }
}

extension SettingsModel {
    /// A model with made-up values and no actions, for previews and for the test that draws the window.
    static var sample: SettingsModel {
        let model = SettingsModel(mode: .always, lockAndMusic: true, port: 4747,
                                  link: "http://MacBook-Pro.local:4747/#k=c2FtcGxlLWtleS1mb3ItdGhlLXByZXZpZXctb25seQ",
                                  claudeOn: true, version: "0.4.0", checksAutomatically: true)
        let phones = PhoneCounts(onCable: 1, overWiFi: 0, waitingForCable: 0)
        model.phones = phones
        model.status = .streaming(phones)
        model.claudeHooksInstalled = true
        model.claudeSessions = 3
        model.claudeWaiting = 1
        model.claudeSettingsExists = true
        model.update = .upToDate
        model.lastChecked = Date().addingTimeInterval(-5 * 60)
        return model
    }
}
