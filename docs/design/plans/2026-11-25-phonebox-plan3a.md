# PhoneBox Plan 3A — Metrikler

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Bu plan için not:** Görev 1–7 Mac'te tek başına yürütülebilir. Görev 8 kısa bir iPhone kontrolüdür ve
> kullanıcıyla birlikte (inline) yapılır.
>
> **Yürütme notu (2026-11-25):** Plan alt ajanlarla yürütüldü (dal `plan3a`). İncelemelerden sonra yapılan
> düzeltmeler yüzünden aşağıdaki kod blokları düzeltme öncesi hâlidir; doğruluk kaynağı daldaki koddur.
> - `4eb587f`: güç `SystemLoad`'dan (pildeyken `SystemPowerIn` 0), sıcaklık ve disk kapasitesi tek bir başarısız
>   okumada boşalmıyor, ağ indeksi taşmıyor.
> - `b143c39`: bulunamayan birincil arayüz her saniye yeniden aranıyor.
> - `e751400`: ağ hızlarının ikisi de önceden okunuyor (ilk snapshot dolu); IOReport'ta sadece "GPU Energy" kanalına
>   abone olunuyor (175 kanal yerine); disk kapasitesi 10 sn yerine **60 sn**'de bir (okuması ~9 ms); işlem listesi
>   okunamazsa uygulama listesi boşalmıyor; uygulama adı en fazla 80 karakter; `μJ` (U+03BC) birimi.
> - `4e56dfe`: ağ sayaçları `net.link.generic.ifdata`'dan; `getifaddrs` ve `NET_RT_IFLIST2` bu macOS'ta sadece alt
>   32 biti veriyor (4 GiB'da başa dönüyordu).
>
> Sonuç: 105 test; PhoneBox bir telefona veri gönderirken `top`'ta %0,74 CPU (düzeltmelerden önce %1,34).

**Goal:** Telefondaki dashboard'a CPU ve RAM'in yanında GPU, çip sıcaklığı, güç, ağ, disk, pil ve en çok kaynak
kullanan uygulamaları eklemek; PhoneBox veri gönderirken ~%1 CPU'yu geçmesin.

**Architecture:** Saf hesaplar (`CounterRate`, `Temperatures`, `EnergyRate`, `BatteryInfo`, `AppUsage`) ve yeni
snapshot alanları `PhoneBoxCore`'a test edilerek eklenir. Uygulamada her kaynak için küçük bir toplayıcı
(`Collectors/`) vardır; `Sampler` her saniye hepsini toplar (sıcaklık 5 sn'de, uygulama listesi 3 sn'de bir
yenilenir). Sayfa yeni metrikleri sade satırlar ve bir uygulama listesi olarak gösterir; tam tasarım (yerleşim C)
Plan 4'tedir.

**Tech Stack:** Swift 6.4 (Swift 5 dil modu), IOKit (GPU, disk, pil, güç telemetrisi), IOKit.ps, `IOHIDEventSystemClient`
ve `libIOReport` (resmi olmayan, `dlsym` ile), `sysctl(NET_RT_IFLIST2)`, SystemConfiguration, `libproc`, AppKit
(`NSWorkspace`), Swift Testing, sade JS.

**Spec:** `docs/design/2026-11-25-phonebox-design.md` bölüm 6 · **Deneme:** `docs/spike-results.md` (spike 6)
**Önceki plan:** `docs/design/plans/2026-11-25-phonebox-plan2.md` (main'de, 79 test)

## Global Constraints

- macOS 14+, Apple Silicon; `swiftLanguageModes: [.v5]`; ek bağımlılık yok. Her şey ana kuyrukta.
- Snapshot alanları (design §6): `gpu {util}`, `temp {avg, max}` (çip die sensörleri, °C), `power {gpu, system}`
  (W; CPU/ANE root gerektirdiği için yok), `net {rx, tx, iface}` (bayt/sn), `disk {free, total, read, write}`
  (bayt, bayt/sn), `battery {percent, charging, minutesLeft}`, `apps [{pid, bundleId, name, cpu, mem, quittable}]`.
  Okunamayan değer JSON'da yer almaz; sayfa "—" gösterir. JSON'da NaN/sonsuz olamaz.
- `apps`: CPU'ya göre ilk 5 ile belleğe göre ilk 5'in birleşimi (en fazla 10); yardımcı süreçler en dıştaki
  `.app`'e yazılır; CPU tek çekirdeğin yüzdesi (Activity Monitor gibi); `quittable` sadece Dock'taki uygulamalar
  (Finder ve PhoneBox hariç). Root'a ait süreçler okunamaz ve listede yoktur.
- Sıklık: snapshot her saniye; sıcaklık en fazla 5 sn'de bir okunur (sadece çip sensörleri); uygulama listesi her
  3. saniyede bir gönderilir; çalışan uygulama adları 10 sn'de bir yenilenir; disk kapasitesi 10 sn'de bir okunur.
- Uyanınca bütün sayaçlar sıfırlanır (ilk değer sıçrama yerine boş gelir).
- Ölçülen yük (planlama sırasında, M4): PhoneBox bir telefona veri gönderirken `top`'ta ~%1,0–1,2 CPU.
- Commit mesajları İngilizce, emir kipinde. Aşağıdaki her `git commit` komutuna, commit'i yapan ortamın istediği
  `Co-Authored-By: …` satırı ikinci bir `-m` olarak eklenir (commit'i yapan modeli adlandırır).

## Planlama sırasında doğrulananlar (2026-11-25)

Kodun tamamı `main`'in bir kopyasında derlendi, test edildi ve çalıştırıldı:
- `make test`: 20 takımda 103 test geçti (79 + 24 yeni). `swift build` uyarısız.
- Uygulama "Her zaman" modunda çalıştırılıp tarayıcıdan WebSocket ile ham snapshot alındı: GPU %1 / 0,01 W, sistem
  19,3 W, çip 39,8 °C (en yüksek 42), `en0` ↓1 KB/s, disk 6,5 / 494,4 GB boş (okuma/yazma hızlarıyla), pil %80,
  uygulamalar (Chrome yardımcılarıyla tek satır, kapatılabilir; menü çubuğu uygulamaları kapatılamaz). "iPhone
  Yansıtma"nın 31 GB'ı `top`'la aynı çıktı (fiziksel ayak izi).
- İlk sürümde PhoneBox %3,3 CPU kullandı; `sample` profili sürenin %69'unu 44 sensörün her saniye okunmasında
  gösterdi. Sıcaklık 5 sn'ye ve sadece çip sensörlerine, uygulama adları 10 sn'ye, uygulama listesi 3 sn'ye alınınca
  ~%1'e indi.
- Sayfa yeni satırları ve uygulama listesini Türkçe biçimlerle gösterdi.

## Dosya yapısı

```
Sources/PhoneBoxCore/   Metrics.swift (yeni), AppUsage.swift (yeni), Snapshot.swift, Messages.swift
Sources/PhoneBox/Collectors/  HostPort, PrivateSymbols, GPUCollector, TemperatureCollector, PowerCollector,
                        NetworkCollector, DiskCollector, BatteryCollector, AppsCollector (yeni);
                        CPUCollector, MemoryCollector (değişir)
Sources/PhoneBox/Sampler.swift (değişir)
Resources/web/          index.html, styles.css, app.js (değişir)
Tests/PhoneBoxCoreTests/ MetricsTests.swift, AppUsageTests.swift (yeni), MessagesTests.swift (değişir)
```

---

### Task 1: Metrik modelleri ve saf hesaplar

**Files:**
- Create: `Sources/PhoneBoxCore/Metrics.swift`
- Test: `Tests/PhoneBoxCoreTests/MetricsTests.swift`

**Interfaces:**
- Consumes: `CPULoad.rounded(_:)` (Plan 2)
- Produces: `GPUSample(util:)`, `TemperatureSample(avg:max:)`, `PowerSample(gpu:system:)`,
  `NetworkSample(rx:tx:iface:)`, `DiskSample(free:total:read:write:)`, `BatterySample(percent:charging:minutesLeft:)`;
  `Double.finiteOrNil`; `struct CounterRate { mutating rate(value:at:) -> Double?; mutating reset() }`;
  `Temperatures.chipSensors(_:) -> Set<String>`, `Temperatures.summary(_:) -> TemperatureSample?`;
  `EnergyRate.watts(energy:unit:seconds:) -> Double?`; `BatteryInfo.sample(from:) -> BatterySample?`.

- [ ] **Step 1: Başarısız testi yaz**

`Tests/PhoneBoxCoreTests/MetricsTests.swift`:

```swift
import Foundation
import Testing
@testable import PhoneBoxCore

struct CounterRateTests {
    @Test func firstReadingHasNoRate() {
        var rate = CounterRate()
        #expect(rate.rate(value: 1_000, at: 10) == nil)
    }

    @Test func computesBytesPerSecondRounded() {
        var rate = CounterRate()
        _ = rate.rate(value: 1_000, at: 10)
        #expect(rate.rate(value: 4_000, at: 12) == 1_500)
        #expect(rate.rate(value: 4_001, at: 15) == 0)
    }

    @Test func startsOverWhenTheCounterGoesBackOrTimeStands() {
        var rate = CounterRate()
        _ = rate.rate(value: 5_000, at: 10)
        #expect(rate.rate(value: 100, at: 11) == nil)
        #expect(rate.rate(value: 600, at: 12) == 500)
        #expect(rate.rate(value: 700, at: 12) == nil)
    }

    @Test func resetForgetsTheLastReading() {
        var rate = CounterRate()
        _ = rate.rate(value: 5_000, at: 10)
        rate.reset()
        #expect(rate.rate(value: 6_000, at: 11) == nil)
    }
}

struct TemperaturesTests {
    @Test func summarisesTheDieSensors() {
        let readings: [(name: String, celsius: Double)] = [
            ("PMU tdie1", 50), ("PMU tdie2", 54), ("PMU2 tdie1", 46), ("PMU tdev1", 80),
            ("gas gauge battery", 31), ("NAND CH0 temp", 43),
        ]
        #expect(Temperatures.summary(readings) == TemperatureSample(avg: 50, max: 54))
    }

    @Test func fallsBackToOtherPMUSensorsButNotCalibration() {
        let readings: [(name: String, celsius: Double)] = [("PMU tdev1", 40), ("PMU tdev2", 44), ("PMU tcal", 90)]
        #expect(Temperatures.summary(readings) == TemperatureSample(avg: 42, max: 44))
    }

    @Test func choosesTheChipSensorsByName() {
        #expect(Temperatures.chipSensors(["PMU tdie1", "PMU2 tdie3", "PMU tdev1", "NAND CH0 temp"]) == ["PMU tdie1", "PMU2 tdie3"])
        #expect(Temperatures.chipSensors(["PMU tdev1", "PMU tcal", "gas gauge battery"]) == ["PMU tdev1"])
        #expect(Temperatures.chipSensors(["gas gauge battery"]).isEmpty)
    }

    @Test func ignoresImpossibleValuesAndEmptyInput() {
        #expect(Temperatures.summary([("PMU tdie1", -1), ("PMU tdie2", 500)]) == nil)
        #expect(Temperatures.summary([]) == nil)
        #expect(Temperatures.summary([("gas gauge battery", 31)]) == nil)
    }
}

struct EnergyRateTests {
    @Test func convertsEachUnitToWatts() {
        #expect(EnergyRate.watts(energy: 2_000, unit: "mJ", seconds: 1) == 2)
        #expect(EnergyRate.watts(energy: 500_000, unit: "uJ", seconds: 0.5) == 1)
        #expect(EnergyRate.watts(energy: 510_018_661, unit: "nJ", seconds: 2) == 0.26)
        #expect(EnergyRate.watts(energy: 1_000_000, unit: " µJ ", seconds: 1) == 1)
    }

    @Test func refusesUnknownUnitsAndBadIntervals() {
        #expect(EnergyRate.watts(energy: 1, unit: "W", seconds: 1) == nil)
        #expect(EnergyRate.watts(energy: 1, unit: "mJ", seconds: 0) == nil)
        #expect(EnergyRate.watts(energy: -1, unit: "mJ", seconds: 1) == nil)
    }
}

struct BatteryInfoTests {
    @Test func readsADischargingBattery() {
        let description: [String: Any] = ["Type": "InternalBattery", "Current Capacity": 86, "Max Capacity": 100,
                                          "Is Charging": false, "Time to Empty": 312, "Time to Full Charge": -1]
        #expect(BatteryInfo.sample(from: description) == BatterySample(percent: 86, charging: false, minutesLeft: 312))
    }

    @Test func readsAChargingBatteryAndAnUnknownEstimate() {
        let description: [String: Any] = ["Type": "InternalBattery", "Current Capacity": 40, "Max Capacity": 100,
                                          "Is Charging": true, "Time to Full Charge": -1]
        #expect(BatteryInfo.sample(from: description) == BatterySample(percent: 40, charging: true, minutesLeft: nil))
    }

    @Test func ignoresUPSesAndBrokenDescriptions() {
        #expect(BatteryInfo.sample(from: ["Type": "UPS", "Current Capacity": 50, "Max Capacity": 100]) == nil)
        #expect(BatteryInfo.sample(from: ["Type": "InternalBattery", "Current Capacity": 50, "Max Capacity": 0]) == nil)
        #expect(BatteryInfo.sample(from: [:]) == nil)
    }

    @Test func keepsThePercentInRange() {
        let description: [String: Any] = ["Type": "InternalBattery", "Current Capacity": 120, "Max Capacity": 100]
        #expect(BatteryInfo.sample(from: description)?.percent == 100)
    }
}

struct FiniteTests {
    @Test func dropsNaNAndInfinity() {
        #expect(1.5.finiteOrNil == 1.5)
        #expect(Double.nan.finiteOrNil == nil)
        #expect(Double.infinity.finiteOrNil == nil)
    }
}
```

- [ ] **Step 2: Testin başarısız olduğunu gör**

Run: `make test FILTER="CounterRateTests|TemperaturesTests|EnergyRateTests|BatteryInfoTests|FiniteTests"`
Expected: FAIL — `cannot find 'CounterRate' in scope` ve benzerleri.

- [ ] **Step 3: Uygulamayı yaz**

`Sources/PhoneBoxCore/Metrics.swift`:

```swift
import Foundation

// The snapshot fields that Plan 3A adds (design §6). Every value is finite; collectors pass raw numbers through
// `finiteOrNil` so a NaN from a sensor becomes a missing value instead of an encoding error.

public struct GPUSample: Equatable, Codable, Sendable {
    /// Busy percentage, 0…100.
    public var util: Double
    public init(util: Double) { self.util = util }
}

/// Chip temperature from the die sensors, °C.
public struct TemperatureSample: Equatable, Codable, Sendable {
    public var avg: Double
    public var max: Double
    public init(avg: Double, max: Double) {
        self.avg = avg
        self.max = max
    }
}

/// Watts. CPU and Neural Engine power need root on Apple silicon (spike 6), so they are not here.
public struct PowerSample: Equatable, Codable, Sendable {
    public var gpu: Double?
    /// Whole-Mac power from the battery telemetry; MacBooks only.
    public var system: Double?
    public init(gpu: Double?, system: Double?) {
        self.gpu = gpu
        self.system = system
    }
}

/// Bytes per second on the primary network interface.
public struct NetworkSample: Equatable, Codable, Sendable {
    public var rx: Double
    public var tx: Double
    public var iface: String
    public init(rx: Double, tx: Double, iface: String) {
        self.rx = rx
        self.tx = tx
        self.iface = iface
    }
}

/// The startup volume: capacity in bytes, read and write in bytes per second (nil until two readings exist).
public struct DiskSample: Equatable, Codable, Sendable {
    public var free: UInt64
    public var total: UInt64
    public var read: Double?
    public var write: Double?
    public init(free: UInt64, total: UInt64, read: Double?, write: Double?) {
        self.free = free
        self.total = total
        self.read = read
        self.write = write
    }
}

public struct BatterySample: Equatable, Codable, Sendable {
    public var percent: Int
    public var charging: Bool
    /// Minutes to empty while discharging, to full while charging; nil while macOS is still estimating.
    public var minutesLeft: Int?
    public init(percent: Int, charging: Bool, minutesLeft: Int?) {
        self.percent = percent
        self.charging = charging
        self.minutesLeft = minutesLeft
    }
}

extension Double {
    /// Nil for NaN and infinity, so an odd sensor value is left out of the snapshot instead of breaking it.
    public var finiteOrNil: Double? { isFinite ? self : nil }
}

/// Turns an ever-growing counter (bytes received, bytes read) into a per-second rate.
public struct CounterRate: Sendable {
    private var last: (value: UInt64, time: TimeInterval)?

    public init() {}

    /// Nil for the first reading, when the counter went backwards (reset, interface change) or no time passed.
    public mutating func rate(value: UInt64, at time: TimeInterval) -> Double? {
        defer { last = (value, time) }
        guard let last, value >= last.value, time > last.time else { return nil }
        return (Double(value - last.value) / (time - last.time)).rounded()
    }

    public mutating func reset() {
        last = nil
    }
}

public enum Temperatures {
    /// The sensors that describe the chip: the die sensors (`PMU tdie*`, `PMU2 tdie*`); if a chip names them
    /// differently, every `PMU` sensor except the calibration ones. Reading a sensor is a system call, so the
    /// collector asks only for these.
    public static func chipSensors(_ names: [String]) -> Set<String> {
        let die = names.filter { $0.hasPrefix("PMU tdie") || $0.hasPrefix("PMU2 tdie") }
        return Set(die.isEmpty ? names.filter { $0.hasPrefix("PMU") && !$0.contains("tcal") } : die)
    }

    /// Average and maximum of the chip sensors (see `chipSensors`). Readings outside 1…130 °C are ignored.
    public static func summary(_ readings: [(name: String, celsius: Double)]) -> TemperatureSample? {
        let chosenNames = chipSensors(readings.map(\.name))
        let chosen = readings.filter { chosenNames.contains($0.name) && $0.celsius > 0 && $0.celsius < 130 }
        guard !chosen.isEmpty else { return nil }
        let values = chosen.map(\.celsius)
        return TemperatureSample(avg: CPULoad.rounded(values.reduce(0, +) / Double(values.count)),
                                 max: CPULoad.rounded(values.max()!))
    }
}

public enum EnergyRate {
    /// Watts from an energy counter delta in IOReport's unit (`mJ`, `uJ`/`µJ` or `nJ`) over `seconds`.
    public static func watts(energy: Double, unit: String, seconds: Double) -> Double? {
        guard seconds > 0, energy >= 0 else { return nil }
        let joules: Double
        switch unit.trimmingCharacters(in: .whitespaces) {
        case "mJ": joules = energy / 1e3
        case "uJ", "µJ": joules = energy / 1e6
        case "nJ": joules = energy / 1e9
        default: return nil
        }
        return (joules / seconds * 100).rounded() / 100
    }
}

public enum BatteryInfo {
    /// Reads one power source description from `IOPSGetPowerSourceDescription`. Nil when it is not an internal
    /// battery (desktop Macs, UPSes) or has no capacity.
    public static func sample(from description: [String: Any]) -> BatterySample? {
        guard description["Type"] as? String == "InternalBattery",
              let current = description["Current Capacity"] as? Int,
              let maximum = description["Max Capacity"] as? Int, maximum > 0
        else { return nil }
        let charging = description["Is Charging"] as? Bool ?? false
        let minutes = (charging ? description["Time to Full Charge"] : description["Time to Empty"]) as? Int
        return BatterySample(percent: min(100, max(0, current * 100 / maximum)), charging: charging,
                             minutesLeft: minutes.flatMap { $0 > 0 ? $0 : nil })
    }
}
```

- [ ] **Step 4: Testin geçtiğini gör**

Run: aynı komut → Expected: `Test run with 15 tests in 5 suites passed`. Sonra `make test` → `94 tests in 19 suites`.

- [ ] **Step 5: Commit**

```bash
git add Sources/PhoneBoxCore/Metrics.swift Tests/PhoneBoxCoreTests/MetricsTests.swift
git commit -m "Add the metric samples, counter rates and sensor maths"
```

---

### Task 2: Uygulama listesi hesabı

**Files:**
- Create: `Sources/PhoneBoxCore/AppUsage.swift`
- Test: `Tests/PhoneBoxCoreTests/AppUsageTests.swift`

**Interfaces:**
- Consumes: `CPULoad.rounded(_:)`
- Produces: `struct ProcessReading { pid, path, cpuNanos, memory }`, `struct AppInfo { pid, bundleId, name, quittable }`,
  `struct AppSample { pid, bundleId?, name, cpu, mem, quittable }` (Codable), `AppUsage.topCount = 5`,
  `AppUsage.bundlePath(forExecutable:)`, `AppUsage.displayName(_:)`,
  `AppUsage.top(previousCPU:current:elapsedNanos:apps:) -> [AppSample]`.

- [ ] **Step 1: Başarısız testi yaz**

`Tests/PhoneBoxCoreTests/AppUsageTests.swift`:

```swift
import Foundation
import Testing
@testable import PhoneBoxCore

struct AppUsageTests {
    let chrome = "/Applications/Google Chrome.app"
    let second: UInt64 = 1_000_000_000

    @Test func findsTheOutermostAppBundle() {
        let helper = chrome + "/Contents/Frameworks/Google Chrome Framework.framework/Helpers/"
            + "Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        #expect(AppUsage.bundlePath(forExecutable: helper) == chrome)
        #expect(AppUsage.bundlePath(forExecutable: chrome + "/Contents/MacOS/Google Chrome") == chrome)
        #expect(AppUsage.bundlePath(forExecutable: "/usr/bin/swift-frontend") == nil)
        #expect(AppUsage.bundlePath(forExecutable: "/Users/eren/my.application/run") == nil)
    }

    @Test func removesDirectionMarksFromNames() {
        #expect(AppUsage.displayName("\u{200E}WhatsApp") == "WhatsApp")
        #expect(AppUsage.displayName(" \u{202B}Safari\u{202C} ") == "Safari")
        #expect(AppUsage.displayName("çğıöşü") == "çğıöşü")
    }

    @Test func groupsHelpersIntoTheirAppAndComputesPercentOfOneCore() {
        let apps = [chrome: AppInfo(pid: 10, bundleId: "com.google.Chrome", name: "Google Chrome", quittable: true)]
        let helperPath = chrome + "/Contents/Frameworks/X.framework/Helpers/Helper.app/Contents/MacOS/Helper"
        let current = [
            ProcessReading(pid: 10, path: chrome + "/Contents/MacOS/Google Chrome", cpuNanos: 3 * second, memory: 100),
            ProcessReading(pid: 11, path: helperPath, cpuNanos: 2 * second, memory: 50),
        ]
        let top = AppUsage.top(previousCPU: [10: 2 * second, 11: second / 2], current: current, elapsedNanos: 2 * second,
                               apps: apps)
        #expect(top == [AppSample(pid: 10, bundleId: "com.google.Chrome", name: "Google Chrome", cpu: 125, mem: 150,
                                  quittable: true)])
    }

    @Test func newOrResetProcessesCountAsZeroThisTime() {
        let current = [ProcessReading(pid: 7, path: "/usr/bin/node", cpuNanos: 5 * second, memory: 10),
                       ProcessReading(pid: 8, path: "/usr/bin/ruby", cpuNanos: 1, memory: 20)]
        let top = AppUsage.top(previousCPU: [8: 9 * second], current: current, elapsedNanos: second, apps: [:])
        #expect(top.map(\.cpu) == [0, 0])
        #expect(Set(top.map(\.name)) == ["node", "ruby"])
        #expect(top.allSatisfy { !$0.quittable && $0.bundleId == nil })
    }

    @Test func namesAnAppThatMacOSDoesNotListAfterItsBundle() {
        let current = [ProcessReading(pid: 5, path: "/Applications/Tool.app/Contents/MacOS/tool", cpuNanos: 0, memory: 1)]
        #expect(AppUsage.top(previousCPU: [:], current: current, elapsedNanos: second, apps: [:]).first?.name == "Tool")
    }

    @Test func listsTopByCPUThenTopByMemoryWithoutDuplicates() {
        var current: [ProcessReading] = []
        var previous: [Int32: UInt64] = [:]
        for index in 1...8 {
            let pid = Int32(index)
            previous[pid] = 0
            // CPU grows with the index, memory shrinks with it.
            current.append(ProcessReading(pid: pid, path: "/bin/p\(index)", cpuNanos: UInt64(index) * second / 10,
                                          memory: UInt64(100 - index)))
        }
        let top = AppUsage.top(previousCPU: previous, current: current, elapsedNanos: second, apps: [:])
        #expect(top.map(\.name) == ["p8", "p7", "p6", "p5", "p4", "p1", "p2", "p3"])
    }

    @Test func returnsNothingForNoElapsedTime() {
        let current = [ProcessReading(pid: 1, path: "/bin/a", cpuNanos: 1, memory: 1)]
        #expect(AppUsage.top(previousCPU: [:], current: current, elapsedNanos: 0, apps: [:]).isEmpty)
    }
}
```

- [ ] **Step 2: Testin başarısız olduğunu gör**

Run: `make test FILTER=AppUsageTests` → Expected: FAIL — `cannot find 'AppUsage' in scope`.

- [ ] **Step 3: Uygulamayı yaz**

`Sources/PhoneBoxCore/AppUsage.swift`:

```swift
import Foundation

/// One process as `libproc` reports it.
public struct ProcessReading: Equatable, Sendable {
    public var pid: Int32
    /// Path of the executable.
    public var path: String
    /// User + system CPU time so far, in nanoseconds.
    public var cpuNanos: UInt64
    /// Physical footprint in bytes (what Activity Monitor calls Memory).
    public var memory: UInt64

    public init(pid: Int32, path: String, cpuNanos: UInt64, memory: UInt64) {
        self.pid = pid
        self.path = path
        self.cpuNanos = cpuNanos
        self.memory = memory
    }
}

/// What macOS knows about a running app, keyed by its bundle path (from `NSRunningApplication`).
public struct AppInfo: Equatable, Sendable {
    public var pid: Int32
    public var bundleId: String?
    public var name: String
    /// A regular (Dock) app that the phone may quit later (Plan 3B); Finder and PhoneBox are never quittable.
    public var quittable: Bool

    public init(pid: Int32, bundleId: String?, name: String, quittable: Bool) {
        self.pid = pid
        self.bundleId = bundleId
        self.name = name
        self.quittable = quittable
    }
}

/// One row of the "apps" list (design §6).
public struct AppSample: Equatable, Codable, Sendable {
    public var pid: Int32
    public var bundleId: String?
    public var name: String
    /// Percent of one core, like Activity Monitor (can exceed 100).
    public var cpu: Double
    /// Bytes.
    public var mem: UInt64
    public var quittable: Bool

    public init(pid: Int32, bundleId: String?, name: String, cpu: Double, mem: UInt64, quittable: Bool) {
        self.pid = pid
        self.bundleId = bundleId
        self.name = name
        self.cpu = cpu
        self.mem = mem
        self.quittable = quittable
    }
}

public enum AppUsage {
    public static let topCount = 5

    /// The outermost `.app` bundle that contains an executable, so that "Google Chrome Helper (Renderer)" deep
    /// inside Chrome counts as Chrome. Nil when the executable is not inside an app.
    public static func bundlePath(forExecutable path: String) -> String? {
        var components: [Substring] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: false) {
            components.append(component)
            if component.hasSuffix(".app") { return components.joined(separator: "/") }
        }
        return nil
    }

    /// Removes the invisible direction marks some apps put in their names (WhatsApp starts with U+200E) and trims.
    public static func displayName(_ raw: String) -> String {
        let marks: Set<Unicode.Scalar> = ["\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}",
                                          "\u{202E}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}"]
        let kept = raw.unicodeScalars.filter { !marks.contains($0) }
        return String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Groups processes into apps, turns CPU time into percent of one core over `elapsedNanos`, and returns the
    /// top apps by CPU followed by the top apps by memory that are not already listed (at most 2 × `topCount`).
    /// A process with no earlier reading (or whose counter went backwards) counts as 0 % this time.
    public static func top(previousCPU: [Int32: UInt64], current: [ProcessReading], elapsedNanos: UInt64,
                           apps: [String: AppInfo]) -> [AppSample] {
        guard elapsedNanos > 0 else { return [] }
        struct Group {
            var pid: Int32
            var bundleId: String?
            var name: String
            var quittable: Bool
            var cpuNanos: UInt64 = 0
            var memory: UInt64 = 0
        }
        var groups: [String: Group] = [:]
        for process in current {
            let bundle = bundlePath(forExecutable: process.path)
            let key = bundle ?? process.path
            var group = groups[key] ?? {
                if let bundle, let info = apps[bundle] {
                    return Group(pid: info.pid, bundleId: info.bundleId, name: displayName(info.name),
                                 quittable: info.quittable)
                }
                let fallback = bundle.map { ($0 as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "") }
                return Group(pid: process.pid, bundleId: nil,
                             name: displayName(fallback ?? (process.path as NSString).lastPathComponent), quittable: false)
            }()
            if let before = previousCPU[process.pid], process.cpuNanos >= before {
                group.cpuNanos += process.cpuNanos - before
            }
            group.memory += process.memory
            groups[key] = group
        }
        let samples = groups.values.map { group in
            AppSample(pid: group.pid, bundleId: group.bundleId, name: group.name,
                      cpu: CPULoad.rounded(Double(group.cpuNanos) / Double(elapsedNanos) * 100),
                      mem: group.memory, quittable: group.quittable)
        }
        let byCPU = samples.sorted { ($0.cpu, $0.mem) > ($1.cpu, $1.mem) }.prefix(topCount)
        let byMemory = samples.sorted { $0.mem > $1.mem }.prefix(topCount)
        var result = Array(byCPU)
        for sample in byMemory where !result.contains(where: { $0.pid == sample.pid && $0.name == sample.name }) {
            result.append(sample)
        }
        return result
    }
}
```

- [ ] **Step 4: Testin geçtiğini gör**

Run: `make test FILTER=AppUsageTests` → `7 tests in 1 suite`; `make test` → `101 tests in 20 suites`.

- [ ] **Step 5: Commit**

```bash
git add Sources/PhoneBoxCore/AppUsage.swift Tests/PhoneBoxCoreTests/AppUsageTests.swift
git commit -m "Group processes into apps and rank them by CPU and memory"
```

---

### Task 3: Snapshot'a yeni alanlar ve çökmeyen JSON

**Files:**
- Modify: `Sources/PhoneBoxCore/Snapshot.swift` (dosyanın tamamı aşağıdaki gibi)
- Modify: `Sources/PhoneBoxCore/Messages.swift` (dosyanın tamamı aşağıdaki gibi; `try!` kalkar)
- Test: `Tests/PhoneBoxCoreTests/MessagesTests.swift` (dosyanın tamamı aşağıdaki gibi; iki test eklenir)

**Interfaces:**
- Consumes: Görev 1 ve 2'nin örnek tipleri.
- Produces: `Snapshot(t:cpu:mem:gpu:temp:power:net:disk:battery:apps:)`; `ServerMessage.json()` artık hiç çökmez:
  kodlanamayan bir snapshot sadece `t` ile gönderilir.

- [ ] **Step 1: Testleri yaz**

`Tests/PhoneBoxCoreTests/MessagesTests.swift`:

```swift
import Testing
@testable import PhoneBoxCore

struct ServerMessageTests {
    @Test func encodesHello() {
        #expect(ServerMessage.hello(nonce: "ab", app: "PhoneBox 0.1.0").json()
            == #"{"app":"PhoneBox 0.1.0","nonce":"ab","type":"hello","v":1}"#)
    }

    @Test func encodesReadyWithTheAccessObject() {
        #expect(ServerMessage.ready(mode: .cable, access: .notOnCable).json()
            == #"{"access":{"commands":false,"reason":"not-on-cable","streaming":false},"mode":"cable","type":"ready","v":1}"#)
    }

    @Test func encodesAccessFlat() {
        #expect(ServerMessage.access(.granted).json()
            == #"{"commands":true,"reason":"ok","streaming":true,"type":"access","v":1}"#)
    }

    @Test func encodesSnapshotAndLeavesOutMissingMetrics() {
        let cpu = CPUSample(total: 12.5, cores: [10, 15], pCores: 1, load: [1, 2, 3])
        #expect(ServerMessage.snapshot(Snapshot(t: 1_000, cpu: cpu)).json()
            == #"{"cpu":{"cores":[10,15],"load":[1,2,3],"pCores":1,"total":12.5},"t":1000,"type":"snapshot","v":1}"#)
    }

    @Test func encodesEveryPlan3AMetric() {
        let snapshot = Snapshot(
            t: 5, gpu: GPUSample(util: 17), temp: TemperatureSample(avg: 52.5, max: 56), power: PowerSample(gpu: 0.2, system: nil),
            net: NetworkSample(rx: 1_200, tx: 30, iface: "en0"), disk: DiskSample(free: 10, total: 20, read: nil, write: 4),
            battery: BatterySample(percent: 86, charging: true, minutesLeft: nil),
            apps: [AppSample(pid: 9, bundleId: nil, name: "node", cpu: 1.5, mem: 64, quittable: false)])
        #expect(ServerMessage.snapshot(snapshot).json()
            == #"{"apps":[{"cpu":1.5,"mem":64,"name":"node","pid":9,"quittable":false}],"#
            + #""battery":{"charging":true,"percent":86},"disk":{"free":10,"total":20,"write":4},"gpu":{"util":17},"#
            + #""net":{"iface":"en0","rx":1200,"tx":30},"power":{"gpu":0.2},"t":5,"temp":{"avg":52.5,"max":56},"#
            + #""type":"snapshot","v":1}"#)
    }

    @Test func aSnapshotWithANonFiniteNumberFallsBackToItsTimestamp() {
        let snapshot = Snapshot(t: 7, cpu: CPUSample(total: .nan, cores: [], pCores: 0, load: []), gpu: GPUSample(util: 3))
        #expect(ServerMessage.snapshot(snapshot).json() == #"{"t":7,"type":"snapshot","v":1}"#)
    }

    @Test func encodesAcks() {
        #expect(ServerMessage.ack(seq: 4, ok: true, error: nil).json() == #"{"ok":true,"seq":4,"type":"ack","v":1}"#)
        #expect(ServerMessage.ack(seq: 5, ok: false, error: "not-allowed").json()
            == #"{"error":"not-allowed","ok":false,"seq":5,"type":"ack","v":1}"#)
    }
}

struct ClientMessageTests {
    @Test func parsesAuth() {
        #expect(ClientMessage.parse(#"{"v":1,"type":"auth","mac":"ff"}"#) == .auth(mac: "ff"))
    }

    @Test func parsesCommandsKeepingArgsAsText() {
        #expect(ClientMessage.parse(#"{"v":1,"type":"cmd","seq":2,"name":"mute","args":"{\"on\":true}","mac":"aa"}"#)
            == .command(seq: 2, name: "mute", args: #"{"on":true}"#, mac: "aa"))
    }

    @Test func rejectsOtherVersionsTypesAndJunk() {
        #expect(ClientMessage.parse(#"{"v":2,"type":"auth","mac":"ff"}"#) == nil)
        #expect(ClientMessage.parse(#"{"v":1,"type":"hello"}"#) == nil)
        #expect(ClientMessage.parse(#"{"v":1,"type":"cmd","seq":"2","name":"x","args":"{}","mac":"a"}"#) == nil)
        #expect(ClientMessage.parse("not json") == nil)
        #expect(ClientMessage.parse("[1,2]") == nil)
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `make test FILTER=ServerMessageTests` → Expected: FAIL — `Snapshot` için `gpu:` gibi argümanlar yok (derleme hatası).

- [ ] **Step 3: Snapshot ve mesajlar**

`Sources/PhoneBoxCore/Snapshot.swift`:

```swift
/// One second of the Mac, as the phone receives it (design §6). A metric that could not be read is left out
/// of the JSON; the dashboard shows "—" for it. `apps` is sent every third second.
public struct Snapshot: Equatable, Codable, Sendable {
    /// Milliseconds since 1970.
    public var t: Int64
    public var cpu: CPUSample?
    public var mem: MemorySample?
    public var gpu: GPUSample?
    public var temp: TemperatureSample?
    public var power: PowerSample?
    public var net: NetworkSample?
    public var disk: DiskSample?
    public var battery: BatterySample?
    public var apps: [AppSample]?

    public init(t: Int64, cpu: CPUSample? = nil, mem: MemorySample? = nil, gpu: GPUSample? = nil,
                temp: TemperatureSample? = nil, power: PowerSample? = nil, net: NetworkSample? = nil,
                disk: DiskSample? = nil, battery: BatterySample? = nil, apps: [AppSample]? = nil) {
        self.t = t
        self.cpu = cpu
        self.mem = mem
        self.gpu = gpu
        self.temp = temp
        self.power = power
        self.net = net
        self.disk = disk
        self.battery = battery
        self.apps = apps
    }
}
```

`Sources/PhoneBoxCore/Messages.swift`:

```swift
import Foundation

/// Messages from the Mac to the phone (design §5). Every message carries `"v":1`.
public enum ServerMessage: Equatable, Sendable {
    case hello(nonce: String, app: String)
    case ready(mode: AccessMode, access: Access)
    case access(Access)
    case snapshot(Snapshot)
    case ack(seq: Int, ok: Bool, error: String?)

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    /// Compact JSON with sorted keys. Never crashes: a snapshot that cannot be encoded (a non-finite number that
    /// slipped past a collector) is sent with its timestamp only, and the phone keeps its previous values.
    public func json() -> String {
        if let data = try? Self.encoder.encode(self) { return String(decoding: data, as: UTF8.self) }
        if case let .snapshot(snapshot) = self, snapshot != Snapshot(t: snapshot.t) {
            return ServerMessage.snapshot(Snapshot(t: snapshot.t)).json()
        }
        return #"{"type":"error","v":1}"#
    }
}

extension ServerMessage: Encodable {
    private enum Keys: String, CodingKey {
        case v, type, nonce, app, mode, access, streaming, commands, reason, t, cpu, mem, gpu, temp, power, net, disk,
             battery, apps, seq, ok, error
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(1, forKey: .v)
        switch self {
        case let .hello(nonce, app):
            try container.encode("hello", forKey: .type)
            try container.encode(nonce, forKey: .nonce)
            try container.encode(app, forKey: .app)
        case let .ready(mode, access):
            try container.encode("ready", forKey: .type)
            try container.encode(mode, forKey: .mode)
            try container.encode(access, forKey: .access)
        case let .access(access):
            try container.encode("access", forKey: .type)
            try container.encode(access.streaming, forKey: .streaming)
            try container.encode(access.commands, forKey: .commands)
            try container.encode(access.reason, forKey: .reason)
        case let .snapshot(snapshot):
            try container.encode("snapshot", forKey: .type)
            try container.encode(snapshot.t, forKey: .t)
            try container.encodeIfPresent(snapshot.cpu, forKey: .cpu)
            try container.encodeIfPresent(snapshot.mem, forKey: .mem)
            try container.encodeIfPresent(snapshot.gpu, forKey: .gpu)
            try container.encodeIfPresent(snapshot.temp, forKey: .temp)
            try container.encodeIfPresent(snapshot.power, forKey: .power)
            try container.encodeIfPresent(snapshot.net, forKey: .net)
            try container.encodeIfPresent(snapshot.disk, forKey: .disk)
            try container.encodeIfPresent(snapshot.battery, forKey: .battery)
            try container.encodeIfPresent(snapshot.apps, forKey: .apps)
        case let .ack(seq, ok, error):
            try container.encode("ack", forKey: .type)
            try container.encode(seq, forKey: .seq)
            try container.encode(ok, forKey: .ok)
            try container.encodeIfPresent(error, forKey: .error)
        }
    }
}

/// Messages from the phone to the Mac.
public enum ClientMessage: Equatable, Sendable {
    case auth(mac: String)
    /// `args` is the JSON text exactly as the phone signed it.
    case command(seq: Int, name: String, args: String, mac: String)

    /// Nil for anything that is not a well-formed version 1 message.
    public static func parse(_ text: String) -> ClientMessage? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              object["v"] as? Int == 1
        else { return nil }
        switch object["type"] as? String {
        case "auth":
            guard let mac = object["mac"] as? String else { return nil }
            return .auth(mac: mac)
        case "cmd":
            guard let seq = object["seq"] as? Int, let name = object["name"] as? String,
                  let args = object["args"] as? String, let mac = object["mac"] as? String
            else { return nil }
            return .command(seq: seq, name: name, args: args, mac: mac)
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini gör**

Run: `make test FILTER=ServerMessageTests` → `7 tests in 1 suite`; `make test` → `103 tests in 20 suites`.

- [ ] **Step 5: Commit**

```bash
git add Sources/PhoneBoxCore/Snapshot.swift Sources/PhoneBoxCore/Messages.swift Tests/PhoneBoxCoreTests/MessagesTests.swift
git commit -m "Send the new metrics and never crash on a value that cannot be encoded"
```

---

### Task 4: GPU, sıcaklık ve güç toplayıcıları

**Files:**
- Create: `Sources/PhoneBox/Collectors/HostPort.swift`, `Sources/PhoneBox/Collectors/PrivateSymbols.swift`,
  `Sources/PhoneBox/Collectors/GPUCollector.swift`, `Sources/PhoneBox/Collectors/TemperatureCollector.swift`,
  `Sources/PhoneBox/Collectors/PowerCollector.swift`
- Modify: `Sources/PhoneBox/Collectors/CPUCollector.swift`, `Sources/PhoneBox/Collectors/MemoryCollector.swift`
  (`mach_host_self()` yerine `HostPort.host`)

**Interfaces:**
- Consumes: `Temperatures`, `EnergyRate`, `finiteOrNil`, `Log`
- Produces: `HostPort.host`; `PrivateSymbols.function(_:_:as:)`, `.iokit`, `.ioReport`; `GPUCollector().sample()`,
  `TemperatureCollector().sample()` (5 sn önbellekli), `PowerCollector().sample()` / `.reset()`.

Bu görevdeki kod sistemle konuşur; birim testi yoktur, doğrulama derleme ve Görev 7'deki çalıştırmadır.

- [ ] **Step 1: Ortak yardımcılar**

`Sources/PhoneBox/Collectors/HostPort.swift`:

```swift
import Darwin

/// `mach_host_self()` hands out a new send right on every call; ask once instead of twice a second.
enum HostPort {
    static let host: host_t = mach_host_self()
}
```

`Sources/PhoneBox/Collectors/PrivateSymbols.swift`:

```swift
import Foundation

/// Looks up a function in a private library at run time. If macOS removes it, the collector that needs it returns
/// nil and the dashboard shows "—" for that metric (design §13, "Resmi olmayan API'ler").
enum PrivateSymbols {
    static func function<T>(_ library: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
        guard let library, let pointer = dlsym(library, name) else {
            Log.app.notice("Private symbol \(name, privacy: .public) is not available")
            return nil
        }
        return unsafeBitCast(pointer, to: type)
    }

    static let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
    static let ioReport = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW)
}
```

`CPUCollector.swift` ve `MemoryCollector.swift`'te `mach_host_self()` çağrısını `HostPort.host` ile değiştir:

```bash
sed -i '' 's/host_processor_info(mach_host_self(), /host_processor_info(HostPort.host, /' Sources/PhoneBox/Collectors/CPUCollector.swift
sed -i '' 's/host_statistics64(mach_host_self(), /host_statistics64(HostPort.host, /' Sources/PhoneBox/Collectors/MemoryCollector.swift
grep -n "mach_host_self" Sources/PhoneBox/Collectors/CPUCollector.swift Sources/PhoneBox/Collectors/MemoryCollector.swift
```

Expected: son `grep` hiçbir şey yazmaz.

- [ ] **Step 2: GPU, sıcaklık, güç**

`Sources/PhoneBox/Collectors/GPUCollector.swift`:

```swift
import IOKit
import PhoneBoxCore

/// GPU busy percentage from the accelerator's `PerformanceStatistics` (public IOKit; spike 6).
final class GPUCollector {
    func sample() -> GPUSample? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString,
                                                           kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let utilisation = stats["Device Utilization %"] as? Int {
                return GPUSample(util: Double(min(100, max(0, utilisation))))
            }
        }
        return nil
    }
}
```

`Sources/PhoneBox/Collectors/TemperatureCollector.swift`:

```swift
import Foundation
import PhoneBoxCore

/// Chip temperature from the HID temperature sensors (`IOHIDEventSystemClient`, private; spike 6).
///
/// Every sensor read is a call into the HID system, and reading all 44 sensors each second cost about 3 % CPU on an
/// M4. So it reads only the chip sensors, every 5 seconds (temperature changes slowly), and looks the sensor list up
/// again once a minute.
final class TemperatureCollector {
    private typealias ClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias ClientSetMatching = @convention(c) (CFTypeRef, CFDictionary) -> Int32
    private typealias ClientCopyServices = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias ServiceCopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias ServiceCopyEvent = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias EventGetFloatValue = @convention(c) (CFTypeRef, Int32) -> Double

    static let readInterval: TimeInterval = 5
    static let sensorListInterval: TimeInterval = 60
    private static let temperatureEvent: Int64 = 15  // kIOHIDEventTypeTemperature

    private let copyServices: ClientCopyServices?
    private let copyProperty: ServiceCopyProperty?
    private let copyEvent: ServiceCopyEvent?
    private let floatValue: EventGetFloatValue?
    private let client: CFTypeRef?
    private var sensors: [(name: String, service: CFTypeRef)] = []
    private var sensorsTime: TimeInterval = -.infinity
    private var last: TemperatureSample?
    private var lastTime: TimeInterval = -.infinity

    init() {
        let library = PrivateSymbols.iokit
        let create = PrivateSymbols.function(library, "IOHIDEventSystemClientCreate", as: ClientCreate.self)
        let setMatching = PrivateSymbols.function(library, "IOHIDEventSystemClientSetMatching", as: ClientSetMatching.self)
        copyServices = PrivateSymbols.function(library, "IOHIDEventSystemClientCopyServices", as: ClientCopyServices.self)
        copyProperty = PrivateSymbols.function(library, "IOHIDServiceClientCopyProperty", as: ServiceCopyProperty.self)
        copyEvent = PrivateSymbols.function(library, "IOHIDServiceClientCopyEvent", as: ServiceCopyEvent.self)
        floatValue = PrivateSymbols.function(library, "IOHIDEventGetFloatValue", as: EventGetFloatValue.self)
        client = create?(kCFAllocatorDefault)?.takeRetainedValue()
        if let client, let setMatching {
            _ = setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        }
    }

    /// The last summary, read again at most every `readInterval`.
    func sample() -> TemperatureSample? {
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
        guard now - lastTime >= Self.readInterval else { return last }
        lastTime = now
        if now - sensorsTime >= Self.sensorListInterval || sensors.isEmpty {
            sensors = chipSensors()
            sensorsTime = now
        }
        guard let copyEvent, let floatValue else { return nil }
        var readings: [(name: String, celsius: Double)] = []
        for sensor in sensors {
            guard let event = copyEvent(sensor.service, Self.temperatureEvent, 0, 0)?.takeRetainedValue(),
                  let celsius = floatValue(event, Int32(Self.temperatureEvent << 16)).finiteOrNil
            else { continue }
            readings.append((sensor.name, celsius))
        }
        last = Temperatures.summary(readings)
        return last
    }

    private func chipSensors() -> [(name: String, service: CFTypeRef)] {
        guard let client, let copyServices, let copyProperty,
              let services = copyServices(client)?.takeRetainedValue() as? [CFTypeRef]
        else { return [] }
        let named = services.compactMap { service -> (name: String, service: CFTypeRef)? in
            guard let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String else { return nil }
            return (name, service)
        }
        let chosen = Temperatures.chipSensors(named.map(\.name))
        return named.filter { chosen.contains($0.name) }
    }
}
```

`Sources/PhoneBox/Collectors/PowerCollector.swift`:

```swift
import Foundation
import IOKit
import PhoneBoxCore

/// GPU watts from IOReport's "GPU Energy" counter (private) and whole-Mac watts from the battery telemetry (public).
/// CPU and Neural Engine counters do not move without root on Apple silicon (spike 6), so they are not read.
final class PowerCollector {
    private typealias CopyChannelsInGroup = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias CreateSubscription = @convention(c) (UnsafeRawPointer?, CFMutableDictionary,
        UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?) -> Unmanaged<CFTypeRef>?
    private typealias CreateSamples = @convention(c) (CFTypeRef, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateSamplesDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias ChannelString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias SimpleIntegerValue = @convention(c) (CFDictionary, Int32) -> Int64

    private let createSamples: CreateSamples?
    private let createDelta: CreateSamplesDelta?
    private let channelName: ChannelString?
    private let unitLabel: ChannelString?
    private let integerValue: SimpleIntegerValue?
    private var subscription: CFTypeRef?
    private var subscribedChannels: CFMutableDictionary?
    private var previous: (sample: CFDictionary, time: UInt64)?

    init() {
        let library = PrivateSymbols.ioReport
        createSamples = PrivateSymbols.function(library, "IOReportCreateSamples", as: CreateSamples.self)
        createDelta = PrivateSymbols.function(library, "IOReportCreateSamplesDelta", as: CreateSamplesDelta.self)
        channelName = PrivateSymbols.function(library, "IOReportChannelGetChannelName", as: ChannelString.self)
        unitLabel = PrivateSymbols.function(library, "IOReportChannelGetUnitLabel", as: ChannelString.self)
        integerValue = PrivateSymbols.function(library, "IOReportSimpleGetIntegerValue", as: SimpleIntegerValue.self)
        guard let copyChannels = PrivateSymbols.function(library, "IOReportCopyChannelsInGroup", as: CopyChannelsInGroup.self),
              let subscribe = PrivateSymbols.function(library, "IOReportCreateSubscription", as: CreateSubscription.self),
              let channels = copyChannels("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue(),
              let mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, CFDictionaryGetCount(channels), channels)
        else { return }
        var subscribed: Unmanaged<CFMutableDictionary>?
        subscription = subscribe(nil, mutable, &subscribed, 0, nil)?.takeRetainedValue()
        subscribedChannels = subscribed?.takeUnretainedValue()
    }

    /// Forget the last reading, e.g. after the Mac wakes.
    func reset() {
        previous = nil
    }

    func sample() -> PowerSample? {
        let gpu = gpuWatts()
        let system = Self.systemWatts()
        guard gpu != nil || system != nil else { return nil }
        return PowerSample(gpu: gpu, system: system)
    }

    private func gpuWatts() -> Double? {
        guard let subscription, let subscribedChannels, let createSamples, let createDelta, let channelName, let unitLabel,
              let integerValue, let current = createSamples(subscription, subscribedChannels, nil)?.takeRetainedValue()
        else { return nil }
        let now = DispatchTime.now().uptimeNanoseconds
        defer { previous = (current, now) }
        guard let previous, now > previous.time,
              let delta = createDelta(previous.sample, current, nil)?.takeRetainedValue(),
              let items = (delta as NSDictionary)["IOReportChannels"] as? [NSDictionary]
        else { return nil }
        let seconds = Double(now - previous.time) / 1e9
        for item in items {
            let channel = item as CFDictionary
            guard channelName(channel)?.takeUnretainedValue() as String? == "GPU Energy",
                  let unit = unitLabel(channel)?.takeUnretainedValue() as String?
            else { continue }
            return EnergyRate.watts(energy: Double(integerValue(channel, 0)), unit: unit, seconds: seconds)
        }
        return nil
    }

    /// `AppleSmartBattery` → `PowerTelemetryData.SystemPowerIn` (milliwatts); nil on Macs without a battery.
    static func systemWatts() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let telemetry = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
              let milliwatts = telemetry["SystemPowerIn"] as? Int, milliwatts >= 0
        else { return nil }
        return (Double(milliwatts) / 10).rounded() / 100
    }
}
```

- [ ] **Step 3: Derle**

Run: `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"` → Expected: çıktı yok.

- [ ] **Step 4: Commit**

```bash
git add Sources/PhoneBox/Collectors
git commit -m "Read GPU use, chip temperature and power"
```

---

### Task 5: Ağ, disk, pil ve uygulama toplayıcıları

**Files:**
- Create: `Sources/PhoneBox/Collectors/NetworkCollector.swift`, `Sources/PhoneBox/Collectors/DiskCollector.swift`,
  `Sources/PhoneBox/Collectors/BatteryCollector.swift`, `Sources/PhoneBox/Collectors/AppsCollector.swift`

**Interfaces:**
- Consumes: `CounterRate`, `BatteryInfo`, `AppUsage`, `ProcessReading`, `AppInfo`
- Produces: `NetworkCollector().sample()` / `.reset()`, `DiskCollector().sample()` / `.reset()`,
  `BatteryCollector().sample()`, `AppsCollector().sample()` / `.reset()` (`@MainActor`).

- [ ] **Step 1: Toplayıcıları yaz**

`Sources/PhoneBox/Collectors/NetworkCollector.swift`:

```swift
import Darwin
import Foundation
import PhoneBoxCore
import SystemConfiguration

/// Download and upload speed of the primary network interface. Uses the 64-bit counters from
/// `sysctl(NET_RT_IFLIST2)`; the 32-bit ones in `getifaddrs` wrap every 4 GB.
final class NetworkCollector {
    private var interface: String?
    private var received = CounterRate()
    private var sent = CounterRate()

    func reset() {
        received.reset()
        sent.reset()
    }

    func sample() -> NetworkSample? {
        guard let name = Self.primaryInterface(), let counters = Self.counters(for: name) else { return nil }
        if name != interface {
            interface = name
            reset()
        }
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
        guard let rx = received.rate(value: counters.rx, at: now), let tx = sent.rate(value: counters.tx, at: now)
        else { return nil }
        return NetworkSample(rx: rx, tx: tx, iface: name)
    }

    /// The interface macOS uses for the default route, e.g. `en0` (Wi-Fi).
    static func primaryInterface() -> String? {
        let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        return global?["PrimaryInterface"] as? String
    }

    static func counters(for name: String) -> (rx: UInt64, tx: UInt64)? {
        let index = if_nametoindex(name)
        guard index != 0 else { return nil }
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return nil }
        return buffer.withUnsafeBytes { raw -> (rx: UInt64, tx: UInt64)? in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { return nil }
                if Int32(header.ifm_type) == RTM_IFINFO2, header.ifm_index == UInt16(index),
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    return (message.ifm_data.ifi_ibytes, message.ifm_data.ifi_obytes)
                }
                offset += Int(header.ifm_msglen)
            }
            return nil
        }
    }
}
```

`Sources/PhoneBox/Collectors/DiskCollector.swift`:

```swift
import Foundation
import IOKit
import PhoneBoxCore

/// Free and total space of the startup volume (refreshed every 10 s; it is slow to compute) and the read/write
/// speed of all block storage drivers.
final class DiskCollector {
    private static let capacityInterval: TimeInterval = 10
    private var capacity: (free: UInt64, total: UInt64)?
    private var capacityTime: TimeInterval = -.infinity
    private var reads = CounterRate()
    private var writes = CounterRate()

    func reset() {
        reads.reset()
        writes.reset()
    }

    func sample() -> DiskSample? {
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
        if now - capacityTime >= Self.capacityInterval {
            capacity = Self.readCapacity()
            capacityTime = now
        }
        guard let capacity else { return nil }
        let bytes = Self.readBytes()
        return DiskSample(free: capacity.free, total: capacity.total,
                          read: bytes.flatMap { reads.rate(value: $0.read, at: now) },
                          write: bytes.flatMap { writes.rate(value: $0.written, at: now) })
    }

    static func readCapacity() -> (free: UInt64, total: UInt64)? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0,
              let free = values.volumeAvailableCapacityForImportantUsage, free >= 0
        else { return nil }
        return (UInt64(free), UInt64(total))
    }

    /// Bytes read and written since boot, summed over every `IOBlockStorageDriver`.
    static func readBytes() -> (read: UInt64, written: UInt64)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator)
                == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0
        var written: UInt64 = 0
        var found = false
        while case let driver = IOIteratorNext(iterator), driver != 0 {
            defer { IOObjectRelease(driver) }
            guard let statistics = IORegistryEntryCreateCFProperty(driver, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any]
            else { continue }
            read += UInt64(max(0, statistics["Bytes (Read)"] as? Int ?? 0))
            written += UInt64(max(0, statistics["Bytes (Write)"] as? Int ?? 0))
            found = true
        }
        return found ? (read, written) : nil
    }
}
```

`Sources/PhoneBox/Collectors/BatteryCollector.swift`:

```swift
import IOKit.ps
import PhoneBoxCore

/// The internal battery from the power sources API; nil on Macs without one.
final class BatteryCollector {
    func sample() -> BatterySample? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
               let sample = BatteryInfo.sample(from: description) {
                return sample
            }
        }
        return nil
    }
}
```

`Sources/PhoneBox/Collectors/AppsCollector.swift`:

```swift
import AppKit
import Darwin
import PhoneBoxCore

/// The apps using the most CPU and memory (design §6). Reads every process this user may inspect through `libproc`;
/// processes of other users (root daemons such as WindowServer) cannot be read without privileges and are skipped.
@MainActor
final class AppsCollector {
    /// Asking `NSWorkspace` for the running apps is costly; a list up to 10 s old is good enough for names.
    static let appListInterval: UInt64 = 10_000_000_000
    private var previousCPU: [Int32: UInt64] = [:]
    private var previousTime: UInt64?
    private var apps: [String: AppInfo] = [:]
    private var appsTime: UInt64?

    func reset() {
        previousCPU = [:]
        previousTime = nil
        appsTime = nil
    }

    func sample() -> [AppSample]? {
        let now = DispatchTime.now().uptimeNanoseconds
        let readings = Self.readProcesses()
        defer {
            previousCPU = Dictionary(readings.map { ($0.pid, $0.cpuNanos) }, uniquingKeysWith: { first, _ in first })
            previousTime = now
        }
        guard let previousTime, now > previousTime else { return nil }
        if appsTime.map({ now - $0 >= Self.appListInterval }) ?? true {
            apps = Self.runningApps()
            appsTime = now
        }
        return AppUsage.top(previousCPU: previousCPU, current: readings, elapsedNanos: now - previousTime, apps: apps)
    }

    /// `rusage` CPU times are in Mach absolute time units; this converts them to nanoseconds.
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(1, info.denom)))
    }()

    static func readProcesses() -> [ProcessReading] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return [] }
        var readings: [ProcessReading] = []
        readings.reserveCapacity(Int(count))
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        for pid in pids.prefix(Int(count)) where pid > 0 {
            var usage = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            guard result == 0, proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            let ticks = usage.ri_user_time &+ usage.ri_system_time
            let nanos = ticks.multipliedReportingOverflow(by: timebase.numer)
            readings.append(ProcessReading(pid: pid, path: String(cString: path),
                                           cpuNanos: nanos.overflow ? ticks : nanos.partialValue / timebase.denom,
                                           memory: usage.ri_phys_footprint))
        }
        return readings
    }

    /// Running apps keyed by bundle path, so helper processes can be named after their app.
    static func runningApps() -> [String: AppInfo] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var apps: [String: AppInfo] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let path = app.bundleURL?.path else { continue }
            let quittable = app.activationPolicy == .regular && app.bundleIdentifier != "com.apple.finder"
                && app.processIdentifier != ownPID
            apps[path] = AppInfo(pid: app.processIdentifier, bundleId: app.bundleIdentifier,
                                 name: app.localizedName ?? (path as NSString).lastPathComponent, quittable: quittable)
        }
        return apps
    }
}
```

- [ ] **Step 2: Derle**

Run: `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"` → Expected: çıktı yok.

- [ ] **Step 3: Commit**

```bash
git add Sources/PhoneBox/Collectors
git commit -m "Read network, disk and battery figures and the busiest apps"
```

---

### Task 6: Örnekleyiciyi bağla

**Files:**
- Modify: `Sources/PhoneBox/Sampler.swift` (dosyanın tamamı aşağıdaki gibi)

**Interfaces:**
- Consumes: Görev 4 ve 5'in toplayıcıları.
- Produces: `Sampler.appsEvery = 3`; her saniye tam bir `Snapshot`.

- [ ] **Step 1: Sampler**

`Sources/PhoneBox/Sampler.swift`:

```swift
import Foundation
import PhoneBoxCore

/// Builds a `Snapshot` once a second while at least one phone may receive data (design §4, §6). The app list
/// is the most expensive part, so it is read every `appsEvery` seconds.
@MainActor
final class Sampler {
    /// Reading every process takes a few milliseconds; every 3 s keeps PhoneBox under 1 % CPU.
    static let appsEvery = 3
    var onSnapshot: ((Snapshot) -> Void)?

    private var timer: Timer?
    /// Keeps App Nap from slowing the one-second timer while a phone is streaming.
    private var activity: NSObjectProtocol?
    private var tickCount = 0
    private let cpu = CPUCollector()
    private let memory = MemoryCollector()
    private let gpu = GPUCollector()
    private let temperature = TemperatureCollector()
    private let power = PowerCollector()
    private let network = NetworkCollector()
    private let disk = DiskCollector()
    private let battery = BatteryCollector()
    private let apps = AppsCollector()

    var isRunning: Bool { timer != nil }

    func setRunning(_ running: Bool) {
        guard running != isRunning else { return }
        if running {
            resetCounters()
            primeCounters()
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                             reason: "Streaming to iPhone")
        } else {
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
            activity = nil
            timer?.invalidate()
            timer = nil
        }
    }

    /// After sleep every counter jumped; start over so the first values are not nonsense.
    func resetAfterWake() {
        resetCounters()
    }

    private func resetCounters() {
        cpu.reset()
        power.reset()
        network.reset()
        disk.reset()
        apps.reset()
        tickCount = 0
    }

    /// Take a first reading of every counter so the first tick already has rates.
    private func primeCounters() {
        _ = cpu.sample()
        _ = power.sample()
        _ = network.sample()
        _ = disk.sample()
        _ = apps.sample()
    }

    private func tick() {
        tickCount += 1
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        onSnapshot?(Snapshot(
            t: now, cpu: cpu.sample(), mem: memory.sample(), gpu: gpu.sample(), temp: temperature.sample(),
            power: power.sample(), net: network.sample(), disk: disk.sample(), battery: battery.sample(),
            apps: tickCount % Self.appsEvery == 0 ? apps.sample() : nil))
    }
}
```

- [ ] **Step 2: Derle ve testleri çalıştır**

Run: `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"` → çıktı yok; `make test` → `103 tests in 20 suites`.

- [ ] **Step 3: Commit**

```bash
git add Sources/PhoneBox/Sampler.swift
git commit -m "Sample every metric each second, temperature and the app list less often"
```

---

### Task 7: Sayfada yeni metrikler, Mac'te deneme ve tasarım notları

**Files:**
- Modify: `Resources/web/index.html`, `Resources/web/styles.css`, `Resources/web/app.js` (üçünün de tamamı aşağıdaki gibi)
- Modify: `docs/design/2026-11-25-phonebox-design.md` (bölüm 6)

**Interfaces:**
- Consumes: yeni snapshot alanları.
- Produces: sayfada GPU, Sıcaklık, Güç, Ağ, Disk, Pil satırları ve "En çok kullananlar" listesi.

- [ ] **Step 1: Sayfa**

`Resources/web/index.html`:

```html
<!doctype html>
<html lang="tr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="PhoneBox">
<meta name="theme-color" content="#000000">
<title>PhoneBox</title>
<link rel="stylesheet" href="styles.css">
</head>
<body>
<header>
  <span class="title">PhoneBox</span>
  <span id="status" class="status"><span class="dot"></span><span id="status-text"></span></span>
</header>

<main id="metrics">
  <section class="gauge" id="cpu">
    <div class="ring"><div class="inner"><span class="value" id="cpu-value">—</span><span class="label">CPU</span></div></div>
    <div class="detail" id="cpu-detail"></div>
  </section>
  <section class="gauge" id="ram">
    <div class="ring"><div class="inner"><span class="value" id="ram-value">—</span><span class="label">RAM</span></div></div>
    <div class="detail" id="ram-detail"></div>
  </section>
</main>

<section id="details" class="details">
  <div class="row"><span class="name" data-text="gpu"></span><span class="value-cell"><span id="gpu-value">—</span><span class="sub" id="gpu-sub"></span></span></div>
  <div class="row"><span class="name" data-text="temp"></span><span class="value-cell"><span id="temp-value">—</span><span class="sub" id="temp-sub"></span></span></div>
  <div class="row"><span class="name" data-text="power"></span><span class="value-cell"><span id="power-value">—</span><span class="sub" id="power-sub"></span></span></div>
  <div class="row"><span class="name" data-text="net"></span><span class="value-cell"><span id="net-value">—</span><span class="sub" id="net-sub"></span></span></div>
  <div class="row"><span class="name" data-text="disk"></span><span class="value-cell"><span id="disk-value">—</span><span class="sub" id="disk-sub"></span></span></div>
  <div class="row"><span class="name" data-text="battery"></span><span class="value-cell"><span id="battery-value">—</span><span class="sub" id="battery-sub"></span></span></div>
</section>

<section id="apps" class="apps">
  <h2 data-text="apps"></h2>
  <ol id="app-list"></ol>
</section>

<div id="message" class="message" hidden></div>

<div id="start" class="start">
  <button id="start-button" type="button"></button>
  <p id="start-note"></p>
</div>

<video id="keepawake" playsinline preload="auto" src="keepawake.mp4"></video>
<script src="sha256.js"></script>
<script src="app.js"></script>
</body>
</html>
```

`Resources/web/styles.css`:

```css
/* "Sade koyu" (design §8): black, system font, soft cards. Plan 4 replaces this with the full layout C. */
:root {
  --bg: #000;
  --card: #1c1c1e;
  --text: #f5f5f7;
  --muted: #8e8e93;
  --track: #2c2c2e;
  --cpu: #30d158;
  --ram: #0a84ff;
  --warn: #ff9f0a;
  --bad: #ff453a;
}

* { box-sizing: border-box; }

html, body {
  margin: 0;
  height: 100%;
  background: var(--bg);
  color: var(--text);
  font: 15px -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
  -webkit-user-select: none;
  user-select: none;
  -webkit-tap-highlight-color: transparent;
}

body {
  display: flex;
  flex-direction: column;
  padding: max(16px, env(safe-area-inset-top)) max(20px, env(safe-area-inset-right))
           max(16px, env(safe-area-inset-bottom)) max(20px, env(safe-area-inset-left));
}

header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.title { font-weight: 600; font-size: 17px; }

.status { display: flex; align-items: center; gap: 6px; color: var(--muted); font-size: 13px; }
.dot { width: 8px; height: 8px; border-radius: 50%; background: var(--muted); }
.status.connected .dot { background: var(--cpu); }
.status.cable .dot { background: var(--warn); }
.status.offline .dot { background: var(--bad); }

main {
  flex: 1;
  display: flex;
  justify-content: center;
  align-items: center;
  gap: 8vmin;
  flex-wrap: wrap;
}

.stale { opacity: 0.35; }

.details, .apps {
  width: 100%;
  max-width: 560px;
  margin: 0 auto;
}

.details { margin-top: 12px; }

.row {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  gap: 12px;
  padding: 9px 2px;
  border-bottom: 1px solid var(--card);
}

.row .name { color: var(--muted); }

.value-cell {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}

.sub { font-weight: 400; font-size: 12px; color: var(--muted); }
.sub:empty { display: none; }

.apps h2 {
  margin: 18px 2px 4px;
  font-size: 12px;
  font-weight: 600;
  color: var(--muted);
  text-transform: uppercase;
  letter-spacing: 0.08em;
}

.apps ol { list-style: none; margin: 0; padding: 0; }

.apps li {
  display: grid;
  grid-template-columns: 1fr auto auto;
  gap: 14px;
  padding: 8px 2px;
  border-bottom: 1px solid var(--card);
  font-variant-numeric: tabular-nums;
}

.apps .app-name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.apps .app-cpu { font-weight: 600; min-width: 4.5em; text-align: right; }
.apps .app-mem { color: var(--muted); min-width: 5.5em; text-align: right; }

.gauge { display: flex; flex-direction: column; align-items: center; gap: 10px; }

.ring {
  --p: 0;
  --color: var(--cpu);
  width: 38vmin;
  height: 38vmin;
  max-width: 220px;
  max-height: 220px;
  border-radius: 50%;
  background: conic-gradient(var(--color) calc(var(--p) * 1%), var(--track) 0);
  display: flex;
  align-items: center;
  justify-content: center;
  transition: --p 0.6s;
}

#ram .ring { --color: var(--ram); }

.inner {
  width: 80%;
  height: 80%;
  border-radius: 50%;
  background: var(--bg);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
}

.value { font-size: 9vmin; font-weight: 700; line-height: 1; font-variant-numeric: tabular-nums; }
.label { margin-top: 4px; font-size: 12px; color: var(--muted); letter-spacing: 0.08em; }
.detail { color: var(--muted); font-size: 13px; font-variant-numeric: tabular-nums; min-height: 1.2em; }

.message {
  position: fixed;
  left: 50%;
  bottom: max(24px, env(safe-area-inset-bottom));
  transform: translateX(-50%);
  max-width: 90vw;
  padding: 12px 18px;
  border-radius: 14px;
  background: var(--card);
  text-align: center;
  font-size: 15px;
}

.start {
  position: fixed;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 14px;
  background: rgba(0, 0, 0, 0.85);
  text-align: center;
  padding: 24px;
}

.start[hidden] { display: none; }

.start button {
  border: 0;
  border-radius: 14px;
  padding: 16px 28px;
  background: var(--cpu);
  color: #000;
  font: 600 18px -apple-system, system-ui, sans-serif;
}

.start p { max-width: 420px; color: var(--muted); font-size: 14px; margin: 0; }

#keepawake { position: fixed; right: 0; bottom: 0; width: 2px; height: 2px; opacity: 0.01; pointer-events: none; }
```

`Resources/web/app.js`:

```javascript
// PhoneBox dashboard (Plan 2: CPU and RAM; Plan 3A: the other metrics and the app list as plain rows).
// Design §5 (protocol), §6 (metrics), §8 (keep-awake, states).
(function () {
  "use strict";

  const TEXT = {
    tr: {
      connecting: "Bağlanıyor…",
      connected: "Bağlı",
      cable: "Kabloyu tak",
      offline: "Mac'e ulaşılamıyor",
      unpaired: "Eşleşmedi",
      noKey: "Bu sayfanın anahtarı yok. iPhone'u Mac'e kabloyla tak ve Mac'te çıkan QR kodunu okut.",
      badKey: "Eşleştirme geçersiz. iPhone'u Mac'e kabloyla tak ve QR kodunu yeniden okut.",
      notOnCable: "Bu telefon Wi-Fi üzerinden bağlı. Veri için iPhone'u Mac'e kabloyla tak.",
      unreachable: "Mac'e ulaşılamıyor. PhoneBox açık mı, telefon kabloyla takılı ya da aynı Wi-Fi'de mi?",
      noData: "Mac şu an veri göndermiyor.",
      start: "Başlat",
      startNote: "Dokunduğunda ekran açık kalır. Telefonda çalan müzik durmaz.",
      memory: (used, total) => `${used} / ${total} GB`,
      load: (value) => `Yük ${value}`,
      gpu: "GPU",
      temp: "Sıcaklık",
      power: "Güç",
      net: "Ağ",
      disk: "Disk",
      battery: "Pil",
      apps: "En çok kullananlar",
      hottest: (value) => `en yüksek ${value} °C`,
      gpuPower: "GPU",
      systemPower: "Mac'in tamamı",
      free: (free, total) => `${free} / ${total} GB boş`,
      diskSpeed: (read, write) => `okuma ${read} · yazma ${write}`,
      charging: "şarj oluyor",
      untilEmpty: (time) => `${time} kaldı`,
      untilFull: (time) => `dolmasına ${time}`,
      duration: (hours, minutes) => (hours ? `${hours} sa ` : "") + `${minutes} dk`,
    },
    en: {
      connecting: "Connecting…",
      connected: "Connected",
      cable: "Plug in the cable",
      offline: "Cannot reach the Mac",
      unpaired: "Not paired",
      noKey: "This page has no key. Plug the iPhone into the Mac and scan the QR code the Mac shows.",
      badKey: "Pairing is no longer valid. Plug the iPhone into the Mac and scan the QR code again.",
      notOnCable: "This phone is connected over Wi-Fi. Plug the iPhone into the Mac to see data.",
      unreachable: "Cannot reach the Mac. Is PhoneBox running, and is the phone plugged in or on the same Wi-Fi?",
      noData: "The Mac is not sending data right now.",
      start: "Start",
      startNote: "Once you tap, the screen stays on. Music playing on the phone keeps playing.",
      memory: (used, total) => `${used} / ${total} GB`,
      load: (value) => `Load ${value}`,
      gpu: "GPU",
      temp: "Temperature",
      power: "Power",
      net: "Network",
      disk: "Disk",
      battery: "Battery",
      apps: "Top apps",
      hottest: (value) => `hottest ${value} °C`,
      gpuPower: "GPU",
      systemPower: "whole Mac",
      free: (free, total) => `${free} of ${total} GB free`,
      diskSpeed: (read, write) => `read ${read} · write ${write}`,
      charging: "charging",
      untilEmpty: (time) => `${time} left`,
      untilFull: (time) => `${time} to full`,
      duration: (hours, minutes) => (hours ? `${hours} h ` : "") + `${minutes} min`,
    },
  };
  const language = (navigator.language || "en").toLowerCase().startsWith("tr") ? "tr" : "en";
  const t = TEXT[language];
  const number = new Intl.NumberFormat(language, { maximumFractionDigits: 1, minimumFractionDigits: 1 });
  const whole = new Intl.NumberFormat(language, { maximumFractionDigits: 0 });
  const $ = (id) => document.getElementById(id);
  document.documentElement.lang = language;
  for (const element of document.querySelectorAll("[data-text]")) element.textContent = t[element.dataset.text];

  // The key comes from the personal link's fragment (#k=…), or from localStorage on later visits (design §5).
  function readKey() {
    const fromLink = new URLSearchParams(location.hash.slice(1)).get("k");
    const decode = (text) => {
      try {
        const bytes = text ? PBCrypto.base64UrlToBytes(text) : null;
        return bytes && bytes.length === 32 ? bytes : null;
      } catch (error) {
        return null;
      }
    };
    const linkBytes = decode(fromLink);
    if (linkBytes) {
      try {
        localStorage.setItem("phonebox-key", fromLink);
      } catch (error) {}
      return linkBytes;
    }
    let stored = null;
    try {
      stored = localStorage.getItem("phonebox-key");
    } catch (error) {}
    return decode(stored);
  }

  const key = readKey();
  const state = {
    socket: null, retries: 0, started: false, stopped: false, nonce: null,
    receivedAt: 0, lastMessageAt: 0, socketOpenedAt: 0, access: null, accessSetAt: 0,
  };

  function setStatus(kind, text) {
    $("status").className = "status " + kind;
    $("status-text").textContent = text;
  }

  function showMessage(text) {
    $("message").textContent = text || "";
    $("message").hidden = !text;
  }

  function setStale(stale) {
    for (const id of ["metrics", "details", "apps"]) $(id).classList.toggle("stale", stale);
  }

  // ---- Keep the screen on (spike V4): an unmuted, silent video that never loops, in an "ambient" audio
  // session so music on the phone keeps playing. WebKit lets the screen sleep for anything else.
  const video = $("keepawake");
  video.addEventListener("timeupdate", () => {
    if (video.currentTime > 0.5) video.currentTime = Math.random() * 0.4;
  });

  function keepAwake() {
    try {
      if (navigator.audioSession) navigator.audioSession.type = "ambient";
    } catch (error) {}
    video.muted = false;
    video.loop = false;
    return video.play();
  }

  // Chrome does not fire visibilitychange when the phone is unlocked, and WebKit pauses media while the
  // page is hidden, so check every few seconds (spike).
  setInterval(() => {
    if (state.started && document.visibilityState === "visible" && video.paused) keepAwake().catch(() => {});
    replaceStaleSocket();
    if (key) connect();
  }, 3000);

  $("start-button").textContent = t.start;
  $("start-note").textContent = t.startNote;
  $("start").addEventListener("click", () => {
    keepAwake().then(
      () => {
        state.started = true;
        $("start").hidden = true;
      },
      () => {
        $("start").hidden = false;
      }
    );
  });

  // ---- Connection.
  function send(message) {
    if (state.socket && state.socket.readyState === WebSocket.OPEN) state.socket.send(JSON.stringify(message));
  }

  function connect() {
    if (state.stopped || document.visibilityState !== "visible" || (state.socket && state.socket.readyState <= WebSocket.OPEN)) return;
    if (!state.receivedAt) setStatus("", t.connecting);
    const socket = new WebSocket(`ws://${location.host}/ws`);
    state.socket = socket;
    state.lastMessageAt = Date.now();
    state.socketOpenedAt = Date.now();
    socket.onmessage = (event) => {
      state.lastMessageAt = Date.now();
      try {
        handle(JSON.parse(event.data));
      } catch (error) {}
    };
    socket.onclose = (event) => {
      if (state.socket === socket) state.socket = null;
      setStale(true);
      if (event.code === 4001) {
        state.stopped = true;
        $("start").hidden = true;
        setStatus("offline", t.unpaired);
        showMessage(t.badKey);
        return;
      }
      if (event.code === 4003) {
        // Authentication did not arrive in time: retryable, not a bad key.
        setStatus("", t.connecting);
        setTimeout(connect, 1000);
        return;
      }
      if (event.code === 4002) {
        // Not a failure (the Mac asked for a fresh connection); a short pause keeps repeats from spinning.
        setTimeout(connect, 250);
        return;
      }
      // A close while the page is hidden (phone locked) is not a failure; the page reconnects on return.
      if (document.visibilityState === "visible") state.retries += 1;
      if (state.retries >= 3) {
        setStatus("offline", t.offline);
        showMessage(t.unreachable);
      } else {
        setStatus("", t.connecting);
      }
      setTimeout(connect, [1000, 2000, 5000][Math.min(Math.max(state.retries, 1) - 1, 2)]);
    };
  }

  // After lock/sleep iOS can leave a socket that reports OPEN but delivers nothing. While the Mac is streaming
  // (snapshots arrive every second or so), silence for 5 s means the socket is dead: replace it right away.
  function replaceStaleSocket() {
    if (document.visibilityState !== "visible") return;
    const socket = state.socket;
    if (!socket || socket.readyState !== WebSocket.OPEN) return;
    if (!(state.access && state.access.streaming)) {
      // Not streaming (e.g. first connected over Wi-Fi, or before the USB link came up): try again every ~10 s
      // so the phone moves to the cable without a reload.
      if (state.access && Date.now() - state.accessSetAt >= 10000) replaceSocket();
      return;
    }
    if (Date.now() - state.lastMessageAt <= 5000) return;
    replaceSocket();
  }

  function replaceSocket() {
    const socket = state.socket;
    if (!socket) return connect();
    state.accessSetAt = Date.now();
    socket.onmessage = null;
    socket.onclose = null;
    try {
      socket.close();
    } catch (error) {}
    state.socket = null;
    setStale(true);
    connect();
  }

  function handle(message) {
    switch (message.type) {
      case "hello":
        state.nonce = message.nonce;
        send({ v: 1, type: "auth", mac: PBCrypto.hmacHex(key, "auth:" + message.nonce) });
        break;
      case "ready":
        state.retries = 0;
        applyAccess(message.access);
        break;
      case "access":
        applyAccess(message);
        break;
      case "snapshot":
        render(message);
        break;
    }
  }

  function applyAccess(access) {
    state.access = access;
    state.accessSetAt = Date.now();
    if (access.streaming) {
      setStatus("connected", t.connected);
      showMessage("");
    } else if (access.reason === "not-on-cable") {
      setStatus("cable", t.cable);
      setStale(true);
      showMessage(t.notOnCable);
    } else {
      setStatus("offline", t.noData);
      setStale(true);
      showMessage(t.noData);
    }
  }

  function render(snapshot) {
    state.receivedAt = Date.now();
    setStale(false);
    if (snapshot.cpu) {
      setRing("cpu", snapshot.cpu.total);
      $("cpu-value").textContent = Math.round(snapshot.cpu.total) + "%";
      const load = snapshot.cpu.load;
      $("cpu-detail").textContent = load && load.length ? t.load(number.format(load[0])) : "";
    }
    if (snapshot.mem) {
      const valid = snapshot.mem.total > 0;
      const percent = valid ? (snapshot.mem.used / snapshot.mem.total) * 100 : 0;
      setRing("ram", percent);
      $("ram-value").textContent = valid ? Math.round(percent) + "%" : "—";
      const gb = (bytes) => number.format(bytes / 1073741824);
      $("ram-detail").textContent = t.memory(gb(snapshot.mem.used), gb(snapshot.mem.total));
    }
    renderDetails(snapshot);
    if (snapshot.apps) renderApps(snapshot.apps);
  }

  // ---- Plan 3A rows. A missing metric shows "—".
  function setRow(id, value, sub) {
    $(id + "-value").textContent = value == null ? "—" : value;
    $(id + "-sub").textContent = value == null || !sub ? "" : sub;
  }

  function speed(bytesPerSecond) {
    if (bytesPerSecond == null) return "—";
    if (bytesPerSecond >= 1e6) return number.format(bytesPerSecond / 1e6) + " MB/s";
    if (bytesPerSecond >= 1e3) return whole.format(bytesPerSecond / 1e3) + " KB/s";
    return whole.format(bytesPerSecond) + " B/s";
  }

  function duration(minutes) {
    return t.duration(Math.floor(minutes / 60), minutes % 60);
  }

  function renderDetails(snapshot) {
    const gpu = snapshot.gpu;
    setRow("gpu", gpu ? Math.round(gpu.util) + "%" : null);

    const temp = snapshot.temp;
    setRow("temp", temp ? number.format(temp.avg) + " °C" : null,
           temp && temp.max - temp.avg >= 1 ? t.hottest(number.format(temp.max)) : "");

    const power = snapshot.power;
    if (power && power.system != null) setRow("power", number.format(power.system) + " W", t.systemPower);
    else if (power && power.gpu != null) setRow("power", number.format(power.gpu) + " W", t.gpuPower);
    else setRow("power", null);

    const net = snapshot.net;
    setRow("net", net ? `↓ ${speed(net.rx)} · ↑ ${speed(net.tx)}` : null, net ? net.iface : "");

    const disk = snapshot.disk;
    const gb = (bytes) => number.format(bytes / 1e9);
    setRow("disk", disk ? t.free(gb(disk.free), gb(disk.total)) : null,
           disk && (disk.read != null || disk.write != null) ? t.diskSpeed(speed(disk.read), speed(disk.write)) : "");

    const battery = snapshot.battery;
    let batterySub = "";
    if (battery && battery.minutesLeft != null) {
      batterySub = battery.charging ? t.untilFull(duration(battery.minutesLeft)) : t.untilEmpty(duration(battery.minutesLeft));
    } else if (battery && battery.charging) {
      batterySub = t.charging;
    }
    setRow("battery", battery ? battery.percent + "%" + (battery.charging ? " ⚡" : "") : null, batterySub);
  }

  function renderApps(apps) {
    const list = $("app-list");
    const sorted = apps.slice().sort((a, b) => b.cpu - a.cpu || b.mem - a.mem);
    list.replaceChildren(...sorted.map((app) => {
      const item = document.createElement("li");
      const cells = [
        ["app-name", app.name],
        ["app-cpu", number.format(app.cpu) + "%"],
        ["app-mem", app.mem >= 1e9 ? number.format(app.mem / 1e9) + " GB" : whole.format(app.mem / 1e6) + " MB"],
      ];
      for (const [className, text] of cells) {
        const cell = document.createElement("span");
        cell.className = className;
        cell.textContent = text;
        item.append(cell);
      }
      return item;
    }));
  }

  function setRing(id, percent) {
    document.querySelector(`#${id} .ring`).style.setProperty("--p", Math.max(0, Math.min(100, percent)).toFixed(1));
  }

  // Reconnect right away when the page comes back (spike: iOS drops the socket 10–15 s after locking).
  for (const name of ["visibilitychange", "pageshow", "focus"]) {
    window.addEventListener(name, () => {
      if (document.visibilityState !== "visible") return;
      // The three events often fire together; a socket opened less than 1 s ago is kept.
      if (Date.now() - state.socketOpenedAt >= 1000) {
        if (state.access && !state.access.streaming && state.socket) replaceSocket();
        else replaceStaleSocket();
      }
      connect();
    });
  }
  window.addEventListener("hashchange", () => location.reload());

  if (!key) {
    $("start").hidden = true;
    setStatus("offline", t.unpaired);
    showMessage(t.noKey);
    return;
  }
  connect();
})();
```

Sözdizimi: `swift -e 'import JavaScriptCore; let c = JSContext()!; c.exceptionHandler = { _, e in print("ERROR", e!) }; c.evaluateScript("function check(){" + (try! String(contentsOfFile: "Resources/web/app.js", encoding: .utf8)) + "}"); print("syntax ok")'` → `syntax ok`.

- [ ] **Step 2: Mac'te dene**

Kullanıcının gerçek ayarlarını ve anahtarını yedekle, "Her zaman" modunda çalıştır:

```bash
S="$HOME/Library/Application Support/PhoneBox"; mkdir -p build; cp "$S/pairing-key" build/phonebox-key.bak 2>/dev/null; defaults export com.phonebox.PhoneBox build/phonebox-defaults.plist 2>/dev/null
pkill -x PhoneBox; make app && defaults write com.phonebox.PhoneBox mode always && open build/PhoneBox.app
```

Tarayıcıda `http://localhost:4747/#k=<anahtar>` (anahtar: `cat ~/Library/Application\ Support/PhoneBox/pairing-key`) aç,
"Başlat"a bas. Expected: CPU/RAM halkalarının altında altı satır — GPU (%), Sıcaklık (°C, gerekirse "en yüksek"),
Güç (W, "Mac'in tamamı" ya da "GPU"), Ağ (↓ · ↑ ve arayüz adı), Disk ("x / y GB boş", okuma/yazma), Pil (%, şarjda ⚡) —
ve en fazla 10 satırlık "En çok kullananlar" listesi; liste 3 sn'de bir yenilenir. Okunamayan değer "—".

PhoneBox'ın yükü: sayfa açıkken `top -l 3 -s 3 -pid $(pgrep -x PhoneBox) -stats pid,cpu | tail -2` → Expected: ~%1–1,5.
Sayfayı kapatınca (veri alan kimse yokken) örnekleyici durur ve yük ~%0'a iner.

Ayarları geri yükle:

```bash
pkill -x PhoneBox; defaults delete com.phonebox.PhoneBox; [ -f build/phonebox-defaults.plist ] && defaults import com.phonebox.PhoneBox build/phonebox-defaults.plist; [ -f build/phonebox-key.bak ] && cp build/phonebox-key.bak "$HOME/Library/Application Support/PhoneBox/pairing-key"
```

- [ ] **Step 3: Tasarımı güncelle**

`docs/design/2026-11-25-phonebox-design.md` bölüm 6'da:
- Tablonun `temp` satırını şöyle yap: `| \`temp\` | \`avg\`, \`max\` (°C): çip die sensörleri (\`PMU tdie*\`, \`PMU2 tdie*\`); CPU/GPU ayrımı sensör adlarından güvenilir çıkarılamadığı için tek değer. 5 sn'de bir okunur | \`IOHIDEventSystemClient\` (resmi olmayan) |`
- `apps` satırında "2 saniyede bir" → "3 saniyede bir".
- Tablonun üstündeki "Hedef: PhoneBox'ın kendi CPU kullanımı %1'in altında." cümlesinin sonuna ekle: " Ölçülen (Plan 3A, M4): veri gönderirken ~%1; sıcaklığı her saniye okumak tek başına ~%3 tutuyordu."

- [ ] **Step 4: Commit**

```bash
git add Resources/web/index.html Resources/web/styles.css Resources/web/app.js docs/design/2026-11-25-phonebox-design.md
git commit -m "Show the new metrics and the busiest apps on the phone"
```

---

### Task 8: iPhone'da kısa kontrol (kullanıcıyla)

- [ ] **Step 1:** `make run`; telefonda dashboard'u aç (kablo modunda). Yeni satırlar ve uygulama listesi telefon
  ekranında okunaklı mı, taşan ya da kesilen bir şey var mı? Yatay ve dikey tutarak bak.
- [ ] **Step 2:** `docs/manual-testing.md`'deki "Sonuçlar" bölümüne Plan 3A için tarih, sürüm ve gözlemleri ekle; listeye
  "Yeni metrik satırları ve uygulama listesi telefonda okunaklı" maddesini ekle.
- [ ] **Step 3: Commit**

```bash
git add docs/manual-testing.md
git commit -m "Record the Plan 3A phone check"
```
