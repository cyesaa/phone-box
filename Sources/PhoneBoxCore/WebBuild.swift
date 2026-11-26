import CryptoKit
import Foundation

/// Names one set of dashboard files (design §8 "Menü çubuğu", güncelleme): `ready` carries it, and a page that stays
/// open across an update sees another name and reloads, so it never runs old code against a newer Mac side.
public enum WebBuild {
    /// The first 12 hex digits of a SHA-256 over every file's path, size and contents, in path order.
    public static func fingerprint(_ files: [String: Data]) -> String {
        var hasher = SHA256()
        for path in files.keys.sorted() {
            let contents = files[path] ?? Data()
            hasher.update(data: Data("\(path)\n\(contents.count)\n".utf8))
            hasher.update(data: contents)
        }
        return hasher.finalize().prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}
