import AppKit
import PhoneBoxCore

/// Runs the phone's commands on the Mac (design §7). Spike 7: none of them asks for a permission.
@MainActor
final class CommandRunner: CommandRunning {
    /// Seconds between answering `sleep` and sleeping, so that the `ack` reaches the phone first.
    static let sleepDelay: TimeInterval = 1
    static let pmset = "/usr/bin/pmset"

    private let nowPlaying: NowPlayingService

    init(nowPlaying: NowPlayingService) {
        self.nowPlaying = nowPlaying
    }

    func run(_ command: Command, completion: @escaping @MainActor (CommandResult) -> Void) {
        switch command {
        case let .quitApp(bundleId, force):
            completion(Self.quit(bundleId: bundleId, force: force))
        case let .media(action):
            nowPlaying.send(action, completion: completion)
        case let .volume(level):
            completion(SystemAudio.setVolume(level) ? .ok : .failed(.unsupported))
        case let .mute(on):
            completion(SystemAudio.setMuted(on) ? .ok : .failed(.unsupported))
        case .lock:
            if let lockScreen = Self.lockScreen {
                _ = lockScreen()
                completion(.ok)
            } else {
                // Without the private function the display at least goes dark (and locks if a password is required).
                ShortProcess.run(Self.pmset, ["displaysleepnow"]) { completion($0 ? .ok : .failed(.failed)) }
            }
        case .displaySleep:
            ShortProcess.run(Self.pmset, ["displaysleepnow"]) { completion($0 ? .ok : .failed(.failed)) }
        case .sleep:
            completion(.ok)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.sleepDelay) {
                MainActor.assumeIsolated {
                    ShortProcess.run(Self.pmset, ["sleepnow"]) { ok in
                        if !ok { Log.app.error("pmset sleepnow failed") }
                    }
                }
            }
        }
    }

    /// Asks every quittable instance of the app to quit (`terminate`, which may let the app ask to save) or
    /// quits it at once (`forceTerminate`).
    private static func quit(bundleId: String, force: Bool) -> CommandResult {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        let apps = running.map {
            RunningApp(pid: $0.processIdentifier, bundleId: $0.bundleIdentifier, regular: $0.activationPolicy == .regular)
        }
        let targets = Set(QuitRule.targets(bundleId: bundleId, among: apps, ownPid: ProcessInfo.processInfo.processIdentifier))
        guard !targets.isEmpty else { return .failed(.appChanged) }
        var asked = false
        for app in running where targets.contains(app.processIdentifier) {
            if force ? app.forceTerminate() : app.terminate() { asked = true }
        }
        return asked ? .ok : .failed(.failed)
    }

    /// `SACLockScreenImmediate` from the private login.framework: what the menu's Lock Screen item does (spike 7).
    private static let lockScreen = PrivateSymbols.function(PrivateSymbols.login, "SACLockScreenImmediate",
                                                            as: (@convention(c) () -> Int32).self)
}
