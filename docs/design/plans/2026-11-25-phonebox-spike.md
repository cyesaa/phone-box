# PhoneBox Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Bu plan için not:** Görev 1–4 Mac'te tek başına yürütülebilir. Görev 3'ün bazı adımları ve Görev 5 kullanıcının
> elinde iPhone ile yanında olmasını gerektirir; bu yüzden bu plan **aynı oturumda (inline)** yürütülmelidir.

**Goal:** Tasarımın (bkz. `docs/design/2026-11-25-phonebox-design.md` bölüm 11) dayandığı dokuz varsayımı gerçek bir
Mac ve iPhone üzerinde sınamak ve sonuçları `docs/spike-results.md`'ye yazmak. Bu plan PhoneBox'ın kendisini yazmaz;
uygulama planı (Plan 2) bu sonuçlara göre yazılacak.

**Architecture:** `spike/` altında birbirinden bağımsız, atılabilir küçük araçlar: usbmuxd dinleyicisi, sensör
okuyucu, komut deneyicisi ve tek portta HTTP + WebSocket sunan bir deneme sunucusu (`PhoneBoxSpike.app`). Sunucu,
iPhone'da Safari'de açılan bir test sayfası sunar; sayfa ekranın açık kalıp kalmadığını, bağlantının kopup
yeniden kurulduğunu ve anahtarın nereden okunduğunu Mac'teki log'a yazar.

**Tech Stack:** Swift 6.4 araç zinciri (`swiftc`, Swift 5 dil modu), Foundation, Network.framework, CryptoKit,
CoreImage, IOKit, AVFoundation, CoreAudio/AudioToolbox; özel API'ler `dlopen`/`dlsym` ile (`libIOReport.dylib`,
IOKit HID, `login.framework`); düz HTML/JS; bash. Xcode gerekmez, Command Line Tools yeterli.

**Spec:** `docs/design/2026-11-25-phonebox-design.md`

## Global Constraints

- Geliştirme Mac'i: Apple M4 MacBook Pro (Mac16,1), macOS 27.2, `LocalHostName` = `Eren-MacBook-Pro`.
- Xcode yok; her şey `swiftc` ve Command Line Tools ile derlenir. Ek bağımlılık (SwiftPM paketi, npm, brew) yok.
- Deneme kodu atılabilir: `spike/` altında durur, `Sources/` altına girmez. Derleme çıktıları `spike/build/`'e gider
  ve commit edilmez.
- Port: deneme sunucusu varsayılan olarak 4747'yi kullanır (spec'teki port).
- Telefon tarafına hiçbir şey kurulmaz: sadece Safari, Kestirmeler ve iOS ayarları kullanılır.
- Mac'i kilitleyen, uyutan, ekranı kapatan ya da uygulama kapatan her komuttan önce kullanıcıya sorulur.
- macOS 27'de `make-video.swift` AVFoundation "deprecated" uyarıları verir; beklenen bir durumdur, API'ler çalışır.
- Commit mesajları İngilizce, emir kipinde ve `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` satırıyla biter.

## Planlama sırasında yapılan ön denemeler (2026-11-25, iPhone'suz)

Bu plandaki bütün kodlar yazılmadan önce bu Mac'te derlendi ve telefon gerektirmeyen kısımları çalıştırıldı:

| Konu | Gözlem |
|---|---|
| usbmuxd | `Listen` isteğine `Result 0` (OK) döndü; takma/çıkarma olayları için iPhone gerekiyor |
| Sıcaklık | 44 sensör okundu (`PMU tdie1…14`, `PMU2 tdie1…10`, `PMU tdev*`, `NAND CH0 temp`, `gas gauge battery`) |
| Güç | "Energy Model" grubunda `CPU Energy`, `ECPU`, `PCPU`, `ANE`, `DRAM` sayaçları **root olmadan ilerlemiyor** (12 sn yük altında sabit kaldı); bütün IOReport grupları tarandı, ilerleyen tek enerji kanalı `GPU Energy` (nJ) |
| Sistem gücü | `AppleSmartBattery` → `PowerTelemetryData.SystemPowerIn`: 7,22 W okundu |
| GPU kullanımı | `IOAccelerator` → `Device Utilization %`: %24 okundu |
| Ses | CoreAudio ile varsayılan çıkış seviyesi okundu (0,5) |
| Kilit | `login.framework` `dlopen` ile açıldı, `SACLockScreenImmediate` bulundu (çağrılmadı) |
| Uygulama adları | `localizedName` görünmez karakter içerebiliyor (WhatsApp → `U+200E` + "WhatsApp") |
| Sunucu | HTTP, WebSocket el sıkışması, maskeli istemci çerçeveleri, saniyelik tick ve iki video varyantı Chromium'da uçtan uca çalıştı |
| Video | iOS Safari videoyu byte aralığı istekleriyle çeker; sunucu `Range` isteğine `206 Partial Content` döner (curl ile doğrulandı) |

---

### Task 1: usbmuxd dinleyicisi (spike 5)

**Files:**
- Create: `spike/usbwatch.swift`

**Interfaces:**
- Consumes: yok
- Produces: `swift spike/usbwatch.swift` → her olay için bir satır: `HH:mm:ss ATTACHED id=<n> type=USB|Network …`
  ve `HH:mm:ss DETACHED id=<n> type=…`. Plan 2'deki `USBWatcher` bu protokolü (16 baytlık küçük-endian başlık +
  XML plist, `MessageType` = `Listen`/`Attached`/`Detached`) kullanacak.

- [ ] **Step 1: Dinleyiciyi yaz**

(`spike/build/` zaten `.gitignore`'daki `build/` satırıyla dışarıda kalır.)

`spike/usbwatch.swift`:

```swift
// Spike 5: does usbmuxd tell us when an iPhone is plugged in or out, without Xcode?
// Run: swift spike/usbwatch.swift      (stop with Ctrl-C)
import Foundation

let socketPath = "/var/run/usbmuxd"

func stamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f.string(from: Date())
}

func connectToUsbmuxd() -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { fatalError("socket() failed: errno \(errno)") }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let path = Array(socketPath.utf8) + [0]
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: path) }
    let result = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else { fatalError("connect(\(socketPath)) failed: errno \(errno)") }
    return fd
}

/// usbmuxd packet: 16-byte little-endian header (length, version 1, message 8 = plist, tag) + XML plist.
func sendPlist(_ fd: Int32, _ message: [String: Any], tag: UInt32) {
    let body = try! PropertyListSerialization.data(fromPropertyList: message, format: .xml, options: 0)
    var packet = Data()
    for value in [UInt32(16 + body.count), 1, 8, tag] {
        withUnsafeBytes(of: value.littleEndian) { packet.append(contentsOf: $0) }
    }
    packet.append(body)
    _ = packet.withUnsafeBytes { write(fd, $0.baseAddress, packet.count) }
}

func readExactly(_ fd: Int32, _ count: Int) -> Data? {
    var data = Data(count: count)
    var received = 0
    while received < count {
        let n = data.withUnsafeMutableBytes { read(fd, $0.baseAddress! + received, count - received) }
        if n <= 0 { return nil }
        received += n
    }
    return data
}

func readPlist(_ fd: Int32) -> [String: Any]? {
    guard let header = readExactly(fd, 16) else { return nil }
    let length = Int(UInt32(littleEndian: header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
    guard length >= 16, let body = readExactly(fd, length - 16) else { return nil }
    return (try? PropertyListSerialization.propertyList(from: body, format: nil)) as? [String: Any]
}

setvbuf(stdout, nil, _IOLBF, 0)
let fd = connectToUsbmuxd()
sendPlist(fd, ["MessageType": "Listen", "ClientVersionString": "phonebox-spike", "ProgName": "phonebox-spike"], tag: 1)
print("\(stamp()) listening on \(socketPath): plug an iPhone in and out")

var connectionTypes: [Int: String] = [:]
while let message = readPlist(fd) {
    let deviceID = message["DeviceID"] as? Int ?? -1
    switch message["MessageType"] as? String {
    case "Result":
        print("\(stamp()) Listen result: \(message["Number"] ?? "?") (0 means OK)")
    case "Attached":
        let properties = message["Properties"] as? [String: Any] ?? [:]
        let type = properties["ConnectionType"] as? String ?? "?"
        let serial = properties["SerialNumber"] as? String ?? "?"
        connectionTypes[deviceID] = type
        print("\(stamp()) ATTACHED id=\(deviceID) type=\(type) product=\(properties["ProductID"] ?? "?") serial=\(serial.prefix(8))…")
    case "Detached":
        print("\(stamp()) DETACHED id=\(deviceID) type=\(connectionTypes.removeValue(forKey: deviceID) ?? "?")")
    default:
        print("\(stamp()) other message: \(message)")
    }
}
print("\(stamp()) usbmuxd closed the connection")
```

- [ ] **Step 2: iPhone'suz çalıştır**

Run: `perl -e 'alarm 10; exec @ARGV' swift spike/usbwatch.swift`
Expected: `listening on /var/run/usbmuxd…` ve `Listen result: 0 (0 means OK)` satırları; 10 saniye sonra `alarm` ile
çıkar (çıkış kodu 142 normaldir).

- [ ] **Step 3: Commit**

```bash
git add spike/usbwatch.swift
git commit -m "Add the usbmuxd listener spike" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(Takma/çıkarma olayları Görev 5'te iPhone ile sınanır.)

---

### Task 2: Sensör okuyucu (spike 6)

**Files:**
- Create: `spike/sensors.swift`

**Interfaces:**
- Consumes: yok
- Produces: `swift spike/sensors.swift` → sıcaklık sensörleri, "Energy Model" kanallarının 1 saniyelik watt değerleri,
  pil telemetrisinden sistem gücü ve GPU kullanımı. Plan 2'deki sensör ve güç collector'ları bu `dlsym` imzalarını
  kullanacak.

- [ ] **Step 1: Okuyucuyu yaz**

`spike/sensors.swift`:

```swift
// Spike 6: can we read temperatures, power and GPU use without sudo on Apple silicon?
// Run: swift spike/sensors.swift
import Foundation
import IOKit

func symbol<T>(_ library: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T {
    guard let pointer = dlsym(library, name) else { fatalError("missing symbol \(name)") }
    return unsafeBitCast(pointer, to: type)
}

// MARK: Temperatures: IOHIDEventSystemClient (private API in IOKit)

let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
let hidClientCreate = symbol(iokit, "IOHIDEventSystemClientCreate",
                             as: (@convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?).self)
let hidClientSetMatching = symbol(iokit, "IOHIDEventSystemClientSetMatching",
                                  as: (@convention(c) (CFTypeRef, CFDictionary) -> Int32).self)
let hidClientCopyServices = symbol(iokit, "IOHIDEventSystemClientCopyServices",
                                   as: (@convention(c) (CFTypeRef) -> Unmanaged<CFArray>?).self)
let hidServiceCopyProperty = symbol(iokit, "IOHIDServiceClientCopyProperty",
                                    as: (@convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?).self)
let hidServiceCopyEvent = symbol(iokit, "IOHIDServiceClientCopyEvent",
                                 as: (@convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?).self)
let hidEventGetFloatValue = symbol(iokit, "IOHIDEventGetFloatValue",
                                   as: (@convention(c) (CFTypeRef, Int32) -> Double).self)

let temperatureEventType: Int64 = 15  // kIOHIDEventTypeTemperature

func readTemperatures() -> [(name: String, celsius: Double)] {
    guard let client = hidClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { return [] }
    let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
    _ = hidClientSetMatching(client, matching)
    guard let services = hidClientCopyServices(client)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
    var readings: [(name: String, celsius: Double)] = []
    for service in services {
        let name = hidServiceCopyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String ?? "?"
        guard let event = hidServiceCopyEvent(service, temperatureEventType, 0, 0)?.takeRetainedValue() else { continue }
        let celsius = hidEventGetFloatValue(event, Int32(temperatureEventType << 16))
        if celsius > 0 && celsius < 150 { readings.append((name, celsius)) }
    }
    return readings.sorted { $0.name < $1.name }
}

// MARK: Power: IOReport "Energy Model" channels (private library)

let ioReport = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW)
let reportCopyChannelsInGroup = symbol(ioReport, "IOReportCopyChannelsInGroup",
    as: (@convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?).self)
let reportCreateSubscription = symbol(ioReport, "IOReportCreateSubscription",
    as: (@convention(c) (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>,
                         UInt64, CFTypeRef?) -> Unmanaged<CFTypeRef>?).self)
let reportCreateSamples = symbol(ioReport, "IOReportCreateSamples",
    as: (@convention(c) (CFTypeRef, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?).self)
let reportCreateSamplesDelta = symbol(ioReport, "IOReportCreateSamplesDelta",
    as: (@convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?).self)
let reportChannelGetChannelName = symbol(ioReport, "IOReportChannelGetChannelName",
    as: (@convention(c) (CFDictionary) -> Unmanaged<CFString>?).self)
let reportChannelGetUnitLabel = symbol(ioReport, "IOReportChannelGetUnitLabel",
    as: (@convention(c) (CFDictionary) -> Unmanaged<CFString>?).self)
let reportSimpleGetIntegerValue = symbol(ioReport, "IOReportSimpleGetIntegerValue",
    as: (@convention(c) (CFDictionary, Int32) -> Int64).self)

func readPower(over interval: TimeInterval) -> [(name: String, watts: Double)] {
    guard let channels = reportCopyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue(),
          let mutableChannels = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, CFDictionaryGetCount(channels), channels)
    else { return [] }
    var subscribed: Unmanaged<CFMutableDictionary>?
    guard let subscription = reportCreateSubscription(nil, mutableChannels, &subscribed, 0, nil)?.takeRetainedValue(),
          let subscribedChannels = subscribed?.takeUnretainedValue(),
          let first = reportCreateSamples(subscription, subscribedChannels, nil)?.takeRetainedValue()
    else { return [] }
    Thread.sleep(forTimeInterval: interval)
    guard let second = reportCreateSamples(subscription, subscribedChannels, nil)?.takeRetainedValue(),
          let delta = reportCreateSamplesDelta(first, second, nil)?.takeRetainedValue(),
          let items = (delta as NSDictionary)["IOReportChannels"] as? [NSDictionary]
    else { return [] }
    var readings: [(name: String, watts: Double)] = []
    for item in items {
        let channel = item as CFDictionary
        let name = reportChannelGetChannelName(channel)?.takeUnretainedValue() as String? ?? "?"
        let unit = (reportChannelGetUnitLabel(channel)?.takeUnretainedValue() as String? ?? "")
            .trimmingCharacters(in: .whitespaces)
        let value = Double(reportSimpleGetIntegerValue(channel, 0))
        let divisor: Double
        switch unit {
        case "mJ": divisor = 1e3
        case "uJ", "µJ": divisor = 1e6
        case "nJ": divisor = 1e9
        default: continue
        }
        let watts = value / divisor / interval
        if watts > 0.001 { readings.append((name, watts)) }
    }
    return readings
}

// MARK: Total system power (MacBook only): AppleSmartBattery telemetry, public IOKit

func readSystemPowerWatts() -> Double? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    guard let telemetry = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString,
                                                         kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
          let milliwatts = telemetry["SystemPowerIn"] as? Int
    else { return nil }
    return Double(milliwatts) / 1000
}

// MARK: GPU utilisation: IOAccelerator "PerformanceStatistics", public IOKit

func readGPUUtilisation() -> Int? {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
    else { return nil }
    defer { IOObjectRelease(iterator) }
    while case let service = IOIteratorNext(iterator), service != 0 {
        defer { IOObjectRelease(service) }
        if let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString,
                                                       kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
           let utilisation = stats["Device Utilization %"] as? Int {
            return utilisation
        }
    }
    return nil
}

// MARK: Report

let temperatures = readTemperatures()
print("Temperatures: \(temperatures.count) sensors")
for t in temperatures { print(String(format: "  %-24@ %6.1f °C", t.name as NSString, t.celsius)) }

let power = readPower(over: 1)
print("Power (Energy Model, over 1 s): \(power.count) channels")
for p in power.sorted(by: { $0.watts > $1.watts }).prefix(15) {
    print(String(format: "  %-24@ %7.3f W", p.name as NSString, p.watts))
}
for wanted in ["CPU Energy", "GPU Energy"] {
    let found = power.first { $0.name == wanted }
    print("  -> \(wanted): \(found.map { String(format: "%.3f W", $0.watts) } ?? "not found")")
}
let ane = power.filter { $0.name.hasPrefix("ANE") }.reduce(0) { $0 + $1.watts }
print(String(format: "  -> ANE (sum of ANE* channels): %.3f W", ane))

print("System power (battery telemetry): \(readSystemPowerWatts().map { String(format: "%.2f W", $0) } ?? "not available")")
print("GPU utilisation: \(readGPUUtilisation().map { "\($0) %" } ?? "not available")")
```

- [ ] **Step 2: Çalıştır ve çıktıyı kaydet**

Run: `swift spike/sensors.swift | tee spike/build/sensors.txt` (önce `mkdir -p spike/build`)
Expected (ön denemeye göre): `Temperatures: 44 sensors` civarı; `Power … 1 channels` ve sadece `GPU Energy`;
`-> CPU Energy: not found`; `System power (battery telemetry): ~5–20 W`; `GPU utilisation: <n> %`.
`CPU Energy` bulunursa (sayaç bu sefer ilerliyorsa) bunu sonuçlara ayrıca yaz.

- [ ] **Step 3: Commit**

```bash
git add spike/sensors.swift
git commit -m "Add the sensor and power spike" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Komut deneyicisi (spike 7)

**Files:**
- Create: `spike/commands.swift`

**Interfaces:**
- Consumes: NotchBox'ın derlenmiş medya adaptörü: `~/Documents/GitHub/notch-box/Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl`
  ve `~/Documents/GitHub/notch-box/build/adapter/MediaRemoteAdapter.framework` (başka yerdeyse `NOTCHBOX_DIR`).
- Produces: Plan 2'deki `CommandRunner` için her komutun çalışan biçimi ve izin davranışı.

- [ ] **Step 1: Deneyiciyi yaz**

`spike/commands.swift`:

```swift
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
```

- [ ] **Step 2: Zararsız komutları çalıştır**

Run: `swift spike/commands.swift apps` → Expected: Dock'taki uygulamalar, `pid<TAB>bundle id<TAB>ad` biçiminde.
Run: `swift spike/commands.swift volume` → Expected: `volume is <0…1>`.

- [ ] **Step 3: Kullanıcı izniyle etkili komutları sırayla dene**

Her satırdan önce kullanıcıya ne olacağını söyle ve onay al. Her birinde macOS'un bir izin penceresi açıp açmadığını
not et.

1. TextEdit'i aç (`open -a TextEdit`), boş bir belgeye bir harf yaz, sonra `swift spike/commands.swift quit com.apple.TextEdit`
   → Expected: TextEdit kaydetmeyi sorar, `still running after 3 s` yazar. Pencereyi "Silme" ile kapat.
2. Kullanıcı Spotify/Müzik'te bir şey çalarken `swift spike/commands.swift media playpause`, sonra `media next`
   → Expected: `adapter exit status 0` ve müzik durur / sonraki parçaya geçer.
3. `swift spike/commands.swift mute on`, sonra `mute off` → Expected: `mute = 1`, `mute = 0`.
4. `swift spike/commands.swift volume 0.3`, sonra eski değere geri dön → Expected: `volume set to 0.3`.
5. `swift spike/commands.swift display-off` → Expected: ekran kararır; bir tuşla geri gelir.
6. `swift spike/commands.swift lock` → Expected: `SACLockScreenImmediate returned 0` ve kilit ekranı.
7. `swift spike/commands.swift sleep` → Expected: Mac uyur; kullanıcı uyandırır.

- [ ] **Step 4: Commit**

```bash
git add spike/commands.swift
git commit -m "Add the command spike" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Deneme sunucusu, test sayfası ve video üreticisi (spike 1–4, 8, 9 için)

**Files:**
- Create: `spike/server/main.swift`
- Create: `spike/server/Info.plist`
- Create: `spike/web/index.html`
- Create: `spike/make-video.swift`
- Create: `spike/build.sh`

**Interfaces:**
- Consumes: yok
- Produces: `spike/build.sh` → `spike/build/PhoneBoxSpike.app` (ad-hoc imzalı, `LSUIElement`, `com.phonebox.spike`)
  ve `spike/build/{usbwatch,sensors,commands,make-video}`. Sunucu: `GET /` ve dosyalar (Range destekli),
  `GET /ws` WebSocket; Mac → sayfa `{"type":"hello","nonce":…}` ve saniyede bir `{"type":"tick","n":…}`;
  sayfa → Mac `{"type":"log","msg":…}`. Plan 2'deki `Server` bu HTTP/WebSocket kodunu temel alacak.

- [ ] **Step 1: Sunucuyu yaz**

`spike/server/main.swift`:

```swift
// PhoneBox spike server: one TCP port serves the test page over HTTP and a WebSocket at /ws.
// It prints a QR code for http://<LocalHostName>.local:<port>/#k=spike, logs everything the page
// reports, and sends a "tick" to every page once a second (standing in for real snapshots).
//
// Usage: PhoneBoxSpike [--port 4747] [--web <dir>]   (default web dir: Contents/Resources/web in the .app)
import CoreImage
import CryptoKit
import Foundation
import Network
import SystemConfiguration

setvbuf(stdout, nil, _IOLBF, 0)

func log(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    print("\(formatter.string(from: Date())) \(message)")
}

// MARK: Options

var port: UInt16 = 4747
var webDirectory = Bundle.main.resourceURL!.appendingPathComponent("web")
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--port": port = UInt16(arguments.next() ?? "") ?? port
    case "--web": webDirectory = URL(fileURLWithPath: arguments.next() ?? ".")
    default: log("unknown option \(argument)")
    }
}

// MARK: QR code in the terminal (ANSI background colours work on light and dark terminals)

func printQRCode(_ text: String) {
    let filter = CIFilter(name: "CIQRCodeGenerator")!
    filter.setValue(Data(text.utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    let image = filter.outputImage!
    let width = Int(image.extent.width), height = Int(image.extent.height)
    var pixels = [UInt8](repeating: 255, count: width * height)
    let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    context.draw(CIContext().createCGImage(image, from: image.extent)!, in: CGRect(x: 0, y: 0, width: width, height: height))
    let white = "\u{1B}[47m  ", black = "\u{1B}[40m  ", reset = "\u{1B}[0m"
    let quiet = String(repeating: white, count: width + 4) + reset
    print(quiet); print(quiet)
    for y in 0..<height {
        var row = white + white
        for x in 0..<width { row += pixels[y * width + x] < 128 ? black : white }
        print(row + white + white + reset)
    }
    print(quiet); print(quiet)
}

// MARK: HTTP

let contentTypes = ["html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8",
                    "css": "text/css; charset=utf-8", "mp4": "video/mp4", "png": "image/png"]

func httpResponse(status: String, contentType: String, body: Data, extraHeaders: String = "") -> Data {
    var head = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\n"
    head += "Accept-Ranges: bytes\r\nCache-Control: no-store\r\nConnection: close\r\n\(extraHeaders)\r\n"
    return Data(head.utf8) + body
}

/// iOS Safari plays <video> only from servers that answer byte-range requests with 206 Partial Content.
func serveFile(path: String, range: String?) -> Data {
    let name = path == "/" ? "index.html" : String(path.dropFirst())
    guard !name.contains(".."), !name.contains("/"),
          let body = try? Data(contentsOf: webDirectory.appendingPathComponent(name))
    else { return httpResponse(status: "404 Not Found", contentType: "text/plain", body: Data("not found".utf8)) }
    let type = contentTypes[(name as NSString).pathExtension] ?? "application/octet-stream"
    if let range, range.hasPrefix("bytes="), !body.isEmpty {
        let bounds = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        let start = Int(bounds.first ?? "") ?? 0
        let end = min(bounds.count > 1 ? Int(bounds[1]) ?? body.count - 1 : body.count - 1, body.count - 1)
        guard start <= end else {
            return httpResponse(status: "416 Range Not Satisfiable", contentType: "text/plain", body: Data(),
                                extraHeaders: "Content-Range: bytes */\(body.count)\r\n")
        }
        return httpResponse(status: "206 Partial Content", contentType: type, body: body.subdata(in: start..<(end + 1)),
                            extraHeaders: "Content-Range: bytes \(start)-\(end)/\(body.count)\r\n")
    }
    return httpResponse(status: "200 OK", contentType: type, body: body)
}

// MARK: WebSocket (RFC 6455, text frames only; client frames are always masked)

final class Client {
    let id: Int
    let connection: NWConnection
    var isWebSocket = false
    init(id: Int, connection: NWConnection) { self.id = id; self.connection = connection }

    func sendText(_ text: String) {
        let payload = Data(text.utf8)
        var frame = Data([0x81])
        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else if payload.count < 65_536 {
            frame.append(126)
            frame.append(contentsOf: [UInt8(payload.count >> 8), UInt8(payload.count & 0xff)])
        } else {
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) { frame.append(UInt8((payload.count >> shift) & 0xff)) }
        }
        connection.send(content: frame + payload, completion: .contentProcessed { _ in })
    }
}

let queue = DispatchQueue(label: "server")
var clients: [Int: Client] = [:]
var nextClientID = 1

func receive(_ client: Client, exactly count: Int, _ handler: @escaping (Data) -> Void) {
    client.connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
        guard let data, data.count == count, error == nil else { return close(client, reason: "read ended") }
        handler(data)
    }
}

func readFrame(_ client: Client) {
    receive(client, exactly: 2) { header in
        let opcode = header[0] & 0x0f
        let masked = header[1] & 0x80 != 0
        let shortLength = Int(header[1] & 0x7f)
        func withLength(_ length: Int) {
            receive(client, exactly: (masked ? 4 : 0) + length) { rest in
                var payload = [UInt8](rest.dropFirst(masked ? 4 : 0))
                if masked {
                    let mask = [UInt8](rest.prefix(4))
                    for i in payload.indices { payload[i] ^= mask[i % 4] }
                }
                handleFrame(client, opcode: opcode, payload: Data(payload))
            }
        }
        if shortLength == 126 {
            receive(client, exactly: 2) { bytes in withLength(Int(bytes[0]) << 8 | Int(bytes[1])) }
        } else if shortLength == 127 {
            receive(client, exactly: 8) { bytes in withLength(bytes.reduce(0) { $0 << 8 | Int($1) }) }
        } else {
            withLength(shortLength)
        }
    }
}

func handleFrame(_ client: Client, opcode: UInt8, payload: Data) {
    switch opcode {
    case 0x1:
        let text = String(decoding: payload, as: UTF8.self)
        if let message = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
           message["type"] as? String == "log" {
            log("#\(client.id) page: \(message["msg"] ?? "")")
        } else {
            log("#\(client.id) text: \(text)")
        }
        readFrame(client)
    case 0x8:
        client.connection.send(content: Data([0x88, 0x00]), completion: .contentProcessed { _ in })
        close(client, reason: "close frame")
    case 0x9:
        client.connection.send(content: Data([0x8A, UInt8(payload.count)]) + payload, completion: .contentProcessed { _ in })
        readFrame(client)
    default:
        readFrame(client)
    }
}

func close(_ client: Client, reason: String) {
    guard clients.removeValue(forKey: client.id) != nil else { return }
    if client.isWebSocket { log("#\(client.id) WebSocket closed (\(reason)); open: \(clients.values.filter(\.isWebSocket).count)") }
    client.connection.cancel()
}

func readRequest(_ client: Client, buffer: Data = Data()) {
    client.connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, error in
        guard let data, error == nil else { return close(client, reason: "no request") }
        let request = buffer + data
        guard let end = request.range(of: Data("\r\n\r\n".utf8)) else {
            return request.count > 65_536 ? close(client, reason: "header too big") : readRequest(client, buffer: request)
        }
        let lines = String(decoding: request[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        guard parts.count >= 2 else { return close(client, reason: "bad request line") }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        let path = String(parts[1])
        if path == "/ws", headers["upgrade"]?.lowercased() == "websocket", let key = headers["sec-websocket-key"] {
            let accept = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
            let response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
            client.connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
            client.isWebSocket = true
            log("#\(client.id) WebSocket open from \(headers["user-agent"]?.prefix(60) ?? "?"); open: \(clients.values.filter(\.isWebSocket).count)")
            client.sendText(#"{"type":"hello","nonce":"\#(UUID().uuidString)"}"#)
            readFrame(client)
        } else {
            log("#\(client.id) GET \(path)\(headers["range"].map { " (\($0))" } ?? "")")
            client.connection.send(content: serveFile(path: path, range: headers["range"]),
                                   completion: .contentProcessed { _ in close(client, reason: "http done") })
        }
    }
}

// MARK: Start

let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
listener.stateUpdateHandler = { state in
    switch state {
    case .ready:
        let host = (SCDynamicStoreCopyLocalHostName(nil) as String?) ?? "localhost"
        let url = "http://\(host).local:\(port)/#k=spike"
        log("listening on port \(port), serving \(webDirectory.path)")
        log("open on the iPhone: \(url)")
        printQRCode(url)
    case .failed(let error):
        log("listener failed: \(error)")
        exit(1)
    default:
        break
    }
}
listener.newConnectionHandler = { connection in
    let client = Client(id: nextClientID, connection: connection)
    nextClientID += 1
    clients[client.id] = client
    connection.start(queue: queue)
    readRequest(client)
}
listener.start(queue: queue)

var tick = 0
let timer = DispatchSource.makeTimerSource(queue: queue)
timer.schedule(deadline: .now() + 1, repeating: 1)
timer.setEventHandler {
    tick += 1
    for client in clients.values where client.isWebSocket {
        client.sendText(#"{"type":"tick","n":\#(tick)}"#)
    }
}
timer.resume()
dispatchMain()
```

- [ ] **Step 2: Uygulama paketinin Info.plist'ini yaz**

`spike/server/Info.plist` (`NSLocalNetworkUsageDescription` macOS'un Yerel Ağ izni penceresi için gerekli):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>com.phonebox.spike</string>
	<key>CFBundleName</key>
	<string>PhoneBoxSpike</string>
	<key>CFBundleExecutable</key>
	<string>PhoneBoxSpike</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.0.1</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSLocalNetworkUsageDescription</key>
	<string>PhoneBox serves its dashboard to your iPhone on the local network.</string>
</dict>
</plist>
```

- [ ] **Step 3: Test sayfasını yaz**

`spike/web/index.html`:

```html
<!doctype html>
<html lang="tr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<title>PhoneBox Spike</title>
<style>
  body { margin: 0; padding: 20px; background: #000; color: #f5f5f7; font: 15px -apple-system, system-ui, sans-serif; }
  h1 { font-size: 20px; margin: 0 0 12px; }
  .row { display: flex; justify-content: space-between; padding: 7px 0; border-bottom: 1px solid #1c1c1e; }
  .row b { font-weight: 600; text-align: right; }
  label { display: block; padding: 8px 0; }
  button { margin-top: 14px; width: 100%; padding: 14px; font-size: 17px; border: 0; border-radius: 12px; background: #30d158; color: #000; font-weight: 600; }
  #keepawake { position: fixed; right: 0; bottom: 0; width: 2px; height: 2px; opacity: 0.01; }
  .ok { color: #30d158; } .bad { color: #ff453a; }
</style>
</head>
<body>
<h1>PhoneBox deneme</h1>
<div class="row"><span>Anahtar</span><b id="key">—</b></div>
<div class="row"><span>Ana ekran uygulaması</span><b id="standalone">—</b></div>
<div class="row"><span>Bağlantı</span><b id="conn">—</b></div>
<div class="row"><span>Bağlantı sayısı</span><b id="connects">0</b></div>
<div class="row"><span>Son tick</span><b id="tick">—</b></div>
<div class="row"><span>Başlayalı</span><b id="elapsed">—</b></div>
<div class="row"><span>Son gizlenme</span><b id="hidden">—</b></div>
<div class="row"><span>Video</span><b id="video">—</b></div>

<label><input type="radio" name="variant" value="v1" checked> V1: sessiz, döngülü, sadece görüntü</label>
<label><input type="radio" name="variant" value="v2"> V2: sessiz, döngüsüz (başa sarar), ses izli</label>
<label><input type="radio" name="variant" value="v3"> V3: sesi açık (ses izi sessiz) — telefondaki müziği durdurabilir</label>
<button id="start">Başlat</button>

<video id="keepawake" playsinline></video>

<script>
const $ = (id) => document.getElementById(id);
const startedAt = Date.now();
let started = null;

// Key: from the URL fragment first, then localStorage.
const fragmentKey = new URLSearchParams(location.hash.slice(1)).get("k");
let storedKey = null;
try { storedKey = localStorage.getItem("pb-key"); } catch (e) {}
const key = fragmentKey || storedKey;
try { if (fragmentKey) localStorage.setItem("pb-key", fragmentKey); } catch (e) {}
$("key").textContent = key ? `${key} (${fragmentKey ? "adresten" : "localStorage'dan"})` : "yok";
$("standalone").textContent = navigator.standalone ? "evet" : "hayır (Safari)";

// Logs go to the Mac; queued while the socket is closed.
const queue = [];
let socket = null, connects = 0, retry = 0;
function send(msg) {
  const line = JSON.stringify({ type: "log", msg });
  if (socket && socket.readyState === 1) socket.send(line); else queue.push(line);
}
function elapsed() {
  const s = Math.round((Date.now() - (started || startedAt)) / 1000);
  return `${Math.floor(s / 60)} dk ${s % 60} sn`;
}
function connect() {
  if (socket && socket.readyState <= 1) return;
  $("conn").textContent = "bağlanıyor…";
  socket = new WebSocket(`ws://${location.host}/ws`);
  socket.onopen = () => {
    connects += 1; retry = 0;
    $("conn").innerHTML = '<span class="ok">bağlı</span>';
    $("connects").textContent = connects;
    while (queue.length) socket.send(queue.shift());
    send(`ws open #${connects} after ${elapsed()} key=${key ? "yes" : "no"} standalone=${!!navigator.standalone}`);
  };
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.type === "tick") $("tick").textContent = message.n;
  };
  socket.onclose = () => {
    $("conn").innerHTML = '<span class="bad">kapalı</span>';
    const delay = [1000, 2000, 5000][Math.min(retry, 2)];
    retry += 1;
    setTimeout(connect, delay);
  };
}
document.addEventListener("visibilitychange", () => {
  send(`visibility ${document.visibilityState} at ${elapsed()}`);
  if (document.visibilityState === "hidden") $("hidden").textContent = elapsed();
  else connect();
});
window.addEventListener("pageshow", (e) => { send(`pageshow persisted=${e.persisted}`); connect(); });
connect();
send(`loaded: ${navigator.userAgent}`);

// Keep-awake variants.
const video = $("keepawake");
$("start").onclick = async () => {
  const variant = document.querySelector("input[name=variant]:checked").value;
  video.loop = variant === "v1";
  video.muted = variant !== "v3";
  video.src = variant === "v1" ? "keepawake-video.mp4" : "keepawake-av.mp4";
  video.ontimeupdate = variant === "v1" ? null : () => { if (video.currentTime > 0.5) video.currentTime = Math.random() * 0.4; };
  try {
    await video.play();
    started = Date.now();
    $("video").innerHTML = `<span class="ok">${variant} oynuyor</span>`;
    send(`variant ${variant} playing`);
  } catch (error) {
    $("video").innerHTML = `<span class="bad">${error.name}</span>`;
    send(`variant ${variant} failed: ${error.name} ${error.message}`);
  }
};
video.onpause = () => send(`video paused at ${elapsed()}`);

setInterval(() => {
  $("elapsed").textContent = elapsed();
  const s = Math.round((Date.now() - (started || startedAt)) / 1000);
  if (s > 0 && s % 60 === 0) send(`alive ${elapsed()} visibility=${document.visibilityState} videoPaused=${video.paused}`);
}, 1000);
</script>
</body>
</html>
```

- [ ] **Step 4: Video üreticisini yaz**

`spike/make-video.swift`:

```swift
// Writes the two keep-awake test videos the spike page plays:
//   keepawake-video.mp4  1 s, 64×64 black H.264, no audio
//   keepawake-av.mp4     2 s, 64×64 black H.264 + silent AAC track
// Run: swift spike/make-video.swift spike/web
import AVFoundation

func makeVideo(at url: URL, seconds: Int, withAudio: Bool) throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let size = 64
    let fps: Int32 = 10

    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size, AVVideoHeightKey: size,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: size, kCVPixelBufferHeightKey as String: size,
    ])
    writer.add(videoInput)

    var audioInput: AVAssetWriterInput?
    if withAudio {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000,
        ])
        writer.add(input)
        audioInput = input
    }

    guard writer.startWriting() else { throw writer.error! }
    writer.startSession(atSourceTime: .zero)
    let group = DispatchGroup()

    group.enter()
    var frame = 0
    let frameCount = Int(fps) * seconds
    videoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "video")) {
        while videoInput.isReadyForMoreMediaData {
            if frame == frameCount {
                videoInput.markAsFinished()
                group.leave()
                return
            }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            CVPixelBufferLockBaseAddress(buffer!, [])
            memset(CVPixelBufferGetBaseAddress(buffer!), 0, CVPixelBufferGetDataSize(buffer!))
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
            frame += 1
        }
    }

    if let audioInput {
        var description = AudioStreamBasicDescription(
            mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        let totalFrames = 44_100 * seconds
        var written = 0
        group.enter()
        audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio")) {
            while audioInput.isReadyForMoreMediaData {
                if written >= totalFrames {
                    audioInput.markAsFinished()
                    group.leave()
                    return
                }
                let count = min(1024, totalFrames - written)
                var block: CMBlockBuffer?
                CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: count * 2, blockAllocator: nil,
                                                   customBlockSource: nil, offsetToData: 0, dataLength: count * 2,
                                                   flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
                CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: count * 2)
                var sample: CMSampleBuffer?
                CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                    allocator: nil, dataBuffer: block!, formatDescription: format!, sampleCount: count,
                    presentationTimeStamp: CMTime(value: CMTimeValue(written), timescale: 44_100),
                    packetDescriptions: nil, sampleBufferOut: &sample)
                audioInput.append(sample!)
                written += count
            }
        }
    }

    group.wait()
    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    finished.wait()
    guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
}

let directory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try makeVideo(at: directory.appendingPathComponent("keepawake-video.mp4"), seconds: 1, withAudio: false)
try makeVideo(at: directory.appendingPathComponent("keepawake-av.mp4"), seconds: 2, withAudio: true)
print("Wrote keepawake-video.mp4 and keepawake-av.mp4 in \(directory.path)")
```

- [ ] **Step 5: Derleme betiğini yaz ve çalıştır**

`spike/build.sh`:

```bash
#!/usr/bin/env bash
# Builds the spike tools into spike/build/ (gitignored). The server becomes an ad-hoc signed
# PhoneBoxSpike.app so that macOS attributes network permissions to it, not to Terminal.
set -euo pipefail

SPIKE="$(cd "$(dirname "$0")" && pwd)"
OUT="$SPIKE/build"
APP="$OUT/PhoneBoxSpike.app"
mkdir -p "$OUT"

for tool in usbwatch sensors commands make-video; do
  swiftc -O "$SPIKE/$tool.swift" -o "$OUT/$tool"
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"
swiftc -O "$SPIKE/server/main.swift" -o "$APP/Contents/MacOS/PhoneBoxSpike"
cp "$SPIKE/server/Info.plist" "$APP/Contents/Info.plist"
cp "$SPIKE/web/index.html" "$APP/Contents/Resources/web/"
"$OUT/make-video" "$APP/Contents/Resources/web"
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $OUT"
```

Run: `chmod +x spike/build.sh && spike/build.sh`
Expected: `Wrote keepawake-video.mp4 and keepawake-av.mp4 …` ve `Built …/spike/build`; `make-video.swift` için
"deprecated" uyarıları normaldir. `codesign -dv spike/build/PhoneBoxSpike.app 2>&1 | grep Identifier` →
`Identifier=com.phonebox.spike`.

- [ ] **Step 6: Mac'te uçtan uca dene (iPhone'suz)**

Run (ayrı bir terminalde, bu adımda `open` yerine doğrudan çalıştırılır; böylece izin penceresi Görev 5'e kalır):
`spike/build/PhoneBoxSpike.app/Contents/MacOS/PhoneBoxSpike --port 4799`
Sonra:
- `curl -s -D - -o /dev/null -r 0-1 http://localhost:4799/keepawake-av.mp4` → Expected: `HTTP/1.1 206 Partial Content`
  ve `Content-Range: bytes 0-1/<boyut>`.
- `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4799/yok.txt` → Expected: `404`.
- Tarayıcıda `http://localhost:4799/#k=test` aç → sayfada `Anahtar: test (adresten)`, `Bağlantı: bağlı`, `Son tick`
  her saniye artar; "Başlat" → `v1 oynuyor`. Sunucu terminalinde `WebSocket open`, `page: ws open #1 …`,
  `GET /keepawake-video.mp4 (bytes=…)` ya da `GET /keepawake-video.mp4` ve `page: variant v1 playing` görünür.
Sunucuyu Ctrl-C ile kapat.

- [ ] **Step 7: Commit**

```bash
git add spike/server spike/web/index.html spike/make-video.swift spike/build.sh
git commit -m "Add the spike server, test page and keep-awake videos" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: iPhone ile deneme oturumu (spike 1–5, 8, 9)

**Files:**
- Create: `spike/build/session-notes.md` (commit edilmez; Görev 6'nın ham verisi)

**Interfaces:**
- Consumes: Görev 1–4'ün araçları.
- Produces: her spike maddesi için gözlem notları.

Bu görev kullanıcıyla birlikte yapılır. Her adımda kullanıcıya ne yapacağını Türkçe ve tek tek söyle, gözlemi
`spike/build/session-notes.md`'ye yaz.

- [ ] **Step 1: Sunucuyu uygulama olarak başlat (spike 9)**

Run:
```bash
pkill -x PhoneBoxSpike; open --stdout "$PWD/spike/build/server.log" --stderr "$PWD/spike/build/server.log" spike/build/PhoneBoxSpike.app
```
Run: `tail -f spike/build/server.log` (ayrı terminalde açık kalsın; QR kodu burada görünür)
Gözle: macOS "Yerel Ağ" ya da güvenlik duvarı ("gelen bağlantılara izin verilsin mi?") penceresi açıyor mu? Hangi
metinle? İzin verildi mi? Not et.

- [ ] **Step 2: Takma/çıkarma olayları (spike 5)**

Ayrı terminalde `swift spike/usbwatch.swift` çalıştır. Kullanıcı iPhone'u kabloyla takar, 5 sn bekler, çıkarır,
tekrar takar.
Expected: her takışta `ATTACHED … type=USB`, her çıkarışta `DETACHED … type=USB`. iPhone Wi-Fi eşitlemeye açıksa
`type=Network` satırları da gelebilir; ikisini ayrı not et. İlk takışta iPhone "Bu bilgisayara güvenilsin mi?"
sorarsa bunu da not et.

- [ ] **Step 3: `.local` adresi açılıyor mu (spike 1)**

iPhone ve Mac aynı Wi-Fi'de. Kullanıcı terminaldeki QR'ı iPhone kamerasıyla okutur.
Expected: Safari `http://Eren-MacBook-Pro.local:4747/#k=spike` adresini açar; sayfada `Anahtar: spike (adresten)`,
`Bağlantı: bağlı`, `Son tick` artıyor. Safari bir "Yerel Ağ" izni sorarsa not et. Açılmazsa `ipconfig getifaddr en0`
ile IP'yi al, `http://<ip>:4747/#k=spike` ile dene ve farkı not et.

- [ ] **Step 4: Ekran açık kalıyor mu (spike 2, kritik)**

Kullanıcı iPhone'da Ayarlar → Ekran ve Parlaklık → Otomatik Kilit'i **30 Saniye** yapar (eski değeri not et).
Her varyant için: sayfayı yenile, varyantı seç, "Başlat"a bas, telefona 2 dakika dokunma.
- Log'da `page: visibility hidden at …` görünürse ekran kilitlenmiştir → varyant başarısız; kilitlendiği süreyi yaz.
- 2 dakika boyunca `hidden` gelmezse varyant aday sayılır.
Sıra: V1, V2, sonra (kullanıcı onaylarsa; telefonda çalan müziği durdurabilir) V3.
Aday çıkan ilk varyantla 30 dakikalık uzun test yap: log'da `alive 30 dk …` görünene kadar `hidden` gelmemeli.
Sonra Otomatik Kilit'i eski değerine döndür.

- [ ] **Step 5: Kilitle-aç sonrası yeniden bağlanma (spike 4, kritik)**

Sayfa açıkken kullanıcı yan tuşla telefonu kilitler, 10 sn bekler, açar.
Expected log sırası: `page: visibility hidden …`, `WebSocket closed …`, sonra `WebSocket open …`, `page: ws open #2 …`,
`page: visibility visible …`. Açtıktan sonra `Son tick`'in kaç saniyede yeniden artmaya başladığını not et.
Aynısını 2 dakikalık kilitle tekrarla.

- [ ] **Step 6: Ana ekran simgesi anahtarı koruyor mu (spike 3)**

Safari'de Paylaş → Ana Ekrana Ekle → Ekle. Ana ekrandaki simgeden aç.
Not et: `Anahtar` satırı (`spike (adresten)` / `spike (localStorage'dan)` / `yok`), `Ana ekran uygulaması` satırı
(`evet` beklenir), bağlantı kuruluyor mu. Sonra Safari'de `http://Eren-MacBook-Pro.local:4747/` (anahtarsız) aç ve
`Anahtar` satırını not et (Safari `localStorage`'ı).

- [ ] **Step 7: Kestirmeler şarj otomasyonu (spike 8)**

Kullanıcı iPhone'da: Kestirmeler → Otomasyon → + → "Şarj Aleti" → "Bağlandığında" → "Hemen Çalıştır" → Sonraki →
"URL'yi Aç" eylemi, URL: `http://Eren-MacBook-Pro.local:4747/#k=spike` → Bitti. Safari'yi kapatır, kabloyu çıkarıp
takar.
Expected: onay sorulmadan Safari sayfayı açar. Onay soruluyorsa ya da hiçbir şey olmuyorsa not et. Bittiğinde
otomasyonu silmek isteyip istemediğini kullanıcıya sor.

- [ ] **Step 8: Kapat**

Run: `pkill -x PhoneBoxSpike` ve usbwatch'u Ctrl-C ile durdur. Otomatik Kilit ayarının eski değerine döndüğünü
kullanıcıyla teyit et.

---

### Task 6: Sonuçları yaz ve tasarımı güncelle

**Files:**
- Create: `docs/spike-results.md`
- Modify: `docs/design/2026-11-25-phonebox-design.md` (sadece sonuçların değiştirdiği bölümler)

**Interfaces:**
- Consumes: `spike/build/sensors.txt`, `spike/build/session-notes.md`, Görev 3 gözlemleri, bu plandaki ön denemeler.
- Produces: Plan 2'nin dayanacağı kesin kararlar.

- [ ] **Step 1: `docs/spike-results.md`'yi yaz**

Şu iskeleti gözlemlerle doldur (her satırda "Sonuç" sütunu `Geçti` / `Kaldı` / `Kısmen` olmalı, "Karar" sütunu Plan
2'nin ne yapacağını tek cümleyle söylemeli):

```markdown
# PhoneBox — Deneme (spike) sonuçları

- **Tarih:** <deneme günü>
- **Mac:** MacBook Pro (Mac16,1), Apple M4, macOS 27.2
- **iPhone:** <model>, iOS <sürüm>

| # | Soru | Sonuç | Gözlem | Karar |
|---|---|---|---|---|
| 1 | `.local` adresi Safari'de açılıyor mu? | | | |
| 2 | Sessiz video ile ekran açık kalıyor mu? (V1 / V2 / V3) | | | |
| 3 | Ana ekran simgesi anahtarı koruyor mu? | | | |
| 4 | Kilitle-aç sonrası yeniden bağlanma | | | |
| 5 | usbmuxd takma/çıkarma olayları | | | |
| 6 | Sıcaklık ve güç (sudo'suz) | | | |
| 7 | Medya ve diğer komutlar, izinler | | | |
| 8 | Kestirmeler şarj otomasyonu | | | |
| 9 | macOS Yerel Ağ / güvenlik duvarı izni | | | |

## Ön denemeler (planlama sırasında, 2026-11-25)

<bu planın "Planlama sırasında yapılan ön denemeler" tablosunu buraya taşı>

## Tasarıma etkileri

<her "Kaldı" ya da "Kısmen" satırı için tasarımda neyin değiştiği>
```

- [ ] **Step 2: Tasarım dokümanını sonuçlara göre güncelle**

Kesinleşmiş değişiklikler (ön denemelerden):
- Bölüm 6 `power` satırı: `cpu` ve `ane` watt'ı root olmadan okunamıyor. Satırı şöyle değiştir:
  `| \`power\` | \`gpu\` (W, IOReport "GPU Energy"); MacBook'ta \`system\` (W, pil telemetrisi). CPU ve ANE watt'ı root gerektirdiği için yok | IOReport (resmi olmayan), \`AppleSmartBattery\` |`
- Bölüm 8 dashboard'da "Güç" satırı sistem gücünü (yoksa GPU gücünü) gösterir.
- Bölüm 6'ya not: uygulama adlarından görünmez yön karakterleri (`U+200E`, `U+200F`, `U+202A…U+202E`) temizlenir.
- Bölüm 2 kapsam dışına: "CPU ve Neural Engine watt'ı (root gerektiriyor)".

Görev 5'ten gelen değişiklikler: Spike 2 başarısızsa bölüm 8'deki ilk açılış rehberine "Otomatik Kilit → Asla"
adımı ve ekranda kısa bir açıklama eklenir; başarılı varyant hangisiyse bölüm 8 "Ekranı açık tutma" satırına o
varyant yazılır. Spike 3 başarısızsa bölüm 5'e "ana ekran simgesinde QR yeniden okutulur" yolu eklenir. Spike 1
ya da 4 başarısızsa Plan 2'ye geçmeden kullanıcıyla tasarım yeniden konuşulur.

Dokümanın başındaki durum satırını şöyle güncelle: `- **Durum:** Onaylandı (2026-11-25); deneme sonuçları: \`docs/spike-results.md\``

- [ ] **Step 3: Commit**

```bash
git add docs/spike-results.md docs/design/2026-11-25-phonebox-design.md
git commit -m "Record the spike results and update the design" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Kullanıcıya özetle**

Sonuç tablosunu kısaca anlat; tasarımda değişen her şeyi söyle ve Plan 2'yi (uygulama planı) yazmak için onay iste.
