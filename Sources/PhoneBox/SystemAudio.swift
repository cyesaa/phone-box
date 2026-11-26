import AudioToolbox
import CoreAudio
import PhoneBoxCore

/// The default output device's volume and mute through CoreAudio (design §6, §7). Built-in speakers and most
/// headphones have both; some HDMI and USB outputs have neither, and then the readers return nil and the setters
/// false. Spike 7: no permission prompt.
enum SystemAudio {
    private static func outputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown
        else { return nil }
        return device
    }

    private static func read<Value: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, as initial: Value) -> Value? {
        guard let device = defaultOutputDevice() else { return nil }
        var address = outputAddress(selector)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = initial
        var size = UInt32(MemoryLayout<Value>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    /// What setting the volume or mute did.
    enum Write: Equatable {
        case done
        /// The output has no such control (no output, or some HDMI and USB outputs): the phone greys the control.
        case unsupported
        /// The control is there but did not take the value.
        case failed
    }

    private static func write<Value: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, _ value: Value) -> Write {
        guard let device = defaultOutputDevice() else { return .unsupported }
        var address = outputAddress(selector)
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue
        else { return .unsupported }
        var value = value
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Value>.size), &value)
        return status == noErr ? .done : .failed
    }

    /// 0…1; nil when the output has no volume control.
    static func volume() -> Double? {
        read(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, as: Float32(0))
            .flatMap { Double($0).finiteOrNil }
            .map { min(1, max(0, $0)) }
    }

    static func isMuted() -> Bool? {
        read(kAudioDevicePropertyMute, as: UInt32(0)).map { $0 != 0 }
    }

    static func setVolume(_ level: Double) -> Write {
        guard level.isFinite else { return .failed }
        return write(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(min(1, max(0, level))))
    }

    static func setMuted(_ on: Bool) -> Write {
        write(kAudioDevicePropertyMute, UInt32(on ? 1 : 0))
    }
}
