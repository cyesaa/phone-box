import AppKit
import PhoneBoxCore
import ServiceManagement

/// The alerts the settings ask before they change something (they were the menu's until 0.4.0; their texts are the
/// same).
@MainActor
enum SettingsDialogs {
    /// Before "Lock and Music over Wi-Fi" goes on (design §5): someone who takes over the Wi-Fi network could lock the
    /// Mac and skip songs too.
    static func confirmLockAndMusic() -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.lockAndMusicTitle
        alert.informativeText = L10n.lockAndMusicMessage
        alert.addButton(withTitle: L10n.lockAndMusicAllow)
        alert.addButton(withTitle: L10n.cancel)
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Before "Claude Code Sessions" goes on (design §14 "Kurulum"): it changes ~/.claude/settings.json, and session
    /// titles go to the phone.
    static func confirmClaudeSessions() -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.claudeSessionsTitle
        alert.informativeText = L10n.claudeSessionsMessage
        alert.addButton(withTitle: L10n.claudeSessionsTurnOn)
        alert.addButton(withTitle: L10n.cancel)
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Asks for a port until a valid one is typed (the port typed) or the dialog is cancelled (nil).
    static func askPort(current: UInt16) -> UInt16? {
        var text = String(current)
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
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            text = field.stringValue
            guard let chosen = PortChoice.parse(text) else {
                message = L10n.portInvalid
                continue
            }
            return chosen
        }
    }

    static func confirmReset() -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.resetTitle
        alert.informativeText = L10n.resetMessage
        alert.addButton(withTitle: L10n.resetConfirm)
        alert.addButton(withTitle: L10n.cancel)
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// "Open at Login" (ServiceManagement).
@MainActor
enum LoginItem {
    static var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }

    /// Registers or unregisters PhoneBox; the state afterwards.
    static func toggle() -> LoginItemState {
        let service = SMAppService.mainApp
        // Waiting for approval: a click shows the alert below again instead of withdrawing the request the user is to
        // approve.
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
        guard service.status == .requiresApproval else { return state }
        let alert = NSAlert()
        alert.messageText = L10n.loginApprovalTitle
        alert.informativeText = L10n.loginApprovalMessage
        alert.addButton(withTitle: L10n.loginOpenSettings)
        alert.addButton(withTitle: L10n.cancel)
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { openSystemSettings() }
        return state
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
