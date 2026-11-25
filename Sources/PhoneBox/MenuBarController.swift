import AppKit
import PhoneBoxCore
import ServiceManagement

/// The menu bar icon and its menu (design §8 "Menü çubuğu"). Gray phone: nobody is receiving data;
/// green phone: at least one phone is.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    var onShowQR: (() -> Void)?
    var onModeChange: ((AccessMode) -> Void)?
    var onResetPairing: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusLine = NSMenuItem()
    private let cableItem = NSMenuItem()
    private let alwaysItem = NSMenuItem()
    private let loginItem = NSMenuItem()
    private var mode: AccessMode

    init(mode: AccessMode) {
        self.mode = mode
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
        loginItem.title = L10n.launchAtLogin
        loginItem.action = #selector(toggleLaunchAtLogin)
        let resetItem = NSMenuItem(title: L10n.resetPairing, action: #selector(resetPairing), keyEquivalent: "")
        let quitItem = NSMenuItem(title: L10n.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        for item in [qrItem, cableItem, alwaysItem, loginItem, resetItem] { item.target = self }

        let menu = NSMenu()
        menu.delegate = self
        for item in [statusLine, .separator(), qrItem, .separator(), modeHeader, cableItem, alwaysItem, .separator(),
                     loginItem, resetItem, .separator(), quitItem] {
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
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func showQR() { onShowQR?() }
    @objc private func chooseCable() { setMode(.cable) }
    @objc private func chooseAlways() { setMode(.always) }

    private func setMode(_ newMode: AccessMode) {
        mode = newMode
        onModeChange?(newMode)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.app.error("Open at Login failed: \(error.localizedDescription, privacy: .public)")
        }
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
}
