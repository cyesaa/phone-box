import AppKit
import PhoneBoxCore
import ServiceManagement

/// The menu bar icon and its menu (design §8 "Menü çubuğu"). Gray phone: nobody is receiving data;
/// green phone: at least one phone is.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    var onShowQR: (() -> Void)?
    var onModeChange: ((AccessMode) -> Void)?
    var onPortChange: ((UInt16) -> Void)?
    var onResetPairing: (() -> Void)?
    /// The port shown in the "Port…" item and offered in its dialog.
    var port: UInt16

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusLine = NSMenuItem()
    private let cableItem = NSMenuItem()
    private let alwaysItem = NSMenuItem()
    private let portItem = NSMenuItem()
    private let loginItem = NSMenuItem()
    private let installItem = NSMenuItem()
    private let updates: UpdateService
    private var mode: AccessMode

    init(mode: AccessMode, port: UInt16, updates: UpdateService) {
        self.mode = mode
        self.port = port
        self.updates = updates
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "PhoneBox")
        statusLine.isEnabled = false

        let qrItem = NSMenuItem(title: L10n.showQR, action: #selector(showQR), keyEquivalent: "")
        let modeHeader = NSMenuItem(title: L10n.modeHeader, action: nil, keyEquivalent: "")
        modeHeader.isEnabled = false
        cableItem.title = L10n.modeCable
        cableItem.action = #selector(chooseCable)
        alwaysItem.title = L10n.modeAlways
        alwaysItem.action = #selector(chooseAlways)
        portItem.action = #selector(choosePort)
        loginItem.title = L10n.launchAtLogin
        loginItem.action = #selector(toggleLaunchAtLogin)
        let resetItem = NSMenuItem(title: L10n.resetPairing, action: #selector(resetPairing), keyEquivalent: "")
        installItem.action = #selector(installUpdate)
        installItem.isHidden = true
        let checkItem = NSMenuItem(title: L10n.checkForUpdates, action: #selector(checkForUpdates), keyEquivalent: "")
        let quitItem = NSMenuItem(title: L10n.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        for item in [qrItem, cableItem, alwaysItem, portItem, loginItem, resetItem, installItem, checkItem] {
            item.target = self
        }

        let menu = NSMenu()
        menu.delegate = self
        for item in [statusLine, .separator(), qrItem, .separator(), modeHeader, cableItem, alwaysItem, .separator(),
                     portItem, loginItem, resetItem, .separator(), installItem, checkItem, .separator(), quitItem] {
            menu.addItem(item)
        }
        statusItem.menu = menu
        update(status: L10n.statusWaiting, active: false)
    }

    func update(status: String, active: Bool) {
        statusLine.title = status
        statusItem.button?.contentTintColor = active ? .systemGreen : .secondaryLabelColor
        statusItem.button?.toolTip = "PhoneBox: \(status)"
    }

    func menuWillOpen(_ menu: NSMenu) {
        cableItem.state = mode == .cable ? .on : .off
        alwaysItem.state = mode == .always ? .on : .off
        portItem.title = L10n.portItem(port)
        switch SMAppService.mainApp.status {
        case .enabled: loginItem.state = .on
        case .requiresApproval: loginItem.state = .mixed
        default: loginItem.state = .off
        }
        if let release = updates.availableRelease {
            installItem.title = L10n.installUpdate(release.version.description)
            installItem.isHidden = false
        } else {
            installItem.isHidden = true
        }
    }

    @objc private func showQR() { onShowQR?() }
    @objc private func chooseCable() { setMode(.cable) }
    @objc private func chooseAlways() { setMode(.always) }

    private func setMode(_ newMode: AccessMode) {
        mode = newMode
        onModeChange?(newMode)
    }

    /// Asks for a port until a valid one is typed or the dialog is cancelled.
    @objc private func choosePort() {
        var text = String(port)
        var message = L10n.portMessage
        while true {
            let alert = NSAlert()
            alert.messageText = L10n.portTitle
            alert.informativeText = message
            alert.addButton(withTitle: L10n.portUse)
            alert.addButton(withTitle: L10n.cancel)
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
            field.stringValue = text
            field.placeholderString = String(Settings.defaultPort)
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            text = field.stringValue
            guard let chosen = PortChoice.parse(text) else {
                message = L10n.portInvalid
                continue
            }
            if chosen != port { onPortChange?(chosen) }
            return
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        // Waiting for approval (the mixed item): a click shows the alert below again instead of withdrawing the
        // request the user is to approve.
        if service.status != .requiresApproval {
            do {
                if service.status == .enabled {
                    try service.unregister()
                } else {
                    try service.register()
                }
            } catch {
                Log.app.error("Open at Login failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        // macOS may want the user to allow it in System Settings first (design §8 "Menü çubuğu").
        guard service.status == .requiresApproval else { return }
        let alert = NSAlert()
        alert.messageText = L10n.loginApprovalTitle
        alert.informativeText = L10n.loginApprovalMessage
        alert.addButton(withTitle: L10n.loginOpenSettings)
        alert.addButton(withTitle: L10n.cancel)
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { SMAppService.openSystemSettingsLoginItems() }
    }

    @objc private func resetPairing() {
        let alert = NSAlert()
        alert.messageText = L10n.resetTitle
        alert.informativeText = L10n.resetMessage
        alert.addButton(withTitle: L10n.resetConfirm)
        alert.addButton(withTitle: L10n.cancel)
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { onResetPairing?() }
    }

    @objc private func installUpdate() { updates.installWithConfirmation() }
    @objc private func checkForUpdates() { updates.check(userInitiated: true) }
}
