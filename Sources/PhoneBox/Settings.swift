import Foundation
import PhoneBoxCore
import SystemConfiguration

/// The few choices PhoneBox remembers (design §8 "Menü çubuğu").
@MainActor
final class Settings {
    static let defaultPort: UInt16 = 4747
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var mode: AccessMode {
        get { AccessMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .cable }
        set { defaults.set(newValue.rawValue, forKey: "mode") }
    }

    /// `defaults write com.phonebox.PhoneBox port -int 4848` until the menu gets a port item (Plan 5).
    var port: UInt16 {
        let value = defaults.integer(forKey: "port")
        return (1024...65535).contains(value) ? UInt16(value) : Self.defaultPort
    }

    /// False until a phone has authenticated once; while false, plugging in an iPhone opens the QR window.
    var hasEverPaired: Bool {
        get { defaults.bool(forKey: "hasEverPaired") }
        set { defaults.set(newValue, forKey: "hasEverPaired") }
    }

    /// `Erens-MacBook-Pro` from System Settings → General → Sharing → Local hostname.
    static func localHostName() -> String {
        (SCDynamicStoreCopyLocalHostName(nil) as String?) ?? "localhost"
    }

    /// "Eren's MacBook Pro" from System Settings → General → Sharing; the page shows it in its "⋯" menu.
    static func computerName() -> String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? localHostName()
    }

    /// "Apple M4 Pro" from `machdep.cpu.brand_string`; empty if it cannot be read.
    static func chipName() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(cString: bytes)
    }

    /// The personal link in the QR code (design §5). Always with `http://`: Safari tries HTTPS first for an
    /// address typed without a scheme (spike).
    func personalURL(key: PairingKey) -> String {
        "http://\(Self.localHostName()).local:\(port)/#k=\(key.base64URL)"
    }
}
