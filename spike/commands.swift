// Spike 7: do the phone's commands work from a plain process, and does macOS ask for any permission?
// Usage: swift spike/commands.swift <command>
//   apps                       list regular (Dock) apps with pid and bundle id
//   quit <bundle-id> [force]   NSRunningApplication.terminate() / forceTerminate()
//   volume [0…1]               read or set the default output volume (CoreAudio)
//   mute on|off                mute or unmute the default output device
//   media playpause|next|previous   via NotchBox's mediaremote-adapter (NOTCHBOX_DIR, default ~/Documents/GitHub/notch-box)
//   lock                       SACLockScreenImmediate from login.framework
//   display-off                pmset displaysleepnow
//   sleep                      pmset sleepnow
import AppKit
import AudioToolbox
import CoreAudio

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func run(_ executable: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    do { try process.run() } catch { fail("\(executable): \(error)") }
    process.waitUntilExit()
    return process.terminationStatus
}

func defaultOutputDevice() -> AudioObjectID {
    var device = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                             mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
    guard status == noErr else { fail("no default output device (\(status))") }
    return device
}

var volumeAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                               mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
var muteAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                             mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "apps":
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        print("\(app.processIdentifier)\t\(app.bundleIdentifier ?? "?")\t\(app.localizedName ?? "?")")
    }

case "quit":
    guard arguments.count >= 2 else { fail("quit needs a bundle id") }
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: arguments[1]).first
    else { fail("\(arguments[1]) is not running") }
    let force = arguments.count > 2 && arguments[2] == "force"
    print("\(force ? "forceTerminate" : "terminate")() returned \(force ? app.forceTerminate() : app.terminate())")
    for _ in 0..<30 where !app.isTerminated { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    print(app.isTerminated ? "quit within 3 s" : "still running after 3 s (it may be asking to save)")

case "volume":
    let device = defaultOutputDevice()
    var volume = Float32(0)
    var size = UInt32(MemoryLayout<Float32>.size)
    if arguments.count > 1, let wanted = Float32(arguments[1]) {
        volume = max(0, min(1, wanted))
        let status = AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, size, &volume)
        print(status == noErr ? "volume set to \(volume)" : "set failed (\(status)): this device may have no volume control")
    } else {
        let status = AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &volume)
        print(status == noErr ? "volume is \(volume)" : "read failed (\(status)): this device may have no volume control")
    }

case "mute":
    var value = UInt32(arguments.count > 1 && arguments[1] == "on" ? 1 : 0)
    let status = AudioObjectSetPropertyData(defaultOutputDevice(), &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    print(status == noErr ? "mute = \(value)" : "mute failed (\(status))")

case "media":
    let ids = ["playpause": "2", "next": "4", "previous": "5"]
    guard arguments.count > 1, let id = ids[arguments[1]] else { fail("media needs playpause, next or previous") }
    let notchbox = ProcessInfo.processInfo.environment["NOTCHBOX_DIR"]
        ?? NSHomeDirectory() + "/Documents/GitHub/notch-box"
    let status = run("/usr/bin/perl", [notchbox + "/Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl",
                                       notchbox + "/build/adapter/MediaRemoteAdapter.framework", "send", id])
    print("adapter exit status \(status)")

case "lock":
    guard let login = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
          let symbol = dlsym(login, "SACLockScreenImmediate")
    else { fail("SACLockScreenImmediate not found") }
    let lockScreen = unsafeBitCast(symbol, to: (@convention(c) () -> Int32).self)
    print("SACLockScreenImmediate returned \(lockScreen())")

case "display-off":
    print("pmset exit status \(run("/usr/bin/pmset", ["displaysleepnow"]))")

case "sleep":
    print("pmset exit status \(run("/usr/bin/pmset", ["sleepnow"]))")

default:
    fail("unknown command; see the comment at the top of this file")
}
