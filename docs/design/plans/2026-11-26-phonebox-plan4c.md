# PhoneBox Plan 4C — Görünüm ve canlılık

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Bu plan için not:** Görev 1–5 Mac'te tek başına yürütülebilir. Uygulamayı başlatmaz, kullanıcının PhoneBox'ını
> durdurmaz, `defaults`'a ve eşleştirme anahtarına dokunmaz. Görev 2'deki canlı test (`PHONEBOX_LIVE=1`) yalnız
> kontrolcünün isteğiyle ve bir iPhone kabloyla takılıyken çalıştırılır. Görev 6'yı kontrolcü yapar (inline): sayfayı
> önce sahte veriyle (bu planın sonundaki "Ek: deneme sayfası"), sonra kullanıcıyla telefonda dener. Plan 4B
> (komut arayüzü) bu plandan sonra gelir.

**Goal:** Telefondaki sayfayı onaylanan görünüme (design §8 "Stil", "Görünüm ve hareket", "Sınıra yaklaşınca
kızarma", "Saat ve telefonun pili") getirmek. Kapsam:
- Okyanus paleti ve `<canvas>` üstünde Aktivite Halkaları.
- Yumuşak sayı geçişleri, sürekli akan grafik, kayan uygulama satırları.
- Sınırına yaklaşan metriğin kızarması ve güçlü alarm.
- Sağ üstte büyük saat, tarih ve telefonun pili.

Mac tarafında üç ekleme gerekir: telefonun pili (`snapshot.phone`), Mac'in prizde olup olmadığı (`battery.plugged`) ve
çipe göre güç sınırı (`ready.limits`).

**Architecture:** Mac tarafında saf kısımlar `PhoneBoxCore`'dadır ve Swift testleriyle denenir: güç sınırı tablosu,
telefon pilinin değerlerden üretilmesi, son okumanın 5 dk tutulması. Telefon pili uygulama hedefindeki
`PhoneBatteryReader` ile okunur: resmi olmayan `MobileDevice.framework`, `dlopen` ile, ayrı kuyrukta, örnekleyici
çalışırken. Sayfada kızarma (`heat.js`), hareket (`motion.js`) ve saat (`clock.js`) DOM'a dokunmayan dosyalardır ve
JavaScriptCore'da test edilir. `rings.js` ile `chart.js` her karede çizer. `view.js` tek bir `requestAnimationFrame`
döngüsünde değerleri kaydırır, renkleri ve alarmı uygular.

**Tech Stack:** Swift 6 araç zinciri (Swift 5 dil modu), Swift Testing, JavaScriptCore, `dlopen`/`dlsym`; sade
JavaScript (sınıf, `??`, Intl), `<canvas>` 2D, CSS (grid, `dvh`, `env(safe-area-inset-*)`, `@keyframes`), OKLCH renk
hesabı (elle, kütüphanesiz).

## Global Constraints

- Sayfa sade HTML/CSS/JS: dış kütüphane ve derleme adımı yok.
  - Her dosya klasik `<script>` ile sırayla yüklenir ve `globalThis.PhoneBox` altına yazar; ES modül `import`'u yok.
  - Saf dosyalar DOM'a yüklenirken dokunmaz; böylece JavaScriptCore'da test edilebilir.
  - Ekrana giden her metin `textContent` ile yazılır; `innerHTML` yok.
- Yerleşim değişmez (design §8): yatayda halkalar | grafik + 3×2 kutucuk + şerit | saat başlığı + şarkı kartı +
  uygulamalar; dikeyde yukarıdan aşağı saat satırı, halkalar, grafik, kutucuklar, uygulamalar, şarkı, şerit.
  Kaydırma yok, iPhone SE'den Pro Max'e kadar sığar.
- Okyanus paleti. Zemin `#01060d`, kart `#0b1622`, ikincil yazı `#6d8aa3`, ana yazı `#eaf6ff`. Metrik renkleri:
  CPU `#00c2ff` (halkanın açık ucu `#7ff3ff`), RAM `#3d6bff` (`#9db4ff`), GPU `#7b61ff`, sıcaklık `#00e0b0`, güç
  `#4ff0d0`, ağ `#8be9ff` (↑ çizgisi `#7b61ff`), disk `#6f8fa8` (yazma çizgisi `#4ff0d0`), pil `#00d0a0`.
- Kızarma sınırları (kızarmaya başlar → kıpkırmızı):
  - CPU %40 → %95; RAM %75 → %95; GPU %40 → %95; sıcaklık (ortalama) 60 → 95 °C.
  - Güç `ready.limits.power`; gelmezse 15 → 35 W.
  - Ağ (↓ + ↑) 10 → 100 MB/s.
  - Disk boş 30 → 5 GB (ondalık); pil %30 → %10, yalnız `plugged` false iken.
  - Uygulama satırı %60 → %200.
- Seviye: başlangıçta 0, sınırda 1, arada doğrusal; renkte iki ucu yumuşatılır (smoothstep), 1/100'e yuvarlanır.
- Renk yolu B: OKLCH'de ton artan yönde döner (mavi → mor → pembe → kırmızı). Hedef `#ff2d2d`, halkanın açık ucu
  `#ff8a7a`. Yolun ortasında doygunluk +0,05·sin(πt). Ekranın gösteremediği renkte doygunluk azaltılır.
- Alarm:
  - Art arda 3 snapshot'ta seviye ≥ 1 ise çalar; art arda 3 snapshot'ta seviye < 0,9 ise söner.
  - Değeri gelmeyen ya da kızarmayan (prizdeki pil) metrik sakin sayılır. Değerler bayatlayınca bütün alarmlar
    susar.
  - Karar gelen değerle verilir; uygulama satırları alarm çaldırmaz.
- Güçlü alarm:
  - Kenar ışığı: `inset 0 0 110px 24px rgba(255,40,40,.95)` ve `inset 0 0 0 3px rgba(255,70,70,.95)`.
  - Saniyede bir atar: opaklık 0,45 + 0,55 × nabız.
  - Çaldığı an 0,7 sn'lik bir "pop": halka ×1,07, kutucuk ×1,06, kenar parlar.
  - Saat başlığında tarihin yerine "▲ <ad> <değer>", en yüksek seviyeli iki alarm.
  - Alarm yokken seviye 0,7'yi geçen bir metrik kenarda en çok 0,4 opaklıkla soluk bir ışık yakar.
- Hareket süreleri:
  - Sayı geçişi 900 ms (yavaşlayarak biten).
  - Grafik: son değer 700 ms'de oturur; zaman sürekli kayar; metrik değişince 300 ms solup belirir.
  - Satır kayması 700 ms; uygulama çubuğu 1 sn.
  - Saat rakamı 700 ms kayar; iki nokta 2 sn'de bir nefes alır.
  - Halka parıltısı 1,4 sn'de bir; grafik ucunun nabzı ~1,6 sn.
- Hareketi Azalt (`prefers-reduced-motion`): parıltı, nabız, atma, pop, rakam ve satır kayması kapanır. Renk ve
  sayı geçişleri kalır; alarm ışığı sabit yanar.
- Tek `requestAnimationFrame` döngüsü (`PhoneBox.motion.onFrame`). Her karede önce boyutlar okunur, sonra yazılır.
  Metin ve stil yalnız değişince yazılır. Metin sığdırma her snapshot'ta bir kez yapılır.
- Telefon pili:
  - `MobileDevice.framework` (`/Library/Apple/System/Library/PrivateFrameworks/…`, yoksa `/System/Library/…`),
    yalnız USB arayüzündeki (tip 1) cihazlar.
  - Takılınca 2 sn sonra, sonra 60 sn'de bir okunur; okumalar ayrı kuyrukta, aynı anda tek okuma.
  - Son iyi okuma 5 dk tutulur; iki iPhone takılıysa ya da telefon çıkınca hemen unutulur.
  - Yalnız örnekleyici çalışırken okunur. Sayfada yalnız `access.cable` iken görünür.
- Güç sınırı tablosu (`machdep.cpu.brand_string`'in son sözcüğü; "Mac'in tamamı" / masaüstünde "yalnız GPU"):
  temel 15→35 / 5→15, Pro 25→60 / 10→30, Max 35→100 / 20→60, Ultra 50→160 / 30→90; bilinmeyen çip temel.
- Kod yorumları İngilizce. Commit mesajları İngilizce, emir kipinde. Aşağıdaki her `git commit` komutuna, commit'i
  yapan ortamın istediği `Co-Authored-By: …` satırı ikinci bir `-m` olarak eklenir.
- Testler `make test FILTER="<Suite>|<Suite>"` ile (tırnaklar kalsın). Derleme uyarısı denetimi iki adımdır ve ikisi
  de çıktı vermemeli:
  - `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"`
  - `make test 2>&1 | grep -E "warning:" | grep -v "ld: warning"`

## Planlama sırasında doğrulananlar (2026-11-26)

Kodun tamamı `main`'in (f11962d) bir kopyasında görev görev yazıldı. Her görevin sonunda derleme ve test uyarısızdı,
testler geçti. Sonda: `PhoneBoxCoreTests` 31 takımda 177 test, `PhoneBoxTests` 5 takımda 18 test (canlı testler
`PHONEBOX_LIVE=1` olmadan atlanır). `make app` paketi kurdu; yeni sayfa dosyaları pakette.

- **Telefon pili:** `PHONEBOX_LIVE=1 make test FILTER="PhoneBatteryLiveTests"` kabloya takılı iPhone'un pilini
  2,4 sn'de okudu (M4, macOS 27.2). Okuyucunun bildirimleri ana iş parçacığında geliyor. `BatteryCurrentCapacity`
  sayı, `BatteryIsCharging` ve `ExternalConnected` boolean (CFBoolean).
- **Sayfa:** "Ek: deneme sayfası" ile, sahte veriyle, şu ölçülerde denendi: 734×372, 667×375 (SE yatay), 393×759,
  375×647 (SE dikey). Konsolda JavaScript hatası yok; taşan ya da kesilen öğe yok (ağ kutusu 13 px'e kadar küçülüyor).
- **Senaryolar:**
  - CPU %100 + sıcaklık 101 °C + güç 40 W + bir uygulama %380: halka, kutucuklar, grafik tepesi ve uygulama satırı
    kırmızı. 3 sn sonra kenar ışığı, atan halka ve kutucuklar, "▲ Güç 40,0 W · CPU %100".
  - Ağ 118 MB/s, disk 4 GB boş, pil %6 prizde değil: üç kutucuk kırmızı.
  - Değerler normale dönünce alarm 3 sn sonra sustu.
- **Bulunup düzeltilenler** (kodda düzeltilmiş hâliyle):
  - Satırların "beliriş" sınıfı kalınca her yeni listede satırlar yeniden beliriyordu: sınıf `animationend`'de
    kalkıyor.
  - Kutucuk metni geçişin ortasında birim değiştirince kesiliyordu: sığdırma, gelinen ve gidilen metnin uzun olanıyla
    yapılıyor.
  - Dikey SE'de saat satırı uygulama listesini 2 satıra düşürüyordu: dikeyde saat 22–30 px ve tarih, pil ve nokta
    tek satırda (3 satır).

## Dosya yapısı

```
Sources/PhoneBoxCore/PowerLimits.swift        çipe göre güç sınırı (yeni)
Sources/PhoneBoxCore/PhoneBattery.swift       telefon pili: örnek, değerlerden üretme, 5 dk'lık hafıza (yeni)
Sources/PhoneBoxCore/Messages.swift, Snapshot.swift, Metrics.swift   ready.limits, snapshot.phone, battery.plugged
Sources/PhoneBox/Collectors/PhoneBatteryReader.swift   MobileDevice ile okuma (yeni)
Sources/PhoneBox/Collectors/PrivateSymbols.swift, Sampler.swift, DashboardHub.swift, Settings.swift, AppDelegate.swift
Resources/web/  heat.js, motion.js, clock.js, rings.js                       (yeni)
                metrics.js, chart.js, view.js, app.js, i18n.js, index.html, styles.css   (değişir)
Tests/PhoneBoxCoreTests/  PowerLimitsTests, PhoneBatteryTests, WebMotionTests (yeni); MessagesTests, MetricsTests,
                          WebPageTests (değişir)
Tests/PhoneBoxTests/      PhoneBatteryLiveTests (yeni); DashboardHubTests (değişir)
```

"Bul / Şununla değiştir" adımlarında "Bul" metni dosyada tam olarak bir kez geçer; Edit aracıyla birebir değiştirin.

---

### Task 1: Güç sınırı ve Mac'in prizde olup olmadığı

**Files:**
- Create: `Sources/PhoneBoxCore/PowerLimits.swift`, `Tests/PhoneBoxCoreTests/PowerLimitsTests.swift`
- Modify: `Sources/PhoneBoxCore/Messages.swift`, `Sources/PhoneBoxCore/Metrics.swift`,
  `Tests/PhoneBoxCoreTests/MessagesTests.swift`, `Tests/PhoneBoxCoreTests/MetricsTests.swift`
- Modify: `Sources/PhoneBox/DashboardHub.swift`, `Sources/PhoneBox/Settings.swift`, `Sources/PhoneBox/AppDelegate.swift`,
  `Tests/PhoneBoxTests/DashboardHubTests.swift`

**Interfaces:**
- Consumes: mevcut `ServerMessage`, `BatterySample`, `BatteryInfo.sample(from:)`, `DashboardHub.init`.
- Produces:
  - `PowerLimits(start: Double, full: Double)`, `PowerLimits.standard` (15, 35),
    `PowerLimits.forChip(_ brand: String, wholeMac: Bool) -> PowerLimits`. `Encodable` olarak `{"power":[start,full]}`.
  - `ServerMessage.ready(mode:host:powerLimits:access:)`; JSON'da `"limits":{"power":[15,35]}`.
  - `BatterySample(percent:charging:plugged:minutesLeft:)`; `plugged` her zaman JSON'da.
  - `DashboardHub.init(mode:key:appName:hostName:powerLimits: = .standard, commands:usbInterfaces:)`.
  - `Settings.chipName() -> String` ("Apple M4"; okunamazsa "").

- [ ] **Step 1: Testleri yaz**

`Tests/PhoneBoxCoreTests/PowerLimitsTests.swift`:

```swift
import Testing
@testable import PhoneBoxCore

struct PowerLimitsTests {
    @Test func picksLimitsByChipFamily() {
        #expect(PowerLimits.forChip("Apple M4", wholeMac: true) == PowerLimits(start: 15, full: 35))
        #expect(PowerLimits.forChip("Apple M4 Pro", wholeMac: true) == PowerLimits(start: 25, full: 60))
        #expect(PowerLimits.forChip("Apple M2 Max", wholeMac: true) == PowerLimits(start: 35, full: 100))
        #expect(PowerLimits.forChip("Apple M3 Ultra", wholeMac: true) == PowerLimits(start: 50, full: 160))
    }

    @Test func desktopMacsGetGPULimits() {
        #expect(PowerLimits.forChip("Apple M4", wholeMac: false) == PowerLimits(start: 5, full: 15))
        #expect(PowerLimits.forChip("Apple M4 Pro", wholeMac: false) == PowerLimits(start: 10, full: 30))
        #expect(PowerLimits.forChip("Apple M2 Max", wholeMac: false) == PowerLimits(start: 20, full: 60))
        #expect(PowerLimits.forChip("Apple M2 Ultra", wholeMac: false) == PowerLimits(start: 30, full: 90))
    }

    @Test func anUnknownChipGetsTheStandardLimits() {
        #expect(PowerLimits.forChip("", wholeMac: true) == .standard)
        #expect(PowerLimits.forChip("Apple M9 Hyper", wholeMac: true) == .standard)
    }
}
```

`Tests/PhoneBoxCoreTests/MessagesTests.swift`:

Bul (1/3):

```swift
    }

    @Test func encodesReadyWithTheAccessObject() {
        #expect(ServerMessage.ready(mode: .cable, host: "Eren's MacBook Pro", access: .notOnCable).json()
            == #"{"access":{"cable":false,"commands":false,"reason":"not-on-cable","streaming":false},"host":"Eren's MacBook Pro","mode":"cable","type":"ready","v":1}"#)
    }
```

Şununla değiştir:

```swift
    }

    @Test func encodesReadyWithTheAccessObjectAndThePowerLimits() {
        let ready = ServerMessage.ready(mode: .cable, host: "Eren's MacBook Pro", powerLimits: PowerLimits(start: 15, full: 35.5),
                                        access: .notOnCable)
        #expect(ready.json()
            == #"{"access":{"cable":false,"commands":false,"reason":"not-on-cable","streaming":false},"host":"Eren's MacBook Pro","limits":{"power":[15,35.5]},"mode":"cable","type":"ready","v":1}"#)
    }
```

Bul (2/3):

```swift
            net: NetworkSample(rx: 1_200, tx: 30, iface: "en0"), disk: DiskSample(free: 10, total: 20, read: nil, write: 4),
            battery: BatterySample(percent: 86, charging: true, minutesLeft: nil),
            apps: [AppSample(pid: 9, bundleId: nil, name: "node", cpu: 1.5, mem: 64, quittable: false)])
```

Şununla değiştir:

```swift
            net: NetworkSample(rx: 1_200, tx: 30, iface: "en0"), disk: DiskSample(free: 10, total: 20, read: nil, write: 4),
            battery: BatterySample(percent: 86, charging: true, plugged: true, minutesLeft: nil),
            apps: [AppSample(pid: 9, bundleId: nil, name: "node", cpu: 1.5, mem: 64, quittable: false)])
```

Bul (3/3):

```swift
            == #"{"apps":[{"cpu":1.5,"mem":64,"name":"node","pid":9,"quittable":false}],"#
            + #""battery":{"charging":true,"percent":86},"disk":{"free":10,"total":20,"write":4},"gpu":{"util":17},"#
            + #""net":{"iface":"en0","rx":1200,"tx":30},"power":{"gpu":0.2},"t":5,"temp":{"avg":52.5,"max":56},"#
```

Şununla değiştir:

```swift
            == #"{"apps":[{"cpu":1.5,"mem":64,"name":"node","pid":9,"quittable":false}],"#
            + #""battery":{"charging":true,"percent":86,"plugged":true},"disk":{"free":10,"total":20,"write":4},"gpu":{"util":17},"#
            + #""net":{"iface":"en0","rx":1200,"tx":30},"power":{"gpu":0.2},"t":5,"temp":{"avg":52.5,"max":56},"#
```

`Tests/PhoneBoxCoreTests/MetricsTests.swift`:

Bul (1/2):

```swift
        let description: [String: Any] = ["Type": "InternalBattery", "Current Capacity": 86, "Max Capacity": 100,
                                          "Is Charging": false, "Time to Empty": 312, "Time to Full Charge": -1]
        #expect(BatteryInfo.sample(from: description) == BatterySample(percent: 86, charging: false, minutesLeft: 312))
    }
```

Şununla değiştir:

```swift
        let description: [String: Any] = ["Type": "InternalBattery", "Current Capacity": 86, "Max Capacity": 100,
                                          "Is Charging": false, "Power Source State": "Battery Power", "Time to Empty": 312,
                                          "Time to Full Charge": -1]
        #expect(BatteryInfo.sample(from: description)
            == BatterySample(percent: 86, charging: false, plugged: false, minutesLeft: 312))
    }
```

Bul (2/2):

```swift
        let description: [String: Any] = ["Type": "InternalBattery", "Current Capacity": 40, "Max Capacity": 100,
                                          "Is Charging": true, "Time to Full Charge": -1]
        #expect(BatteryInfo.sample(from: description) == BatterySample(percent: 40, charging: true, minutesLeft: nil))
    }
```

Şununla değiştir:

```swift
        let description: [String: Any] = ["Type": "InternalBattery", "Current Capacity": 40, "Max Capacity": 100,
                                          "Is Charging": true, "Power Source State": "AC Power", "Time to Full Charge": -1]
        #expect(BatteryInfo.sample(from: description)
            == BatterySample(percent: 40, charging: true, plugged: true, minutesLeft: nil))
    }

    @Test func aBatteryHeldOnPowerIsPluggedButNotCharging() {
        let description: [String: Any] = ["Type": "InternalBattery", "Current Capacity": 80, "Max Capacity": 100,
                                          "Is Charging": false, "Power Source State": "AC Power"]
        #expect(BatteryInfo.sample(from: description)
            == BatterySample(percent: 80, charging: false, plugged: true, minutesLeft: nil))
    }
```

`Tests/PhoneBoxTests/DashboardHubTests.swift`:

Bul (1/4):

```swift
    let runner = FakeRunner()

    func makeHub(mode: AccessMode) -> DashboardHub {
        DashboardHub(mode: mode, key: key, appName: "PhoneBox test", hostName: "Test Mac", commands: runner,
                     usbInterfaces: { ["anri1"] })
    }
```

Şununla değiştir:

```swift
    let runner = FakeRunner()
    let limits = PowerLimits(start: 25, full: 60)

    func makeHub(mode: AccessMode) -> DashboardHub {
        DashboardHub(mode: mode, key: key, appName: "PhoneBox test", hostName: "Test Mac", powerLimits: limits,
                     commands: runner, usbInterfaces: { ["anri1"] })
    }
```

Bul (2/4):

```swift
        #expect(cable.authenticated && wifi.authenticated)
        #expect(cable.sent.last == .ready(mode: .always, host: "Test Mac", access: .onCable))
        #expect(wifi.sent.last == .ready(mode: .always, host: "Test Mac", access: .overWiFi))
    }
```

Şununla değiştir:

```swift
        #expect(cable.authenticated && wifi.authenticated)
        #expect(cable.sent.last == .ready(mode: .always, host: "Test Mac", powerLimits: limits, access: .onCable))
        #expect(wifi.sent.last == .ready(mode: .always, host: "Test Mac", powerLimits: limits, access: .overWiFi))
    }
```

Bul (3/4):

```swift
        hub.received(#"{"v":1,"type":"auth","mac":"\#(mac)"}"#, from: phone)
        #expect(phone.sent.last == .ready(mode: .always, host: "Test Mac", access: .overWiFi))
    }
```

Şununla değiştir:

```swift
        hub.received(#"{"v":1,"type":"auth","mac":"\#(mac)"}"#, from: phone)
        #expect(phone.sent.last == .ready(mode: .always, host: "Test Mac", powerLimits: limits, access: .overWiFi))
    }
```

Bul (4/4):

```swift
        let phone = connect(hub, onUSB: false)
        #expect(phone.sent.last == .ready(mode: .cable, host: "Test Mac", access: .notOnCable))
        hub.mode = .always
```

Şununla değiştir:

```swift
        let phone = connect(hub, onUSB: false)
        #expect(phone.sent.last == .ready(mode: .cable, host: "Test Mac", powerLimits: limits, access: .notOnCable))
        hub.mode = .always
```

- [ ] **Step 2: Testlerin derlenmediğini gör**

Run: `make test FILTER="PowerLimitsTests|ServerMessageTests|BatteryInfoTests"` → Expected: derleme hatası
(`PowerLimits` yok, `BatterySample`'ın `plugged` parametresi yok).

- [ ] **Step 3: Güç sınırı tablosu**

`Sources/PhoneBoxCore/PowerLimits.swift`:

```swift
/// Where the page's power tile starts turning red and where it is fully red, in watts (design §8 "Sınıra
/// yaklaşınca kızarma"). The figures are rough, per chip family, and open to community testing.
public struct PowerLimits: Equatable, Sendable {
    public var start: Double
    public var full: Double

    public init(start: Double, full: Double) {
        self.start = start
        self.full = full
    }

    /// A plain M-series chip, whole Mac; also used for a chip PhoneBox does not know.
    public static let standard = PowerLimits(start: 15, full: 35)

    /// `brand` is `machdep.cpu.brand_string`, e.g. "Apple M4 Pro". `wholeMac` is true when the power tile shows the
    /// whole Mac (MacBooks); desktop Macs only report the GPU's power.
    public static func forChip(_ brand: String, wholeMac: Bool) -> PowerLimits {
        let tier = brand.split(separator: " ").last.map(String.init) ?? ""
        switch (tier, wholeMac) {
        case ("Pro", true): return PowerLimits(start: 25, full: 60)
        case ("Pro", false): return PowerLimits(start: 10, full: 30)
        case ("Max", true): return PowerLimits(start: 35, full: 100)
        case ("Max", false): return PowerLimits(start: 20, full: 60)
        case ("Ultra", true): return PowerLimits(start: 50, full: 160)
        case ("Ultra", false): return PowerLimits(start: 30, full: 90)
        case (_, false): return PowerLimits(start: 5, full: 15)
        default: return standard
        }
    }
}

extension PowerLimits: Encodable {
    private enum Keys: String, CodingKey { case power }

    /// `{"power":[15,35]}`, the `limits` object of the `ready` message (design §5).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode([start, full], forKey: .power)
    }
}
```

- [ ] **Step 4: `ready` sınırı taşır, pil prizde mi söyler**

`Sources/PhoneBoxCore/Messages.swift`:

Bul (1/4):

```swift
    case hello(nonce: String, app: String)
    case ready(mode: AccessMode, host: String, access: Access)
    case access(Access)
```

Şununla değiştir:

```swift
    case hello(nonce: String, app: String)
    case ready(mode: AccessMode, host: String, powerLimits: PowerLimits, access: Access)
    case access(Access)
```

Bul (2/4):

```swift
    private enum Keys: String, CodingKey {
        case v, type, nonce, app, mode, host, access, streaming, commands, cable, reason, t, cpu, mem, gpu, temp, power, net, disk,
             battery, apps, media, audio, seq, ok, error
```

Şununla değiştir:

```swift
    private enum Keys: String, CodingKey {
        case v, type, nonce, app, mode, host, limits, access, streaming, commands, cable, reason, t, cpu, mem, gpu, temp, power, net, disk,
             battery, apps, media, audio, seq, ok, error
```

Bul (3/4):

```swift
            try container.encode(app, forKey: .app)
        case let .ready(mode, host, access):
            try container.encode("ready", forKey: .type)
```

Şununla değiştir:

```swift
            try container.encode(app, forKey: .app)
        case let .ready(mode, host, powerLimits, access):
            try container.encode("ready", forKey: .type)
```

Bul (4/4):

```swift
            try container.encode(host, forKey: .host)
            try container.encode(access, forKey: .access)
```

Şununla değiştir:

```swift
            try container.encode(host, forKey: .host)
            try container.encode(powerLimits, forKey: .limits)
            try container.encode(access, forKey: .access)
```

`Sources/PhoneBoxCore/Metrics.swift`:

Bul (1/2):

```swift
    public var charging: Bool
    /// Minutes to empty while discharging, to full while charging; nil while macOS is still estimating.
    public var minutesLeft: Int?
    public init(percent: Int, charging: Bool, minutesLeft: Int?) {
        self.percent = percent
        self.charging = charging
        self.minutesLeft = minutesLeft
```

Şununla değiştir:

```swift
    public var charging: Bool
    /// On the power adapter (charging or not); the page turns a low battery red only when this is false.
    public var plugged: Bool
    /// Minutes to empty while discharging, to full while charging; nil while macOS is still estimating.
    public var minutesLeft: Int?
    public init(percent: Int, charging: Bool, plugged: Bool, minutesLeft: Int?) {
        self.percent = percent
        self.charging = charging
        self.plugged = plugged
        self.minutesLeft = minutesLeft
```

Bul (2/2):

```swift
        let charging = description["Is Charging"] as? Bool ?? false
        let minutes = (charging ? description["Time to Full Charge"] : description["Time to Empty"]) as? Int
        return BatterySample(percent: min(100, max(0, current * 100 / maximum)), charging: charging,
                             minutesLeft: minutes.flatMap { $0 > 0 ? $0 : nil })
```

Şununla değiştir:

```swift
        let charging = description["Is Charging"] as? Bool ?? false
        let plugged = description["Power Source State"] as? String == "AC Power"
        let minutes = (charging ? description["Time to Full Charge"] : description["Time to Empty"]) as? Int
        return BatterySample(percent: min(100, max(0, current * 100 / maximum)), charging: charging, plugged: plugged,
                             minutesLeft: minutes.flatMap { $0 > 0 ? $0 : nil })
```

- [ ] **Step 5: Uygulama çipini bulur, sınırı gönderir**

`Sources/PhoneBox/DashboardHub.swift`:

Bul (1/4):

```swift
    private let appName: String
    /// The Mac's name, shown in the page's status line.
    private let hostName: String
    private let commands: any CommandRunning
```

Şununla değiştir:

```swift
    private let appName: String
    /// The Mac's name, shown at the top of the page's "⋯" menu.
    private let hostName: String
    /// Where the page's power tile turns red, for this Mac's chip.
    private let powerLimits: PowerLimits
    private let commands: any CommandRunning
```

Bul (2/4):

```swift
    var onConnectionClosed: ((any PhoneConnection) -> Void)?

    init(mode: AccessMode, key: PairingKey, appName: String, hostName: String, commands: any CommandRunning,
         usbInterfaces: @escaping () -> Set<String> = USBLinks.iPhoneInterfaceNames) {
        self.mode = mode
```

Şununla değiştir:

```swift
    var onConnectionClosed: ((any PhoneConnection) -> Void)?

    init(mode: AccessMode, key: PairingKey, appName: String, hostName: String, powerLimits: PowerLimits = .standard,
         commands: any CommandRunning, usbInterfaces: @escaping () -> Set<String> = USBLinks.iPhoneInterfaceNames) {
        self.mode = mode
```

Bul (3/4):

```swift
        self.hostName = hostName
        self.commands = commands
```

Şununla değiştir:

```swift
        self.hostName = hostName
        self.powerLimits = powerLimits
        self.commands = commands
```

Bul (4/4):

```swift
            clients[id] = client
            connection.send(.ready(mode: mode, host: hostName, access: client.access))
            onAuthenticated?()
```

Şununla değiştir:

```swift
            clients[id] = client
            connection.send(.ready(mode: mode, host: hostName, powerLimits: powerLimits, access: client.access))
            onAuthenticated?()
```

`Sources/PhoneBox/Settings.swift`:

Bul:

```swift
    }

    /// "Eren's MacBook Pro" from System Settings → General → Sharing; the page shows it in its status line.
    static func computerName() -> String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? localHostName()
    }
```

Şununla değiştir:

```swift
    }

    /// "Eren's MacBook Pro" from System Settings → General → Sharing; the page shows it in its "⋯" menu.
    static func computerName() -> String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? localHostName()
    }

    /// "Apple M4 Pro" from `machdep.cpu.brand_string`; empty if it cannot be read.
    static func chipName() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(cString: bytes)
    }
```

`Sources/PhoneBox/AppDelegate.swift`:

Bul:

```swift
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        hub = DashboardHub(mode: settings.mode, key: key, appName: "PhoneBox \(version)", hostName: Settings.computerName(),
                           commands: commandRunner)
        let webDirectory = Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true)
```

Şununla değiştir:

```swift
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        // A Mac with a battery reports its whole power draw; a desktop Mac only the GPU's.
        let powerLimits = PowerLimits.forChip(Settings.chipName(), wholeMac: BatteryCollector().sample() != nil)
        hub = DashboardHub(mode: settings.mode, key: key, appName: "PhoneBox \(version)", hostName: Settings.computerName(),
                           powerLimits: powerLimits, commands: commandRunner)
        let webDirectory = Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true)
```

- [ ] **Step 6: Testleri çalıştır**

Run: `make test FILTER="PowerLimitsTests|ServerMessageTests|BatteryInfoTests|DashboardHubTests"` → Expected: hepsi geçer.
Run: iki uyarı denetimi → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 17 tests in 4 suites passed` ve `Test run with 163 tests in 29 suites passed`.

- [ ] **Step 7: Commit**

```bash
git add Sources/PhoneBoxCore/PowerLimits.swift Sources/PhoneBoxCore/Messages.swift Sources/PhoneBoxCore/Metrics.swift \
  Sources/PhoneBox/DashboardHub.swift Sources/PhoneBox/Settings.swift Sources/PhoneBox/AppDelegate.swift \
  Tests/PhoneBoxCoreTests/PowerLimitsTests.swift Tests/PhoneBoxCoreTests/MessagesTests.swift \
  Tests/PhoneBoxCoreTests/MetricsTests.swift Tests/PhoneBoxTests/DashboardHubTests.swift
git commit -m "Send power limits for the chip and whether the Mac is on power"
```

---

### Task 2: Telefonun pili

**Files:**
- Create: `Sources/PhoneBoxCore/PhoneBattery.swift`, `Tests/PhoneBoxCoreTests/PhoneBatteryTests.swift`
- Create: `Sources/PhoneBox/Collectors/PhoneBatteryReader.swift`, `Tests/PhoneBoxTests/PhoneBatteryLiveTests.swift`
- Modify: `Sources/PhoneBoxCore/Snapshot.swift`, `Sources/PhoneBoxCore/Messages.swift`,
  `Tests/PhoneBoxCoreTests/MessagesTests.swift`, `Sources/PhoneBox/Collectors/PrivateSymbols.swift`,
  `Sources/PhoneBox/Sampler.swift`

**Interfaces:**
- Consumes: Görev 1'in `ServerMessage`'ı; mevcut `JSONValue.integer`, `JSONValue.bool`, `PrivateSymbols.function`,
  `Log.app`.
- Produces:
  - `PhoneBatterySample(percent: Int, charging: Bool, plugged: Bool)`.
  - `PhoneBatteryInfo.sample(capacity:charging:external:) -> PhoneBatterySample?`.
  - `PhoneBatteryMemory`: `remember(_:at:)`, `forget()`, `current(at:)`, `keepFor` = 300 sn.
  - `Snapshot.phone`; JSON'da `"phone":{"charging":…,"percent":…,"plugged":…}`, yoksa alan yok.
  - `MobileDeviceAPI.load() -> MobileDeviceAPI?`, `readBattery(_ device: DeviceRef)`; `PhoneBatteryReader`:
    `start()`, `stop()`, `latest`. `Sampler` onu açıp kapatır ve `phone: phoneBattery.latest` gönderir.

- [ ] **Step 1: Testleri yaz**

`Tests/PhoneBoxCoreTests/PhoneBatteryTests.swift`:

```swift
import Foundation
import Testing
@testable import PhoneBoxCore

struct PhoneBatteryTests {
    @Test func readsTheValuesThePhoneGives() {
        let sample = PhoneBatteryInfo.sample(capacity: NSNumber(value: 76), charging: kCFBooleanTrue, external: kCFBooleanTrue)
        #expect(sample == PhoneBatterySample(percent: 76, charging: true, plugged: true))
        #expect(PhoneBatteryInfo.sample(capacity: NSNumber(value: 100), charging: kCFBooleanFalse, external: nil)
            == PhoneBatterySample(percent: 100, charging: false, plugged: false))
    }

    @Test func refusesAMissingOrOddCapacity() {
        #expect(PhoneBatteryInfo.sample(capacity: nil, charging: kCFBooleanTrue, external: kCFBooleanTrue) == nil)
        #expect(PhoneBatteryInfo.sample(capacity: kCFBooleanTrue, charging: nil, external: nil) == nil)
        #expect(PhoneBatteryInfo.sample(capacity: NSNumber(value: 101), charging: nil, external: nil) == nil)
        #expect(PhoneBatteryInfo.sample(capacity: NSNumber(value: -1), charging: nil, external: nil) == nil)
        #expect(PhoneBatteryInfo.sample(capacity: "76", charging: nil, external: nil) == nil)
    }

    @Test func keepsAReadingForFiveMinutes() {
        var memory = PhoneBatteryMemory()
        let start = Date(timeIntervalSince1970: 1_000)
        let sample = PhoneBatterySample(percent: 50, charging: true, plugged: true)
        #expect(memory.current(at: start) == nil)
        memory.remember(sample, at: start)
        #expect(memory.current(at: start.addingTimeInterval(300)) == sample)
        #expect(memory.current(at: start.addingTimeInterval(301)) == nil)
    }

    @Test func forgetsAtOnceWhenThePhoneGoes() {
        var memory = PhoneBatteryMemory()
        let start = Date(timeIntervalSince1970: 1_000)
        memory.remember(PhoneBatterySample(percent: 50, charging: false, plugged: true), at: start)
        memory.forget()
        #expect(memory.current(at: start) == nil)
    }
}
```

`Tests/PhoneBoxCoreTests/MessagesTests.swift`:

Bul:

```swift
            == #"{"audio":{"muted":false,"volume":0.5},"media":{"app":"Spotify","playing":true,"title":"Kara Toprak"},"t":9,"type":"snapshot","v":1}"#)
    }
```

Şununla değiştir:

```swift
            == #"{"audio":{"muted":false,"volume":0.5},"media":{"app":"Spotify","playing":true,"title":"Kara Toprak"},"t":9,"type":"snapshot","v":1}"#)
    }

    @Test func encodesThePhonesBattery() {
        let snapshot = Snapshot(t: 3, phone: PhoneBatterySample(percent: 76, charging: true, plugged: true))
        #expect(ServerMessage.snapshot(snapshot).json()
            == #"{"phone":{"charging":true,"percent":76,"plugged":true},"t":3,"type":"snapshot","v":1}"#)
    }
```

- [ ] **Step 2: Testlerin derlenmediğini gör**

Run: `make test FILTER="PhoneBatteryTests|ServerMessageTests"` → Expected: derleme hatası (`PhoneBatterySample`,
`PhoneBatteryInfo`, `PhoneBatteryMemory` yok).

- [ ] **Step 3: Örnek, değerlerden üretme, hafıza ve snapshot alanı**

`Sources/PhoneBoxCore/PhoneBattery.swift`:

```swift
import Foundation

/// The battery of the iPhone plugged into the Mac (design §6 `phone`). Safari gives a page no battery information,
/// so the Mac reads it over USB.
public struct PhoneBatterySample: Equatable, Codable, Sendable {
    public var percent: Int
    public var charging: Bool
    /// On a power source; on the Mac's cable this is normally true.
    public var plugged: Bool
    public init(percent: Int, charging: Bool, plugged: Bool) {
        self.percent = percent
        self.charging = charging
        self.plugged = plugged
    }
}

public enum PhoneBatteryInfo {
    /// From the phone's `com.apple.mobile.battery` values: `BatteryCurrentCapacity` (a number, 0…100),
    /// `BatteryIsCharging` and `ExternalConnected` (booleans). Nil without a usable capacity.
    public static func sample(capacity: Any?, charging: Any?, external: Any?) -> PhoneBatterySample? {
        guard let percent = JSONValue.integer(capacity), (0...100).contains(percent) else { return nil }
        return PhoneBatterySample(percent: percent, charging: JSONValue.bool(charging) ?? false,
                                  plugged: JSONValue.bool(external) ?? false)
    }
}

/// Keeps the last good reading for a while, so one failed read (the phone busy, or locked) does not make the
/// page's battery icon blink.
public struct PhoneBatteryMemory: Sendable {
    /// A reading older than this is dropped and the page hides the icon.
    public static let keepFor: TimeInterval = 300
    private var last: PhoneBatterySample?
    private var readAt = Date.distantPast

    public init() {}

    public mutating func remember(_ sample: PhoneBatterySample, at date: Date) {
        last = sample
        readAt = date
    }

    /// The phone was unplugged, or a second one was plugged in: the reading no longer belongs to "the" phone.
    public mutating func forget() {
        last = nil
    }

    public func current(at date: Date) -> PhoneBatterySample? {
        date.timeIntervalSince(readAt) <= Self.keepFor ? last : nil
    }
}
```

`Sources/PhoneBoxCore/Snapshot.swift`:

Bul (1/4):

```swift
/// of the JSON; the dashboard shows "—" for it. `apps` is sent every third second; `media` only while something
/// is playing (or paused) and `audio` only for an output with volume control.
public struct Snapshot: Equatable, Codable, Sendable {
```

Şununla değiştir:

```swift
/// of the JSON; the dashboard shows "—" for it. `apps` is sent every third second; `media` only while something
/// is playing (or paused), `audio` only for an output with volume control and `phone` only while one iPhone is
/// plugged in over USB and its battery could be read.
public struct Snapshot: Equatable, Codable, Sendable {
```

Bul (2/4):

```swift
    public var audio: AudioSample?

    public init(t: Int64, cpu: CPUSample? = nil, mem: MemorySample? = nil, gpu: GPUSample? = nil,
```

Şununla değiştir:

```swift
    public var audio: AudioSample?
    public var phone: PhoneBatterySample?

    public init(t: Int64, cpu: CPUSample? = nil, mem: MemorySample? = nil, gpu: GPUSample? = nil,
```

Bul (3/4):

```swift
                disk: DiskSample? = nil, battery: BatterySample? = nil, apps: [AppSample]? = nil,
                media: MediaSample? = nil, audio: AudioSample? = nil) {
        self.t = t
```

Şununla değiştir:

```swift
                disk: DiskSample? = nil, battery: BatterySample? = nil, apps: [AppSample]? = nil,
                media: MediaSample? = nil, audio: AudioSample? = nil, phone: PhoneBatterySample? = nil) {
        self.t = t
```

Bul (4/4):

```swift
        self.audio = audio
    }
```

Şununla değiştir:

```swift
        self.audio = audio
        self.phone = phone
    }
```

`Sources/PhoneBoxCore/Messages.swift`:

Bul (1/2):

```swift
        case v, type, nonce, app, mode, host, limits, access, streaming, commands, cable, reason, t, cpu, mem, gpu, temp, power, net, disk,
             battery, apps, media, audio, seq, ok, error
    }
```

Şununla değiştir:

```swift
        case v, type, nonce, app, mode, host, limits, access, streaming, commands, cable, reason, t, cpu, mem, gpu, temp, power, net, disk,
             battery, apps, media, audio, phone, seq, ok, error
    }
```

Bul (2/2):

```swift
            try container.encodeIfPresent(snapshot.audio, forKey: .audio)
        case let .ack(seq, ok, error):
```

Şununla değiştir:

```swift
            try container.encodeIfPresent(snapshot.audio, forKey: .audio)
            try container.encodeIfPresent(snapshot.phone, forKey: .phone)
        case let .ack(seq, ok, error):
```

- [ ] **Step 4: Testleri çalıştır**

Run: `make test FILTER="PhoneBatteryTests|ServerMessageTests"` → Expected: hepsi geçer.

- [ ] **Step 5: MobileDevice ile okuyucu**

`Sources/PhoneBox/Collectors/PrivateSymbols.swift`:

Bul:

```swift
    static let login = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW)
}
```

Şununla değiştir:

```swift
    static let login = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW)
    /// Finder and Xcode talk to iPhones through it; newer macOS keeps it under /Library/Apple.
    static let mobileDevice = dlopen("/Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice", RTLD_NOW)
        ?? dlopen("/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice", RTLD_NOW)
}
```

`Sources/PhoneBox/Collectors/PhoneBatteryReader.swift`:

```swift
import Foundation
import PhoneBoxCore

/// An iPhone as MobileDevice hands it out (`am_device *`).
struct DeviceRef: @unchecked Sendable, Equatable {
    let pointer: UnsafeMutableRawPointer
}

/// The few functions of the private MobileDevice framework that reading a phone's battery needs (2026-11-26:
/// works without root on macOS 27; the phone only has to trust this Mac). Nil if the framework or a function is
/// missing.
struct MobileDeviceAPI: @unchecked Sendable {
    typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    typealias Subscribe = @convention(c) (Callback, UInt32, UInt32, UnsafeMutableRawPointer?,
                                          UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    typealias Unsubscribe = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias Retain = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
    typealias Release = @convention(c) (UnsafeMutableRawPointer) -> Void
    typealias Call = @convention(c) (UnsafeMutableRawPointer) -> Int32
    typealias CopyValue = @convention(c) (UnsafeMutableRawPointer, CFString?, CFString?) -> Unmanaged<CFTypeRef>?

    /// `msg` values of `am_device_notification_callback_info`.
    static let connected: UInt32 = 1
    static let disconnected: UInt32 = 2
    /// `AMDeviceGetInterfaceType`: 1 is USB, 2 is the network (Wi-Fi sync).
    static let usb: Int32 = 1

    let subscribe: Subscribe
    let unsubscribe: Unsubscribe
    let retain: Retain
    let release: Release
    let interfaceType: Call
    let connect: Call
    let disconnect: Call
    let validatePairing: Call
    let startSession: Call
    let stopSession: Call
    let copyValue: CopyValue

    static func load() -> MobileDeviceAPI? {
        let library = PrivateSymbols.mobileDevice
        func function<T>(_ name: String, _ type: T.Type) -> T? { PrivateSymbols.function(library, name, as: type) }
        guard let subscribe = function("AMDeviceNotificationSubscribe", Subscribe.self),
              let unsubscribe = function("AMDeviceNotificationUnsubscribe", Unsubscribe.self),
              let retain = function("AMDeviceRetain", Retain.self),
              let release = function("AMDeviceRelease", Release.self),
              let interfaceType = function("AMDeviceGetInterfaceType", Call.self),
              let connect = function("AMDeviceConnect", Call.self),
              let disconnect = function("AMDeviceDisconnect", Call.self),
              let validatePairing = function("AMDeviceValidatePairing", Call.self),
              let startSession = function("AMDeviceStartSession", Call.self),
              let stopSession = function("AMDeviceStopSession", Call.self),
              let copyValue = function("AMDeviceCopyValue", CopyValue.self)
        else { return nil }
        return MobileDeviceAPI(subscribe: subscribe, unsubscribe: unsubscribe, retain: retain, release: release,
                               interfaceType: interfaceType, connect: connect, disconnect: disconnect,
                               validatePairing: validatePairing, startSession: startSession, stopSession: stopSession,
                               copyValue: copyValue)
    }

    /// Connects, starts a session, reads the battery values and closes again (~150 ms). Blocks: call it off the
    /// main thread.
    func readBattery(_ device: DeviceRef) -> PhoneBatterySample? {
        let pointer = device.pointer
        guard connect(pointer) == 0 else { return nil }
        defer { _ = disconnect(pointer) }
        guard validatePairing(pointer) == 0, startSession(pointer) == 0 else { return nil }
        defer { _ = stopSession(pointer) }
        func value(_ key: String) -> Any? {
            copyValue(pointer, "com.apple.mobile.battery" as CFString, key as CFString)?.takeRetainedValue()
        }
        return PhoneBatteryInfo.sample(capacity: value("BatteryCurrentCapacity"), charging: value("BatteryIsCharging"),
                                       external: value("ExternalConnected"))
    }
}

/// Reads the battery of the iPhone plugged in over USB (design §6 `phone`): a moment after it is plugged in and
/// then once a minute, only between `start()` and `stop()` (while the sampler runs). Reads run on their own queue,
/// one at a time, so they never hold up a snapshot. With two iPhones plugged in there is no "the" phone and
/// `latest` is nil.
@MainActor
final class PhoneBatteryReader {
    static let interval: TimeInterval = 60
    /// The phone needs a moment after usbmuxd reports it before it answers.
    static let settleDelay: TimeInterval = 2

    private let api = MobileDeviceAPI.load()
    private let queue = DispatchQueue(label: "com.phonebox.PhoneBox.phone-battery", qos: .utility)
    private var subscription: UnsafeMutableRawPointer?
    private var devices: [DeviceRef] = []
    private var memory = PhoneBatteryMemory()
    private var timer: Timer?
    private var reading = false

    /// The last good reading of the one iPhone on USB, at most 5 minutes old.
    var latest: PhoneBatterySample? { memory.current(at: Date()) }

    func start() {
        guard let api, subscription == nil else { return }
        // Called on the main thread, which is where MobileDevice delivers its notifications; phones already plugged
        // in are reported right away.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: MobileDeviceAPI.Callback = { info, context in
            guard let info, let context else { return }
            // struct am_device_notification_callback_info { am_device *dev; unsigned int msg; }
            let device = DeviceRef(pointer: info.load(as: UnsafeMutableRawPointer.self))
            let message = info.load(fromByteOffset: MemoryLayout<UnsafeMutableRawPointer>.size, as: UInt32.self)
            let reader = Unmanaged<PhoneBatteryReader>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { reader.deviceChanged(device, message: message) }
        }
        var subscription: UnsafeMutableRawPointer?
        guard api.subscribe(callback, 0, 0, context, &subscription) == 0 else {
            Log.app.notice("Cannot watch iPhones for their battery")
            return
        }
        self.subscription = subscription
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        guard let api, let subscription else { return }
        _ = api.unsubscribe(subscription)
        self.subscription = nil
        for device in devices { api.release(device.pointer) }
        devices.removeAll()
        memory.forget()
    }

    private func deviceChanged(_ device: DeviceRef, message: UInt32) {
        guard let api, subscription != nil else { return }
        switch message {
        case MobileDeviceAPI.connected where api.interfaceType(device.pointer) == MobileDeviceAPI.usb:
            guard !devices.contains(device) else { return }
            _ = api.retain(device.pointer)
            devices.append(device)
            memory.forget()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
                MainActor.assumeIsolated { self?.read() }
            }
        case MobileDeviceAPI.disconnected:
            guard let index = devices.firstIndex(of: device) else { return }
            api.release(devices.remove(at: index).pointer)
            memory.forget()
        default:
            break
        }
    }

    private func read() {
        guard let api, devices.count == 1, let device = devices.first, !reading else { return }
        reading = true
        _ = api.retain(device.pointer)
        queue.async { [weak self] in
            let sample = api.readBattery(device)
            api.release(device.pointer)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.finished(device, sample) }
            }
        }
    }

    private func finished(_ device: DeviceRef, _ sample: PhoneBatterySample?) {
        reading = false
        // The phone may have been unplugged, or another one plugged in, while it was read.
        guard let sample, devices == [device] else { return }
        memory.remember(sample, at: Date())
    }
}
```

`Sources/PhoneBox/Sampler.swift`:

Bul (1/3):

```swift
    private let audio = AudioCollector()

    var isRunning: Bool { timer != nil }
```

Şununla değiştir:

```swift
    private let audio = AudioCollector()
    private let phoneBattery = PhoneBatteryReader()

    var isRunning: Bool { timer != nil }
```

Bul (2/3):

```swift
            nowPlaying.start()
        } else {
            nowPlaying.stop()
```

Şununla değiştir:

```swift
            nowPlaying.start()
            phoneBattery.start()
        } else {
            phoneBattery.stop()
            nowPlaying.stop()
```

Bul (3/3):

```swift
            power: power.sample(), net: network.sample(), disk: disk.sample(), battery: battery.sample(),
            apps: tickCount % Self.appsEvery == 0 ? apps.sample() : nil, media: nowPlaying.current(), audio: audio.sample()))
    }
```

Şununla değiştir:

```swift
            power: power.sample(), net: network.sample(), disk: disk.sample(), battery: battery.sample(),
            apps: tickCount % Self.appsEvery == 0 ? apps.sample() : nil, media: nowPlaying.current(), audio: audio.sample(),
            phone: phoneBattery.latest))
    }
```

`Tests/PhoneBoxTests/PhoneBatteryLiveTests.swift` (yalnız `PHONEBOX_LIVE=1` ile çalışır):

```swift
import Foundation
import Testing
@testable import PhoneBox
import PhoneBoxCore

/// Reads the battery of the iPhone plugged into this Mac, so it runs only on request and with one trusted iPhone on
/// the cable: `PHONEBOX_LIVE=1 make test FILTER=PhoneBatteryLiveTests`.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PHONEBOX_LIVE"] == "1"))
struct PhoneBatteryLiveTests {
    @Test func readsThePluggedInPhone() async throws {
        #expect(MobileDeviceAPI.load() != nil)
        let reader = PhoneBatteryReader()
        reader.start()
        defer { reader.stop() }
        var sample: PhoneBatterySample?
        for _ in 0..<40 where sample == nil {
            try await Task.sleep(for: .milliseconds(250))
            sample = reader.latest
        }
        let battery = try #require(sample, "no iPhone battery within 10 s: is one trusted iPhone plugged in?")
        #expect((0...100).contains(battery.percent))
        #expect(battery.plugged)
    }
}
```

- [ ] **Step 6: Derle ve test et**

Run: iki uyarı denetimi → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 18 tests in 5 suites passed` ve `Test run with 168 tests in 30 suites passed`.
Canlı testi (`PHONEBOX_LIVE=1 make test FILTER="PhoneBatteryLiveTests"`) kontrolcü istemedikçe çalıştırmayın; bir
iPhone'un kabloyla takılı olmasını gerektirir. Kontrolcü çalıştırırsa: Expected: 1 test geçer.

- [ ] **Step 7: Commit**

```bash
git add Sources/PhoneBoxCore/PhoneBattery.swift Sources/PhoneBoxCore/Snapshot.swift Sources/PhoneBoxCore/Messages.swift \
  Sources/PhoneBox/Collectors/PrivateSymbols.swift Sources/PhoneBox/Collectors/PhoneBatteryReader.swift \
  Sources/PhoneBox/Sampler.swift Tests/PhoneBoxCoreTests/PhoneBatteryTests.swift \
  Tests/PhoneBoxCoreTests/MessagesTests.swift Tests/PhoneBoxTests/PhoneBatteryLiveTests.swift
git commit -m "Read the plugged-in iPhone's battery and send it with the snapshot"
```

---

### Task 3: Kızarma, hareket ve saat modülleri

**Files:**
- Create: `Resources/web/heat.js`, `Resources/web/motion.js`, `Resources/web/clock.js`,
  `Tests/PhoneBoxCoreTests/WebMotionTests.swift`
- Modify: `Resources/web/metrics.js`, `Tests/PhoneBoxCoreTests/WebPageTests.swift`

**Interfaces:**
- Consumes: mevcut `PhoneBox.metrics.values(snapshot)`; `WebPageTests.webDirectory`.
- Produces (`globalThis.PhoneBox` altında; bu görevde sayfa henüz yüklemez, Görev 4–5 yükler):
  - `heat = { limits(power) -> {cpu, ram, gpu, temp, power, net, disk, battery, app: [start, full]}, level(range, value)
    -> 0…1 | null, color(hex, level, light) -> [r, g, b], css(rgb, alpha), mix(a, b, t), rgb(hex), oklch(rgb),
    Alarm, hot }`. `Alarm(rounds = 3)`: `update(levels) -> [yeni çalanlar]`, `active() -> [çalanlar]`, `clear()`,
    `ringing` (Set).
  - `motion = { ease(x), between(from, to, t), Glide(duration = 900), onFrame(task), reduced() }`.
    `Glide`: `push(snapshot, now)`, `at(now) -> snapshot | null`.
  - `clock = { parts(date, language) -> {time: "09:05", day: "26 Kas Per"}, Clock(element) }`.
    `Clock.show(text, still)`.
  - `metrics.colors` (Okyanus), `metrics.light` (`{cpu, ram}`), `metrics.heatValues(snapshot)`,
    `metrics.graphHeat(metric)` (disk için null).

- [ ] **Step 1: Testleri yaz**

`Tests/PhoneBoxCoreTests/WebMotionTests.swift`:

```swift
import Foundation
import JavaScriptCore
import Testing

/// Runs the dashboard's `heat.js`, `motion.js` and `clock.js` (with `metrics.js` for the values that turn red) in
/// JavaScriptCore: the limits, the level, the colour path, the alarm rule, the gliding values and the clock text.
struct WebMotionTests {
    let context: JSContext

    init() throws {
        context = try #require(JSContext())
        context.exceptionHandler = { _, exception in Issue.record("JavaScript error: \(exception?.toString() ?? "?")") }
        for name in ["i18n.js", "format.js", "metrics.js", "heat.js", "motion.js", "clock.js"] {
            context.evaluateScript(try String(contentsOf: WebPageTests.webDirectory.appendingPathComponent(name), encoding: .utf8))
        }
        context.evaluateScript("""
            var H = PhoneBox.heat, M = PhoneBox.motion, L = H.limits([25, 60]);
            function hex(color) { return "#" + color.map(function (c) { return (c < 16 ? "0" : "") + c.toString(16); }).join(""); }
            """)
    }

    func string(_ code: String) -> String? { context.evaluateScript(code)?.toString() }

    @Test func takesThePowerLimitsFromTheMac() {
        #expect(string("L.power.join('-') + ' ' + L.cpu.join('-') + ' ' + L.disk.join('-')") == "25-60 40-95 30000000000-5000000000")
        for bad in ["undefined", "[1]", "[40, 20]", "['a', 3]", "[NaN, 3]"] {
            #expect(string("H.limits(\(bad)).power.join('-')") == "15-35", "\(bad)")
        }
    }

    @Test func measuresHowCloseAValueIsToItsLimit() {
        #expect(string("[30, 40, 67.5, 95, 120].map(function (v) { return H.level(L.cpu, v); }).join(',')") == "0,0,0.5,1,1")
        #expect(string("[40e9, 30e9, 17.5e9, 5e9, 1e9].map(function (v) { return H.level(L.disk, v); }).join(',')") == "0,0,0.5,1,1")
        #expect(string("[H.level(L.cpu, null), H.level(L.cpu, NaN), H.level(undefined, 3)].join(',')") == ",,")
    }

    @Test func turnsFromTheMetricsColourThroughVioletToRed() {
        #expect(string("hex(H.color('#00c2ff', 0))") == "#00c2ff")
        #expect(string("hex(H.color('#00c2ff', 1))") == "#ff2d2d")
        #expect(string("hex(H.color('#7ff3ff', 1, true))") == "#ff8a7a")
        // The hue only turns upwards: blue (~240°), violet, pink, then red (~29° + 360°).
        let hues = string("""
            [0, 0.25, 0.5, 0.75, 1].map(function (level) {
              var hue = H.oklch(H.color('#00c2ff', level))[2];
              return Math.round(hue < 200 ? hue + 360 : hue);
            }).join(',')
            """)
        let values = (hues ?? "").split(separator: ",").compactMap { Int($0) }
        #expect(values.count == 5)
        #expect(values == values.sorted())
        #expect((260...340).contains(values[2]), "half way should be violet or pink, got \(values[2])°")
    }

    @Test func ringsAfterThreeSnapshotsAtTheLimitAndStopsAfterThreeBelow() {
        let result = string("""
            (function () {
              var alarm = new H.Alarm(), log = [];
              function step(level) { var started = alarm.update({ cpu: level }); log.push(started.join("") + ":" + alarm.active().join("")); }
              step(1); step(1); step(1);            // rings on the third
              step(0.95); step(0.95); step(0.95);   // still above 0.9: keeps ringing
              step(0.5); step(null); step(0.2);     // a missing value counts as calm: stops on the third
              step(1); step(0.4); step(1);          // a spike now and then never rings
              return log.join(" ");
            })()
            """)
        #expect(result == ": : cpu:cpu :cpu :cpu :cpu :cpu :cpu : : : :")
    }

    @Test func clearsTheAlarmWhenTheValuesGoStale() {
        #expect(string("(function () { var a = new H.Alarm(); a.update({ temp: 1 }); a.update({ temp: 1 }); a.update({ temp: 1 }); a.clear(); a.update({ temp: 1 }); return a.active().length; })()") == "0")
    }

    @Test func findsTheValuesThatTurnRed() {
        let values = string("""
            JSON.stringify(PhoneBox.metrics.heatValues({ t: 1, cpu: { total: 63.6 }, mem: { used: 12, total: 16 }, gpu: { util: 17 },
              temp: { avg: 45.6, max: 54 }, power: { gpu: 0.4, system: 21.9 }, net: { rx: 1200, tx: 34 },
              disk: { free: 21.6e9, total: 494e9 }, battery: { percent: 80, charging: false, plugged: true } }))
            """)
        #expect(values == #"{"cpu":63.6,"ram":75,"gpu":17,"temp":45.6,"power":21.9,"net":1234,"disk":21600000000,"battery":null}"#)
        #expect(string("PhoneBox.metrics.heatValues({ battery: { percent: 12, charging: false, plugged: false } }).battery") == "12")
        #expect(string("PhoneBox.metrics.heatValues({ battery: { percent: 12, charging: false } }).battery") == "null")
        #expect(string("[PhoneBox.metrics.graphHeat('disk'), PhoneBox.metrics.graphHeat('net')].join(',')") == ",net")
    }

    @Test func blendsSnapshotsNumberByNumber() {
        let result = string("""
            JSON.stringify(M.between({ cpu: { total: 10, load: [1] }, mem: { used: 4 } },
                                     { cpu: { total: 30, load: [2] }, mem: { used: 8, total: 16 }, media: { title: "x" } }, 0.5))
            """)
        #expect(result == #"{"cpu":{"total":20,"load":[2]},"mem":{"used":6,"total":16},"media":{"title":"x"}}"#)
    }

    @Test func glidesToEachSnapshotFromWhatIsShown() {
        let result = string("""
            (function () {
              var glide = new M.Glide(900), out = [];
              glide.push({ v: 0 }, 0);
              out.push(glide.at(0).v);
              glide.push({ v: 100 }, 1000);
              out.push(Math.round(glide.at(1450).v), glide.at(1900).v);
              glide.push({ v: 0 }, 2000);
              glide.push({ v: 50 }, 2450);           // mid-way: starts from what is on screen
              out.push(Math.round(glide.at(2450).v), glide.at(3350).v);
              return out.join(",") + " " + (new M.Glide().at(5) === null);
            })()
            """)
        #expect(result == "0,88,100,13,50 true")
    }

    @Test func writesTheClockInBothLanguages() {
        #expect(string("JSON.stringify(PhoneBox.clock.parts(new Date(2026, 10, 26, 9, 5), 'tr'))") == #"{"time":"09:05","day":"26 Kas Per"}"#)
        #expect(string("JSON.stringify(PhoneBox.clock.parts(new Date(2026, 10, 26, 21, 40), 'en'))") == #"{"time":"21:40","day":"Thu, Nov 26"}"#)
    }
}
```

`Tests/PhoneBoxCoreTests/WebPageTests.swift` (CPU'nun yeni rengi):

Bul:

```swift
        #expect(string(#"PhoneBox.metrics.lines("net").map(function (l) { return l.key; }).join(",")"#) == "netRx,netTx")
        #expect(string(#"PhoneBox.metrics.lines("cpu")[0].color"#) == "#30d158")
        #expect(string(#"["cpu", "temp", "net", "power", "battery"].map(PhoneBox.metrics.scale).join(",")"#)
```

Şununla değiştir:

```swift
        #expect(string(#"PhoneBox.metrics.lines("net").map(function (l) { return l.key; }).join(",")"#) == "netRx,netTx")
        #expect(string(#"PhoneBox.metrics.lines("cpu")[0].color"#) == "#00c2ff")
        #expect(string(#"["cpu", "temp", "net", "power", "battery"].map(PhoneBox.metrics.scale).join(",")"#)
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `make test FILTER="WebMotionTests|WebPageTests"` → Expected: başarısız (yeni dosyalar yok: "JavaScript error";
CPU rengi hâlâ `#30d158`).

- [ ] **Step 3: Kızarma**

`Resources/web/heat.js`:

```js
// Turning red near a limit (design §8 "Sınıra yaklaşınca kızarma"): the limits, the level 0…1, the colour along
// path B (ocean → blue → violet → pink → red) and the alarm rule. Pure, so it is tested in JavaScriptCore.
(function (global) {
  "use strict";

  const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
  const finite = (value) => typeof value === "number" && Number.isFinite(value);

  /// [starts turning red, fully red] for each metric; `power` is the pair the Mac sent in `ready.limits`. A limit
  /// below its start means lower is worse (free disk space in bytes, the battery when it is not on power).
  function limits(power) {
    const ok = Array.isArray(power) && power.length === 2 && power.every(finite) && power[0] < power[1];
    return {
      cpu: [40, 95], ram: [75, 95], gpu: [40, 95], temp: [60, 95], power: ok ? power.slice() : [15, 35],
      net: [10e6, 100e6], disk: [30e9, 5e9], battery: [30, 10], app: [60, 200],
    };
  }

  /// 0 below the start, 1 at or past the limit, straight in between; null for a missing value.
  function level(range, value) {
    if (!range || !finite(value)) return null;
    return clamp((value - range[0]) / (range[1] - range[0]), 0, 1);
  }

  // ---- Colour: OKLCH keeps the in-between colours vivid (an RGB blend of blue and red goes grey).
  const toLinear = (channel) => {
    const c = channel / 255;
    return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  };
  const toByte = (linear) => {
    const c = linear <= 0.0031308 ? 12.92 * linear : 1.055 * Math.pow(linear, 1 / 2.4) - 0.055;
    return Math.round(clamp(c, 0, 1) * 255);
  };

  function rgb(hex) {
    const value = parseInt(hex.slice(1), 16);
    return [(value >> 16) & 255, (value >> 8) & 255, value & 255];
  }

  /// [lightness 0…1, chroma, hue in degrees 0…360).
  function oklch(color) {
    const [r, g, b] = color.map(toLinear);
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    const L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
    const A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
    const B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
    return [L, Math.hypot(A, B), ((Math.atan2(B, A) * 180) / Math.PI + 360) % 360];
  }

  function linearFromOklab(L, A, B) {
    const l = Math.pow(L + 0.3963377774 * A + 0.2158037573 * B, 3);
    const m = Math.pow(L - 0.1055613458 * A - 0.0638541728 * B, 3);
    const s = Math.pow(L - 0.0894841775 * A - 1.291485548 * B, 3);
    return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
      -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
      -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s];
  }

  /// An OKLCH colour as RGB; a colour the screen cannot show loses chroma until it can.
  function fromOklch(L, C, hue) {
    const angle = (hue * Math.PI) / 180;
    const at = (chroma) => linearFromOklab(L, chroma * Math.cos(angle), chroma * Math.sin(angle));
    const inside = (linear) => linear.every((value) => value >= -0.0005 && value <= 1.0005);
    let linear = at(C);
    if (!inside(linear)) {
      let low = 0;
      let high = C;
      for (let step = 0; step < 16; step += 1) {
        const middle = (low + high) / 2;
        if (inside(at(middle))) low = middle;
        else high = middle;
      }
      linear = at(low);
    }
    return linear.map(toByte);
  }

  const hot = "#ff2d2d";
  const hotLight = "#ff8a7a";
  const cache = new Map();

  /// `hex` at heat `level`, as [r, g, b]. The hue turns upwards (blue, violet, pink) until it reaches red; `light`
  /// is the bright end of a ring and ends at a light red. The level is eased at both ends and rounded to 1/100.
  function color(hex, heatLevel, light) {
    const level = clamp(finite(heatLevel) ? heatLevel : 0, 0, 1);
    const t = Math.round(level * level * (3 - 2 * level) * 100) / 100;
    const target = light ? hotLight : hot;
    if (t === 0) return rgb(hex);
    if (t === 1) return rgb(target);
    const key = `${hex}|${target}|${t}`;
    let result = cache.get(key);
    if (!result) {
      const [L0, C0, h0] = oklch(rgb(hex));
      const [L1, C1, h1] = oklch(rgb(target));
      let turn = h1 - h0;
      while (turn < 0) turn += 360;
      // A little more chroma half way keeps violet and pink from looking washed out.
      result = fromOklch(L0 + (L1 - L0) * t, C0 + (C1 - C0) * t + Math.sin(Math.PI * t) * 0.05, h0 + turn * t);
      cache.set(key, result);
    }
    return result;
  }

  const css = (color, alpha = 1) => `rgba(${color[0]}, ${color[1]}, ${color[2]}, ${alpha})`;
  const mix = (a, b, t) => a.map((value, index) => Math.round(value + (b[index] - value) * t));

  /// The alarm (design §8): a metric rings after `rounds` snapshots in a row at or past its limit and stops after
  /// `rounds` in a row below 0.9. A missing value, or one that does not turn red (the battery on power), counts as
  /// calm. A one-second spike never rings; the colour shows it anyway.
  class Alarm {
    constructor(rounds = 3) {
      this.rounds = rounds;
      this.counts = {};
      this.ringing = new Set();
    }

    /// `levels` maps each metric to its level or null; returns the metrics that just started ringing.
    update(levels) {
      const started = [];
      for (const metric of Object.keys(levels)) {
        const value = levels[metric];
        const count = this.counts[metric] || { over: 0, under: 0 };
        count.over = value !== null && value >= 1 ? count.over + 1 : 0;
        count.under = value === null || value < 0.9 ? count.under + 1 : 0;
        this.counts[metric] = count;
        if (!this.ringing.has(metric) && count.over >= this.rounds) {
          this.ringing.add(metric);
          started.push(metric);
        } else if (this.ringing.has(metric) && count.under >= this.rounds) {
          this.ringing.delete(metric);
        }
      }
      return started;
    }

    /// The ringing metrics, in the order they started.
    active() {
      return Array.from(this.ringing);
    }

    /// The values went stale: nothing rings.
    clear() {
      this.counts = {};
      this.ringing.clear();
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.heat = { limits, level, color, css, mix, rgb, oklch, Alarm, hot };
})(typeof window !== "undefined" ? window : globalThis);
```

- [ ] **Step 4: Hareket ve saat**

`Resources/web/motion.js`:

```js
// How things move (design §8 "Görünüm ve hareket"): values glide to each new snapshot, and one
// requestAnimationFrame loop draws everything. `ease`, `between` and `Glide` are pure and tested in JavaScriptCore.
(function (global) {
  "use strict";

  /// Starts fast and slows to a stop.
  const ease = (x) => 1 - Math.pow(1 - Math.max(0, Math.min(1, x)), 3);

  /// A snapshot part way (`t` 0…1) from `from` to `to`: a number found at the same place in both is blended,
  /// anything else is `to`'s. Arrays (cores, load, apps) are taken as they are.
  function between(from, to, t) {
    if (typeof to === "number") {
      return typeof from === "number" && Number.isFinite(from) && Number.isFinite(to) ? from + (to - from) * t : to;
    }
    if (!to || typeof to !== "object" || Array.isArray(to)) return to;
    const source = from && typeof from === "object" && !Array.isArray(from) ? from : {};
    const result = {};
    for (const key of Object.keys(to)) result[key] = between(source[key], to[key], t);
    return result;
  }

  /// The values on screen: each new snapshot is reached in `duration` ms, starting from what is shown, so a snapshot
  /// that arrives mid-way does not make a value jump.
  class Glide {
    constructor(duration = 900) {
      this.duration = duration;
      this.from = null;
      this.to = null;
      this.start = 0;
    }

    push(snapshot, now) {
      this.from = this.to ? this.at(now) : snapshot;
      this.to = snapshot;
      this.start = now;
    }

    /// The snapshot to show at `now`; null before the first one.
    at(now) {
      if (!this.to) return null;
      const t = ease((now - this.start) / this.duration);
      return t >= 1 ? this.to : between(this.from, this.to, t);
    }
  }

  // One loop for every drawing. The browser stops it while the page is hidden (phone locked, other tab).
  const tasks = [];
  let running = false;

  function frame(now) {
    for (const task of tasks) task(now);
    global.requestAnimationFrame(frame);
  }

  /// Calls `task(now)` on every frame.
  function onFrame(task) {
    tasks.push(task);
    if (running || !global.requestAnimationFrame) return;
    running = true;
    global.requestAnimationFrame(frame);
  }

  /// "Reduce Motion" is on: no shine, pulse, rolling digits or sliding rows; colours and numbers still change.
  function reduced() {
    return Boolean(global.matchMedia && global.matchMedia("(prefers-reduced-motion: reduce)").matches);
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.motion = { ease, between, Glide, onFrame, reduced };
})(typeof window !== "undefined" ? window : globalThis);
```

`Resources/web/clock.js`:

```js
// The phone's clock at the top of the page (design §8 "Saat ve telefonun pili"). `parts` is pure and tested in
// JavaScriptCore; `Clock` rolls a changed digit up and out and the new one in from below.
(function (global) {
  "use strict";

  const pad = (value) => String(value).padStart(2, "0");

  /// "09:05" (24-hour in both languages) and the date: "26 Kas Per" in Turkish, "Thu, Nov 26" in English.
  function parts(date, language) {
    const day = new Intl.DateTimeFormat(language, { weekday: "short", day: "numeric", month: "short" }).format(date);
    return { time: `${pad(date.getHours())}:${pad(date.getMinutes())}`, day };
  }

  class Clock {
    constructor(element) {
      this.element = element;
      this.text = "";
    }

    /// Shows `text`; with `still` ("Reduce Motion") the digits change without rolling.
    show(text, still) {
      if (text === this.text) return;
      const document = global.document;
      if (this.element.childElementCount !== text.length) {
        this.element.replaceChildren(...Array.from(text, (character) => {
          const cell = document.createElement("span");
          cell.className = character === ":" ? "clock-colon" : "clock-digit";
          if (character === ":") cell.textContent = ":";
          return cell;
        }));
      }
      Array.from(text).forEach((character, index) => {
        const cell = this.element.children[index];
        if (character === ":" || cell.dataset.value === character) return;
        cell.dataset.value = character;
        const old = cell.lastElementChild;
        if (old) {
          if (still) old.remove();
          else {
            old.className = "out";
            global.setTimeout(() => old.remove(), 700);
          }
        }
        const next = document.createElement("span");
        next.className = still ? "" : "in";
        next.textContent = character;
        cell.appendChild(next);
      });
      this.text = text;
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.clock = { parts, Clock };
})(typeof window !== "undefined" ? window : globalThis);
```

- [ ] **Step 5: Okyanus renkleri ve kızaran değerler**

`Resources/web/metrics.js`:

Bul (1/4):

```js
  const GiB = 1073741824;

  const colors = {
    cpu: "#30d158", ram: "#0a84ff", gpu: "#bf5af2", temp: "#ff9f0a", power: "#ffd60a", net: "#64d2ff",
    disk: "#8e8e93", battery: "#30d158",
  };
  const order = ["cpu", "ram", "gpu", "temp", "power", "net", "disk", "battery"];
```

Şununla değiştir:

```js
  const GiB = 1073741824;

  // The "Okyanus" palette (design §8 "Stil"); `light` is the bright end of a ring.
  const colors = {
    cpu: "#00c2ff", ram: "#3d6bff", gpu: "#7b61ff", temp: "#00e0b0", power: "#4ff0d0", net: "#8be9ff",
    disk: "#6f8fa8", battery: "#00d0a0",
  };
  const light = { cpu: "#7ff3ff", ram: "#9db4ff" };
  const order = ["cpu", "ram", "gpu", "temp", "power", "net", "disk", "battery"];
```

Bul (2/4):

```js
      case "net":
        return [{ key: "netRx", color, width: 2.2, fill: true }, { key: "netTx", color: "#bf5af2", width: 1.6, fill: false }];
      case "disk":
        return [{ key: "diskRead", color: "#d1d1d6", width: 2.2, fill: true }, { key: "diskWrite", color: "#ff9f0a", width: 1.6, fill: false }];
      default:
```

Şununla değiştir:

```js
      case "net":
        return [{ key: "netRx", color, width: 2.2, fill: true }, { key: "netTx", color: "#7b61ff", width: 1.6, fill: false }];
      case "disk":
        return [{ key: "diskRead", color, width: 2.2, fill: true }, { key: "diskWrite", color: "#4ff0d0", width: 1.6, fill: false }];
      default:
```

Bul (3/4):

```js
        return [{ key: metric, color, width: 2.2, fill: true }];
    }
  }

  /// How the graph's vertical axis is chosen (see `PhoneBox.chart.range`).
```

Şununla değiştir:

```js
        return [{ key: metric, color, width: 2.2, fill: true }];
    }
  }

  /// The numbers that turn a metric red (design §8, see `PhoneBox.heat.limits`): the network's ↓ + ↑, free disk
  /// space in bytes, and the battery only when it is not on power.
  function heatValues(snapshot) {
    const v = values(snapshot);
    const { net, disk, battery } = snapshot;
    return {
      cpu: v.cpu, ram: v.ram, gpu: v.gpu, temp: v.tempAvg, power: v.power,
      net: net ? num(net.rx + net.tx) : null,
      disk: disk ? num(disk.free) : null,
      battery: battery && battery.plugged === false ? num(battery.percent) : null,
    };
  }

  /// Which limits the graph's lines are measured against: the disk graph shows reading and writing, not free space,
  /// so it never turns red.
  function graphHeat(metric) {
    return metric === "disk" ? null : metric;
  }

  /// How the graph's vertical axis is chosen (see `PhoneBox.chart.range`).
```

Bul (4/4):

```js
  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.metrics = { colors, order, values, lines, scale, tile, header, axisLabel, GiB };
})(typeof window !== "undefined" ? window : globalThis);
```

Şununla değiştir:

```js
  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.metrics = { colors, light, order, values, heatValues, graphHeat, lines, scale, tile, header, axisLabel, GiB };
})(typeof window !== "undefined" ? window : globalThis);
```

- [ ] **Step 6: Testleri çalıştır**

Run: `make test FILTER="WebMotionTests|WebPageTests"` → Expected: 22 test geçer.
Run: iki uyarı denetimi → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 18 tests in 5 suites passed` ve `Test run with 177 tests in 31 suites passed`.

- [ ] **Step 7: Commit**

```bash
git add Resources/web/heat.js Resources/web/motion.js Resources/web/clock.js Resources/web/metrics.js \
  Tests/PhoneBoxCoreTests/WebMotionTests.swift Tests/PhoneBoxCoreTests/WebPageTests.swift
git commit -m "Add the heat, motion and clock modules with the Okyanus colours"
```

---

### Task 4: Halkalar, akan grafik, kayan satırlar ve kızarma

**Files:**
- Create: `Resources/web/rings.js`
- Modify (dosyanın tamamı): `Resources/web/view.js`
- Modify: `Resources/web/chart.js`, `Resources/web/app.js`, `Resources/web/index.html`, `Resources/web/i18n.js`,
  `Resources/web/styles.css`

**Interfaces:**
- Consumes: Görev 3'ün `heat`, `motion`, `metrics.colors/light/heatValues/graphHeat`; mevcut `chart.range`, `History`.
- Produces:
  - `rings.draw(canvas, size, {fraction, from, to, now, still, glow})`.
  - `chart.draw(canvas, width, height, lines, bounds, {label, shift, settle, heat(color, value), limit: {value, label},
    now, still, glow})` (eski `draw(canvas, lines, bounds, label)`'ın yerine).
  - `View`: `render(snapshot, now)`, `frame(now)`, `setLimits(power)`, `switchTo(metric, history)`,
    `renderGraph(history)` (artık çizmez, çizgileri hazırlar), `fitTiles(previous)`, `levelsOf(snapshot)`,
    `drawRing(...)`, `paintTile(...)`, `drawGraph(canvas, size, now, still)`; satırlar `app-bar` çubuğuyla.
  - `t.limit` ("SINIR" / "LIMIT"). Görev 5 `drawRing`, `paintTile`, `drawGraph`'a alarm parametreleri ekler.

- [ ] **Step 1: Halkaların çizimi**

`Resources/web/rings.js`:

```js
// The CPU and RAM rings on a <canvas> (design §8 "Görünüm ve hareket"): a thick arc whose colour runs from dark to
// light, a round tip that glows, and a shine that sweeps over the filled part. Checked by eye.
(function (global) {
  "use strict";

  /// Draws one ring into a square canvas `size` CSS pixels wide. `spec`: `fraction` 0…1 filled; `from` and `to`,
  /// [r, g, b] at the arc's start and end; `now` for the shine and the tip's glow; `still` leaves those out ("Reduce
  /// Motion"); `glow` 0…1 adds a pulsing glow around the arc while the metric's alarm rings.
  function draw(canvas, size, spec) {
    if (!size) return;
    const { css, mix } = global.PhoneBox.heat;
    const ratio = Math.min(global.devicePixelRatio || 1, 3);
    const pixels = Math.round(size * ratio);
    if (canvas.width !== pixels || canvas.height !== pixels) {
      canvas.width = pixels;
      canvas.height = pixels;
    }
    const g = canvas.getContext("2d");
    g.setTransform(ratio, 0, 0, ratio, 0, 0);
    g.clearRect(0, 0, size, size);

    const center = size / 2;
    const width = size * 0.12;
    const radius = center - width / 2 - 3;
    const fraction = Math.max(0, Math.min(1, spec.fraction || 0));
    const start = -Math.PI / 2;
    const end = start + Math.PI * 2 * fraction;
    const arc = (from, to) => {
      g.beginPath();
      g.arc(center, center, radius, from, to);
    };

    g.lineWidth = width;
    g.lineCap = "round";
    g.strokeStyle = css(spec.from, 0.16);
    arc(0, Math.PI * 2);
    g.stroke();
    if (fraction <= 0) return;

    if (spec.glow > 0) {
      g.save();
      g.shadowColor = css(spec.to, 0.95);
      g.shadowBlur = width * (0.5 + spec.glow);
      g.strokeStyle = css(spec.from, 0.3 + 0.5 * spec.glow);
      arc(start, end);
      g.stroke();
      g.restore();
    }

    // The arc in short pieces, each a step further from `from` towards `to`.
    const steps = 72;
    const pieces = Math.max(1, Math.ceil(steps * fraction));
    for (let index = 0; index < pieces; index += 1) {
      g.strokeStyle = css(mix(spec.from, spec.to, index / steps));
      g.lineCap = index === 0 ? "round" : "butt";
      arc(start + (index / steps) * Math.PI * 2, Math.min(end, start + ((index + 1.4) / steps) * Math.PI * 2));
      g.stroke();
    }

    const tip = mix(spec.from, spec.to, fraction);
    g.save();
    g.beginPath();
    g.arc(center + Math.cos(end) * radius, center + Math.sin(end) * radius, width / 2, 0, Math.PI * 2);
    g.fillStyle = css(tip);
    if (!spec.still) {
      g.shadowColor = css(spec.to);
      g.shadowBlur = width * (0.9 + 0.25 * Math.sin(spec.now / 400));
    }
    g.fill();
    g.restore();
    if (spec.still) return;

    const sweep = (spec.now / 1400) % 1;
    g.lineWidth = width * 0.55;
    g.lineCap = "round";
    g.strokeStyle = "rgba(255, 255, 255, 0.24)";
    arc(start + (end - start) * sweep, start + (end - start) * Math.min(1, sweep + 0.08));
    g.stroke();
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.rings = { draw };
})(typeof window !== "undefined" ? window : globalThis);
```

- [ ] **Step 2: Grafik her karede**

`Resources/web/chart.js`:

Bul (1/10):

```js
// The 60-second graph on a <canvas> (design §8 "Grafik"). `range` is pure and tested; `draw` is checked by eye.
(function (global) {
```

Şununla değiştir:

```js
// The 60-second graph on a <canvas> (design §8 "Grafik", "Görünüm ve hareket"). `range` is pure and tested; `draw`
// runs on every animation frame and is checked by eye.
(function (global) {
```

Bul (2/10):

```js
  }

  function rgba(hex, alpha) {
    const value = parseInt(hex.slice(1), 16);
    return `rgba(${(value >> 16) & 255}, ${(value >> 8) & 255}, ${value & 255}, ${alpha})`;
  }

  /// Draws `lines` ([{values, color, width, fill, alpha}]) scaled to `bounds`, with `label` at the top left.
  function draw(canvas, lines, bounds, label) {
    const ratio = global.devicePixelRatio || 1;
    const width = canvas.clientWidth;
    const height = canvas.clientHeight;
    if (!width || !height) return;
    if (canvas.width !== Math.round(width * ratio) || canvas.height !== Math.round(height * ratio)) {
```

Şununla değiştir:

```js
  }

  /// A smooth line through `points` (midpoint curves), as the current path.
  function trace(g, points) {
    g.moveTo(points[0][0], points[0][1]);
    for (let index = 1; index < points.length - 1; index += 1) {
      const [x, y] = points[index];
      g.quadraticCurveTo(x, y, (x + points[index + 1][0]) / 2, (y + points[index + 1][1]) / 2);
    }
    const last = points[points.length - 1];
    g.lineTo(last[0], last[1]);
  }

  /// Draws `lines` ([{values, color, width, fill, alpha}]) scaled to `bounds` on a canvas `width`×`height` CSS
  /// pixels. `options`:
  /// - `label`: the top of the axis, at the top left;
  /// - `shift` 0…1: how far time has moved on since the newest value, so the line scrolls left smoothly;
  /// - `settle` 0…1: how far the newest value has moved from the one before it;
  /// - `heat(color, value)`: the colour at the height of `value`, as [r, g, b], or null for plain colours;
  /// - `limit` {value, label}: the dashed red line where the metric is fully red;
  /// - `now`, `still`: the pulse on the newest point (none with "Reduce Motion"); `glow` 0…1 makes it an alarm.
  function draw(canvas, width, height, lines, bounds, options) {
    if (!width || !height) return;
    const heat = global.PhoneBox.heat;
    const ratio = Math.min(global.devicePixelRatio || 1, 3);
    if (canvas.width !== Math.round(width * ratio) || canvas.height !== Math.round(height * ratio)) {
```

Bul (3/10):

```js
    g.clearRect(0, 0, width, height);

    g.strokeStyle = "#2c2c2e";
    g.lineWidth = 1;
```

Şununla değiştir:

```js
    g.clearRect(0, 0, width, height);

    g.strokeStyle = "rgba(109, 138, 163, 0.25)";
    g.lineWidth = 1;
```

Bul (4/10):

```js
    g.setLineDash([]);

    if (label) {
      g.fillStyle = "#8e8e93";
      g.font = "10px -apple-system, system-ui, sans-serif";
      g.textBaseline = "top";
      g.fillText(label, 0, 0);
    }

    const pad = 3;
    const span = bounds.max - bounds.min || 1;
    const y = (value) => pad + (1 - (Math.min(Math.max(value, bounds.min), bounds.max) - bounds.min) / span) * (height - 2 * pad);
    for (const line of lines) {
      const count = line.values.length;
      const x = (index) => (count <= 1 ? width : (index / (count - 1)) * width);
      const runs = [];
      let run = [];
      line.values.forEach((value, index) => {
        if (value === null) {
```

Şununla değiştir:

```js
    g.setLineDash([]);

    if (options.label) {
      g.fillStyle = "#6d8aa3";
      g.font = "10px -apple-system, system-ui, sans-serif";
      g.textBaseline = "top";
      g.fillText(options.label, 0, 0);
    }

    const pad = 4;
    const span = bounds.max - bounds.min || 1;
    const y = (value) => pad + (1 - (Math.min(Math.max(value, bounds.min), bounds.max) - bounds.min) / span) * (height - 2 * pad);

    const limit = options.limit;
    if (limit && limit.value >= bounds.min && limit.value <= bounds.max) {
      const red = heat.rgb(heat.hot);
      const ly = Math.round(y(limit.value)) + 0.5;
      g.strokeStyle = heat.css(red, 0.5);
      g.setLineDash([4, 4]);
      g.beginPath();
      g.moveTo(0, ly);
      g.lineTo(width, ly);
      g.stroke();
      g.setLineDash([]);
      g.fillStyle = heat.css(red, 0.8);
      g.font = "600 9px -apple-system, system-ui, sans-serif";
      g.textBaseline = ly > 14 ? "bottom" : "top";
      g.fillText(limit.label, width - g.measureText(limit.label).width - 2, ly > 14 ? ly - 3 : ly + 3);
    }

    const shift = options.shift || 0;
    let head = null;
    lines.forEach((line, lineIndex) => {
      const values = line.values.slice();
      const count = values.length;
      // The newest value slides in from the one before it.
      const last = values[count - 1];
      const before = values[count - 2];
      if (last !== null && before !== null && before !== undefined && options.settle < 1) {
        values[count - 1] = before + (last - before) * options.settle;
      }
      const x = (index) => (count <= 1 ? width : ((index - shift) / (count - 1)) * width);
      const runs = [];
      let run = [];
      values.forEach((value, index) => {
        if (value === null) {
```

Bul (5/10):

```js
      if (run.length) runs.push(run);
      g.globalAlpha = line.alpha ?? 1;
```

Şununla değiştir:

```js
      if (run.length) runs.push(run);

      // Each height takes the colour of its own value, so peaks near the limit are red.
      const base = heat.rgb(line.color);
      const stroke = g.createLinearGradient(0, 0, 0, height);
      const area = g.createLinearGradient(0, 0, 0, height);
      for (let step = 12; step >= 0; step -= 1) {
        const value = bounds.min + (span * step) / 12;
        const position = Math.max(0, Math.min(1, y(value) / height));
        const color = options.heat ? options.heat(line.color, value) || base : base;
        stroke.addColorStop(position, heat.css(color));
        area.addColorStop(position, heat.css(color, 0.35 * (1 - position)));
      }

      g.globalAlpha = line.alpha ?? 1;
```

Bul (6/10):

```js
        if (points.length === 1) {
          g.fillStyle = line.color;
          g.beginPath();
```

Şununla değiştir:

```js
        if (points.length === 1) {
          g.fillStyle = stroke;
          g.beginPath();
```

Bul (7/10):

```js
        if (line.fill) {
          const gradient = g.createLinearGradient(0, 0, 0, height);
          gradient.addColorStop(0, rgba(line.color, 0.35));
          gradient.addColorStop(1, rgba(line.color, 0));
          g.fillStyle = gradient;
          g.beginPath();
          g.moveTo(points[0][0], height);
          for (const [px, py] of points) g.lineTo(px, py);
          g.lineTo(points[points.length - 1][0], height);
          g.closePath();
```

Şununla değiştir:

```js
        if (line.fill) {
          g.fillStyle = area;
          g.beginPath();
          trace(g, points);
          g.lineTo(points[points.length - 1][0], height);
          g.lineTo(points[0][0], height);
          g.closePath();
```

Bul (8/10):

```js
        }
        g.strokeStyle = line.color;
        g.lineWidth = line.width;
```

Şununla değiştir:

```js
        }
        g.strokeStyle = stroke;
        g.lineWidth = line.width;
```

Bul (9/10):

```js
        g.beginPath();
        points.forEach(([px, py], index) => (index ? g.lineTo(px, py) : g.moveTo(px, py)));
        g.stroke();
```

Şununla değiştir:

```js
        g.beginPath();
        trace(g, points);
        g.stroke();
```

Bul (10/10):

```js
      g.globalAlpha = 1;
    }
  }
```

Şununla değiştir:

```js
      g.globalAlpha = 1;
      if (lineIndex === 0 && values[count - 1] !== null && runs.length) {
        const newest = runs[runs.length - 1];
        const value = values[count - 1];
        head = { point: newest[newest.length - 1], color: options.heat ? options.heat(line.color, value) || base : base };
      }
    });

    // The newest point of the main line, with a ring of light that pulses (wider while the alarm rings).
    if (!head) return;
    const [hx, hy] = head.point;
    const glow = options.glow || 0;
    const pulse = options.still ? 0 : 0.5 + 0.5 * Math.sin(options.now / 260);
    const halo = glow > 0 ? 4 + 9 * glow : 3 + 5 * pulse;
    g.fillStyle = heat.css(head.color, glow > 0 ? 0.3 : 0.16);
    g.beginPath();
    g.arc(hx, hy, 3.2 + halo, 0, Math.PI * 2);
    g.fill();
    g.fillStyle = heat.css(head.color);
    g.beginPath();
    g.arc(hx, hy, 3.2, 0, Math.PI * 2);
    g.fill();
  }
```

- [ ] **Step 3: Görünüm**

`Resources/web/view.js` (dosyanın tamamı):

```js
// Puts the Mac's data on the page (design §8): rings, tiles, the graph and its header, the app list, the now-playing
// card, the status line and the state card. Values glide to each new snapshot and turn red near their limits;
// `frame` draws them on every animation frame. Text always goes in with textContent: names come from other apps.
(function (global) {
  "use strict";

  const $ = (id) => global.document.getElementById(id);
  const PB = () => global.PhoneBox;
  const tileMetrics = ["gpu", "temp", "power", "net", "disk", "battery"];
  const smooth = (x) => x * x * (3 - 2 * x);

  // Most frames change nothing on the page: write a text or a style only when it differs from the last write.
  const written = new WeakMap();
  function put(element, property, value) {
    let cache = written.get(element);
    if (!cache) {
      cache = {};
      written.set(element, cache);
    }
    if (cache[property] === value) return;
    cache[property] = value;
    if (property === "text") element.textContent = value;
    else if (property.startsWith("--")) element.style.setProperty(property, value);
    else element.style[property] = value;
  }

  class View {
    constructor(t, format) {
      const { motion, heat } = PB();
      this.t = t;
      this.format = format;
      this.host = t.mac;
      this.access = null;
      this.kind = "connecting";
      this.stale = true;
      this.selected = "cpu";
      this.sortBy = "cpu";
      this.snapshot = { t: 0 };
      this.apps = null;
      this.glide = new motion.Glide(900);
      this.limits = heat.limits();
      this.arrivedAt = 0;
      this.graph = null;
      this.rows = new Map();
      this.white = heat.rgb("#eaf6ff");
      this.card = heat.rgb("#0b1622");
      this.ringButtons = {};
      for (const button of global.document.querySelectorAll(".ring-button")) this.ringButtons[button.dataset.metric] = button;
    }

    fillTexts() {
      for (const element of global.document.querySelectorAll("[data-text]")) element.textContent = this.t[element.dataset.text];
      for (const element of global.document.querySelectorAll("[data-metric-label]")) {
        element.textContent = this.t.metric[element.dataset.metricLabel];
      }
      $("more").setAttribute("aria-label", this.t.more);
    }

    setHost(host) {
      this.host = host || this.t.mac;
      this.renderStatus();
    }

    /// The power limits from `ready.limits.power`; the other limits are fixed (design §8).
    setLimits(power) {
      this.limits = PB().heat.limits(power);
    }

    setAccess(access) {
      this.access = access;
      this.renderStatus();
    }

    setState(kind) {
      this.kind = kind;
      this.renderStatus();
      this.renderStateCard();
    }

    setStale(stale) {
      this.stale = stale;
      $("dashboard").classList.toggle("stale", stale);
      this.renderStatus();
    }

    // "● MacBook Pro · kablo": green on the cable, orange on Wi-Fi (no commands), grey while (re)connecting.
    renderStatus() {
      const t = this.t;
      const problems = { cable: t.stateCable, offline: t.stateOffline, unpaired: t.stateUnpaired, nokey: t.stateUnpaired,
                         nodata: t.stateNoData };
      let className = "status";
      let text = t.connecting;
      if (this.kind === "streaming" && !this.stale) {
        const cable = Boolean(this.access && this.access.cable);
        className += cable ? " streaming" : " wifi";
        text = `${this.host} · ${cable ? t.cable : t.wifi}`;
      } else if (problems[this.kind]) {
        className += " problem";
        text = problems[this.kind];
      }
      $("status").className = className;
      $("status-text").textContent = text;
    }

    renderStateCard() {
      const t = this.t;
      const cards = {
        cable: [t.stateCable, t.stateCableText],
        offline: [t.stateOffline, t.stateOfflineText],
        unpaired: [t.stateUnpaired, t.stateUnpairedText],
        nokey: [t.stateUnpaired, t.stateNoKeyText],
        nodata: [t.stateNoData, t.stateNoDataText],
      };
      const card = cards[this.kind];
      $("state").hidden = !card;
      if (!card) return;
      $("state-title").textContent = card[0];
      $("state-text").textContent = card[1];
    }

    /// A new snapshot: the values start gliding to it; the app list and the now-playing card change at once.
    render(snapshot, now) {
      const previous = this.glide.at(now);
      this.snapshot = snapshot;
      this.glide.push(snapshot, now);
      this.arrivedAt = now;
      this.fitTiles(previous);
      const playingBefore = !$("now-playing").hidden;
      this.renderNowPlaying(snapshot.media);
      if (snapshot.apps) this.apps = snapshot.apps;
      // A new app list arrives every 3 s; the card appearing or going changes how many rows fit.
      if (snapshot.apps || playingBefore !== !$("now-playing").hidden) this.renderApps();
    }

    // A long value (busy network, a disk over 1 TB) gets a smaller font instead of being cut off. Measured once
    // per snapshot, not on every frame: with the longer of the text the value glides from and the one it glides to
    // (a speed can change unit on the way), and all writes before the first read.
    fitTiles(previous) {
      const { metrics } = PB();
      const elements = tileMetrics.map((metric) => $(metric + "-tile"));
      elements.forEach((element, index) => {
        const next = metrics.tile(tileMetrics[index], this.snapshot, this.format);
        const before = previous ? metrics.tile(tileMetrics[index], previous, this.format) : "";
        put(element, "text", before.length > next.length ? before : next);
        element.style.fontSize = "";
      });
      for (const element of elements) {
        let size = parseFloat(global.getComputedStyle(element).fontSize);
        while (element.scrollWidth > element.clientWidth + 1 && size > 9) {
          size -= 1;
          element.style.fontSize = size + "px";
        }
      }
    }

    /// Each metric's heat level (0…1, or null) for a snapshot.
    levelsOf(snapshot) {
      const { heat, metrics } = PB();
      const values = metrics.heatValues(snapshot);
      const levels = {};
      for (const metric of Object.keys(values)) levels[metric] = heat.level(this.limits[metric], values[metric]);
      return levels;
    }

    /// Draws everything that moves. Sizes are read first, before any write, so the page is laid out once a frame.
    frame(now) {
      const shown = this.glide.at(now) || this.snapshot;
      const still = PB().motion.reduced();
      const ringSizes = {};
      for (const metric of ["cpu", "ram"]) ringSizes[metric] = this.ringButtons[metric].querySelector("canvas").clientWidth;
      const graph = $("graph");
      const graphSize = [graph.clientWidth, graph.clientHeight];

      const levels = this.levelsOf(shown);
      const { cpu, mem } = shown;
      const f = this.format;
      const memoryOK = mem && mem.total > 0;
      this.drawRing("cpu", ringSizes.cpu, cpu ? cpu.total : null, levels.cpu, now, still,
                    cpu && cpu.load && cpu.load.length ? this.t.load(f.decimal(cpu.load[0])) : "");
      this.drawRing("ram", ringSizes.ram, memoryOK ? (mem.used / mem.total) * 100 : null, levels.ram, now, still,
                    memoryOK ? this.t.memory(f.gibibytes(mem.used), f.gibibytes(mem.total)) : "");
      for (const metric of tileMetrics) this.paintTile(metric, shown, levels[metric]);
      this.renderHeader(shown, levels);
      this.drawGraph(graph, graphSize, now, still);
    }

    drawRing(metric, size, percent, level, now, still, sub) {
      const { heat, metrics, rings } = PB();
      const ok = typeof percent === "number" && Number.isFinite(percent);
      const heated = level ?? 0;
      const from = heat.color(metrics.colors[metric], heated);
      const to = heat.color(metrics.light[metric], heated, true);
      const button = this.ringButtons[metric];
      rings.draw(button.querySelector("canvas"), size, { fraction: ok ? percent / 100 : 0, from, to, now, still, glow: 0 });
      const value = $(metric + "-ring");
      put(value, "text", this.format.percent(ok ? percent : null));
      put(value, "color", heat.css(heat.mix(this.white, to, smooth(heated))));
      put($(metric + "-sub"), "text", sub);
      put(button, "--color", heat.css(from));
    }

    /// A tile's value and colours: the dot and the value turn red with the level, the tile's background warms a
    /// little, and past 0.4 a thin frame appears.
    paintTile(metric, shown, level) {
      const { heat, metrics } = PB();
      const heated = level ?? 0;
      const color = heat.color(metrics.colors[metric], heated);
      const value = $(metric + "-tile");
      const tile = value.closest(".tile");
      put(value, "text", metrics.tile(metric, shown, this.format));
      put(value, "color", heat.css(heat.mix(color, this.white, 0.3 - 0.2 * smooth(heated))));
      put(tile, "--color", heat.css(color));
      put(tile, "backgroundColor", heat.css(heat.mix(this.card, color, 0.2 * smooth(heated))));
      const frames = [];
      if (metric === this.selected) frames.push(`inset 0 0 0 2px ${heat.css(color)}`);
      else if (heated > 0.4) frames.push(`inset 0 0 0 1px ${heat.css(color, ((heated - 0.4) * 0.9).toFixed(2))}`);
      put(tile, "boxShadow", frames.join(", "));
    }

    select(metric) {
      this.selected = metric;
      for (const element of global.document.querySelectorAll(".ring-button, .tile")) {
        element.classList.toggle("selected", element.dataset.metric === metric);
      }
      global.document.querySelector(".graph").dataset.metric = metric;
      this.renderHeader(this.snapshot, this.levelsOf(this.snapshot));
    }

    /// A tap on a ring or a tile: the old graph fades out, the new one fades in.
    switchTo(metric, history) {
      if (metric === this.selected) return;
      const canvas = $("graph");
      if (PB().motion.reduced()) {
        this.select(metric);
        this.renderGraph(history);
        return;
      }
      canvas.classList.add("switching");
      global.setTimeout(() => {
        this.select(metric);
        this.renderGraph(history);
        canvas.classList.remove("switching");
      }, 300);
    }

    renderHeader(shown, levels) {
      const { heat, metrics } = PB();
      const { value, detail } = metrics.header(this.selected, shown, this.format, this.t);
      const key = metrics.graphHeat(this.selected);
      const color = heat.color(metrics.colors[this.selected], key ? levels[key] ?? 0 : 0);
      put($("graph-title"), "text", `${this.t.metric[this.selected]} · ${this.t.lastMinute}`);
      put($("graph-value"), "text", value);
      put($("graph-value"), "color", heat.css(color));
      put($("graph-detail"), "text", detail);
    }

    /// The graph's lines, range and axis label, from the history; `frame` draws them.
    renderGraph(history) {
      const m = PB().metrics;
      const lines = m.lines(this.selected).map((line) => Object.assign({}, line, { values: history.series(line.key) }));
      const bounds = PB().chart.range(m.scale(this.selected), lines.map((line) => line.values));
      this.graph = { lines, bounds, label: m.axisLabel(this.selected, bounds, this.format) };
    }

    drawGraph(canvas, size, now, still) {
      if (!this.graph) return;
      const { heat, metrics, chart, motion } = PB();
      const key = metrics.graphHeat(this.selected);
      const battery = this.snapshot.battery;
      // The battery's graph turns red only when the Mac is not on power.
      const range = key && !(key === "battery" && !(battery && battery.plugged === false)) ? this.limits[key] : null;
      const since = now - this.arrivedAt;
      chart.draw(canvas, size[0], size[1], this.graph.lines, this.graph.bounds, {
        label: this.graph.label,
        shift: still ? 0 : Math.max(0, Math.min(1, since / 1000)),
        settle: still ? 1 : motion.ease(since / 700),
        heat: range ? (color, value) => heat.color(color, heat.level(range, value)) : null,
        limit: range ? { value: range[1], label: this.t.limit } : null,
        now,
        still,
        glow: 0,
      });
    }

    renderNowPlaying(media) {
      $("now-playing").hidden = !media;
      $("now-playing").classList.toggle("playing", Boolean(media && media.playing));
      if (!media) return;
      $("np-title").textContent = media.title;
      $("np-sub").textContent = media.artist ? `${media.artist} · ${media.app}` : media.app;
    }

    toggleSort() {
      this.sortBy = this.sortBy === "cpu" ? "mem" : "cpu";
      this.renderApps();
    }

    // Only as many rows as fit without cutting one off; grey rows are apps the phone cannot quit. Rows are kept
    // between lists, so a row that moves slides from its old place to the new one.
    renderApps() {
      $("app-sort").textContent = (this.sortBy === "cpu" ? "CPU" : "RAM") + " ▾";
      const list = $("app-list");
      if (!this.apps) {
        list.replaceChildren();
        this.rows.clear();
        return;
      }
      const { heat, metrics, motion } = PB();
      const still = motion.reduced();
      const key = this.sortBy;
      const other = key === "cpu" ? "mem" : "cpu";
      const sorted = this.apps.slice().sort((a, b) => b[key] - a[key] || b[other] - a[other] || String(a.name).localeCompare(String(b.name)));
      const rowHeight = parseFloat(global.getComputedStyle(list).getPropertyValue("--row")) || 34;
      const fits = Math.max(1, Math.floor((list.clientHeight + 1) / rowHeight));
      const apps = sorted.slice(0, fits);
      const top = Math.max(1e-9, ...apps.map((app) => app[key] || 0));
      const before = new Map();
      for (const [id, item] of this.rows) before.set(id, item.getBoundingClientRect().top);

      const rows = new Map();
      const items = apps.map((app) => {
        const id = app.bundleId || `${app.name}#${app.pid}`;
        let item = this.rows.get(id);
        if (!item) {
          item = global.document.createElement("li");
          const name = global.document.createElement("span");
          name.className = "app-name";
          const figures = global.document.createElement("span");
          figures.className = "app-figures";
          const bar = global.document.createElement("i");
          bar.className = "app-bar";
          item.append(name, figures, bar);
          // Fades in once; the class goes, or every new list (which re-inserts the rows) would fade it in again.
          if (!still) {
            item.classList.add("enter");
            item.addEventListener("animationend", () => item.classList.remove("enter"), { once: true });
          }
        }
        item.classList.toggle("dim", !app.quittable);
        item.children[0].textContent = app.name;
        item.children[1].textContent = `${this.format.percent(app.cpu)} · ${this.format.memory(app.mem)}`;
        // On the CPU list the bar and the figures turn red as an app fills two cores.
        const level = key === "cpu" ? heat.level(this.limits.app, app.cpu) ?? 0 : 0;
        const color = heat.color(key === "cpu" ? metrics.colors.cpu : metrics.colors.ram, level);
        item.children[1].style.color = level > 0.02 ? heat.css(heat.mix(color, this.white, 0.15)) : "";
        item.children[2].style.backgroundColor = heat.css(color);
        item.children[2].style.width = `${Math.max(2, ((app[key] || 0) / top) * 100).toFixed(1)}%`;
        rows.set(id, item);
        return item;
      });
      list.replaceChildren(...items);
      this.rows = rows;
      if (still) return;
      for (const [id, item] of rows) {
        const old = before.get(id);
        if (old === undefined) continue;
        const delta = old - item.getBoundingClientRect().top;
        if (Math.abs(delta) < 1) continue;
        item.style.transition = "none";
        item.style.transform = `translateY(${delta}px)`;
        item.getBoundingClientRect();
        item.style.transition = "";
        item.style.transform = "";
      }
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.View = View;
})(typeof window !== "undefined" ? window : globalThis);
```

- [ ] **Step 4: Bağlama, sayfa, metin ve stil**

`Resources/web/app.js`:

Bul (1/4):

```js
    element.addEventListener("click", () => {
      view.select(element.dataset.metric);
      view.renderGraph(history);
      try {
```

Şununla değiştir:

```js
    element.addEventListener("click", () => {
      view.switchTo(element.dataset.metric, history);
      try {
```

Bul (2/4):

```js
  view.renderGraph(history);

  const key = PB.readKey();
```

Şununla değiştir:

```js
  view.renderGraph(history);
  PB.motion.onFrame((now) => view.frame(now));

  const key = PB.readKey();
```

Bul (3/4):

```js
    onStale: (stale) => view.setStale(stale),
    onReady: (ready) => view.setHost(ready.host),
    onAccess: (access) => view.setAccess(access),
```

Şununla değiştir:

```js
    onStale: (stale) => view.setStale(stale),
    onReady: (ready) => {
      view.setHost(ready.host);
      view.setLimits(ready.limits && ready.limits.power);
    },
    onAccess: (access) => view.setAccess(access),
```

Bul (4/4):

```js
      history.push(snapshot.t, PB.metrics.values(snapshot));
      view.render(snapshot);
      view.renderGraph(history);
```

Şununla değiştir:

```js
      history.push(snapshot.t, PB.metrics.values(snapshot));
      view.render(snapshot, global.performance.now());
      view.renderGraph(history);
```

`Resources/web/index.html`:

Bul (1/5):

```html
<meta name="apple-mobile-web-app-title" content="PhoneBox">
<meta name="theme-color" content="#000000">
<link rel="apple-touch-icon" href="apple-touch-icon.png">
```

Şununla değiştir:

```html
<meta name="apple-mobile-web-app-title" content="PhoneBox">
<meta name="theme-color" content="#01060d">
<link rel="apple-touch-icon" href="apple-touch-icon.png">
```

Bul (2/5):

```html
    <button class="ring-button" data-metric="cpu" type="button">
      <span class="ring"><span class="ring-inner"><span class="ring-value" id="cpu-ring">—</span><span class="ring-label">CPU</span></span></span>
      <span class="ring-sub" id="cpu-sub"></span>
```

Şununla değiştir:

```html
    <button class="ring-button" data-metric="cpu" type="button">
      <span class="ring"><canvas aria-hidden="true"></canvas><span class="ring-inner"><span class="ring-value" id="cpu-ring">—</span><span class="ring-label">CPU</span></span></span>
      <span class="ring-sub" id="cpu-sub"></span>
```

Bul (3/5):

```html
    <button class="ring-button" data-metric="ram" type="button">
      <span class="ring"><span class="ring-inner"><span class="ring-value" id="ram-ring">—</span><span class="ring-label">RAM</span></span></span>
      <span class="ring-sub" id="ram-sub"></span>
```

Şununla değiştir:

```html
    <button class="ring-button" data-metric="ram" type="button">
      <span class="ring"><canvas aria-hidden="true"></canvas><span class="ring-inner"><span class="ring-value" id="ram-ring">—</span><span class="ring-label">RAM</span></span></span>
      <span class="ring-sub" id="ram-sub"></span>
```

Bul (4/5):

```html
  <section class="now-playing card" id="now-playing" hidden>
    <span class="np-icon" aria-hidden="true">♪</span>
    <span class="np-text"><span class="np-title" id="np-title"></span><span class="np-sub" id="np-sub"></span></span>
```

Şununla değiştir:

```html
  <section class="now-playing card" id="now-playing" hidden>
    <span class="np-icon" aria-hidden="true"><i></i><i></i><i></i><i></i></span>
    <span class="np-text"><span class="np-title" id="np-title"></span><span class="np-sub" id="np-sub"></span></span>
```

Bul (5/5):

```html
<script src="metrics.js"></script>
<script src="chart.js"></script>
```

Şununla değiştir:

```html
<script src="metrics.js"></script>
<script src="heat.js"></script>
<script src="motion.js"></script>
<script src="rings.js"></script>
<script src="chart.js"></script>
```

`Resources/web/i18n.js`:

Bul (1/2):

```js
      lastMinute: "son 60 sn",
      load: (value) => `yük ${value}`,
```

Şununla değiştir:

```js
      lastMinute: "son 60 sn",
      limit: "SINIR",
      load: (value) => `yük ${value}`,
```

Bul (2/2):

```js
      lastMinute: "last 60 s",
      load: (value) => `load ${value}`,
```

Şununla değiştir:

```js
      lastMinute: "last 60 s",
      limit: "LIMIT",
      load: (value) => `load ${value}`,
```

`Resources/web/styles.css`:

Bul (1/9):

```css
/* PhoneBox dashboard (design §8): black, system font, dark cards. Landscape = layout B, portrait = "tek bakış". */
:root {
  --bg: #000;
  --card: #1c1c1e;
  --raised: #2c2c2e;
  --track: #2c2c2e;
  --text: #f5f5f7;
  --muted: #8e8e93;
  --line: #1c1c1e;
  --cpu: #30d158;
  --ram: #0a84ff;
  --gpu: #bf5af2;
  --temp: #ff9f0a;
  --power: #ffd60a;
  --net: #64d2ff;
  --disk: #8e8e93;
  --battery: #30d158;
  --ok: #30d158;
  --warn: #ff9f0a;
```

Şununla değiştir:

```css
/* PhoneBox dashboard (design §8): "Aktivite Halkaları" in the "Okyanus" palette. Landscape = layout B, portrait =
   "tek bakış". Colours that turn red near a limit are set from view.js; these are the calm ones. */
:root {
  --bg: #01060d;
  --card: #0b1622;
  --raised: #14263a;
  --text: #eaf6ff;
  --muted: #6d8aa3;
  --line: #0b1622;
  --cpu: #00c2ff;
  --ram: #3d6bff;
  --gpu: #7b61ff;
  --temp: #00e0b0;
  --power: #4ff0d0;
  --net: #8be9ff;
  --disk: #6f8fa8;
  --battery: #00d0a0;
  --ok: #00d0a0;
  --warn: #ff9f0a;
```

Bul (2/9):

```css
  color-scheme: dark;
}

@property --p {
  syntax: "<number>";
  inherits: false;
  initial-value: 0;
}
```

Şununla değiştir:

```css
  color-scheme: dark;
}
```

Bul (3/9):

```css
  .np-sub::before { content: "· "; }
  .np-icon { width: 24px; height: 24px; font-size: 13px; }
}
```

Şununla değiştir:

```css
  .np-sub::before { content: "· "; }
  .np-icon { width: 24px; height: 24px; padding: 6px 0; gap: 2px; }
  .np-icon i { width: 3px; }
}
```

Bul (4/9):

```css
.ring-button { display: flex; flex-direction: column; align-items: center; border-radius: 50%; }
.ring {
  --p: 0;
  width: var(--ring);
  height: var(--ring);
  border-radius: 50%;
  display: grid;
  place-items: center;
  background: conic-gradient(var(--color) calc(var(--p) * 1%), var(--track) 0);
  transition: --p 0.6s;
}
.ring-inner {
  width: 80%;
  height: 80%;
  border-radius: 50%;
  background: var(--bg);
  display: flex;
```

Şununla değiştir:

```css
.ring-button { display: flex; flex-direction: column; align-items: center; border-radius: 50%; }
.ring { position: relative; width: var(--ring); height: var(--ring); border-radius: 50%; }
.ring canvas { position: absolute; inset: 0; width: 100%; height: 100%; }
.ring-inner {
  position: absolute;
  inset: 0;
  display: flex;
```

Bul (5/9):

```css
.graph-detail { font-size: 11.5px; color: var(--muted); min-height: 15px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; text-align: right; }
#graph { flex: 1; min-height: 0; width: 100%; margin-top: 2px; }

/* ---- Tiles ---- */
```

Şununla değiştir:

```css
.graph-detail { font-size: 11.5px; color: var(--muted); min-height: 15px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; text-align: right; }
#graph { flex: 1; min-height: 0; width: 100%; margin-top: 2px; transition: opacity 0.3s; }
#graph.switching { opacity: 0.15; }

/* ---- Tiles ---- */
```

Bul (6/9):

```css
.now-playing { display: flex; align-items: center; gap: 9px; padding: 7px 9px; min-width: 0; }
.np-icon { width: 34px; height: 34px; border-radius: 8px; background: var(--raised); display: grid; place-items: center; flex: none; font-size: 16px; }
.np-text { display: flex; flex-direction: column; min-width: 0; line-height: 1.25; }
```

Şununla değiştir:

```css
.now-playing { display: flex; align-items: center; gap: 9px; padding: 7px 9px; min-width: 0; }
/* A small equalizer that moves while something plays. */
.np-icon {
  width: 34px;
  height: 34px;
  border-radius: 8px;
  background: var(--raised);
  display: flex;
  align-items: flex-end;
  justify-content: center;
  gap: 3px;
  padding: 9px 0;
  flex: none;
}
.np-icon i { width: 4px; height: 4px; border-radius: 2px; background: var(--ram); }
.now-playing.playing .np-icon i { animation: eq 0.9s ease-in-out infinite alternate; }
.now-playing.playing .np-icon i:nth-child(2) { animation-delay: -0.35s; animation-duration: 0.7s; }
.now-playing.playing .np-icon i:nth-child(3) { animation-delay: -0.6s; animation-duration: 1.1s; }
.now-playing.playing .np-icon i:nth-child(4) { animation-delay: -0.2s; animation-duration: 0.8s; }
@keyframes eq { from { height: 4px; } to { height: 16px; } }
.np-text { display: flex; flex-direction: column; min-width: 0; line-height: 1.25; }
```

Bul (7/9):

```css
.app-list li {
  display: flex;
```

Şununla değiştir:

```css
.app-list li {
  position: relative;
  display: flex;
```

Bul (8/9):

```css
  border-bottom: 1px solid var(--line);
}
.app-list li:last-child { border-bottom: 0; }
.app-name { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; min-width: 0; }
```

Şununla değiştir:

```css
  border-bottom: 1px solid var(--line);
  transition: transform 0.7s cubic-bezier(0.2, 0.8, 0.2, 1);
}
.app-list li:last-child { border-bottom: 0; }
.app-list li.enter { animation: row-in 0.5s ease-out; }
@keyframes row-in { from { opacity: 0; } }
/* The app's share of the busiest row, under its name; it grows and shrinks with each list. */
.app-bar {
  position: absolute;
  left: 0;
  bottom: -1px;
  height: 2px;
  border-radius: 1px;
  opacity: 0.8;
  transition: width 1s cubic-bezier(0.2, 0.8, 0.2, 1), background-color 1s;
}
.app-figures { transition: color 1s; }
.app-name { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; min-width: 0; }
```

Bul (9/9):

```css
#keepawake { position: fixed; right: 0; bottom: 0; width: 2px; height: 2px; opacity: 0.01; pointer-events: none; }
```

Şununla değiştir:

```css
#keepawake { position: fixed; right: 0; bottom: 0; width: 2px; height: 2px; opacity: 0.01; pointer-events: none; }

/* "Reduce Motion": nothing slides or bounces; colours still change. */
@media (prefers-reduced-motion: reduce) {
  .now-playing.playing .np-icon i { animation: none; height: 10px; }
  .app-list li, #graph { transition: none; }
  .app-list li.enter { animation: none; }
}
```

- [ ] **Step 5: Derle ve test et**

Run: iki uyarı denetimi → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 18 tests in 5 suites passed` ve `Test run with 177 tests in 31 suites passed`
(`bothLanguagesHaveTheSameTexts` yeni `limit` metnini iki dilde arar).
Run: `grep -n "innerHTML\|insertAdjacentHTML\|outerHTML" Resources/web/*.js` → Expected: çıktı yok.
Run: `make app 2>&1 | tail -1` → Expected: `Built …/build/PhoneBox.app`. Uygulamayı başlatmayın; sayfayı kontrolcü
Görev 6'da dener.

- [ ] **Step 6: Commit**

```bash
git add Resources/web/rings.js Resources/web/chart.js Resources/web/view.js Resources/web/app.js \
  Resources/web/index.html Resources/web/i18n.js Resources/web/styles.css
git commit -m "Draw the rings and the graph on every frame, glide the values and turn them red near their limits"
```

---

### Task 5: Saat başlığı, telefonun pili ve alarm

**Files:**
- Modify: `Resources/web/view.js`, `Resources/web/index.html`, `Resources/web/i18n.js`, `Resources/web/styles.css`

**Interfaces:**
- Consumes: Görev 3'ün `heat.Alarm`, `clock.parts`, `clock.Clock`; Görev 4'ün `View`'u; Görev 2'nin `snapshot.phone`.
- Produces:
  - Sayfada `#clock`, `#top-line`, `#phone-battery`, `#phone-percent`, `#edge`, `#menu-host`. `.brand` ve
    `t.cable` kalkar; `#status` ve `#status-text` kalır (Plan 4B'nin bildirimleri ayrı yerde).
  - `View.renderPhone()`, `renderTop(...)`, `renderEdge(...)`, `pop(metric, now, still)`.
  - `View.alarm` (`heat.Alarm`); `setStale(true)` alarmı susturur.

- [ ] **Step 1: Sayfa ve metin**

`Resources/web/index.html`:

Bul (1/4):

```html
  <header class="top">
    <span class="brand">PhoneBox</span>
    <span id="status" class="status" role="status" aria-live="polite"><span class="dot"></span><span id="status-text"></span></span>
  </header>
```

Şununla değiştir:

```html
  <header class="top">
    <b id="clock" class="clock" aria-hidden="true"></b>
    <span class="top-side">
      <span id="top-line" class="top-line"></span>
      <span id="status" class="status" role="status" aria-live="polite">
        <span id="phone-battery" class="phone-battery" hidden>
          <span class="battery-body"><span class="battery-fill"></span><span class="battery-bolt">⚡</span></span><span class="battery-cap"></span>
          <span id="phone-percent"></span>
        </span>
        <span class="dot"></span><span id="status-text"></span>
      </span>
    </span>
  </header>
```

Bul (2/4):

```html
</main>

<div id="state" class="state" hidden><div class="state-card"><h2 id="state-title"></h2><p id="state-text"></p></div></div>
```

Şununla değiştir:

```html
</main>

<div id="edge" class="edge" aria-hidden="true"></div>

<div id="state" class="state" hidden><div class="state-card"><h2 id="state-title"></h2><p id="state-text"></p></div></div>
```

Bul (3/4):

```html
<div id="menu" class="menu" role="menu" hidden>
  <button id="menu-guide" type="button" role="menuitem" data-text="guideItem"></button>
```

Şununla değiştir:

```html
<div id="menu" class="menu" role="menu" hidden>
  <div id="menu-host" class="menu-host"></div>
  <button id="menu-guide" type="button" role="menuitem" data-text="guideItem"></button>
```

Bul (4/4):

```html
<script src="rings.js"></script>
<script src="chart.js"></script>
```

Şununla değiştir:

```html
<script src="rings.js"></script>
<script src="clock.js"></script>
<script src="chart.js"></script>
```

`Resources/web/i18n.js`:

Bul (1/2):

```js
      mac: "Mac",
      cable: "kablo",
      wifi: "Wi-Fi",
```

Şununla değiştir:

```js
      mac: "Mac",
      wifi: "Wi-Fi",
```

Bul (2/2):

```js
      mac: "Mac",
      cable: "cable",
      wifi: "Wi-Fi",
```

Şununla değiştir:

```js
      mac: "Mac",
      wifi: "Wi-Fi",
```

- [ ] **Step 2: Görünüm**

`Resources/web/view.js`:

Bul (1/17):

```js
// Puts the Mac's data on the page (design §8): rings, tiles, the graph and its header, the app list, the now-playing
// card, the status line and the state card. Values glide to each new snapshot and turn red near their limits;
// `frame` draws them on every animation frame. Text always goes in with textContent: names come from other apps.
(function (global) {
```

Şununla değiştir:

```js
// Puts the Mac's data on the page (design §8): rings, tiles, the graph and its header, the app list, the now-playing
// card, the clock header with the phone's battery, the alarm and the state card. Values glide to each new snapshot
// and turn red near their limits; `frame` draws them on every animation frame. Text always goes in with
// textContent: names come from other apps.
(function (global) {
```

Bul (2/17):

```js
    if (property === "text") element.textContent = value;
    else if (property.startsWith("--")) element.style.setProperty(property, value);
```

Şununla değiştir:

```js
    if (property === "text") element.textContent = value;
    else if (property === "class") element.className = value;
    else if (property.startsWith("--")) element.style.setProperty(property, value);
```

Bul (3/17):

```js
      for (const button of global.document.querySelectorAll(".ring-button")) this.ringButtons[button.dataset.metric] = button;
    }
```

Şununla değiştir:

```js
      for (const button of global.document.querySelectorAll(".ring-button")) this.ringButtons[button.dataset.metric] = button;
      this.alarm = new heat.Alarm();
      /// When each metric's alarm started, for the one-off "pop".
      this.poppedAt = {};
      this.clock = new (PB().clock.Clock)($("clock"));
      this.minute = null;
      this.day = "";
    }
```

Bul (4/17):

```js
    }

    setStale(stale) {
```

Şununla değiştir:

```js
    }

    /// Stale values do not ring: the alarm and the edge light go out until fresh snapshots come.
    setStale(stale) {
```

Bul (5/17):

```js
      $("dashboard").classList.toggle("stale", stale);
      this.renderStatus();
```

Şununla değiştir:

```js
      $("dashboard").classList.toggle("stale", stale);
      if (stale) this.alarm.clear();
      this.renderStatus();
```

Bul (6/17):

```js
    }

    // "● MacBook Pro · kablo": green on the cable, orange on Wi-Fi (no commands), grey while (re)connecting.
    renderStatus() {
```

Şununla değiştir:

```js
    }

    // The dot: green on the cable (the phone's battery shows next to it), orange and "Wi-Fi" on Wi-Fi (no commands),
    // grey while (re)connecting, red with what is wrong. The Mac's name is at the top of the "⋯" menu.
    renderStatus() {
```

Bul (7/17):

```js
        className += cable ? " streaming" : " wifi";
        text = `${this.host} · ${cable ? t.cable : t.wifi}`;
      } else if (problems[this.kind]) {
```

Şununla değiştir:

```js
        className += cable ? " streaming" : " wifi";
        text = cable ? "" : t.wifi;
      } else if (problems[this.kind]) {
```

Bul (8/17):

```js
      $("status-text").textContent = text;
    }
```

Şununla değiştir:

```js
      $("status-text").textContent = text;
      $("menu-host").textContent = this.host;
      this.renderPhone();
    }

    /// The phone's own battery, read by the Mac over USB (`snapshot.phone`): only on the cable.
    renderPhone() {
      const phone = this.snapshot.phone;
      const element = $("phone-battery");
      const show = Boolean(phone) && this.kind === "streaming" && !this.stale && Boolean(this.access && this.access.cable);
      element.hidden = !show;
      if (!show) return;
      const { heat, metrics } = PB();
      const level = phone.plugged ? 0 : heat.level(this.limits.battery, phone.percent) ?? 0;
      element.style.setProperty("--level", `${Math.max(0, Math.min(100, phone.percent))}%`);
      element.style.setProperty("--fill", heat.css(heat.color(metrics.colors.battery, level)));
      element.classList.toggle("charging", Boolean(phone.charging));
      $("phone-percent").textContent = this.format.percent(phone.percent);
    }
```

Bul (9/17):

```js
      this.arrivedAt = now;
      this.fitTiles(previous);
```

Şununla değiştir:

```js
      this.arrivedAt = now;
      // The alarm goes by the values that arrived, not the ones gliding on screen.
      for (const metric of this.alarm.update(this.levelsOf(snapshot))) this.poppedAt[metric] = now;
      this.renderPhone();
      this.fitTiles(previous);
```

Bul (10/17):

```js
      const levels = this.levelsOf(shown);
      const { cpu, mem } = shown;
```

Şununla değiştir:

```js
      const levels = this.levelsOf(shown);
      const ringing = new Set(this.alarm.active());
      // The alarm's beat: once a second; steady with "Reduce Motion".
      const pulse = still ? 1 : 0.5 + 0.5 * Math.sin((now / 1000) * Math.PI * 2);
      const glow = (metric) => (ringing.has(metric) ? pulse : 0);
      const { cpu, mem } = shown;
```

Bul (11/17):

```js
      this.drawRing("cpu", ringSizes.cpu, cpu ? cpu.total : null, levels.cpu, now, still,
                    cpu && cpu.load && cpu.load.length ? this.t.load(f.decimal(cpu.load[0])) : "");
      this.drawRing("ram", ringSizes.ram, memoryOK ? (mem.used / mem.total) * 100 : null, levels.ram, now, still,
                    memoryOK ? this.t.memory(f.gibibytes(mem.used), f.gibibytes(mem.total)) : "");
      for (const metric of tileMetrics) this.paintTile(metric, shown, levels[metric]);
      this.renderHeader(shown, levels);
      this.drawGraph(graph, graphSize, now, still);
    }

    drawRing(metric, size, percent, level, now, still, sub) {
      const { heat, metrics, rings } = PB();
```

Şununla değiştir:

```js
      this.drawRing("cpu", ringSizes.cpu, cpu ? cpu.total : null, levels.cpu, now, still,
                    cpu && cpu.load && cpu.load.length ? this.t.load(f.decimal(cpu.load[0])) : "", glow("cpu"),
                    this.pop("cpu", now, still));
      this.drawRing("ram", ringSizes.ram, memoryOK ? (mem.used / mem.total) * 100 : null, levels.ram, now, still,
                    memoryOK ? this.t.memory(f.gibibytes(mem.used), f.gibibytes(mem.total)) : "", glow("ram"),
                    this.pop("ram", now, still));
      for (const metric of tileMetrics) this.paintTile(metric, shown, levels[metric], glow(metric), this.pop(metric, now, still));
      this.renderHeader(shown, levels);
      const graphKey = PB().metrics.graphHeat(this.selected);
      this.drawGraph(graph, graphSize, now, still, graphKey ? glow(graphKey) : 0);
      this.renderTop(shown, levels, ringing, pulse, still);
      this.renderEdge(levels, ringing, pulse, now, still);
    }

    /// 0 → 1 → 0 over the first 0.7 s after a metric's alarm started (none with "Reduce Motion").
    pop(metric, now, still) {
      const since = now - (this.poppedAt[metric] ?? -Infinity);
      return still || !this.alarm.ringing.has(metric) || since >= 700 ? 0 : Math.sin((Math.PI * since) / 700);
    }

    /// The clock, and under it the date, or "▲ CPU %100 · Sıcaklık 97 °C" while alarms ring (the two highest).
    renderTop(shown, levels, ringing, pulse, still) {
      const { clock, metrics } = PB();
      const date = new Date();
      const minute = Math.floor(date.getTime() / 60000);
      if (minute !== this.minute) {
        const parts = clock.parts(date, PB().i18n.language);
        this.minute = minute;
        this.day = parts.day;
        this.clock.show(parts.time, still);
      }
      const line = $("top-line");
      if (!ringing.size) {
        put(line, "class", "top-line");
        put(line, "text", this.day);
        put(line, "opacity", "");
        return;
      }
      const value = (metric) => (metric === "cpu" || metric === "ram"
        ? metrics.header(metric, shown, this.format, this.t).value
        : metrics.tile(metric, shown, this.format));
      const name = (metric) => (metric === "disk" ? this.t.diskTile : this.t.metric[metric]);
      const hottest = Array.from(ringing).sort((a, b) => (levels[b] ?? 0) - (levels[a] ?? 0)).slice(0, 2);
      put(line, "class", "top-line alert");
      put(line, "text", "▲ " + hottest.map((metric) => `${name(metric)} ${value(metric)}`).join(" · "));
      put(line, "opacity", (0.6 + 0.4 * pulse).toFixed(2));
    }

    /// A red light around the screen's edge: faint while a metric nears its limit (level past 0.7), and while an
    /// alarm rings a wide one that beats once a second, after a bright flash when it starts.
    renderEdge(levels, ringing, pulse, now, still) {
      let edge = 0;
      for (const metric of Object.keys(levels)) edge = Math.max(edge, Math.max(0, ((levels[metric] ?? 0) - 0.7) / 0.3) * 0.4);
      if (ringing.size) {
        const flash = Math.max(...Array.from(ringing, (metric) => this.pop(metric, now, still)));
        edge = Math.max(0.45 + 0.55 * pulse, flash);
      }
      put($("edge"), "opacity", (this.stale ? 0 : edge).toFixed(2));
    }

    drawRing(metric, size, percent, level, now, still, sub, glow, pop) {
      const { heat, metrics, rings } = PB();
```

Bul (12/17):

```js
      const button = this.ringButtons[metric];
      rings.draw(button.querySelector("canvas"), size, { fraction: ok ? percent / 100 : 0, from, to, now, still, glow: 0 });
      const value = $(metric + "-ring");
```

Şununla değiştir:

```js
      const button = this.ringButtons[metric];
      rings.draw(button.querySelector("canvas"), size, { fraction: ok ? percent / 100 : 0, from, to, now, still, glow });
      const value = $(metric + "-ring");
```

Bul (13/17):

```js
      put(button, "--color", heat.css(from));
    }
```

Şununla değiştir:

```js
      put(button, "--color", heat.css(from));
      put(button, "transform", pop ? `scale(${(1 + 0.07 * pop).toFixed(3)})` : "");
    }
```

Bul (14/17):

```js
    /// A tile's value and colours: the dot and the value turn red with the level, the tile's background warms a
    /// little, and past 0.4 a thin frame appears.
    paintTile(metric, shown, level) {
      const { heat, metrics } = PB();
```

Şununla değiştir:

```js
    /// A tile's value and colours: the dot and the value turn red with the level, the tile's background warms a
    /// little, past 0.4 a thin frame appears, and while its alarm rings the tile glows with the beat.
    paintTile(metric, shown, level, glow, pop) {
      const { heat, metrics } = PB();
```

Bul (15/17):

```js
      if (metric === this.selected) frames.push(`inset 0 0 0 2px ${heat.css(color)}`);
      else if (heated > 0.4) frames.push(`inset 0 0 0 1px ${heat.css(color, ((heated - 0.4) * 0.9).toFixed(2))}`);
      put(tile, "boxShadow", frames.join(", "));
    }
```

Şununla değiştir:

```js
      if (metric === this.selected) frames.push(`inset 0 0 0 2px ${heat.css(color)}`);
      if (glow > 0) {
        frames.push(`0 0 ${(6 + 12 * glow).toFixed(1)}px ${heat.css(color, 0.6)}`,
                    `inset 0 0 0 1.5px ${heat.css(color, (0.5 + 0.5 * glow).toFixed(2))}`);
      } else if (metric !== this.selected && heated > 0.4) {
        frames.push(`inset 0 0 0 1px ${heat.css(color, ((heated - 0.4) * 0.9).toFixed(2))}`);
      }
      put(tile, "boxShadow", frames.join(", "));
      put(tile, "transform", pop ? `scale(${(1 + 0.06 * pop).toFixed(3)})` : "");
    }
```

Bul (16/17):

```js
    }

    drawGraph(canvas, size, now, still) {
      if (!this.graph) return;
```

Şununla değiştir:

```js
    }

    drawGraph(canvas, size, now, still, glow) {
      if (!this.graph) return;
```

Bul (17/17):

```js
        still,
        glow: 0,
      });
    }
```

Şununla değiştir:

```js
        still,
        glow,
      });
      const red = heat.rgb(heat.hot);
      put(canvas.parentElement, "boxShadow", glow > 0 ? `inset 0 0 0 1.5px ${heat.css(red, (0.4 + 0.5 * glow).toFixed(2))}` : "");
    }
```

- [ ] **Step 3: Stil**

`Resources/web/styles.css`:

Bul (1/7):

```css
    --row: 34px;
    grid-template-columns: calc(var(--ring) + 8px) minmax(0, 1fr)
      clamp(176px, calc((100vw - env(safe-area-inset-left) - env(safe-area-inset-right)) * 0.26), 240px);
    grid-template-rows: auto auto minmax(0, 1fr) auto auto;
```

Şununla değiştir:

```css
    --row: 34px;
    --side: clamp(176px, calc((100vw - env(safe-area-inset-left) - env(safe-area-inset-right)) * 0.26), 240px);
    grid-template-columns: calc(var(--ring) + 8px) minmax(0, 1fr) var(--side);
    grid-template-rows: auto auto minmax(0, 1fr) auto auto;
```

Bul (2/7):

```css
  }
  .brand { display: none; }
  .top { justify-content: flex-end; }
  .rings { flex-direction: column; justify-content: space-around; }
```

Şununla değiştir:

```css
  }
  .clock { font-size: calc(var(--side) * 0.16); }
  .rings { flex-direction: column; justify-content: space-around; }
```

Bul (3/7):

```css
  .rings { flex-direction: row; justify-content: space-around; }
  .np-text { flex-direction: row; gap: 6px; align-items: baseline; }
```

Şununla değiştir:

```css
  .rings { flex-direction: row; justify-content: space-around; }
  /* One short row on top, so a small phone keeps room for the app list. */
  .clock { font-size: clamp(22px, 4dvh, 30px); }
  .top .top-side { flex-direction: row; align-items: center; gap: 8px; }
  .np-text { flex-direction: row; gap: 6px; align-items: baseline; }
```

Bul (4/7):

```css
}

/* ---- Status ---- */
.brand { font-weight: 600; font-size: 15px; }
.status { display: flex; align-items: center; gap: 6px; color: var(--muted); font-size: 12px; white-space: nowrap; min-width: 0; }
```

Şununla değiştir:

```css
}

/* ---- Clock header (design §8 "Saat ve telefonun pili"); its size is set per orientation above. ---- */
.clock {
  display: flex;
  align-items: center;
  flex: none;
  font-weight: 700;
  line-height: 1;
  letter-spacing: -0.01em;
  font-variant-numeric: tabular-nums;
}
/* A changed digit rolls up and out while the new one comes in from below. */
.clock-digit { position: relative; display: block; width: 0.6em; height: 1em; overflow: hidden; }
.clock-digit span { position: absolute; inset: 0; line-height: 1em; text-align: center; }
.clock-digit .in { animation: digit-in 0.7s cubic-bezier(0.2, 0.8, 0.2, 1) both; }
.clock-digit .out { animation: digit-out 0.7s cubic-bezier(0.2, 0.8, 0.2, 1) both; }
.clock-colon { display: block; width: 0.3em; height: 1em; line-height: 1em; text-align: center; transform: translateY(-0.07em); animation: colon 2s ease-in-out infinite; }
@keyframes digit-in { from { transform: translateY(90%); opacity: 0; } }
@keyframes digit-out { to { transform: translateY(-90%); opacity: 0; } }
@keyframes colon { 50% { opacity: 0.3; } }
.top-side { display: flex; flex-direction: column; align-items: flex-end; gap: 5px; min-width: 0; }
.top-line { max-width: 100%; font-size: 11.5px; color: var(--muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.top-line.alert { color: #ff6b6b; font-weight: 600; }

/* The phone's battery: the fill follows the level and glides when it changes. */
.phone-battery { display: flex; align-items: center; gap: 4px; color: var(--text); font-size: 12px; font-variant-numeric: tabular-nums; }
.battery-body { position: relative; display: block; width: 22px; height: 11px; padding: 1px; border: 1.5px solid rgba(234, 246, 255, 0.55); border-radius: 3.5px; }
.battery-fill {
  display: block;
  height: 100%;
  width: var(--level, 100%);
  border-radius: 1.5px;
  background: var(--fill, var(--battery));
  transition: width 1.2s cubic-bezier(0.2, 0.8, 0.2, 1), background-color 1s;
}
.battery-bolt { display: none; position: absolute; inset: -1px 0 0; font-size: 9px; line-height: 11px; text-align: center; color: #fff; text-shadow: 0 0 2px var(--bg), 0 0 2px var(--bg); }
.phone-battery.charging .battery-bolt { display: block; }
.battery-cap { width: 2px; height: 5px; margin-left: -3px; margin-right: 2px; background: rgba(234, 246, 255, 0.55); border-radius: 0 1px 1px 0; }

.status { display: flex; align-items: center; gap: 6px; color: var(--muted); font-size: 12px; white-space: nowrap; min-width: 0; }
```

Bul (5/7):

```css
.menu-backdrop { position: fixed; inset: 0; }
.menu { position: fixed; min-width: 220px; background: var(--raised); border-radius: 14px; overflow: hidden; box-shadow: 0 8px 30px rgba(0, 0, 0, 0.6); }
```

Şununla değiştir:

```css
.menu-backdrop { position: fixed; inset: 0; }
.menu-host { padding: 10px 14px 8px; font-size: 12px; color: var(--muted); border-bottom: 1px solid #3a3a3c; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.menu { position: fixed; min-width: 220px; background: var(--raised); border-radius: 14px; overflow: hidden; box-shadow: 0 8px 30px rgba(0, 0, 0, 0.6); }
```

Bul (6/7):

```css
.menu button:active { background: #3a3a3c; }

/* ---- State card ---- */
```

Şununla değiştir:

```css
.menu button:active { background: #3a3a3c; }

/* ---- Alarm: a red light around the screen's edge, above the page and below the cards; it never takes a tap. */
.edge {
  position: fixed;
  inset: 0;
  pointer-events: none;
  opacity: 0;
  box-shadow: inset 0 0 110px 24px rgba(255, 40, 40, 0.95), inset 0 0 0 3px rgba(255, 70, 70, 0.95);
}

/* ---- State card ---- */
```

Bul (7/7):

```css
  .now-playing.playing .np-icon i { animation: none; height: 10px; }
  .app-list li, #graph { transition: none; }
  .app-list li.enter { animation: none; }
}
```

Şununla değiştir:

```css
  .now-playing.playing .np-icon i { animation: none; height: 10px; }
  .app-list li, #graph, .battery-fill { transition: none; }
  .app-list li.enter { animation: none; }
  .clock-colon { animation: none; }
}
```

- [ ] **Step 4: Derle ve test et**

Run: `grep -rn "t\.cable\|class=\"brand\"" Resources/web/` → Expected: çıktı yok.
Run: iki uyarı denetimi → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 18 tests in 5 suites passed` ve `Test run with 177 tests in 31 suites passed`.
Run: `grep -n "innerHTML\|insertAdjacentHTML\|outerHTML" Resources/web/*.js` → Expected: çıktı yok.
Run: `make app 2>&1 | tail -1` → Expected: `Built …/build/PhoneBox.app`. Uygulamayı başlatmayın.

- [ ] **Step 5: Commit**

```bash
git add Resources/web/view.js Resources/web/index.html Resources/web/i18n.js Resources/web/styles.css
git commit -m "Put the clock and the phone's battery at the top and ring the alarm near a limit"
```

---

### Task 6: Mac'te ve telefonda kontrol (kontrolcü, inline)

- [ ] **Step 1: Sahte veriyle.** "Ek: deneme sayfası"nı kur; Mac'in tarayıcı panelinde `resize_window` ile 734×372,
  667×375, 814×409, 393×759, 375×647. Her ölçüde:
  - ekran dışına taşan ya da kesilen öğe yok;
  - halkalar, grafik ve saat çiziliyor;
  - bir kutucuğa dokununca grafik solup yenisi beliriyor;
  - "⋯" menüsünün başında Mac'in adı var;
  - konsolda JavaScript hatası yok (yalnız `favicon.ico` 404'ü olabilir).
- [ ] **Step 2: Senaryolar** (734×372'de):
  - `sim.set({ cpu: 100, temp: 101, power: 40, apps: { Code: 380 } })`: önce renkler kızarır. 3 sn sonra kenar
    ışığı, atan halka ve kutucuklar, "▲ …" görünür. `sim.clear()`: 3 sn sonra susar.
  - `sim.set({ rx: 118e6, free: 4e9, plugged: false, battery: 6 })`: ağ, disk ve pil kızarır.
  - `sim.state.cable = false` yazıp sayfayı yenile: pil simgesi yok, turuncu nokta ve "Wi-Fi".
- [ ] **Step 3: Gerçek uygulamayla, kullanıcıyla telefonda.** Kullanıcıdan onay alıp çalışan PhoneBox'ı
  bu dalın `make run`'ıyla değiştir. Telefon kabloyla takılı, ana ekran simgesinden açık. Bakılacaklar:
  - Saat ve tarih doğru; sağ üstte telefonun pili, Ayarlar'daki yüzdeyle aynı.
  - Hareketler akıcı, sayfa takılmıyor.
  - Mac'te `bash -c 'for i in $(seq 10); do yes > /dev/null & done; sleep 20; kill $(jobs -p)'`: CPU halkası
    kızarır, 3 sn sonra telefonda alarm çalar, yük bitince susar. Bu sırada güç kutucuğunun gösterdiği en yüksek
    watt'ı not et (M4 sınırı 35 W'ın kalibrasyonu için).
  - Telefonu 2 dk kilitle, aç: pil simgesi görünüyor ve güncelleniyor (kilitliyken okuma çalışmıyorsa simge 5 dk
    sonra kaybolur; sonucu not et).
  - Telefonda Ayarlar → Erişilebilirlik → Hareket → Hareketi Azalt açılınca parıltı ve atma duruyor, renkler kalıyor.
- [ ] **Step 4: Belgeler.**
  - `docs/manual-testing.md`'ye "Görünüm ve kızarma" kontrol listesini ekle; "Sonuçlar"a Plan 4C'yi yaz (ölçülen en
    yüksek güç ve kilitliyken pil sonucu dahil).
  - Ölçülen güç M4 sınırından çok farklıysa `PowerLimits` tablosunu ve design §8'i birlikte güncelle.

---

## Ek: deneme sayfası (kontrolcü için)

Sayfanın gerçek dosyalarını yükler, `WebSocket` yerine Mac'i taklit eden sahte bir soket koyar: her anahtarı kabul
eder, saniyede bir snapshot gönderir. Konsoldan `sim.set({...})` bir değeri hedefe doğru iter, `sim.clear()` serbest
bırakır. Depoya eklenmez; scratchpad'deki bir klasöre (aşağıda `H`) yazılır, depo kökü `R`.

`H/fake-ws.js`:

```js
// A stand-in for the Mac: replaces WebSocket with a fake that authenticates any key and sends a simulated snapshot
// every second. `sim.set({ cpu: 100 })` pushes a value towards a target; `sim.clear()` lets it drift back.
(function (global) {
  "use strict";
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const GiB = 1073741824;
  const state = {
    cpu: 22, ram: 72, gpu: 8, temp: 50, power: 9, rx: 2e5, tx: 4e4, free: 16e9, battery: 80, plugged: true,
    phone: { percent: 100, charging: false, plugged: true }, media: true, cable: true, override: {},
    apps: [
      { pid: 1, bundleId: "com.google.Chrome", name: "Google Chrome", cpu: 22, mem: 5.3 * GiB, quittable: true },
      { pid: 2, bundleId: "com.microsoft.VSCode", name: "Code", cpu: 14, mem: 7.4 * GiB, quittable: true },
      { pid: 3, bundleId: "com.anthropic.claude", name: "Claude", cpu: 9, mem: 1.8 * GiB, quittable: true },
      { pid: 4, bundleId: "com.spotify.client", name: "Spotify", cpu: 4, mem: 0.31 * GiB, quittable: true },
      { pid: 5, bundleId: "com.tinyspeck.slackmacgap", name: "Slack", cpu: 3, mem: 0.64 * GiB, quittable: true },
      { pid: 6, bundleId: "com.apple.finder", name: "Finder", cpu: 1, mem: 0.18 * GiB, quittable: false },
      { pid: 7, bundleId: "com.apple.Music", name: "Music", cpu: 1, mem: 0.21 * GiB, quittable: true },
      { pid: 8, bundleId: null, name: "node", cpu: 2, mem: 0.12 * GiB, quittable: false },
    ],
  };
  let tick = 0;
  function step() {
    const o = state.override;
    const toward = (key, target, rate) => { state[key] += (target - state[key]) * rate; };
    toward("cpu", o.cpu ?? 15 + Math.random() * 22, o.cpu !== undefined ? 0.55 : 0.5);
    toward("ram", o.ram ?? 70 + Math.random() * 3, 0.5);
    toward("gpu", o.gpu ?? 4 + Math.random() * 10, 0.55);
    toward("temp", o.temp ?? 48 + state.cpu * 0.12 + Math.random() * 2, 0.3);
    toward("power", o.power ?? 5 + state.cpu * 0.12 + Math.random() * 2, 0.55);
    toward("rx", o.rx ?? (Math.random() < 0.15 ? 1e6 + Math.random() * 3e6 : 2e4 + Math.random() * 3e5), 0.7);
    toward("tx", o.tx ?? 5e3 + Math.random() * 1e5, 0.7);
    toward("free", o.free ?? 16e9, 0.45);
    toward("battery", o.battery ?? 80, 0.45);
    state.plugged = o.plugged ?? true;
    for (const app of state.apps) {
      const target = o.apps && o.apps[app.name] !== undefined ? o.apps[app.name] : app.cpu + (Math.random() - 0.5) * (app.cpu > 10 ? 8 : 3);
      app.cpu = clamp(app.cpu + (target - app.cpu) * 0.6, 0, 800);
    }
  }
  function snapshot() {
    tick += 1;
    step();
    const s = {
      v: 1, type: "snapshot", t: Date.now(),
      cpu: { total: clamp(state.cpu, 0, 100), cores: [], pCores: 4, load: [1 + state.cpu / 14, 2, 2] },
      mem: { used: (clamp(state.ram, 0, 100) / 100) * 16 * GiB, total: 16 * GiB, app: 0, wired: 0, compressed: 0, swapUsed: 0, pressure: "normal" },
      gpu: { util: clamp(state.gpu, 0, 100) }, temp: { avg: state.temp, max: state.temp + 6 },
      power: { gpu: state.gpu * 0.1, system: state.power }, net: { rx: state.rx, tx: state.tx, iface: "en0" },
      disk: { free: state.free, total: 494e9, read: 2e5, write: 8e4 },
      battery: { percent: Math.round(state.battery), charging: false, plugged: state.plugged },
      audio: { volume: 0.5, muted: false },
    };
    if (state.media) s.media = { title: "Kara Toprak", artist: "Barış Manço", app: "Spotify", playing: true };
    if (state.phone) s.phone = state.phone;
    if (tick % 3 === 0) s.apps = state.apps.map((a) => Object.assign({}, a));
    return s;
  }
  class FakeSocket {
    constructor() {
      this.readyState = 0;
      global.setTimeout(() => {
        this.readyState = 1;
        this.emit({ v: 1, type: "hello", nonce: "00", app: "PhoneBox test" });
      }, 50);
    }
    send(text) {
      const message = JSON.parse(text);
      if (message.type !== "auth") return;
      this.emit({ v: 1, type: "ready", mode: "cable", host: "MacBook Pro", limits: { power: [15, 35] },
                  access: { streaming: true, commands: state.cable, cable: state.cable, reason: "ok" } });
      this.timer = global.setInterval(() => this.emit(snapshot()), 1000);
    }
    close() {
      this.readyState = 3;
      global.clearInterval(this.timer);
    }
    emit(message) {
      if (this.onmessage) this.onmessage({ data: JSON.stringify(message) });
    }
  }
  FakeSocket.CONNECTING = 0; FakeSocket.OPEN = 1; FakeSocket.CLOSING = 2; FakeSocket.CLOSED = 3;
  global.WebSocket = FakeSocket;
  try { global.localStorage.setItem("phonebox-guide-done", "1"); } catch (error) {}
  global.sim = { state, set: (values) => Object.assign(state.override, values), clear: () => { state.override = {}; } };
})(window);
```

`H/make.py` (`R/Resources/web/index.html`'den `H/page.html`'i üretir):

```python
"""Builds harness/page.html from the replay copy's index.html: same page, but with fake-ws.js loaded first and every
relative path pointing at p4af/Resources/web."""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.join(os.path.dirname(HERE), "p4af", "Resources", "web")
html = open(os.path.join(WEB, "index.html"), encoding="utf-8").read()
html = html.replace("<head>", '<head>\n<base href="/p4af/Resources/web/">', 1)
first_script = '<script src="sha256.js"></script>'
assert html.count(first_script) == 1
html = html.replace(first_script, '<script src="/harness/fake-ws.js"></script>\n' + first_script)
open(os.path.join(HERE, "page.html"), "w", encoding="utf-8").write(html)
print(os.path.join(HERE, "page.html"))
```

Çalıştırma: `H` ile `R`'yi aynı köke bağlayan bir klasörde (`ln -s R <kök>/p4af`, `H` = `<kök>/harness`)
`python3 harness/make.py` ve `python3 -m http.server 8731 --bind 127.0.0.1`. Tarayıcı panelinde
`http://127.0.0.1:8731/harness/page.html#k=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA` aç, "Başlat"ı
`document.getElementById('start').hidden = true` ile kapat.
