import PhoneBoxCore

/// The default output's volume for the page's slider (design §6); nil for an output without volume control.
final class AudioCollector {
    func sample() -> AudioSample? {
        guard let volume = SystemAudio.volume() else { return nil }
        return AudioSample(volume: (volume * 100).rounded() / 100, muted: SystemAudio.isMuted() ?? false)
    }
}
