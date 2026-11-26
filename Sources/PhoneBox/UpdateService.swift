import AppKit
import PhoneBoxCore

/// Looks for a newer PhoneBox release on GitHub soon after launch and twice a day, and installs it by running the
/// one-line installer, which quits this copy, puts the new one in place and opens it (design §8 "Menü çubuğu").
/// `defaults write com.phonebox.PhoneBox CheckForUpdatesAutomatically -bool false` turns the automatic checks off;
/// "Check for Updates…" still works.
@MainActor
final class UpdateService {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(LatestRelease)
        case installing
        case failed
    }

    private static let automaticKey = "CheckForUpdatesAutomatically"
    /// For testing: `defaults write com.phonebox.PhoneBox UpdateFeedURL file:///path/release.json` reads that file
    /// instead of GitHub, and `UpdateInstallCommand '<shell command>'` runs that instead of the installer.
    private static let feedOverrideKey = "UpdateFeedURL"
    private static let installOverrideKey = "UpdateInstallCommand"

    private(set) var status: Status = .idle {
        didSet { if status != oldValue { onChange?() } }
    }
    var onChange: (() -> Void)?
    let currentVersion: AppVersion?
    private let session: URLSession
    private var timer: Timer?
    /// A click on "Check for Updates…" that arrived while an automatic check was running: it gets its answer too.
    private var answerUser = false
    /// What the last check that got an answer found: a failed check falls back to it, so a known update stays offered.
    private var lastFound: LatestRelease?

    init(bundle: Bundle = .main) {
        currentVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap(AppVersion.init)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    private var feedURL: URL {
        UserDefaults.standard.string(forKey: Self.feedOverrideKey).flatMap(URL.init(string:))
            ?? UpdateCheck.latestReleaseURL
    }

    private var installCommand: String {
        UserDefaults.standard.string(forKey: Self.installOverrideKey) ?? UpdateCheck.installCommand
    }

    private var checksAutomatically: Bool {
        UserDefaults.standard.object(forKey: Self.automaticKey) as? Bool ?? true
    }

    var availableRelease: LatestRelease? {
        if case let .available(release) = status { return release }
        return nil
    }

    func start() {
        guard checksAutomatically, timer == nil else { return }
        let first = Timer(timeInterval: UpdateCheck.launchDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.check(userInitiated: false)
                let repeating = Timer(timeInterval: UpdateCheck.interval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.check(userInitiated: false) }
                }
                repeating.tolerance = 10 * 60
                RunLoop.main.add(repeating, forMode: .common)
                self.timer = repeating
            }
        }
        RunLoop.main.add(first, forMode: .common)
        timer = first
    }

    /// Asks GitHub for the latest release. A check from the menu answers in an alert.
    func check(userInitiated: Bool) {
        guard status != .installing, let currentVersion else { return }
        if status == .checking {
            if userInitiated { answerUser = true }
            return
        }
        status = .checking
        var request = URLRequest(url: feedURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PhoneBox/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { data, response, error in
            // A file:// feed (testing) has no HTTP status.
            let code = (response as? HTTPURLResponse)?.statusCode ?? (data == nil ? 0 : 200)
            let release = code == 200 ? data.flatMap(LatestRelease.parse) : nil
            let failed = error != nil || code != 200
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.finishCheck(release: release, failed: failed, code: code, userInitiated: userInitiated)
                }
            }
        }.resume()
    }

    private func finishCheck(release: LatestRelease?, failed: Bool, code: Int, userInitiated: Bool) {
        guard let currentVersion else { return }
        let userInitiated = userInitiated || answerUser
        answerUser = false
        if !failed { lastFound = release }
        if failed {
            Log.app.notice("Update check failed (HTTP \(code, privacy: .public))")
            // An update found before is still there: keep offering it, also to a click on "Check for Updates…".
            let known = UpdateCheck.availableUpdate(current: currentVersion, latest: lastFound)
            status = known.map(Status.available) ?? .failed
        } else if let update = UpdateCheck.availableUpdate(current: currentVersion, latest: release) {
            Log.app.notice("Update available: \(update.version.description, privacy: .public)")
            status = .available(update)
        } else {
            status = .upToDate
        }
        guard userInitiated else { return }
        switch status {
        case .available: installWithConfirmation()
        case .upToDate: alert(L10n.updateUpToDate(currentVersion.description), info: nil)
        default: alert(L10n.updateCheckFailed, info: L10n.updateCheckFailedHint)
        }
    }

    /// Asks once more, then runs the installer.
    func installWithConfirmation() {
        guard let release = availableRelease, let currentVersion else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = L10n.updateAvailableTitle(release.version.description)
        alert.informativeText = L10n.updateAvailableInfo(currentVersion.description)
        alert.addButton(withTitle: L10n.updateInstall)
        alert.addButton(withTitle: L10n.updateReleaseNotes)
        alert.addButton(withTitle: L10n.updateLater)
        switch alert.runModal() {
        case .alertFirstButtonReturn: install()
        case .alertSecondButtonReturn: NSWorkspace.shared.open(release.pageURL)
        default: break
        }
    }

    /// Runs the installer in a shell that outlives this process: the installer quits PhoneBox, replaces the app and
    /// opens the new one. Its output goes to ~/Library/Logs/PhoneBox/update.log.
    private func install() {
        let logFolder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/PhoneBox", isDirectory: true)
        try? FileManager.default.createDirectory(at: logFolder, withIntermediateDirectories: true)
        let logFile = logFolder.appendingPathComponent("update.log")
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "set -o pipefail; \(installCommand)"]
        let handle = try? FileHandle(forWritingTo: logFile)
        if let handle {
            process.standardOutput = handle
            process.standardError = handle
        }
        process.terminationHandler = { process in
            try? handle?.close()
            let code = process.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if code == 0 { self.installFinished() } else { self.installFailed(code: code, log: logFile) }
                }
            }
        }
        do {
            try process.run()
            status = .installing
            Log.app.notice("Running the installer")
        } catch {
            try? handle?.close()
            Log.app.error("Could not start the installer: \(error.localizedDescription, privacy: .public)")
            installFailed(code: -1, log: logFile)
        }
    }

    /// A successful installer quits PhoneBox first, so this copy is still running only when the installer did not
    /// replace it (an `UpdateInstallCommand`, or a copy outside the installer's folder): the menu works again.
    private func installFinished() {
        Log.app.notice("The installer finished, but this PhoneBox is still running")
        status = .idle
    }

    private func installFailed(code: Int32, log: URL) {
        Log.app.error("Installer exited with \(code, privacy: .public)")
        status = .failed
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(UpdateCheck.installCommand, forType: .string)
        alert(L10n.updateInstallFailed, info: L10n.updateInstallFailedHint)
        NSWorkspace.shared.activateFileViewerSelecting([log])
    }

    private func alert(_ message: String, info: String?) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = message
        if let info { alert.informativeText = info }
        alert.runModal()
    }
}
