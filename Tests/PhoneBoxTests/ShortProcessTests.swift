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

    /// A stand-in for the media adapter that ignores SIGTERM: `trap '' TERM` holds across the `exec`.
    func stubborn(_ seconds: Int = 8) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "trap '' TERM; exec /bin/sleep \(seconds)"]
        try process.run()
        return process
    }

    /// True once `process` has ended (and been reaped) within `seconds`.
    func ends(_ process: Process, within seconds: Double) async throws -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if !process.isRunning { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return !process.isRunning
    }

    /// PhoneBox quits before `killDelay`: a process stopped a moment before gets half a second, then SIGKILL.
    @Test func killsWhatStillRunsAtQuitAfterAMoment() async throws {
        let process = try stubborn()
        defer { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        // Its shell has set the trap once it runs sleep.
        try await Task.sleep(for: .milliseconds(200))
        ShortProcess.terminate(process)
        #expect(ShortProcess.leftovers.contains { $0 === process })
        let start = Date()
        ShortProcess.endAtQuit([process], grace: 0.5)
        let took = Date().timeIntervalSince(start)
        #expect(took >= 0.45 && took < 1, "\(took)")
        #expect(try await ends(process, within: 1))
        #expect(process.terminationReason == .uncaughtSignal)
        #expect(process.terminationStatus == SIGKILL)
    }

    /// Quitting stays quick: nothing left waits nothing, and a process that ends on SIGTERM only as long as it takes.
    @Test func quitsAtOnceWhenNothingIsLeft() async throws {
        var start = Date()
        ShortProcess.endAtQuit([], grace: 0.5)
        #expect(Date().timeIntervalSince(start) < 0.05)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["8"]
        try process.run()
        defer { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        ShortProcess.terminate(process)
        start = Date()
        ShortProcess.endAtQuit([process], grace: 0.5)
        #expect(Date().timeIntervalSince(start) < 0.3)
        #expect(try await ends(process, within: 1))
        #expect(process.terminationReason == .uncaughtSignal)
        #expect(process.terminationStatus == SIGTERM)
        #expect(!ShortProcess.leftovers.contains { $0 === process })
    }

    /// A `send` still running when PhoneBox quits is one of the leftovers too.
    @Test func aToolStillRunningAtQuitIsALeftover() async throws {
        let marker = "phonebox-test-\(UUID().uuidString)"
        let finished = await withCheckedContinuation { continuation in
            ShortProcess.run("/bin/sh", ["-c", "trap '' TERM; exec /bin/sleep 8", marker], timeout: 30) {
                continuation.resume(returning: $0)
            }
            let process = ShortProcess.leftovers.first { $0.arguments?.last == marker }
            #expect(process != nil)
            if let process { ShortProcess.endAtQuit([process], grace: 0.1) }
        }
        #expect(!finished)
    }
}
