import Darwin
import Foundation

/// Runs a short command-line tool (`pmset`, the media adapter's `send`) without blocking the main queue.
@MainActor
enum ShortProcess {
    /// Seconds a process may take to exit after SIGTERM before it gets SIGKILL. The media adapter's framework replaces
    /// SIGTERM's action with one that only stops a run loop: `send` never runs one, and a `stream` stopped before its
    /// run loop starts misses the stop, so both would run on.
    static let killDelay: TimeInterval = 1.5

    /// SIGTERM now, and SIGKILL `killDelay` seconds later if the process is still running.
    static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + killDelay) {
            // Not reaped yet while it runs, so the pid cannot belong to another process.
            guard process.isRunning else { return }
            Log.app.notice("\(process.executableURL?.lastPathComponent ?? "?", privacy: .public) ignored SIGTERM; killing it")
            kill(process.processIdentifier, SIGKILL)
        }
    }

    /// `completion(true)` when the tool exited with status 0 within `timeout` seconds; a tool still running then is
    /// stopped (`terminate`) and counts as failed. `completion` runs once, on the main actor.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 5,
                    completion: @escaping @MainActor (Bool) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            let ok = finished.terminationReason == .exit && finished.terminationStatus == 0
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(ok) } }
        }
        do {
            try process.run()
        } catch {
            Log.app.error("Could not run \(executable, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return completion(false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            MainActor.assumeIsolated { terminate(process) }
        }
    }
}
