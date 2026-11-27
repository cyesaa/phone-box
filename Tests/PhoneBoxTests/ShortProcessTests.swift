import Foundation
import Testing
@testable import PhoneBox

/// Runs only harmless tools (`true`, `false`, `sleep`); `withCheckedContinuation` would trap if `completion` ran twice.
@MainActor
struct ShortProcessTests {
    func run(_ executable: String, _ arguments: [String] = [], timeout: TimeInterval = 5) async -> Bool {
        await withCheckedContinuation { continuation in
            ShortProcess.run(executable, arguments, timeout: timeout) { continuation.resume(returning: $0) }
        }
    }

    @Test func reportsTheExitStatus() async {
        let succeeded = await run("/usr/bin/true")
        let failed = await run("/usr/bin/false")
        #expect(succeeded)
        #expect(!failed)
    }

    @Test func stopsAToolThatTakesTooLong() async {
        let start = Date()
        let finished = await run("/bin/sleep", ["5"], timeout: 0.2)
        #expect(!finished)
        #expect(Date().timeIntervalSince(start) < 3)
    }

    /// The media adapter's framework turns SIGTERM into a run loop stop, so `send` ignores it: SIGKILL follows.
    @Test func killsAToolThatIgnoresSIGTERM() async {
        let start = Date()
        let finished = await run("/bin/sh", ["-c", "trap '' TERM; exec /bin/sleep 8"], timeout: 0.2)
        #expect(!finished)
        #expect(Date().timeIntervalSince(start) < 0.2 + ShortProcess.killDelay + 1.5)
    }

    @Test func failsForAToolThatDoesNotExist() async {
        let ran = await run("/nonexistent/phonebox-tool")
        #expect(!ran)
    }
}
