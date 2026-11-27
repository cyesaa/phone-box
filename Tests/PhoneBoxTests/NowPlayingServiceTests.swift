import Darwin
import Foundation
import Testing
@testable import PhoneBox

/// Stopping the media adapter (design §7). It runs a stand-in for the adapter, a harmless perl script in a temporary
/// folder, never the real one.
@MainActor
struct NowPlayingServiceTests {
    /// The real adapter ignores SIGTERM until its run loop runs: a `stop()` just after a start would leave it running.
    @Test func killsAnAdapterThatIgnoresSIGTERM() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (service, pid) = try await startStandIn(in: folder)
        defer { kill(pid, SIGKILL) }

        service.stop()
        try await Task.sleep(for: .milliseconds(500))
        #expect(kill(pid, 0) == 0, "the stand-in should outlive SIGTERM")
        #expect(try await ends(pid, within: ShortProcess.killDelay + 2))
    }

    /// PhoneBox quits right after `stop()`, before `killDelay`: the adapter is one of the leftovers it kills at quit.
    @Test func anAdapterStoppedAtQuitIsALeftover() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (service, pid) = try await startStandIn(in: folder)
        defer { kill(pid, SIGKILL) }

        service.stop()
        let leftovers = ShortProcess.leftovers.filter { $0.processIdentifier == pid }
        #expect(leftovers.count == 1)
        ShortProcess.endAtQuit(leftovers, grace: 0.1)
        #expect(try await ends(pid, within: ShortProcess.killDelay + 2))
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhoneBoxNowPlayingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The service running a stand-in in `folder`, and the stand-in's pid once it ignores SIGTERM.
    private func startStandIn(in folder: URL) async throws -> (NowPlayingService, pid_t) {
        // The service passes the framework's place as the script's first argument: there it writes its pid, once it
        // ignores SIGTERM.
        let script = folder.appendingPathComponent("adapter.pl")
        try #"$SIG{TERM} = "IGNORE"; open(my $f, ">", "$ARGV[0].tmp") or die; print $f $$; close $f; rename("$ARGV[0].tmp", $ARGV[0]); sleep 10;"#
            .write(to: script, atomically: true, encoding: .utf8)
        let pidFile = folder.appendingPathComponent("pid")
        let service = NowPlayingService(location: AdapterLocation(scriptPath: script.path, frameworkPath: pidFile.path))
        service.start()
        return (service, try #require(try await readPid(pidFile)))
    }

    private func readPid(_ file: URL, within seconds: Double = 5) async throws -> pid_t? {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let text = try? String(contentsOf: file, encoding: .utf8), let pid = pid_t(text) { return pid }
            try await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    /// True once `pid` is gone (and reaped) within `seconds`.
    private func ends(_ pid: pid_t, within seconds: Double) async throws -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if kill(pid, 0) != 0 && errno == ESRCH { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return kill(pid, 0) != 0 && errno == ESRCH
    }
}
