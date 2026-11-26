import Foundation

/// Menu and window texts; English and Turkish in `Resources/{en,tr}.lproj/Localizable.strings`.
enum L10n {
    /// Where the texts come from: the app's bundle. The tests, whose runner has no texts, read them from one language's
    /// folder in `Resources` with `L10n.$bundle.withValue(…)`.
    @TaskLocal static var bundle: Bundle = .main

    private static func text(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// The current language's locale, for case changes ("i" becomes "İ" in Turkish).
    static var locale: Locale { Locale(identifier: text("locale.identifier")) }

    static var statusWaiting: String { text("status.waiting") }
    static func statusStreaming(_ count: Int) -> String { String(format: text("status.streaming"), count) }
    static var statusWaitingForCable: String { text("status.waitingForCable") }
    static func statusPortInUse(_ port: UInt16) -> String { String(format: text("status.portInUse"), Int(port)) }
    static var statusUSBUnavailable: String { text("status.usbUnavailable") }

    static var settings: String { text("menu.settings") }
    static var showQR: String { text("menu.showQR") }
    static var launchAtLogin: String { text("menu.launchAtLogin") }
    static var checkForUpdates: String { text("menu.checkForUpdates") }
    static func installUpdate(_ version: String) -> String { String(format: text("menu.installUpdate"), version) }
    static var quit: String { text("menu.quit") }

    static var portTitle: String { text("port.title") }
    static var portMessage: String { text("port.message") }
    static var portInvalid: String { text("port.invalid") }
    static var portUse: String { text("port.use") }
    static func portInUse(_ port: UInt16) -> String { String(format: text("port.inUse"), Int(port)) }

    static var loginApprovalTitle: String { text("login.approvalTitle") }
    static var loginApprovalMessage: String { text("login.approvalMessage") }
    static var loginOpenSettings: String { text("login.openSettings") }

    static var lockAndMusicTitle: String { text("lockAndMusic.title") }
    static var lockAndMusicMessage: String { text("lockAndMusic.message") }
    static var lockAndMusicAllow: String { text("lockAndMusic.allow") }

    static var claudeSessionsTitle: String { text("claudeSessions.title") }
    static var claudeSessionsMessage: String { text("claudeSessions.message") }
    static var claudeSessionsTurnOn: String { text("claudeSessions.turnOn") }
    static var claudeSettingsFailedTitle: String { text("claudeSessions.failedTitle") }
    static func claudeSettingsFailedMessage(_ reason: String) -> String {
        String(format: text("claudeSessions.failedMessage"), reason)
    }
    static var claudeSettingsNotJSON: String { text("claudeSessions.notJSON") }
    static var claudeSettingsNotAnObject: String { text("claudeSessions.notAnObject") }
    static var claudeSettingsUnknownHooks: String { text("claudeSessions.unknownHooks") }

    static func updateUpToDate(_ version: String) -> String { String(format: text("update.upToDate"), version) }
    static var updateCheckFailed: String { text("update.checkFailed") }
    static var updateCheckFailedHint: String { text("update.checkFailedHint") }
    static func updateAvailableTitle(_ version: String) -> String { String(format: text("update.availableTitle"), version) }
    static func updateAvailableInfo(_ version: String) -> String { String(format: text("update.availableInfo"), version) }
    static var updateInstall: String { text("update.install") }
    static var updateReleaseNotes: String { text("update.releaseNotes") }
    static var updateLater: String { text("update.later") }
    static var updateInstallFailed: String { text("update.installFailed") }
    static var updateInstallFailedHint: String { text("update.installFailedHint") }

    static var resetTitle: String { text("reset.title") }
    static var resetMessage: String { text("reset.message") }
    static var resetConfirm: String { text("reset.confirm") }
    static var cancel: String { text("cancel") }

    static var qrTitle: String { text("qr.title") }
    static var qrInstructions: String { text("qr.instructions") }
    static var qrCopy: String { text("qr.copy") }
    static var qrCopied: String { text("qr.copied") }

    // The settings window (design §8 "Ayarlar penceresi").
    static var sectionConnection: String { text("settings.connection") }
    static var sectionPairing: String { text("settings.pairing") }
    static var sectionClaude: String { text("settings.claude") }
    static var sectionGeneral: String { text("settings.general") }

    static var statusConnected: String { text("settings.status.connected") }
    static var statusWaitingHint: String { text("settings.status.waitingHint") }
    static var statusWaitingForCableHint: String { text("settings.status.waitingForCableHint") }
    static var statusPortInUseHint: String { text("settings.status.portInUseHint") }
    static func phonesOnCable(_ count: Int) -> String { String(format: text("settings.phones.cable"), count) }
    static func phonesOverWiFi(_ count: Int) -> String { String(format: text("settings.phones.wifi"), count) }
    static func phonesOnBoth(_ count: Int, cable: Int, wifi: Int) -> String {
        String(format: text("settings.phones.both"), count, cable, wifi)
    }
    static var data: String { text("settings.data") }
    static var sendData: String { text("settings.sendData") }
    static var sendDataCaption: String { text("settings.sendData.caption") }
    static var modeCable: String { text("settings.mode.cable") }
    static var modeAlways: String { text("settings.mode.always") }
    static var lockAndMusic: String { text("settings.lockAndMusic") }
    static var lockAndMusicCaption: String { text("settings.lockAndMusic.caption") }
    static var network: String { text("settings.network") }
    static var port: String { text("settings.port") }
    static var portCaption: String { text("settings.port.caption") }
    static var portChange: String { text("settings.port.change") }

    static var qrEnlarge: String { text("settings.qr.enlarge") }
    static var pairedPhones: String { text("settings.phones") }
    static func connectedNow(_ phones: String) -> String { String(format: text("settings.phones.now"), phones) }
    static var connectedNone: String { text("settings.phones.none") }
    static var resetPairing: String { text("settings.reset") }
    static var resetButton: String { text("settings.reset.button") }

    static var claudeToggle: String { text("settings.claude.toggle") }
    static var claudeCaption: String { text("settings.claude.caption") }
    static var claudeStatus: String { text("settings.claude.status") }
    static var claudeOff: String { text("settings.claude.off") }
    static var claudeNotInstalled: String { text("settings.claude.notInstalled") }
    static func claudeInstalled(_ sessions: Int) -> String { String(format: text("settings.claude.installed"), sessions) }
    static func claudeWaiting(_ count: Int) -> String { String(format: text("settings.claude.waiting"), count) }
    static var file: String { text("settings.file") }
    static var claudeFileCaption: String { text("settings.claude.fileCaption") }
    static var claudeReveal: String { text("settings.claude.reveal") }

    static var updates: String { text("settings.updates") }
    static var updateLineUpToDate: String { text("settings.update.upToDate") }
    static func updateLineAvailable(_ version: String) -> String { String(format: text("settings.update.available"), version) }
    static var updateLineChecking: String { text("settings.update.checking") }
    static var updateLineFailed: String { text("settings.update.failed") }
    static var updateLineInstalling: String { text("settings.update.installing") }
    static var updateLineNever: String { text("settings.update.never") }
    static func updateLineChecked(_ ago: String) -> String { String(format: text("settings.update.checked"), ago) }
    static var updateLineAutomatic: String { text("settings.update.automatic") }
    static var updateCheckNow: String { text("settings.update.check") }
    static var updateInstallButton: String { text("settings.update.install") }
    static var agoNow: String { text("settings.ago.now") }
    static func agoMinutes(_ count: Int) -> String { String(format: text("settings.ago.minutes"), count) }
    static func agoHours(_ count: Int) -> String { String(format: text("settings.ago.hours"), count) }
    static func agoDays(_ count: Int) -> String { String(format: text("settings.ago.days"), count) }
    static var about: String { text("settings.about") }
    static var openOnGitHub: String { text("settings.github") }
    static var mitLicense: String { text("settings.license") }
    static var licenses: String { text("settings.licenses") }
    static var licensesCaption: String { text("settings.licenses.caption") }
    static var open: String { text("settings.open") }
}
