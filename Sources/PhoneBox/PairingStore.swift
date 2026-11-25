import Foundation
import PhoneBoxCore

/// Keeps the pairing key in `~/Library/Application Support/PhoneBox/pairing-key`, readable only by the user.
///
/// Not the keychain: PhoneBox is signed ad hoc, so macOS would ask for the keychain password after every update
/// (NotchBox does), and "nothing extra to do" is the point of PhoneBox. Anything that can read this file runs as
/// the user and could control the Mac anyway.
enum PairingStore {
    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhoneBox", isDirectory: true)
            .appendingPathComponent("pairing-key")
    }

    static func loadOrCreate() -> PairingKey {
        if let text = try? String(contentsOf: fileURL, encoding: .utf8),
           let key = PairingKey(base64URL: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return key
        }
        return reset()
    }

    /// A new key; every paired phone has to scan the new QR code.
    @discardableResult
    static func reset() -> PairingKey {
        let key = PairingKey.generate()
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try Data(key.base64URL.utf8).write(to: fileURL, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            Log.app.error("Could not save the pairing key: \(error.localizedDescription, privacy: .public)")
        }
        return key
    }
}
