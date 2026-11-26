import Foundation

/// A release version: up to three numbers ("0.4.0", "v1.2"); missing parts count as 0. Spaces and line breaks around
/// it are ignored ("0.1.1\n" from a file or a command's output).
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        while numbers.count < 3 { numbers.append(0) }
        (major, minor, patch) = (numbers[0], numbers[1], numbers[2])
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// The newest published release on GitHub.
public struct LatestRelease: Equatable, Sendable {
    public let version: AppVersion
    /// The release page, with its notes.
    public let pageURL: URL

    public init(version: AppVersion, pageURL: URL) {
        self.version = version
        self.pageURL = pageURL
    }

    /// Reads GitHub's "latest release" answer; nil for drafts, pre-releases and anything unexpected. The page is opened
    /// from the update dialog, so it has to be an https page on github.com.
    public static func parse(_ data: Data) -> LatestRelease? {
        struct Response: Decodable {
            let tag_name: String
            let html_url: String
            let draft: Bool?
            let prerelease: Bool?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              response.draft != true, response.prerelease != true,
              let version = AppVersion(response.tag_name),
              let url = URL(string: response.html_url),
              url.scheme == "https", url.host(percentEncoded: false) == "github.com"
        else { return nil }
        return LatestRelease(version: version, pageURL: url)
    }
}

/// When and where PhoneBox looks for a newer release, and how it installs one (design §8 "Menü çubuğu", §12).
public enum UpdateCheck {
    public static let repository = "cyesaa/phone-box"
    /// The first check waits a little after launch, then one runs twice a day.
    public static let launchDelay: TimeInterval = 15
    public static let interval: TimeInterval = 12 * 60 * 60

    /// The repository's page, opened from the settings window's "About".
    public static var repositoryURL: URL {
        URL(string: "https://github.com/\(repository)")!
    }

    public static var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    /// The one-line installer; running it again updates PhoneBox in place.
    public static var installCommand: String {
        "curl -fsSL https://raw.githubusercontent.com/\(repository)/main/install.sh | bash"
    }

    /// The environment the installer runs with: this app's, without the installer's own settings (`PHONEBOX_*`). `open`
    /// passes the caller's environment to the app, so an app installed with `PHONEBOX_VERSION=…` (or a test install
    /// with `PHONEBOX_ZIP`) would otherwise reinstall that version or zip instead of the latest release.
    public static func installerEnvironment(_ environment: [String: String]) -> [String: String] {
        environment.filter { !$0.key.hasPrefix("PHONEBOX_") }
    }

    public static func availableUpdate(current: AppVersion, latest: LatestRelease?) -> LatestRelease? {
        guard let latest, current < latest.version else { return nil }
        return latest
    }
}
