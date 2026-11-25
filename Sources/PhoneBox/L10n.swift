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
    static var launchAtLogin: String { text("menu.launchAtLogin") }
    static var resetPairing: String { text("menu.resetPairing") }
    static var quit: String { text("menu.quit") }

    static var resetTitle: String { text("reset.title") }
    static var resetMessage: String { text("reset.message") }
    static var resetConfirm: String { text("reset.confirm") }
    static var cancel: String { text("cancel") }

    static var qrTitle: String { text("qr.title") }
    static var qrInstructions: String { text("qr.instructions") }
    static var qrCopy: String { text("qr.copy") }
    static var qrCopied: String { text("qr.copied") }
}
