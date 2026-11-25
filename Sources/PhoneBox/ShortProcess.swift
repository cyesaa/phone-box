import Foundation

/// Runs a short command-line tool (`pmset`, the media adapter's `send`) without blocking the main queue.
@MainActor
enum ShortProcess {
    /// `completion(true)` when the tool exited with status 0 within `timeout` seconds; a tool still running then is
    /// stopped and counts as failed. `completion` runs once, on the main actor.
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
            if process.isRunning { process.terminate() }
        }
    }
}
