import Foundation
import Testing
@testable import PhoneBox

/// Talks to this Mac's real output device, so it runs only on request:
/// `PHONEBOX_LIVE=1 make test FILTER=SystemAudioLiveTests`. It writes back the values it read, so nothing changes.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PHONEBOX_LIVE"] == "1"))
struct SystemAudioLiveTests {
    @Test func readsAndWritesBackTheVolumeAndMute() throws {
        let volume = try #require(SystemAudio.volume(), "this output has no volume control")
        #expect((0...1).contains(volume))
        #expect(SystemAudio.setVolume(volume) == .done)
        let after = try #require(SystemAudio.volume())
        #expect(abs(after - volume) < 0.01)
        let muted = try #require(SystemAudio.isMuted() as Bool?)
        #expect(SystemAudio.setMuted(muted) == .done)
        #expect(SystemAudio.isMuted() == muted)
        #expect(AudioCollector().sample() != nil)
    }
}
