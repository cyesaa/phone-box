import AppKit
import PhoneBoxCore

/// Where scripts/bundle.sh puts mediaremote-adapter inside PhoneBox.app.
struct AdapterLocation {
    let scriptPath: String
    let frameworkPath: String

    /// Nil when the app was built without the adapter (e.g. `swift run`): then the snapshot has no `media` and
    /// media commands answer `unsupported`.
    static func inAppBundle(_ bundle: Bundle = .main) -> AdapterLocation? {
        guard let script = bundle.path(forResource: "mediaremote-adapter", ofType: "pl"),
              let frameworks = bundle.privateFrameworksPath
        else { return nil }
        let framework = frameworks + "/MediaRemoteAdapter.framework"
        guard FileManager.default.fileExists(atPath: framework) else { return nil }
        return AdapterLocation(scriptPath: script, frameworkPath: framework)
    }

    func arguments(_ command: [String]) -> [String] {
        [scriptPath, frameworkPath] + command
    }
}

/// What the Mac is playing, and play/pause, next and previous (design §6, §7), through mediaremote-adapter
/// (vendored, see THIRD_PARTY_NOTICES.md). The adapter runs under `/usr/bin/perl`, which MediaRemote still answers
/// on current macOS, and streams one JSON line per change. It runs only while a phone receives data.
@MainActor
final class NowPlayingService {
    static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    static let streamArguments = ["stream", "--no-diff", "--no-artwork", "--debounce=100"]
    /// Waits before restarting an adapter that exited; the last one repeats.
    static let restartDelays: [TimeInterval] = [1, 2, 5, 10, 30]
    /// An adapter that ran this long before it exited counts as healthy: the next restart waits only 1 s again.
    static let healthyRun: TimeInterval = 30

    private let location: AdapterLocation?
    private var process: Process?
    private var assembler = LineAssembler()
    private var state = NowPlayingState()
    private var running = false
    private var failures = 0
    private var startedAt = Date.distantPast
    private var names: [String: String] = [:]

    init(location: AdapterLocation? = .inAppBundle()) {
        self.location = location
    }

    func start() {
        guard !running else { return }
        running = true
        failures = 0
        launch()
    }

    func stop() {
        running = false
        let old = process
        process = nil
        old?.terminate()
        state.clear()
        assembler.reset()
    }

    /// For the snapshot: nil while nothing is playing, or without the adapter.
    func current() -> MediaSample? {
        guard let track = state.current(at: Date()) else { return nil }
        return MediaSample(title: track.title, artist: track.artist, app: appName(for: track.bundleId), playing: track.playing)
    }

    /// `mediaremote-adapter.pl … send <id>` (MediaRemote command numbers). `unsupported` without the adapter.
    func send(_ action: Command.MediaAction, completion: @escaping @MainActor (CommandResult) -> Void) {
        guard let location else { return completion(.failed(.unsupported)) }
        let id = switch action {
        case .playPause: "2"
        case .next: "4"
        case .previous: "5"
        }
        ShortProcess.run(Self.perl.path, location.arguments(["send", id])) { completion($0 ? .ok : .failed(.failed)) }
    }

    private func launch() {
        guard running, let location else { return }
        let process = Process()
        let output = Pipe()
        process.executableURL = Self.perl
        process.arguments = location.arguments(Self.streamArguments)
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.received(data, from: process) }
            }
        }
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.exited(finished) }
            }
        }
        do {
            try process.run()
            self.process = process
            startedAt = Date()
        } catch {
            // The read handler holds the process and the pipe; without this every failed start leaks both.
            output.fileHandleForReading.readabilityHandler = nil
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            Log.app.error("Could not start the media adapter: \(error.localizedDescription, privacy: .public)")
            scheduleRestart()
        }
    }

    private func received(_ data: Data, from source: Process) {
        guard source === process, !data.isEmpty else { return }
        for line in assembler.append(data) {
            state.received(NowPlayingStream.parse(line), at: Date())
        }
    }

    private func exited(_ finished: Process) {
        guard finished === process else { return }
        process = nil
        state.clear()
        assembler.reset()
        Log.app.notice("The media adapter exited with status \(finished.terminationStatus)")
        if Date().timeIntervalSince(startedAt) >= Self.healthyRun { failures = 0 }
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard running else { return }
        let delay = Self.restartDelays[min(failures, Self.restartDelays.count - 1)]
        failures += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.running, self.process == nil else { return }
                self.launch()
            }
        }
    }

    /// "Spotify" for `com.spotify.client`; the player is running, so its name is at hand. Found names are cached
    /// (players are few); the bundle identifier stands in until macOS lists the player.
    private func appName(for bundleId: String) -> String {
        if let name = names[bundleId] { return name }
        let cleanedId = AppUsage.displayName(bundleId)
        let fallback = cleanedId.isEmpty ? "?" : cleanedId
        guard let raw = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.localizedName
        else { return fallback }
        let name = AppUsage.displayName(raw)
        guard !name.isEmpty else { return fallback }
        names[bundleId] = name
        return name
    }
}
