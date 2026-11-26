import Foundation
import PhoneBoxCore

/// Builds a `Snapshot` once a second while at least one phone may receive data (design §4, §6). The app list
/// is the most expensive part, so it is read every `appsEvery` seconds.
@MainActor
final class Sampler {
    /// Reading every process takes a few milliseconds; every 3 s keeps PhoneBox under 1 % CPU.
    static let appsEvery = 3
    var onSnapshot: ((Snapshot) -> Void)?
    /// The Claude Code sessions for the snapshot's `claude`; nil while the feature is off.
    var claudeSessions: (() -> [ClaudeSession]?)?
    /// Also sends the media commands, so the command runner shares it.
    let nowPlaying = NowPlayingService()

    private var timer: Timer?
    /// Keeps App Nap from slowing the one-second timer while a phone is streaming.
    private var activity: NSObjectProtocol?
    private var tickCount = 0
    private let cpu = CPUCollector()
    private let memory = MemoryCollector()
    private let gpu = GPUCollector()
    private let temperature = TemperatureCollector()
    private let power = PowerCollector()
    private let network = NetworkCollector()
    private let disk = DiskCollector()
    private let battery = BatteryCollector()
    private let apps = AppsCollector()
    private let audio = AudioCollector()
    private let phoneBattery = PhoneBatteryReader()

    var isRunning: Bool { timer != nil }

    func setRunning(_ running: Bool) {
        guard running != isRunning else { return }
        if running {
            resetCounters()
            primeCounters()
            // Fire half way through each second. The page files a snapshot under its whole second; a timer that
            // fires near a second's edge drifts across it, putting two snapshots in one slot and leaving a gap.
            let start = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) + 1.5)
            let timer = Timer(fire: start, interval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                             reason: "Streaming to iPhone")
            nowPlaying.start()
            phoneBattery.start()
        } else {
            phoneBattery.stop()
            nowPlaying.stop()
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
            activity = nil
            timer?.invalidate()
            timer = nil
        }
    }

    /// After sleep every counter jumped; start over so the first values are not nonsense.
    func resetAfterWake() {
        resetCounters()
    }

    private func resetCounters() {
        cpu.reset()
        power.reset()
        network.reset()
        disk.reset()
        apps.reset()
        tickCount = 0
    }

    /// Take a first reading of every counter so the first tick already has rates.
    private func primeCounters() {
        _ = cpu.sample()
        _ = power.sample()
        _ = network.sample()
        _ = disk.sample()
        _ = apps.sample()
    }

    private func tick() {
        tickCount += 1
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        onSnapshot?(Snapshot(
            t: now, cpu: cpu.sample(), mem: memory.sample(), gpu: gpu.sample(), temp: temperature.sample(),
            power: power.sample(), net: network.sample(), disk: disk.sample(), battery: battery.sample(),
            apps: tickCount % Self.appsEvery == 0 ? apps.sample() : nil, media: nowPlaying.current(), audio: audio.sample(),
            phone: phoneBattery.latest, claude: claudeSessions?()))
    }
}
