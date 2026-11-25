import AppKit
import Testing
@testable import PhoneBox
import PhoneBoxCore

/// Runs real commands on this Mac, so only on request: `PHONEBOX_LIVE=1 make test FILTER=CommandRunnerLiveTests`.
/// It opens Chess and quits it; it never locks, sleeps or turns off the display.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PHONEBOX_LIVE"] == "1"))
struct CommandRunnerLiveTests {
    let runner = CommandRunner(nowPlaying: NowPlayingService(location: nil))

    func run(_ command: Command) async -> CommandResult {
        await withCheckedContinuation { continuation in
            runner.run(command) { continuation.resume(returning: $0) }
        }
    }

    @Test func quitsAnAppItOpened() async throws {
        try #require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Chess").isEmpty,
                     "Chess is already open; close it first")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        let chess = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Chess.app"),
                                                                 configuration: configuration)
        try await Task.sleep(for: .seconds(1))
        #expect(await run(.quitApp(bundleId: "com.apple.Chess", force: false)) == .ok)
        for _ in 0..<30 where !chess.isTerminated { try await Task.sleep(for: .milliseconds(100)) }
        #expect(chess.isTerminated)
    }

    @Test func refusesFinderAndAppsThatAreNotRunning() async {
        #expect(await run(.quitApp(bundleId: "com.apple.finder", force: false)) == .failed(.appChanged))
        #expect(await run(.quitApp(bundleId: "com.example.NotRunning", force: true)) == .failed(.appChanged))
    }

    @Test func mediaWithoutTheAdapterIsUnsupported() async {
        #expect(await run(.media(.next)) == .failed(.unsupported))
    }
}
