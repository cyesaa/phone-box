import AppKit

/// The menu bar icon and its menu (design §8 "Menü çubuğu"). Gray phone: nobody is receiving data;
/// green phone: at least one phone is. The settings are in the settings window.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    var onShowSettings: (() -> Void)?
    var onShowQR: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusLine = NSMenuItem()
    private let installItem = NSMenuItem()
    private let updates: UpdateService

    init(updates: UpdateService) {
        self.updates = updates
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "PhoneBox")
        let menu = Self.makeMenu(statusLine: statusLine, installItem: installItem, target: self)
        menu.delegate = self
        statusItem.menu = menu
        update(status: L10n.statusWaiting, active: false)
    }

    /// Status line, "Settings…" (⌘,), "Show QR Code…", the update items, "Quit". `installItem` stays hidden until an
    /// update is available.
    static func makeMenu(statusLine: NSMenuItem, installItem: NSMenuItem, target: MenuBarController?) -> NSMenu {
        statusLine.isEnabled = false
        let settingsItem = NSMenuItem(title: L10n.settings, action: #selector(MenuBarController.showSettings),
                                      keyEquivalent: ",")
        let qrItem = NSMenuItem(title: L10n.showQR, action: #selector(MenuBarController.showQR), keyEquivalent: "")
        installItem.action = #selector(MenuBarController.installUpdate)
        installItem.isHidden = true
        let checkItem = NSMenuItem(title: L10n.checkForUpdates, action: #selector(MenuBarController.checkForUpdates),
                                   keyEquivalent: "")
        let quitItem = NSMenuItem(title: L10n.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        for item in [settingsItem, qrItem, installItem, checkItem] {
            item.target = target
        }

        let menu = NSMenu()
        for item in [statusLine, .separator(), settingsItem, qrItem, .separator(), installItem, checkItem, .separator(),
                     quitItem] {
            menu.addItem(item)
        }
        return menu
    }

    func update(status: String, active: Bool) {
        statusLine.title = status
        statusItem.button?.contentTintColor = active ? .systemGreen : .secondaryLabelColor
        statusItem.button?.toolTip = "PhoneBox: \(status)"
    }

    func menuWillOpen(_ menu: NSMenu) {
        if let release = updates.availableRelease {
            installItem.title = L10n.installUpdate(release.version.description)
            installItem.isHidden = false
        } else {
            installItem.isHidden = true
        }
    }

    @objc private func showSettings() { onShowSettings?() }
    @objc private func showQR() { onShowQR?() }
    @objc private func installUpdate() { updates.installWithConfirmation() }
    @objc private func checkForUpdates() { updates.check(userInitiated: true) }
}
