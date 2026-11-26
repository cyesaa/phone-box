import Foundation

/// Menu and window texts; English and Turkish in `Resources/{en,tr}.lproj/Localizable.strings`.
enum L10n {
    private static func text(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static var statusWaiting: String { text("status.waiting") }
    static func statusStreaming(_ count: Int) -> String { String(format: text("status.streaming"), count) }
    static var statusWaitingForCable: String { text("status.waitingForCable") }
    static func statusPortInUse(_ port: UInt16) -> String { String(format: text("status.portInUse"), Int(port)) }
    static var statusUSBUnavailable: String { text("status.usbUnavailable") }

    static var showQR: String { text("menu.showQR") }
    static var modeHeader: String { text("menu.mode") }
    static var modeCable: String { text("menu.mode.cable") }
    static var modeAlways: String { text("menu.mode.always") }
    static var lockAndMusic: String { text("menu.lockAndMusic") }
    static func portItem(_ port: UInt16) -> String { String(format: text("menu.port"), Int(port)) }
    static var launchAtLogin: String { text("menu.launchAtLogin") }
    static var resetPairing: String { text("menu.resetPairing") }
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
}
