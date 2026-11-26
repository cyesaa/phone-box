import Foundation
import PhoneBoxCore

/// What the menu's status line and the settings window's status row say (design §8 "Menü çubuğu").
enum ConnectionStatus: Equatable {
    case portInUse(UInt16)
    case streaming(PhoneCounts)
    case waitingForCable
    case usbUnavailable
    case waiting

    /// A port that could not be opened comes first, then phones receiving data, then phones waiting for the cable.
    static func decide(portInUse: UInt16?, phones: PhoneCounts, usbAvailable: Bool) -> ConnectionStatus {
        if let portInUse { return .portInUse(portInUse) }
        if phones.streaming > 0 { return .streaming(phones) }
        if phones.waitingForCable > 0 { return .waitingForCable }
        return usbAvailable ? .waiting : .usbUnavailable
    }

    /// The menu bar icon is green.
    var isActive: Bool {
        if case .streaming = self { return true }
        return false
    }
}

/// The settings window's texts that depend on the state, and the menu's status line; pure, so the tests check them.
enum SettingsText {
    static func menuLine(_ status: ConnectionStatus) -> String {
        switch status {
        case let .streaming(phones): return L10n.statusStreaming(phones.streaming)
        default: return title(status)
        }
    }

    /// The status row's line; the number of phones is on the line under it.
    static func title(_ status: ConnectionStatus) -> String {
        switch status {
        case let .portInUse(port): return L10n.statusPortInUse(port)
        case .streaming: return L10n.statusConnected
        case .waitingForCable: return L10n.statusWaitingForCable
        case .usbUnavailable: return L10n.statusUSBUnavailable
        case .waiting: return L10n.statusWaiting
        }
    }

    /// Under the status row: how many phones get data and over what, or what to do.
    static func detail(_ status: ConnectionStatus) -> String? {
        switch status {
        case .portInUse: return L10n.statusPortInUseHint
        case let .streaming(phones): return self.phones(onCable: phones.onCable, overWiFi: phones.overWiFi)
        case .waitingForCable: return L10n.statusWaitingForCableHint
        case .usbUnavailable: return nil
        case .waiting: return L10n.statusWaitingHint
        }
    }

    /// "2 cihaz · 1 kabloyla, 1 Wi-Fi'den"; nil without phones.
    static func phones(onCable: Int, overWiFi: Int) -> String? {
        switch (onCable, overWiFi) {
        case (0, 0): return nil
        case (_, 0): return L10n.phonesOnCable(onCable)
        case (0, _): return L10n.phonesOverWiFi(overWiFi)
        default: return L10n.phonesOnBoth(onCable + overWiFi, cable: onCable, wifi: overWiFi)
        }
    }

    /// The pairing section's count: every phone connected now, also the ones on Wi-Fi waiting for the cable.
    static func connectedNow(_ phones: PhoneCounts) -> String {
        guard let text = self.phones(onCable: phones.onCable, overWiFi: phones.overWiFi + phones.waitingForCable) else {
            return L10n.connectedNone
        }
        return L10n.connectedNow(text)
    }

    /// "Hook'lar kurulu · 3 oturum · 1 seni bekliyor", or "Kapalı".
    static func claudeStatus(on: Bool, hooksInstalled: Bool, sessions: Int, waiting: Int) -> String {
        guard on else { return L10n.claudeOff }
        guard hooksInstalled else { return L10n.claudeNotInstalled }
        var parts = [L10n.claudeInstalled(sessions)]
        if waiting > 0 { parts.append(L10n.claudeWaiting(waiting)) }
        return parts.joined(separator: " · ")
    }

    /// Why the last install or removal left `~/.claude/settings.json` alone, under the status.
    static func claudeFailure(_ reason: String) -> String {
        "\(L10n.claudeSettingsFailedTitle): \(reason)"
    }

    /// "Güncel · son denetim 5 dk önce · 12 saatte bir kendiliğinden denetler".
    static func update(status: UpdateService.Status, lastChecked: Date?, now: Date, automatic: Bool) -> String {
        var parts: [String] = []
        var showsLastCheck = true
        switch status {
        case .checking:
            return L10n.updateLineChecking
        case .installing:
            return L10n.updateLineInstalling
        case .upToDate:
            parts.append(L10n.updateLineUpToDate)
        case let .available(release):
            parts.append(L10n.updateLineAvailable(release.version.description))
        case .failed:
            parts.append(L10n.updateLineFailed)
        case .idle:
            if lastChecked == nil {
                parts.append(L10n.updateLineNever)
                showsLastCheck = false
            }
        }
        if showsLastCheck, let lastChecked {
            parts.append(L10n.updateLineChecked(ago(now.timeIntervalSince(lastChecked))))
        }
        if automatic { parts.append(L10n.updateLineAutomatic) }
        let line = parts.joined(separator: " · ")
        // "son denetim …" can come first (the installer left this copy running).
        return capitalized(line)
    }

    /// The first letter in capitals by the current language's rules (Turkish "i" becomes "İ").
    static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased(with: L10n.locale) + text.dropFirst()
    }

    /// "az önce", "5 dk önce", "2 sa önce", "3 gün önce": whole units, rounded down.
    static func ago(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: return L10n.agoNow
        case ..<3600: return L10n.agoMinutes(Int(seconds / 60))
        case ..<86400: return L10n.agoHours(Int(seconds / 3600))
        default: return L10n.agoDays(Int(seconds / 86400))
        }
    }
}
