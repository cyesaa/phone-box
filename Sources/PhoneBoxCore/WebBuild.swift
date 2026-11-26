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

    /// The tag in index.html that carries the build. It is empty in the files on disk, which the fingerprint is taken
    /// from; the build goes in only as index.html is served.
    public static let emptyTag = #"<meta name="phonebox-build" content="">"#

    /// index.html as it is served: the empty tag carries `build`, so the page knows which files it runs even before
    /// its first `ready`. Only a build of 12 lowercase hex digits is stamped; anything else leaves the HTML as it is.
    public static func stamp(_ html: Data, build: String) -> Data {
        guard build.count == 12, build.allSatisfy({ "0123456789abcdef".contains($0) }),
              let range = html.range(of: Data(emptyTag.utf8))
        else { return html }
        var stamped = html
        stamped.replaceSubrange(range, with: Data(#"<meta name="phonebox-build" content="\#(build)">"#.utf8))
        return stamped
    }
}
