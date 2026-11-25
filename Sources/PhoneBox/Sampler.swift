import Foundation
import PhoneBoxCore

/// Builds a `Snapshot` once a second while at least one phone may receive data (design §4, §6).
@MainActor
final class Sampler {
    var onSnapshot: ((Snapshot) -> Void)?

    private var timer: Timer?
    private let cpu = CPUCollector()
    private let memory = MemoryCollector()

    var isRunning: Bool { timer != nil }

    func setRunning(_ running: Bool) {
        guard running != isRunning else { return }
        if running {
            cpu.reset()
            _ = cpu.sample()
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    /// After sleep the tick counters jumped; start over so the first value is not nonsense.
    func resetAfterWake() {
        cpu.reset()
    }

    private func tick() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        onSnapshot?(Snapshot(t: now, cpu: cpu.sample(), mem: memory.sample()))
    }
}
