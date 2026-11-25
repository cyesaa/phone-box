# PhoneBox Plan 3B — Komutların Mac tarafı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Bu plan için not:** Görev 1–8 Mac'te tek başına yürütülebilir; uygulamayı başlatmaz, kullanıcının PhoneBox'ını
> durdurmaz, `defaults`'a ve eşleştirme anahtarına dokunmaz, `PHONEBOX_LIVE=1` testlerini çalıştırmaz. Görev 9
> kontrolcü tarafından (inline) yapılır: uygulamayı Mac'te çalıştırıp dener ve sonuçları yazar. Komutların telefondan
> kabloyla uçtan uca denenmesi Plan 4'ün son görevindedir (o zamana kadar sayfada komut düğmesi yok).
>
> **Yürütme notu (2026-11-25):** Plan alt ajanlarla yürütüldü (dal `plan3b`); Görev 1–8'in kodu planlamada denenen
> kodla birebir aynı çıktı. Plandan sapmalar ve sonradan gelen düzeltmeler:
> - Görev 6: canlı testte `#require(SystemAudio.isMuted() as Bool?)` (plandaki satır "ambiguous" uyarısı veriyordu).
> - `5651a94`: PhoneBox kapanınca örnekleyici durduruluyor; yoksa adaptör süreci sahipsiz kalıp bir sonraki medya
>   değişikliğine kadar yaşıyordu (Görev 9'daki Mac denemesinde bulundu).
> - `09d8ac4` (son inceleme): bir iPhone takılınca "Her zaman" modunda da Wi-Fi'deki telefonlar 4002 ile kabloya
>   yönlendiriliyor (yoksa takılı telefon komut alamıyordu); adaptör başlatılamazsa boru ve okuyucu bırakılıyor;
>   `ShortProcess` testleri; design §5'ten `bad-signature` çıkarıldı; elle test listesine Kişisel Erişim Noktası denetimi.
>
> Sonuç: 135 + 17 test; PhoneBox veri gönderirken %0,60 CPU, adaptör %0,03.

**Goal:** Telefondan gelen imzalı komutları (uygulama kapatma, medya, ses, kilit, ekranı kapatma, uyku) sadece kablodaki
telefon için Mac'te çalıştırmak; telefona çalan şarkıyı ve ses seviyesini göndermek; incelemelerden ertelenen protokol
sıkılaştırmalarını yapmak.

**Architecture:** Kurallar (erişim, sıkı ayrıştırma, komut modeli, Origin, adaptör satırlarının çözümü, kapatma kuralı)
`PhoneBoxCore`'a test edilerek eklenir. `DashboardHub` iki küçük protokolle (`PhoneConnection`, `CommandRunning`)
uygulama hedefinde kalır ve yeni `PhoneBoxTests` hedefinde sahte bağlantı ve sahte çalıştırıcıyla test edilir. Mac'e
dokunan parçalar (CoreAudio, mediaremote-adapter süreci, `NSRunningApplication`, `pmset`, `SACLockScreenImmediate`)
uygulamada küçük dosyalardadır.

**Tech Stack:** Swift 6 araç zinciri (Swift 5 dil modu), SwiftPM, Command Line Tools, Swift Testing, CoreAudio,
AppKit, Foundation `Process`, mediaremote-adapter v0.7.7 (git alt modülü, Perl betiği + framework).

## Global Constraints

- macOS 14+, Apple Silicon; `swiftLanguageModes: [.v5]`. Tek yeni bağımlılık mediaremote-adapter v0.7.7
  (`Vendor/mediaremote-adapter`, git alt modülü, commit `e3ff502`, BSD 3-Clause, `THIRD_PARTY_NOTICES.md`); başka
  bağımlılık yok. Her şey ana kuyrukta (`@MainActor`); alt süreçlerin sonucu ana kuyruğa döner.
- Komutlar her iki modda da yalnızca kablodan (iPhone'un USB arayüzündeki kapsamlı IPv6 link-local adresten) gelen
  istemcilere açıktır (design §5 AccessPolicy). "Her zaman" modunda Wi-Fi'deki telefon veri alır, `commands: false`.
- Protokol (design §5): `ready` mesajında `host` (Mac'in adı), `access`'te `cable`. `v` tamsayı `1`, `seq` pozitif ve
  en fazla 2⁵³−1 olan bir JSON tamsayısı olmalı (`true`, `1.0`, negatif geçersiz). İmzası doğru ama bilinmeyen ad ya da
  biçim → `ack` ile `unsupported` (bağlantı açık kalır); bozuk JSON ve tip hataları → 1008. WebSocket yükseltmesinde
  `Origin` varsa `http://` + `Host` olmalı, değilse 403.
- Komutlar (design §7): `quitApp {bundleId, force}`, `media {action: playPause|next|previous}`, `volume {level: 0…1}`,
  `mute {on}`, `lock {}`, `displaySleep {}`, `sleep {}`; eksik ya da fazla anahtar geçersiz. `ack` hataları:
  `not-allowed`, `app-changed`, `unsupported`, `failed`. `sleep`'te `ack` önce gönderilir, Mac 1 sn sonra uyur.
  `quitApp` uygulamayı `bundleId` ile bulur, kapatılabilir bütün örneklerine uygular; Finder, arka plan uygulamaları
  ve PhoneBox kapatılamaz (uygulama listesinin `quittable`'ı ile aynı kural).
- Snapshot (design §6): `media {title, artist?, app, playing}` hiçbir şey çalmıyorsa yok; `audio {volume, muted}`
  çıkışta ses kontrolü yoksa yok. Başlık ve sanatçı `AppUsage.displayName` ile temizlenir (en fazla 80 karakter).
- Adaptör (`/usr/bin/perl mediaremote-adapter.pl <framework> stream --no-diff --no-artwork --debounce=100`) sadece
  bir telefon veri alırken çalışır; çıkarsa 1, 2, 5, 10, 30 sn arayla yeniden başlatılır.
- Hiçbir test kilitlemez, uyutmaz, ekranı kapatmaz. Gerçek sistemi kullanan testler sadece `PHONEBOX_LIVE=1` ile çalışır.
- Ölçülen yük (planlama sırasında, M4): PhoneBox bir istemciye veri gönderirken `top`'ta %0,70 CPU, adaptör %0,00.
- Kod yorumları İngilizce. Commit mesajları İngilizce, emir kipinde. Aşağıdaki her `git commit` komutuna, commit'i
  yapan ortamın istediği `Co-Authored-By: …` satırı ikinci bir `-m` olarak eklenir (commit'i yapan modeli adlandırır).
- Testler `make test FILTER="<Suite>|<Suite>"` ile (tırnaklar kalsın; Makefile Command Line Tools'un Swift Testing
  eklenti yolunu ekler). `swift build --build-tests` bu yol olmadan çalışmaz; kullanmayın.

## Planlama sırasında doğrulananlar (2026-11-25)

Kodun tamamı `main`'in (4728faa) bir kopyasında görev görev yazıldı; her görevin sonunda `swift build` uyarısız,
testler geçti. Sonda: `PhoneBoxCoreTests` 26 takımda 135 test, `PhoneBoxTests` 3 takımda 13 test (4'ü canlı test,
varsayılan olarak atlanır).

- Derlenen uygulama kullanıcının PhoneBox'ının yerine kısa süre çalıştırıldı. Mac'in tarayıcısından (`lo0`, "Her
  zaman" modu):
  - `ready`: `host: "Eren MacBook Pro"`, `access {streaming: true, commands: false, cable: false, reason: "ok"}`.
  - İmzalı `mute` ve bilinmeyen bir komut: ikisi de `not-allowed`.
  - Snapshot'ta `media`: Chrome'da duraklatılmış YouTube videosu (başlık, "Cem Yılmaz", "Google Chrome", `playing:
    false`).
  - Snapshot'ta `audio {volume: 0.81, muted: false}`.
- `nc` ile WebSocket yükseltmesi: `Origin: http://localhost:4747` → 101; `Origin: http://evil.example` → 403.
- PhoneBox 30 sn ortalama %0,70 CPU (ses ve şarkı bilgisiyle), adaptör süreci %0,00.
- `PHONEBOX_LIVE=1`:
  - `SystemAudioLiveTests`: ses seviyesi ve sessiz okunup aynı değer yazıldı.
  - `CommandRunnerLiveTests`: Satranç açılıp `quitApp` ile kapandı; Finder ve çalışmayan uygulama `app-changed`;
    adaptörsüz medya `unsupported`.
- Adaptörün akışı boş bir `payload` ile başlıyor, sonra şarkı geliyor; `playing` bir boolean. Kaydedilen satır
  `MediaTests`'te.
- Planlamada bulunan hata: "Her zaman" modunda Wi-Fi istemcilerine komut izni veriliyordu (`AccessPolicy` `.granted`
  dönüyordu), oysa design §5 sadece kablo diyor. Görev 1 düzeltir.
- Command Line Tools ile bir test hedefi çalıştırılabilir hedefi `@testable import PhoneBox` ile içe aktarabiliyor; bu
  yüzden `DashboardHub` Core'a taşınmadan yerinde test ediliyor.
- Denenmedi (kullanıcıyı rahatsız ederdi ya da telefon gerekir; Plan 4'ün telefon oturumunda):
  - USB'den gerçek komut.
  - Kilit, ekranı kapatma, uyku.
  - Adaptörle medya gönderme.

  Spike 7'de medya dışındakilerin hepsi izin penceresi açmadan çalışmıştı.

## Dosya yapısı

```
Package.swift                         PhoneBoxTests test hedefi (değişir)
Makefile                              adapter hedefi (değişir)
THIRD_PARTY_NOTICES.md                (yeni)
scripts/build-adapter.sh              (yeni), scripts/bundle.sh (değişir)
Vendor/mediaremote-adapter            (git alt modülü, yeni)
Sources/PhoneBoxCore/   AccessPolicy, Messages, Session, HTTP, Snapshot (değişir);
                        JSONValue, Command, Media, QuitRule (yeni)
Sources/PhoneBox/       DashboardHub, ClientConnection, AppDelegate, Settings, Sampler,
                        Collectors/AppsCollector, Collectors/PrivateSymbols (değişir);
                        CommandRunner, SystemAudio, ShortProcess, NowPlayingService, Collectors/AudioCollector (yeni)
Tests/PhoneBoxCoreTests/ AccessPolicyTests, MessagesTests, SessionTests, HTTPTests (değişir);
                        CommandTests, MediaTests, QuitRuleTests (yeni)
Tests/PhoneBoxTests/    DashboardHubTests, SystemAudioLiveTests, CommandRunnerLiveTests (yeni)
```

"Bul / Şununla değiştir" adımlarında "Bul" metni dosyada tam olarak bir kez geçer; Edit aracıyla birebir değiştirin.

---

### Task 1: Komutlar sadece kablodan; Mac'in adı ve bağlantı yolu

**Files:**
- Modify: `Tests/PhoneBoxCoreTests/AccessPolicyTests.swift` (dosyanın tamamı), `Tests/PhoneBoxCoreTests/MessagesTests.swift`
- Modify: `Sources/PhoneBoxCore/AccessPolicy.swift` (dosyanın tamamı), `Sources/PhoneBoxCore/Messages.swift`
- Modify: `Sources/PhoneBox/Settings.swift`, `Sources/PhoneBox/DashboardHub.swift`, `Sources/PhoneBox/AppDelegate.swift`

**Interfaces:**
- Consumes: mevcut `AccessPolicy.decide(mode:clientOnUSB:authenticated:)`, `ServerMessage`.
- Produces: `Access(streaming:commands:cable:reason:)` ve `.onCable`, `.overWiFi`, `.notOnCable`, `.unauthenticated`
  (`.granted` kalkar); `ServerMessage.ready(mode:host:access:)`; `access` mesajında `cable`; `Settings.computerName()`;
  `DashboardHub.init(mode:key:appName:hostName:usbInterfaces:)`.

- [ ] **Step 1: Testleri yaz**

`Tests/PhoneBoxCoreTests/AccessPolicyTests.swift`:

```swift
import Testing
@testable import PhoneBoxCore

struct AccessPolicyTests {
    @Test func cableModeAllowsOnlyClientsOnTheUSBLink() {
        #expect(AccessPolicy.decide(mode: .cable, clientOnUSB: true, authenticated: true) == .onCable)
        #expect(AccessPolicy.decide(mode: .cable, clientOnUSB: false, authenticated: true) == .notOnCable)
    }

    @Test func alwaysModeStreamsToEveryoneButTakesCommandsOnlyFromTheCable() {
        #expect(AccessPolicy.decide(mode: .always, clientOnUSB: true, authenticated: true) == .onCable)
        let wifi = AccessPolicy.decide(mode: .always, clientOnUSB: false, authenticated: true)
        #expect(wifi == .overWiFi)
        #expect(wifi.streaming && !wifi.commands && !wifi.cable)
    }

    @Test func commandsNeverComeFromOffTheCable() {
        for mode in AccessMode.allCases {
            for authenticated in [true, false] {
                #expect(!AccessPolicy.decide(mode: mode, clientOnUSB: false, authenticated: authenticated).commands)
            }
        }
    }

    @Test func unauthenticatedClientsGetNothingInAnyMode() {
        for mode in AccessMode.allCases {
            for onUSB in [true, false] {
                let access = AccessPolicy.decide(mode: mode, clientOnUSB: onUSB, authenticated: false)
                #expect(access == .unauthenticated)
                #expect(!access.streaming && !access.commands)
            }
        }
    }

    @Test func reasonsMatchTheProtocol() {
        #expect(Access.onCable.reason == "ok")
        #expect(Access.overWiFi.reason == "ok")
        #expect(Access.notOnCable.reason == "not-on-cable")
    }
}
```

`Tests/PhoneBoxCoreTests/MessagesTests.swift`:

Bul (1/2):

```swift
    @Test func encodesReadyWithTheAccessObject() {
        #expect(ServerMessage.ready(mode: .cable, access: .notOnCable).json()
            == #"{"access":{"commands":false,"reason":"not-on-cable","streaming":false},"mode":"cable","type":"ready","v":1}"#)
    }
```

Şununla değiştir:

```swift
    @Test func encodesReadyWithTheAccessObject() {
        #expect(ServerMessage.ready(mode: .cable, host: "Eren's MacBook Pro", access: .notOnCable).json()
            == #"{"access":{"cable":false,"commands":false,"reason":"not-on-cable","streaming":false},"host":"Eren's MacBook Pro","mode":"cable","type":"ready","v":1}"#)
    }
```

Bul (2/2):

```swift
    @Test func encodesAccessFlat() {
        #expect(ServerMessage.access(.granted).json()
            == #"{"commands":true,"reason":"ok","streaming":true,"type":"access","v":1}"#)
    }
```

Şununla değiştir:

```swift
    @Test func encodesAccessFlat() {
        #expect(ServerMessage.access(.onCable).json()
            == #"{"cable":true,"commands":true,"reason":"ok","streaming":true,"type":"access","v":1}"#)
        #expect(ServerMessage.access(.overWiFi).json()
            == #"{"cable":false,"commands":false,"reason":"ok","streaming":true,"type":"access","v":1}"#)
    }
```

- [ ] **Step 2: Testlerin derlenmediğini gör**

Run: `make test FILTER="AccessPolicyTests|ServerMessageTests"` → Expected: derleme hatası (`Access` içinde `onCable`,
`overWiFi`, `cable` yok; `ready` çağrısında fazladan `host` argümanı).

- [ ] **Step 3: Erişim kuralı ve mesajlar**

`Sources/PhoneBoxCore/AccessPolicy.swift`:

```swift
/// "Kablo takılıyken" (cable) or "Her zaman" (always), chosen in the menu bar (design §5).
public enum AccessMode: String, Codable, Sendable, CaseIterable {
    case cable
    case always
}

/// What one phone may do right now.
public struct Access: Equatable, Codable, Sendable {
    public var streaming: Bool
    public var commands: Bool
    /// The phone is connected over the iPhone's USB link; the page shows "kablo" or "Wi-Fi".
    public var cable: Bool
    /// `ok`, `not-on-cable`, or `unauthenticated` (never sent: such clients get no messages).
    public var reason: String

    public init(streaming: Bool, commands: Bool, cable: Bool, reason: String) {
        self.streaming = streaming
        self.commands = commands
        self.cable = cable
        self.reason = reason
    }

    public static let onCable = Access(streaming: true, commands: true, cable: true, reason: "ok")
    public static let overWiFi = Access(streaming: true, commands: false, cable: false, reason: "ok")
    public static let notOnCable = Access(streaming: false, commands: false, cable: false, reason: "not-on-cable")
    public static let unauthenticated = Access(streaming: false, commands: false, cable: false, reason: "unauthenticated")
}

/// Design §5 "AccessPolicy". A connection on the iPhone's USB link can only come from a phone that is
/// plugged into this Mac and trusts it. Commands come only from there, in both modes: the page is served over
/// plain HTTP, so an active attacker on the same Wi-Fi could serve a modified page.
public enum AccessPolicy {
    public static func decide(mode: AccessMode, clientOnUSB: Bool, authenticated: Bool) -> Access {
        guard authenticated else { return .unauthenticated }
        if clientOnUSB { return .onCable }
        switch mode {
        case .always: return .overWiFi
        case .cable: return .notOnCable
        }
    }
}
```

`Sources/PhoneBoxCore/Messages.swift`:

Bul (1/4):

```swift
    case hello(nonce: String, app: String)
    case ready(mode: AccessMode, access: Access)
    case access(Access)
```

Şununla değiştir:

```swift
    case hello(nonce: String, app: String)
    case ready(mode: AccessMode, host: String, access: Access)
    case access(Access)
```

Bul (2/4):

```swift
    private enum Keys: String, CodingKey {
        case v, type, nonce, app, mode, access, streaming, commands, reason, t, cpu, mem, gpu, temp, power, net, disk,
             battery, apps, seq, ok, error
```

Şununla değiştir:

```swift
    private enum Keys: String, CodingKey {
        case v, type, nonce, app, mode, host, access, streaming, commands, cable, reason, t, cpu, mem, gpu, temp, power, net, disk,
             battery, apps, seq, ok, error
```

Bul (3/4):

```swift
            try container.encode(app, forKey: .app)
        case let .ready(mode, access):
            try container.encode("ready", forKey: .type)
            try container.encode(mode, forKey: .mode)
            try container.encode(access, forKey: .access)
```

Şununla değiştir:

```swift
            try container.encode(app, forKey: .app)
        case let .ready(mode, host, access):
            try container.encode("ready", forKey: .type)
            try container.encode(mode, forKey: .mode)
            try container.encode(host, forKey: .host)
            try container.encode(access, forKey: .access)
```

Bul (4/4):

```swift
            try container.encode(access.commands, forKey: .commands)
            try container.encode(access.reason, forKey: .reason)
```

Şununla değiştir:

```swift
            try container.encode(access.commands, forKey: .commands)
            try container.encode(access.cable, forKey: .cable)
            try container.encode(access.reason, forKey: .reason)
```

- [ ] **Step 4: Mac'in adı uygulamada**

`Sources/PhoneBox/Settings.swift`:

Bul:

```swift
    }

    /// The personal link in the QR code (design §5). Always with `http://`: Safari tries HTTPS first for an
```

Şununla değiştir:

```swift
    }

    /// "Eren's MacBook Pro" from System Settings → General → Sharing; the page shows it in its status line.
    static func computerName() -> String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? localHostName()
    }

    /// The personal link in the QR code (design §5). Always with `http://`: Safari tries HTTPS first for an
```

`Sources/PhoneBox/DashboardHub.swift`:

Bul (1/4):

```swift
    private let appName: String
    private let usbInterfaces: () -> Set<String>
```

Şununla değiştir:

```swift
    private let appName: String
    /// The Mac's name, shown in the page's status line.
    private let hostName: String
    private let usbInterfaces: () -> Set<String>
```

Bul (2/4):

```swift
    var onConnectionClosed: ((ClientConnection) -> Void)?

    init(mode: AccessMode, key: PairingKey, appName: String, usbInterfaces: @escaping () -> Set<String> = USBLinks.iPhoneInterfaceNames) {
        self.mode = mode
```

Şununla değiştir:

```swift
    var onConnectionClosed: ((ClientConnection) -> Void)?

    init(mode: AccessMode, key: PairingKey, appName: String, hostName: String,
         usbInterfaces: @escaping () -> Set<String> = USBLinks.iPhoneInterfaceNames) {
        self.mode = mode
```

Bul (3/4):

```swift
        self.appName = appName
        self.usbInterfaces = usbInterfaces
```

Şununla değiştir:

```swift
        self.appName = appName
        self.hostName = hostName
        self.usbInterfaces = usbInterfaces
```

Bul (4/4):

```swift
            clients[id] = client
            connection.send(.ready(mode: mode, access: client.access))
            onAuthenticated?()
```

Şununla değiştir:

```swift
            clients[id] = client
            connection.send(.ready(mode: mode, host: hostName, access: client.access))
            onAuthenticated?()
```

`Sources/PhoneBox/AppDelegate.swift`:

Bul:

```swift
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        hub = DashboardHub(mode: settings.mode, key: key, appName: "PhoneBox \(version)")
        let webDirectory = Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true)
```

Şununla değiştir:

```swift
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        hub = DashboardHub(mode: settings.mode, key: key, appName: "PhoneBox \(version)", hostName: Settings.computerName())
        let webDirectory = Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true)
```

- [ ] **Step 5: Testleri çalıştır**

Run: `make test FILTER="AccessPolicyTests|ServerMessageTests"` → Expected: geçer.
Run: `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"` → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 106 tests in 20 suites passed`.

- [ ] **Step 6: Commit**

```bash
git add Sources/PhoneBoxCore/AccessPolicy.swift Sources/PhoneBoxCore/Messages.swift Sources/PhoneBox/Settings.swift \
  Sources/PhoneBox/DashboardHub.swift Sources/PhoneBox/AppDelegate.swift \
  Tests/PhoneBoxCoreTests/AccessPolicyTests.swift Tests/PhoneBoxCoreTests/MessagesTests.swift
git commit -m "Take commands only from the cable and tell the phone the Mac's name"
```

---

### Task 2: Sıkı ayrıştırma ve izinli komutlar

**Files:**
- Create: `Sources/PhoneBoxCore/JSONValue.swift`, `Sources/PhoneBoxCore/Command.swift`, `Tests/PhoneBoxCoreTests/CommandTests.swift`
- Modify: `Sources/PhoneBoxCore/Messages.swift`, `Sources/PhoneBoxCore/Session.swift`, `Sources/PhoneBox/DashboardHub.swift`
- Modify: `Tests/PhoneBoxCoreTests/MessagesTests.swift`, `Tests/PhoneBoxCoreTests/SessionTests.swift`

**Interfaces:**
- Consumes: Görev 1'in `ServerMessage`'ı.
- Produces: `enum Command { quitApp(bundleId:force:), media(MediaAction), volume(level:), mute(on:), lock,
  displaySleep, sleep }`, `Command.MediaAction { playPause, next, previous }`, `Command.parse(name:args:) -> Command?`,
  `Command.name`, `Command.maxBundleIdLength = 255`; `enum CommandFailure: String { notAllowed = "not-allowed",
  appChanged = "app-changed", unsupported, failed }`; `enum CommandResult { ok, failed(CommandFailure) }`;
  `ServerMessage.ack(seq:result:)`; `Session.Outcome.command(seq: Int, command: Command)`; iç kullanım için
  `JSONValue.bool/integer/number`.

- [ ] **Step 1: Testleri yaz**

`Tests/PhoneBoxCoreTests/CommandTests.swift`:

```swift
import Testing
@testable import PhoneBoxCore

struct CommandTests {
    @Test func parsesEveryCommandOfDesignSection7() {
        #expect(Command.parse(name: "quitApp", args: #"{"bundleId":"com.google.Chrome","force":false}"#)
            == .quitApp(bundleId: "com.google.Chrome", force: false))
        #expect(Command.parse(name: "quitApp", args: #"{"force":true,"bundleId":"com.google.Chrome"}"#)
            == .quitApp(bundleId: "com.google.Chrome", force: true))
        #expect(Command.parse(name: "media", args: #"{"action":"playPause"}"#) == .media(.playPause))
        #expect(Command.parse(name: "media", args: #"{"action":"next"}"#) == .media(.next))
        #expect(Command.parse(name: "media", args: #"{"action":"previous"}"#) == .media(.previous))
        #expect(Command.parse(name: "volume", args: #"{"level":0.35}"#) == .volume(level: 0.35))
        #expect(Command.parse(name: "volume", args: #"{"level":0}"#) == .volume(level: 0))
        #expect(Command.parse(name: "volume", args: #"{"level":1}"#) == .volume(level: 1))
        #expect(Command.parse(name: "mute", args: #"{"on":true}"#) == .mute(on: true))
        #expect(Command.parse(name: "lock", args: "{}") == .lock)
        #expect(Command.parse(name: "displaySleep", args: "{}") == .displaySleep)
        #expect(Command.parse(name: "sleep", args: "{}") == .sleep)
    }

    @Test func refusesUnknownNames() {
        for name in ["shutdown", "Lock", "", "quitApp:x", "run"] {
            #expect(Command.parse(name: name, args: "{}") == nil)
        }
    }

    @Test func refusesArgumentsOfTheWrongShape() {
        let bad: [(String, String)] = [
            ("quitApp", #"{"bundleId":"a"}"#),                          // force missing
            ("quitApp", #"{"bundleId":"","force":false}"#),             // empty bundle id
            ("quitApp", #"{"bundleId":"a","force":0}"#),                // 0 is not a boolean
            ("quitApp", #"{"bundleId":7,"force":false}"#),
            ("quitApp", #"{"bundleId":"a","force":false,"pid":812}"#),      // extra key: a pid is never trusted
            ("quitApp", #"{"bundleId":"a","force":false,"path":"/bin/sh"}"#),
            ("media", #"{"action":"stop"}"#),
            ("media", #"{}"#),
            ("volume", #"{"level":1.5}"#),
            ("volume", #"{"level":-0.1}"#),
            ("volume", #"{"level":true}"#),
            ("volume", #"{"level":"0.5"}"#),
            ("mute", #"{"on":1}"#),
            ("lock", #"{"now":true}"#),
            ("sleep", "[]"),
            ("sleep", "not json"),
            ("displaySleep", ""),
        ]
        for (name, args) in bad {
            #expect(Command.parse(name: name, args: args) == nil, "\(name) \(args)")
        }
    }

    @Test func capsTheBundleIdentifierLength() {
        let long = String(repeating: "a", count: Command.maxBundleIdLength + 1)
        #expect(Command.parse(name: "quitApp", args: #"{"bundleId":"\#(long)","force":false}"#) == nil)
        let longest = String(repeating: "a", count: Command.maxBundleIdLength)
        #expect(Command.parse(name: "quitApp", args: #"{"bundleId":"\#(longest)","force":false}"#)
            == .quitApp(bundleId: longest, force: false))
    }

    @Test func namesMatchTheProtocol() {
        #expect(Command.quitApp(bundleId: "a", force: true).name == "quitApp")
        #expect(Command.media(.next).name == "media")
        #expect(Command.volume(level: 0.2).name == "volume")
        #expect(Command.mute(on: false).name == "mute")
        #expect(Command.lock.name == "lock")
        #expect(Command.displaySleep.name == "displaySleep")
        #expect(Command.sleep.name == "sleep")
    }
}
```

`Tests/PhoneBoxCoreTests/MessagesTests.swift`:

Bul (1/2):

```swift
            == #"{"error":"not-allowed","ok":false,"seq":5,"type":"ack","v":1}"#)
    }
}

struct ClientMessageTests {
```

Şununla değiştir:

```swift
            == #"{"error":"not-allowed","ok":false,"seq":5,"type":"ack","v":1}"#)
    }

    @Test func buildsAcksFromCommandResults() {
        #expect(ServerMessage.ack(seq: 1, result: .ok) == .ack(seq: 1, ok: true, error: nil))
        #expect(ServerMessage.ack(seq: 2, result: .failed(.appChanged)) == .ack(seq: 2, ok: false, error: "app-changed"))
        #expect(ServerMessage.ack(seq: 3, result: .failed(.notAllowed)) == .ack(seq: 3, ok: false, error: "not-allowed"))
    }
}

struct ClientMessageTests {
```

Bul (2/2):

```swift
        #expect(ClientMessage.parse("[1,2]") == nil)
    }
}
```

Şununla değiştir:

```swift
        #expect(ClientMessage.parse("[1,2]") == nil)
    }

    @Test func versionMustBeTheInteger1() {
        #expect(ClientMessage.parse(#"{"v":true,"type":"auth","mac":"ff"}"#) == nil)
        #expect(ClientMessage.parse(#"{"v":1.0,"type":"auth","mac":"ff"}"#) == nil)
        #expect(ClientMessage.parse(#"{"v":"1","type":"auth","mac":"ff"}"#) == nil)
        #expect(ClientMessage.parse(#"{"type":"auth","mac":"ff"}"#) == nil)
    }

    @Test func sequenceNumbersMustBePositiveSafeIntegers() {
        func cmd(_ seq: String) -> ClientMessage? {
            ClientMessage.parse(#"{"v":1,"type":"cmd","seq":\#(seq),"name":"lock","args":"{}","mac":"a"}"#)
        }
        #expect(cmd("1") == .command(seq: 1, name: "lock", args: "{}", mac: "a"))
        #expect(cmd("9007199254740991") == .command(seq: 9_007_199_254_740_991, name: "lock", args: "{}", mac: "a"))
        #expect(cmd("true") == nil)
        #expect(cmd("2.0") == nil)
        #expect(cmd("2.5") == nil)
        #expect(cmd("0") == nil)
        #expect(cmd("-3") == nil)
        #expect(cmd("9007199254740992") == nil)
        #expect(cmd("1e3") == nil)
    }
}
```

`Tests/PhoneBoxCoreTests/SessionTests.swift`:

Bul (1/4):

```swift
        #expect(session.receive(commandMessage(session, seq: 1), key: key, commandsAllowed: true, now: now)
            == .command(seq: 1, name: "mute", args: #"{"on":true}"#))
        #expect(session.receive(commandMessage(session, seq: 5), key: key, commandsAllowed: true, now: now)
            == .command(seq: 5, name: "mute", args: #"{"on":true}"#))
    }
```

Şununla değiştir:

```swift
        #expect(session.receive(commandMessage(session, seq: 1), key: key, commandsAllowed: true, now: now)
            == .command(seq: 1, command: .mute(on: true)))
        #expect(session.receive(commandMessage(session, seq: 5), key: key, commandsAllowed: true, now: now)
            == .command(seq: 5, command: .mute(on: true)))
    }
```

Bul (2/4):

```swift
            #expect(session.receive(commandMessage(session, seq: seq), key: key, commandsAllowed: true, now: now)
                == .command(seq: seq, name: "mute", args: #"{"on":true}"#))
        }
```

Şununla değiştir:

```swift
            #expect(session.receive(commandMessage(session, seq: seq), key: key, commandsAllowed: true, now: now)
                == .command(seq: seq, command: .mute(on: true)))
        }
```

Bul (3/4):

```swift
        #expect(session.receive(commandMessage(session, seq: 11), key: key, commandsAllowed: true, now: now.addingTimeInterval(1.1))
            == .command(seq: 11, name: "mute", args: #"{"on":true}"#))
    }
```

Şununla değiştir:

```swift
        #expect(session.receive(commandMessage(session, seq: 11), key: key, commandsAllowed: true, now: now.addingTimeInterval(1.1))
            == .command(seq: 11, command: .mute(on: true)))
    }
```

Bul (4/4):

```swift
    }

    @Test func authTimeoutHasItsOwnCloseCode() {
```

Şununla değiştir:

```swift
    }

    @Test func answersUnknownOrMalformedCommandsWithUnsupported() {
        var session = authenticated()
        #expect(session.receive(commandMessage(session, seq: 1, name: "shutdown", args: "{}"), key: key, commandsAllowed: true, now: now)
            == .reply(.ack(seq: 1, ok: false, error: "unsupported")))
        #expect(session.receive(commandMessage(session, seq: 2, name: "volume", args: #"{"level":2}"#), key: key,
                                commandsAllowed: true, now: now)
            == .reply(.ack(seq: 2, ok: false, error: "unsupported")))
    }

    @Test func notAllowedComesBeforeParsing() {
        var session = authenticated()
        #expect(session.receive(commandMessage(session, seq: 1, name: "shutdown", args: "{}"), key: key, commandsAllowed: false, now: now)
            == .reply(.ack(seq: 1, ok: false, error: "not-allowed")))
    }

    @Test func authTimeoutHasItsOwnCloseCode() {
```

- [ ] **Step 2: Testlerin derlenmediğini gör**

Run: `make test FILTER="CommandTests|ClientMessageTests|ServerMessageTests|SessionTests"` → Expected: derleme hatası
(`Command` yok, `ack(seq:result:)` yok, `.command(seq:command:)` yok).

- [ ] **Step 3: Sıkı JSON okuyucular ve komut modeli**

`Sources/PhoneBoxCore/JSONValue.swift`:

```swift
import Foundation

/// Strict readers for values from `JSONSerialization`, which turns `true`, `1` and `1.0` alike into `NSNumber`.
enum JSONValue {
    /// Largest integer a JavaScript number holds exactly (`Number.MAX_SAFE_INTEGER`).
    static let maxSafeInteger = 9_007_199_254_740_991

    /// Only `true` or `false`, not `1` or `0`.
    static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    /// A whole number written without a fraction or exponent (`7`, not `7.0` or `true`), within ±2⁵³−1.
    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              !CFNumberIsFloatType(number)
        else { return nil }
        let double = number.doubleValue
        guard double.rounded() == double, abs(double) <= Double(maxSafeInteger) else { return nil }
        return number.intValue
    }

    /// Any finite number, but not a boolean.
    static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }
}
```

`Sources/PhoneBoxCore/Command.swift`:

```swift
import Foundation

/// The commands the phone may send (design §7). An unknown name, or arguments of the wrong shape, is answered
/// with `unsupported` and never run.
public enum Command: Equatable, Sendable {
    public enum MediaAction: String, Sendable, CaseIterable {
        case playPause, next, previous
    }

    /// The phone's app list can be 10 s old and merges an app's instances into one row, so the Mac finds the app
    /// again by `bundleId` and never trusts a process id from the phone.
    case quitApp(bundleId: String, force: Bool)
    case media(MediaAction)
    /// 0…1
    case volume(level: Double)
    case mute(on: Bool)
    case lock
    case displaySleep
    case sleep

    /// The protocol name, for logs.
    public var name: String {
        switch self {
        case .quitApp: return "quitApp"
        case .media: return "media"
        case .volume: return "volume"
        case .mute: return "mute"
        case .lock: return "lock"
        case .displaySleep: return "displaySleep"
        case .sleep: return "sleep"
        }
    }

    /// Bundle identifiers are short reverse-DNS names; anything longer is junk.
    public static let maxBundleIdLength = 255

    /// `args` is the JSON object text the phone signed. Nil for an unknown name or for arguments of the wrong
    /// shape, including missing or extra keys.
    public static func parse(name: String, args: String) -> Command? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(args.utf8))) as? [String: Any] else { return nil }
        let keys = Set(object.keys)
        switch name {
        case "quitApp":
            guard keys == ["bundleId", "force"], let bundleId = object["bundleId"] as? String, !bundleId.isEmpty,
                  bundleId.utf8.count <= maxBundleIdLength, let force = JSONValue.bool(object["force"])
            else { return nil }
            return .quitApp(bundleId: bundleId, force: force)
        case "media":
            guard keys == ["action"], let raw = object["action"] as? String, let action = MediaAction(rawValue: raw)
            else { return nil }
            return .media(action)
        case "volume":
            guard keys == ["level"], let level = JSONValue.number(object["level"]), (0...1).contains(level) else { return nil }
            return .volume(level: level)
        case "mute":
            guard keys == ["on"], let on = JSONValue.bool(object["on"]) else { return nil }
            return .mute(on: on)
        case "lock":
            return keys.isEmpty ? .lock : nil
        case "displaySleep":
            return keys.isEmpty ? .displaySleep : nil
        case "sleep":
            return keys.isEmpty ? .sleep : nil
        default:
            return nil
        }
    }
}

/// Why a command was not done; the `ack` message's `error` (design §5).
public enum CommandFailure: String, Equatable, Sendable {
    /// The phone is not on the cable.
    case notAllowed = "not-allowed"
    /// No app with that bundle identifier can be quit any more.
    case appChanged = "app-changed"
    /// Unknown command, wrong arguments, or the Mac cannot do it (e.g. an output without volume control).
    case unsupported
    case failed
}

public enum CommandResult: Equatable, Sendable {
    case ok
    case failed(CommandFailure)
}
```

- [ ] **Step 4: Mesajlar, oturum ve bağlantı yöneticisi**

`Sources/PhoneBoxCore/Messages.swift`:

Bul (1/3):

```swift
}

/// Messages from the phone to the Mac.
```

Şununla değiştir:

```swift
}

extension ServerMessage {
    /// The `ack` for a command's result.
    public static func ack(seq: Int, result: CommandResult) -> ServerMessage {
        switch result {
        case .ok: return .ack(seq: seq, ok: true, error: nil)
        case let .failed(failure): return .ack(seq: seq, ok: false, error: failure.rawValue)
        }
    }
}

/// Messages from the phone to the Mac.
```

Bul (2/3):

```swift
    case command(seq: Int, name: String, args: String, mac: String)

    /// Nil for anything that is not a well-formed version 1 message.
    public static func parse(_ text: String) -> ClientMessage? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              object["v"] as? Int == 1
        else { return nil }
```

Şununla değiştir:

```swift
    case command(seq: Int, name: String, args: String, mac: String)

    /// Nil for anything that is not a well-formed version 1 message. `v` must be the integer 1 and `seq` a
    /// positive integer: `true`, `1.0` or a negative number is not accepted (design §5).
    public static func parse(_ text: String) -> ClientMessage? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              JSONValue.integer(object["v"]) == 1
        else { return nil }
```

Bul (3/3):

```swift
        case "cmd":
            guard let seq = object["seq"] as? Int, let name = object["name"] as? String,
                  let args = object["args"] as? String, let mac = object["mac"] as? String
```

Şununla değiştir:

```swift
        case "cmd":
            guard let seq = JSONValue.integer(object["seq"]), seq > 0, let name = object["name"] as? String,
                  let args = object["args"] as? String, let mac = object["mac"] as? String
```

`Sources/PhoneBoxCore/Session.swift`:

Bul (1/2):

```swift
        case authenticated
        /// A signed, fresh command the caller should run.
        case command(seq: Int, name: String, args: String)
        /// Send this and keep the connection.
```

Şununla değiştir:

```swift
        case authenticated
        /// A signed, fresh, allowed and well-formed command the caller should run, then answer with an `ack`.
        case command(seq: Int, command: Command)
        /// Send this and keep the connection.
```

Bul (2/2):

```swift
            recentCommands.append(now)
            guard commandsAllowed else { return .reply(.ack(seq: seq, ok: false, error: "not-allowed")) }
            return .command(seq: seq, name: name, args: args)
        }
```

Şununla değiştir:

```swift
            recentCommands.append(now)
            guard commandsAllowed else { return .reply(.ack(seq: seq, result: .failed(.notAllowed))) }
            guard let command = Command.parse(name: name, args: args) else {
                return .reply(.ack(seq: seq, result: .failed(.unsupported)))
            }
            return .command(seq: seq, command: command)
        }
```

`Sources/PhoneBox/DashboardHub.swift` (komutlar hâlâ çalıştırılmaz; Görev 5 bağlar):

Bul:

```swift
            changed(wasStreaming: wasStreaming)
        case let .command(seq, _, _):
            // Commands arrive in Plan 3; until then every signed command is answered, never run.
```

Şununla değiştir:

```swift
            changed(wasStreaming: wasStreaming)
        case let .command(seq, _):
            // Commands arrive in Plan 3; until then every signed command is answered, never run.
```

- [ ] **Step 5: Testleri çalıştır**

Run: `make test FILTER="CommandTests|ClientMessageTests|ServerMessageTests|SessionTests"` → Expected: geçer.
Run: `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"` → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 116 tests in 21 suites passed`.

- [ ] **Step 6: Commit**

```bash
git add Sources/PhoneBoxCore/JSONValue.swift Sources/PhoneBoxCore/Command.swift Sources/PhoneBoxCore/Messages.swift \
  Sources/PhoneBoxCore/Session.swift Sources/PhoneBox/DashboardHub.swift Tests/PhoneBoxCoreTests/CommandTests.swift \
  Tests/PhoneBoxCoreTests/MessagesTests.swift Tests/PhoneBoxCoreTests/SessionTests.swift
git commit -m "Parse commands strictly against an allowlist"
```

---

### Task 3: Başka sitelerden WebSocket'e izin yok

**Files:**
- Modify: `Sources/PhoneBoxCore/HTTP.swift`, `Tests/PhoneBoxCoreTests/HTTPTests.swift`, `Sources/PhoneBox/ClientConnection.swift`

**Interfaces:**
- Consumes: `HTTPRequestHead.headers` (adlar küçük harfli).
- Produces: `WebSocketOrigin.isAllowed(origin: String?, host: String?) -> Bool`, `HTTPResponse.forbidden` (403).

- [ ] **Step 1: Testleri yaz**

`Tests/PhoneBoxCoreTests/HTTPTests.swift`:

Dosyanın sonuna ekle:

```swift
struct WebSocketOriginTests {
    @Test func acceptsTheDashboardsOwnPage() {
        #expect(WebSocketOrigin.isAllowed(origin: "http://eren-macbook-pro.local:4747", host: "eren-macbook-pro.local:4747"))
        #expect(WebSocketOrigin.isAllowed(origin: "http://Eren-MacBook-Pro.local:4747", host: "eren-macbook-pro.local:4747"))
        #expect(WebSocketOrigin.isAllowed(origin: "http://localhost:4747", host: "localhost:4747"))
    }

    @Test func refusesOtherSites() {
        #expect(!WebSocketOrigin.isAllowed(origin: "http://evil.example", host: "eren-macbook-pro.local:4747"))
        #expect(!WebSocketOrigin.isAllowed(origin: "https://eren-macbook-pro.local:4747", host: "eren-macbook-pro.local:4747"))
        #expect(!WebSocketOrigin.isAllowed(origin: "http://eren-macbook-pro.local:4748", host: "eren-macbook-pro.local:4747"))
        #expect(!WebSocketOrigin.isAllowed(origin: "null", host: "eren-macbook-pro.local:4747"))
        #expect(!WebSocketOrigin.isAllowed(origin: "http://eren-macbook-pro.local:4747", host: nil))
    }

    @Test func letsNonBrowserClientsWithoutAnOriginThrough() {
        #expect(WebSocketOrigin.isAllowed(origin: nil, host: "eren-macbook-pro.local:4747"))
        #expect(WebSocketOrigin.isAllowed(origin: nil, host: nil))
    }

    @Test func forbiddenIsA403() {
        #expect(String(decoding: HTTPResponse.forbidden, as: UTF8.self).hasPrefix("HTTP/1.1 403 Forbidden\r\n"))
    }
}
```

- [ ] **Step 2: Testlerin derlenmediğini gör**

Run: `make test FILTER="WebSocketOriginTests"` → Expected: derleme hatası (`WebSocketOrigin` yok).

- [ ] **Step 3: Origin kuralı ve 403**

`Sources/PhoneBoxCore/HTTP.swift`:

Bul (1/2):

```swift
        return .complete(HTTPRequestHead(method: String(parts[0]), path: path, headers: headers))
    }
```

Şununla değiştir:

```swift
        return .complete(HTTPRequestHead(method: String(parts[0]), path: path, headers: headers))
    }
}

/// Design §5: browsers always send `Origin` with a WebSocket upgrade. Only the dashboard's own page, loaded from
/// the address the phone used, may connect; a page from another site cannot reach the Mac through the browser.
public enum WebSocketOrigin {
    public static func isAllowed(origin: String?, host: String?) -> Bool {
        guard let origin else { return true }  // not a browser: every page sends Origin
        guard let host, !host.isEmpty else { return false }
        return origin.caseInsensitiveCompare("http://" + host) == .orderedSame
    }
```

Bul (2/2):

```swift
    public static let badRequest = make(status: "400 Bad Request", contentType: "text/plain", body: Data("bad request".utf8))
    public static let busy = make(status: "503 Service Unavailable", contentType: "text/plain", body: Data("too many phones".utf8))
```

Şununla değiştir:

```swift
    public static let badRequest = make(status: "400 Bad Request", contentType: "text/plain", body: Data("bad request".utf8))
    public static let forbidden = make(status: "403 Forbidden", contentType: "text/plain", body: Data("forbidden".utf8))
    public static let busy = make(status: "503 Service Unavailable", contentType: "text/plain", body: Data("too many phones".utf8))
```

`Sources/PhoneBox/ClientConnection.swift`:

Bul:

```swift
            else { return respond(HTTPResponse.badRequest) }
            guard let hub, hub.canAccept else { return respond(HTTPResponse.busy) }
```

Şununla değiştir:

```swift
            else { return respond(HTTPResponse.badRequest) }
            guard WebSocketOrigin.isAllowed(origin: request.headers["origin"], host: request.headers["host"]) else {
                Log.server.notice("Refusing a WebSocket from another site")
                return respond(HTTPResponse.forbidden)
            }
            guard let hub, hub.canAccept else { return respond(HTTPResponse.busy) }
```

- [ ] **Step 4: Testleri çalıştır**

Run: `make test FILTER="WebSocketOriginTests"` → Expected: 4 test geçer.
Run: `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"` → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 120 tests in 22 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/PhoneBoxCore/HTTP.swift Sources/PhoneBox/ClientConnection.swift Tests/PhoneBoxCoreTests/HTTPTests.swift
git commit -m "Refuse WebSocket connections from other sites"
```

---

### Task 4: Snapshot'a çalan şarkı ve ses; adaptör satırlarının çözümü

**Files:**
- Create: `Sources/PhoneBoxCore/Media.swift`, `Tests/PhoneBoxCoreTests/MediaTests.swift`
- Modify: `Sources/PhoneBoxCore/Snapshot.swift`, `Sources/PhoneBoxCore/Messages.swift`, `Tests/PhoneBoxCoreTests/MessagesTests.swift`

**Interfaces:**
- Consumes: `AppUsage.displayName(_:)`, `AppUsage.maxNameLength`, `JSONValue`, `Command.maxBundleIdLength`.
- Produces: `MediaSample(title:artist:app:playing:)`, `AudioSample(volume:muted:)`, `Snapshot(... media:audio:)`;
  `NowPlayingTrack(title:artist:bundleId:playing:)`; `NowPlayingStream.parse(_:) -> NowPlayingStream.Line`
  (`.track`, `.nothing`, `.invalid`); `LineAssembler` (`append(_ data: Data) -> [String]`, `reset()`,
  `maxLineBytes = 65536`); `NowPlayingState` (`received(_:at:)`, `current(at:) -> NowPlayingTrack?`, `clear()`,
  `grace = 1.5`).

- [ ] **Step 1: Testleri yaz**

`Tests/PhoneBoxCoreTests/MediaTests.swift`:

```swift
import Foundation
import Testing
@testable import PhoneBoxCore

struct NowPlayingStreamTests {
    /// Recorded from the adapter on macOS 27.2 (`stream --no-diff --no-artwork`), a paused YouTube video in Chrome.
    let chromeLine = #"{"type":"data","diff":false,"payload":{"artist":"Cem Yılmaz","playbackRate":0,"contentItemIdentifier":"254D6129-F85E-4520-9722-B17D9980417B","title":"Masaj | Cem Yılmaz : Diamond Elite Platinum Plus","elapsedTime":2.0565129999999998,"duration":86.741,"playing":false,"bundleIdentifier":"com.google.Chrome","album":"","processIdentifier":24929,"timestamp":"2026-11-25T19:03:59Z"}}"#

    @Test func parsesARealLine() {
        #expect(NowPlayingStream.parse(chromeLine) == .track(NowPlayingTrack(
            title: "Masaj | Cem Yılmaz : Diamond Elite Platinum Plus", artist: "Cem Yılmaz", bundleId: "com.google.Chrome",
            playing: false)))
    }

    @Test func anEmptyPayloadMeansNothingIsPlaying() {
        #expect(NowPlayingStream.parse(#"{"type":"data","diff":false,"payload":{}}"#) == .nothing)
        #expect(NowPlayingStream.parse(#"{"type":"data","diff":false,"payload":{"title":"","bundleIdentifier":"a"}}"#) == .nothing)
        #expect(NowPlayingStream.parse(#"{"type":"data","diff":false,"payload":{"title":"x"}}"#) == .nothing)
    }

    @Test func prefersTheParentAppAndAcceptsANumericPlayingFlag() {
        let line = #"{"type":"data","payload":{"title":"Song","bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari","playing":1}}"#
        #expect(NowPlayingStream.parse(line) == .track(NowPlayingTrack(title: "Song", artist: nil, bundleId: "com.apple.Safari", playing: true)))
    }

    @Test func cleansAndCapsTheText() {
        let long = String(repeating: "ş", count: 200)
        let line = #"{"type":"data","payload":{"title":"‎\#(long)","artist":"  ","bundleIdentifier":"com.spotify.client","playing":true}}"#
        guard case let .track(track) = NowPlayingStream.parse(line) else { Issue.record("no track"); return }
        #expect(track.title == String(repeating: "ş", count: AppUsage.maxNameLength))
        #expect(track.artist == nil)
    }

    @Test func rejectsOtherLines() {
        #expect(NowPlayingStream.parse("") == .invalid)
        #expect(NowPlayingStream.parse("not json") == .invalid)
        #expect(NowPlayingStream.parse(#"{"type":"error","payload":{}}"#) == .invalid)
    }
}

struct LineAssemblerTests {
    @Test func joinsChunksThatEndAnywhere() {
        var assembler = LineAssembler()
        let bytes = Array("{\"a\":\"ğ\"}\n{\"b\":1}\n".utf8)
        let split = 6  // inside the two-byte "ğ"
        #expect(assembler.append(Data(bytes[..<split])) == [])
        #expect(assembler.append(Data(bytes[split...])) == [#"{"a":"ğ"}"#, #"{"b":1}"#])
    }

    @Test func dropsAnOverlongLine() {
        var assembler = LineAssembler()
        #expect(assembler.append(Data(repeating: 0x61, count: LineAssembler.maxLineBytes + 1)) == [])
        #expect(assembler.append(Data("ok\n".utf8)) == ["ok"])
    }
}

struct NowPlayingStateTests {
    let start = Date(timeIntervalSince1970: 1_000)
    let song = NowPlayingTrack(title: "A", artist: nil, bundleId: "com.spotify.client", playing: true)
    let next = NowPlayingTrack(title: "B", artist: nil, bundleId: "com.spotify.client", playing: true)

    @Test func keepsTheTrackThroughTheGapBetweenTwoTracks() {
        var state = NowPlayingState()
        state.received(.track(song), at: start)
        state.received(.nothing, at: start.addingTimeInterval(1))
        #expect(state.current(at: start.addingTimeInterval(2)) == song)
        state.received(.track(next), at: start.addingTimeInterval(2.2))
        #expect(state.current(at: start.addingTimeInterval(5)) == next)
    }

    @Test func nothingPlayingAppliesAfterTheGrace() {
        var state = NowPlayingState()
        state.received(.track(song), at: start)
        state.received(.nothing, at: start.addingTimeInterval(1))
        state.received(.nothing, at: start.addingTimeInterval(2))  // a repeat does not push the deadline back
        #expect(state.current(at: start.addingTimeInterval(2.5)) == nil)
    }

    @Test func ignoresInvalidLinesAndClears() {
        var state = NowPlayingState()
        #expect(state.current(at: start) == nil)
        state.received(.nothing, at: start)
        state.received(.track(song), at: start)
        state.received(.invalid, at: start.addingTimeInterval(10))
        #expect(state.current(at: start.addingTimeInterval(10)) == song)
        state.clear()
        #expect(state.current(at: start.addingTimeInterval(10)) == nil)
    }
}
```

`Tests/PhoneBoxCoreTests/MessagesTests.swift`:

Bul:

```swift
            + #""type":"snapshot","v":1}"#)
    }
```

Şununla değiştir:

```swift
            + #""type":"snapshot","v":1}"#)
    }

    @Test func encodesMediaAndAudio() {
        let snapshot = Snapshot(t: 9, media: MediaSample(title: "Kara Toprak", artist: nil, app: "Spotify", playing: true),
                                audio: AudioSample(volume: 0.5, muted: false))
        #expect(ServerMessage.snapshot(snapshot).json()
            == #"{"audio":{"muted":false,"volume":0.5},"media":{"app":"Spotify","playing":true,"title":"Kara Toprak"},"t":9,"type":"snapshot","v":1}"#)
    }
```

- [ ] **Step 2: Testlerin derlenmediğini gör**

Run: `make test FILTER="NowPlayingStreamTests|LineAssemblerTests|NowPlayingStateTests|ServerMessageTests"` → Expected:
derleme hatası (`MediaSample`, `NowPlayingStream` yok).

- [ ] **Step 3: Modeller ve çözümleyiciler**

`Sources/PhoneBoxCore/Media.swift`:

```swift
import Foundation

/// What the Mac is playing (design §6). Left out of the snapshot when nothing is.
public struct MediaSample: Equatable, Codable, Sendable {
    public var title: String
    public var artist: String?
    /// The player's name, e.g. "Spotify" or "Google Chrome".
    public var app: String
    public var playing: Bool
    public init(title: String, artist: String?, app: String, playing: Bool) {
        self.title = title
        self.artist = artist
        self.app = app
        self.playing = playing
    }
}

/// The default output's volume (design §6). Left out when the output has no volume control.
public struct AudioSample: Equatable, Codable, Sendable {
    /// 0…1
    public var volume: Double
    public var muted: Bool
    public init(volume: Double, muted: Bool) {
        self.volume = volume
        self.muted = muted
    }
}

/// One track as mediaremote-adapter reports it, before the player's bundle identifier becomes a name.
public struct NowPlayingTrack: Equatable, Sendable {
    public var title: String
    public var artist: String?
    /// The player, or its parent app for a helper (a browser for a web player).
    public var bundleId: String
    public var playing: Bool
    public init(title: String, artist: String?, bundleId: String, playing: Bool) {
        self.title = title
        self.artist = artist
        self.bundleId = bundleId
        self.playing = playing
    }
}

/// Lines of `mediaremote-adapter.pl <framework> stream --no-diff --no-artwork`:
/// `{"type":"data","diff":false,"payload":{…}}`, where an empty payload means nothing is playing. Titles and
/// artists come from any app, so they get the same cleaning and length cap as app names.
public enum NowPlayingStream {
    public enum Line: Equatable, Sendable {
        case track(NowPlayingTrack)
        case nothing
        case invalid
    }

    public static func parse(_ line: String) -> Line {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              object["type"] as? String == "data"
        else { return .invalid }
        guard let payload = object["payload"] as? [String: Any],
              let title = (payload["title"] as? String).map(AppUsage.displayName), !title.isEmpty,
              let bundleId = nonEmpty(payload["parentApplicationBundleIdentifier"]) ?? nonEmpty(payload["bundleIdentifier"])
        else { return .nothing }
        let artist = (payload["artist"] as? String).map(AppUsage.displayName).flatMap { $0.isEmpty ? nil : $0 }
        let playing = JSONValue.bool(payload["playing"]) ?? JSONValue.integer(payload["playing"]).map { $0 != 0 } ?? false
        return .track(NowPlayingTrack(title: title, artist: artist, bundleId: bundleId, playing: playing))
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty, text.utf8.count <= Command.maxBundleIdLength else { return nil }
        return text
    }
}

/// Turns the adapter's stdout chunks into lines; a chunk may end anywhere, even inside a UTF-8 character.
public struct LineAssembler: Sendable {
    /// Without artwork a line is a few hundred bytes; this much without a newline means the stream is junk.
    public static let maxLineBytes = 64 * 1024
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        if buffer.count > Self.maxLineBytes { buffer.removeAll() }
        return lines
    }

    public mutating func reset() {
        buffer.removeAll()
    }
}

/// The track to show. Between two tracks the adapter briefly reports nothing playing; keeping the last track for
/// `grace` seconds stops the phone's card from blinking (NotchBox saw the same gap).
public struct NowPlayingState: Sendable {
    public static let grace: TimeInterval = 1.5
    private var track: NowPlayingTrack?
    private var nothingSince: Date?

    public init() {}

    public mutating func received(_ line: NowPlayingStream.Line, at now: Date) {
        switch line {
        case let .track(track):
            self.track = track
            nothingSince = nil
        case .nothing:
            if track != nil, nothingSince == nil { nothingSince = now }
        case .invalid:
            break
        }
    }

    public func current(at now: Date) -> NowPlayingTrack? {
        if let nothingSince, now.timeIntervalSince(nothingSince) >= Self.grace { return nil }
        return track
    }

    /// The adapter stopped or restarted: forget everything.
    public mutating func clear() {
        track = nil
        nothingSince = nil
    }
}
```

`Sources/PhoneBoxCore/Snapshot.swift`:

Bul (1/4):

```swift
/// One second of the Mac, as the phone receives it (design §6). A metric that could not be read is left out
/// of the JSON; the dashboard shows "—" for it. `apps` is sent every third second.
public struct Snapshot: Equatable, Codable, Sendable {
```

Şununla değiştir:

```swift
/// One second of the Mac, as the phone receives it (design §6). A metric that could not be read is left out
/// of the JSON; the dashboard shows "—" for it. `apps` is sent every third second; `media` only while something
/// is playing (or paused) and `audio` only for an output with volume control.
public struct Snapshot: Equatable, Codable, Sendable {
```

Bul (2/4):

```swift
    public var apps: [AppSample]?

    public init(t: Int64, cpu: CPUSample? = nil, mem: MemorySample? = nil, gpu: GPUSample? = nil,
```

Şununla değiştir:

```swift
    public var apps: [AppSample]?
    public var media: MediaSample?
    public var audio: AudioSample?

    public init(t: Int64, cpu: CPUSample? = nil, mem: MemorySample? = nil, gpu: GPUSample? = nil,
```

Bul (3/4):

```swift
                temp: TemperatureSample? = nil, power: PowerSample? = nil, net: NetworkSample? = nil,
                disk: DiskSample? = nil, battery: BatterySample? = nil, apps: [AppSample]? = nil) {
        self.t = t
```

Şununla değiştir:

```swift
                temp: TemperatureSample? = nil, power: PowerSample? = nil, net: NetworkSample? = nil,
                disk: DiskSample? = nil, battery: BatterySample? = nil, apps: [AppSample]? = nil,
                media: MediaSample? = nil, audio: AudioSample? = nil) {
        self.t = t
```

Bul (4/4):

```swift
        self.apps = apps
    }
```

Şununla değiştir:

```swift
        self.apps = apps
        self.media = media
        self.audio = audio
    }
```

`Sources/PhoneBoxCore/Messages.swift`:

Bul (1/2):

```swift
        case v, type, nonce, app, mode, host, access, streaming, commands, cable, reason, t, cpu, mem, gpu, temp, power, net, disk,
             battery, apps, seq, ok, error
    }
```

Şununla değiştir:

```swift
        case v, type, nonce, app, mode, host, access, streaming, commands, cable, reason, t, cpu, mem, gpu, temp, power, net, disk,
             battery, apps, media, audio, seq, ok, error
    }
```

Bul (2/2):

```swift
            try container.encodeIfPresent(snapshot.apps, forKey: .apps)
        case let .ack(seq, ok, error):
```

Şununla değiştir:

```swift
            try container.encodeIfPresent(snapshot.apps, forKey: .apps)
            try container.encodeIfPresent(snapshot.media, forKey: .media)
            try container.encodeIfPresent(snapshot.audio, forKey: .audio)
        case let .ack(seq, ok, error):
```

- [ ] **Step 4: Testleri çalıştır**

Run: `make test FILTER="NowPlayingStreamTests|LineAssemblerTests|NowPlayingStateTests|ServerMessageTests"` → Expected: geçer.
Run: `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"` → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 131 tests in 25 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/PhoneBoxCore/Media.swift Sources/PhoneBoxCore/Snapshot.swift Sources/PhoneBoxCore/Messages.swift \
  Tests/PhoneBoxCoreTests/MediaTests.swift Tests/PhoneBoxCoreTests/MessagesTests.swift
git commit -m "Add now playing and volume to the snapshot"
```

---

### Task 5: Bağlantı yöneticisi testlerle; komutlar çalıştırıcıya gider

**Files:**
- Modify: `Package.swift` (dosyanın tamamı), `Sources/PhoneBox/DashboardHub.swift` (dosyanın tamamı)
- Create: `Sources/PhoneBox/CommandRunner.swift` (geçici: her komuta `unsupported`; Görev 8 doldurur)
- Modify: `Sources/PhoneBox/ClientConnection.swift`, `Sources/PhoneBox/AppDelegate.swift`
- Create: `Tests/PhoneBoxTests/DashboardHubTests.swift`

**Interfaces:**
- Consumes: Görev 1–4'ün `Access`, `Session.Outcome.command(seq:command:)`, `ServerMessage.ack(seq:result:)`,
  `Command.name`.
- Produces:
  - `@MainActor protocol PhoneConnection: AnyObject`: `interfaceName`, `arrivedOnScopedLinkLocal`, `lastInboundAt`,
    `send(_:)`, `sendPing()`, `markAuthenticated()`, `close(code:reason:)`, `cancel()`. `ClientConnection` uyar.
  - `@MainActor protocol CommandRunning: AnyObject`: `run(_ command: Command, completion: @escaping @MainActor
    (CommandResult) -> Void)`.
  - `DashboardHub.init(mode:key:appName:hostName:commands:usbInterfaces:)`; `opened/received/closed` artık
    `any PhoneConnection` alır; `onConnectionClosed: ((any PhoneConnection) -> Void)?`.
  - `final class CommandRunner: CommandRunning` (`init()`).
  - Test hedefi `PhoneBoxTests` (`@testable import PhoneBox`).

- [ ] **Step 1: Test hedefi ve testler**

`Package.swift`:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PhoneBox",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic with no system calls: protocol, signatures, access rules, metric maths. Tested.
        .target(name: "PhoneBoxCore"),
        // The menu bar app: everything that talks to macOS.
        .executableTarget(name: "PhoneBox", dependencies: ["PhoneBoxCore"]),
        .testTarget(name: "PhoneBoxCoreTests", dependencies: ["PhoneBoxCore"]),
        .testTarget(name: "PhoneBoxTests", dependencies: ["PhoneBox"]),
    ],
    swiftLanguageModes: [.v5]
)
```

`Tests/PhoneBoxTests/DashboardHubTests.swift`:

```swift
import Foundation
import Testing
@testable import PhoneBox
import PhoneBoxCore

/// A phone's WebSocket that only records what the hub does with it.
@MainActor
final class FakeConnection: PhoneConnection {
    let interfaceName: String?
    let arrivedOnScopedLinkLocal: Bool
    var lastInboundAt = Date()
    private(set) var sent: [ServerMessage] = []
    private(set) var closeCode: UInt16?
    private(set) var authenticated = false

    init(interfaceName: String, scopedLinkLocal: Bool) {
        self.interfaceName = interfaceName
        self.arrivedOnScopedLinkLocal = scopedLinkLocal
    }

    func send(_ message: ServerMessage) { sent.append(message) }
    func sendPing() {}
    func markAuthenticated() { authenticated = true }
    func close(code: UInt16, reason: String) { closeCode = code }
    func cancel() {}

    var nonce: String? {
        for case let .hello(nonce, _) in sent { return nonce }
        return nil
    }
}

/// Records the commands and answers with `result`; with `hold`, keeps the completions for the test to call.
@MainActor
final class FakeRunner: CommandRunning {
    var result: CommandResult = .ok
    var hold = false
    private(set) var commands: [Command] = []
    private(set) var pending: [@MainActor (CommandResult) -> Void] = []

    func run(_ command: Command, completion: @escaping @MainActor (CommandResult) -> Void) {
        commands.append(command)
        if hold { pending.append(completion) } else { completion(result) }
    }
}

@MainActor
struct DashboardHubTests {
    let key = PairingKey.generate()
    let runner = FakeRunner()

    func makeHub(mode: AccessMode) -> DashboardHub {
        DashboardHub(mode: mode, key: key, appName: "PhoneBox test", hostName: "Test Mac", commands: runner,
                     usbInterfaces: { ["anri1"] })
    }

    /// A phone on the USB link (`anri1`, scoped link-local) or on Wi-Fi (`en0`), authenticated.
    func connect(_ hub: DashboardHub, onUSB: Bool) -> FakeConnection {
        let phone = onUSB ? FakeConnection(interfaceName: "anri1", scopedLinkLocal: true)
                          : FakeConnection(interfaceName: "en0", scopedLinkLocal: true)
        hub.opened(phone)
        let mac = MessageAuth.hmacHex(key: key.bytes, message: MessageAuth.authMessage(nonce: phone.nonce ?? ""))
        hub.received(#"{"v":1,"type":"auth","mac":"\#(mac)"}"#, from: phone)
        return phone
    }

    func command(_ phone: FakeConnection, seq: Int, name: String, args: String) -> String {
        let mac = MessageAuth.hmacHex(key: key.bytes, message: MessageAuth.commandMessage(
            nonce: phone.nonce ?? "", seq: seq, name: name, args: args))
        let escaped = args.replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"v":1,"type":"cmd","seq":\#(seq),"name":"\#(name)","args":"\#(escaped)","mac":"\#(mac)"}"#
    }

    @Test func readyCarriesTheMacsNameAndTheConnectionPath() {
        let hub = makeHub(mode: .always)
        let cable = connect(hub, onUSB: true)
        let wifi = connect(hub, onUSB: false)
        #expect(cable.authenticated && wifi.authenticated)
        #expect(cable.sent.last == .ready(mode: .always, host: "Test Mac", access: .onCable))
        #expect(wifi.sent.last == .ready(mode: .always, host: "Test Mac", access: .overWiFi))
    }

    @Test func runsACommandFromTheCableAndAcksIt() {
        let hub = makeHub(mode: .cable)
        let phone = connect(hub, onUSB: true)
        hub.received(command(phone, seq: 1, name: "mute", args: #"{"on":true}"#), from: phone)
        #expect(runner.commands == [.mute(on: true)])
        #expect(phone.sent.last == .ack(seq: 1, ok: true, error: nil))
    }

    @Test func refusesCommandsOverWiFiEvenInAlwaysMode() {
        let hub = makeHub(mode: .always)
        let phone = connect(hub, onUSB: false)
        hub.received(command(phone, seq: 1, name: "sleep", args: "{}"), from: phone)
        #expect(runner.commands.isEmpty)
        #expect(phone.sent.last == .ack(seq: 1, ok: false, error: "not-allowed"))
    }

    @Test func aScopedAddressOnAnotherInterfaceIsNotTheCable() {
        let hub = makeHub(mode: .always)
        let phone = FakeConnection(interfaceName: "anri1", scopedLinkLocal: false)  // IPv4 on the USB link
        hub.opened(phone)
        let mac = MessageAuth.hmacHex(key: key.bytes, message: MessageAuth.authMessage(nonce: phone.nonce ?? ""))
        hub.received(#"{"v":1,"type":"auth","mac":"\#(mac)"}"#, from: phone)
        #expect(phone.sent.last == .ready(mode: .always, host: "Test Mac", access: .overWiFi))
    }

    @Test func reportsWhyACommandFailed() {
        let hub = makeHub(mode: .cable)
        let phone = connect(hub, onUSB: true)
        runner.result = .failed(.appChanged)
        hub.received(command(phone, seq: 3, name: "quitApp", args: #"{"bundleId":"com.example.Gone","force":false}"#), from: phone)
        #expect(runner.commands == [.quitApp(bundleId: "com.example.Gone", force: false)])
        #expect(phone.sent.last == .ack(seq: 3, ok: false, error: "app-changed"))
    }

    @Test func neverRunsUnknownOrMalformedCommands() {
        let hub = makeHub(mode: .cable)
        let phone = connect(hub, onUSB: true)
        hub.received(command(phone, seq: 1, name: "shutdown", args: "{}"), from: phone)
        hub.received(command(phone, seq: 2, name: "volume", args: #"{"level":"loud"}"#), from: phone)
        #expect(runner.commands.isEmpty)
        #expect(phone.sent.suffix(2) == [.ack(seq: 1, ok: false, error: "unsupported"), .ack(seq: 2, ok: false, error: "unsupported")])
    }

    @Test func dropsTheAckWhenThePhoneLeftWhileTheCommandRan() {
        let hub = makeHub(mode: .cable)
        let phone = connect(hub, onUSB: true)
        runner.hold = true
        hub.received(command(phone, seq: 1, name: "lock", args: "{}"), from: phone)
        let before = phone.sent.count
        hub.closed(phone)
        runner.pending.first?(.ok)
        #expect(phone.sent.count == before)
    }

    @Test func switchingModesSendsTheNewAccess() {
        let hub = makeHub(mode: .cable)
        var streaming: [Bool] = []
        hub.onStreamingChange = { streaming.append($0) }
        let phone = connect(hub, onUSB: false)
        #expect(phone.sent.last == .ready(mode: .cable, host: "Test Mac", access: .notOnCable))
        hub.mode = .always
        #expect(phone.sent.last == .access(.overWiFi))
        #expect(streaming == [true])
    }

    @Test func aBadSignatureClosesTheConnection() {
        let hub = makeHub(mode: .cable)
        let phone = connect(hub, onUSB: true)
        let forged = command(phone, seq: 1, name: "mute", args: #"{"on":true}"#).replacingOccurrences(of: "mute", with: "lock")
        hub.received(forged, from: phone)
        #expect(phone.closeCode == Session.policyViolationCode)
        #expect(runner.commands.isEmpty)
    }
}
```

- [ ] **Step 2: Testlerin derlenmediğini gör**

Run: `make test FILTER="DashboardHubTests"` → Expected: derleme hatası (`PhoneConnection`, `CommandRunning` yok;
`DashboardHub.init`'te `commands` yok).

- [ ] **Step 3: Bağlantı yöneticisi**

`Sources/PhoneBox/DashboardHub.swift`:

```swift
import Foundation
import PhoneBoxCore

/// What the hub needs from one phone's WebSocket: `ClientConnection` in the app, a fake in the tests.
@MainActor
protocol PhoneConnection: AnyObject {
    /// The network interface the connection arrived on, e.g. `en8` (the iPhone's USB link) or `en0` (Wi-Fi).
    var interfaceName: String? { get }
    /// True when the local end is a scoped IPv6 link-local address, which is how the iPhone's USB link looks.
    var arrivedOnScopedLinkLocal: Bool { get }
    /// When the last frame of any kind arrived.
    var lastInboundAt: Date { get }
    func send(_ message: ServerMessage)
    func sendPing()
    func markAuthenticated()
    func close(code: UInt16, reason: String)
    func cancel()
}

/// Runs a command on the Mac (design §7): `CommandRunner` in the app, a fake in the tests. `completion` is
/// called once, on the main actor.
@MainActor
protocol CommandRunning: AnyObject {
    func run(_ command: Command, completion: @escaping @MainActor (CommandResult) -> Void)
}

/// Keeps track of the phones connected over WebSocket (design §5): the protocol session of each, whether it
/// came in over the iPhone's USB link, what it may do, who gets the snapshots, and the commands they send.
@MainActor
final class DashboardHub {
    static let maxClients = 4
    static let authTimeout: TimeInterval = 5
    /// Close code that tells the page to reconnect at once (to come back over the cable).
    static let reconnectCode: UInt16 = 4002
    /// Seconds between liveness pings, and how long a phone may stay silent before it is dropped.
    static let pingInterval: TimeInterval = 15
    static let silenceLimit: TimeInterval = 45

    private struct Client {
        let connection: any PhoneConnection
        var session: Session
        let onUSB: Bool
        var access: Access
    }

    var mode: AccessMode {
        didSet { if mode != oldValue { refreshAccess() } }
    }
    private var key: PairingKey
    private let appName: String
    /// The Mac's name, shown in the page's status line.
    private let hostName: String
    private let commands: any CommandRunning
    private let usbInterfaces: () -> Set<String>
    private var clients: [ObjectIdentifier: Client] = [:]
    private var livenessTimer: Timer?

    /// True while at least one phone may receive snapshots: the sampler runs only then.
    var onStreamingChange: ((Bool) -> Void)?
    /// Counts for the menu bar: phones receiving data, phones waiting for the cable.
    var onClientsChange: ((_ streaming: Int, _ waitingForCable: Int) -> Void)?
    /// A phone authenticated for the first time with this key.
    var onAuthenticated: (() -> Void)?
    var onConnectionClosed: ((any PhoneConnection) -> Void)?

    init(mode: AccessMode, key: PairingKey, appName: String, hostName: String, commands: any CommandRunning,
         usbInterfaces: @escaping () -> Set<String> = USBLinks.iPhoneInterfaceNames) {
        self.mode = mode
        self.key = key
        self.appName = appName
        self.hostName = hostName
        self.commands = commands
        self.usbInterfaces = usbInterfaces
        let timer = Timer(timeInterval: Self.pingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkLiveness() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        livenessTimer = timer
    }

    /// Pings every authenticated phone and drops the ones that have been silent for too long.
    private func checkLiveness() {
        let now = Date()
        for client in clients.values where client.session.isAuthenticated {
            if now.timeIntervalSince(client.connection.lastInboundAt) > Self.silenceLimit {
                Log.server.notice("Dropping a silent phone")
                client.connection.cancel()
            } else {
                client.connection.sendPing()
            }
        }
    }

    /// Cancels USB phones whose interface is gone (the cable was unplugged).
    func dropVanishedUSBClients() {
        let present = usbInterfaces()
        for client in clients.values where client.session.isAuthenticated && client.onUSB {
            guard let name = client.connection.interfaceName, present.contains(name) else {
                Log.server.notice("Dropping a phone whose USB link is gone")
                client.connection.cancel()
                continue
            }
        }
    }

    var canAccept: Bool { clients.count < Self.maxClients }
    private var isStreaming: Bool { clients.values.contains { $0.access.streaming } }

    func opened(_ connection: any PhoneConnection) {
        let onUSB = connection.arrivedOnScopedLinkLocal && (connection.interfaceName.map(usbInterfaces().contains) ?? false)
        let session = Session(nonce: Session.makeNonce())
        clients[ObjectIdentifier(connection)] = Client(connection: connection, session: session, onUSB: onUSB, access: .unauthenticated)
        Log.server.info("Phone connected on \(connection.interfaceName ?? "?", privacy: .public) (scoped link-local: \(connection.arrivedOnScopedLinkLocal), USB: \(onUSB))")
        connection.send(.hello(nonce: session.nonce, app: appName))
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.authTimeout) { [weak self, weak connection] in
            MainActor.assumeIsolated {
                guard let self, let connection, let client = self.clients[ObjectIdentifier(connection)],
                      !client.session.isAuthenticated
                else { return }
                connection.close(code: Session.authTimeoutCode, reason: "no auth")
            }
        }
    }

    func received(_ text: String, from connection: any PhoneConnection) {
        let id = ObjectIdentifier(connection)
        guard var client = clients[id] else { return }
        let outcome = client.session.receive(text, key: key, commandsAllowed: client.access.commands, now: Date())
        clients[id] = client
        switch outcome {
        case .authenticated:
            let wasStreaming = isStreaming
            connection.markAuthenticated()
            client.access = AccessPolicy.decide(mode: mode, clientOnUSB: client.onUSB, authenticated: true)
            clients[id] = client
            connection.send(.ready(mode: mode, host: hostName, access: client.access))
            onAuthenticated?()
            changed(wasStreaming: wasStreaming)
        case let .command(seq, command):
            Log.server.info("Running \(command.name, privacy: .public) from the phone")
            commands.run(command) { [weak self, weak connection] result in
                // The phone may have gone (or been dropped) while the command ran.
                guard let self, let connection, self.clients[ObjectIdentifier(connection)] != nil else { return }
                if case let .failed(failure) = result {
                    Log.server.notice("\(command.name, privacy: .public) failed: \(failure.rawValue, privacy: .public)")
                }
                connection.send(.ack(seq: seq, result: result))
            }
        case let .reply(message):
            connection.send(message)
        case let .close(code, reason):
            Log.server.notice("Closing a phone: \(reason, privacy: .public)")
            connection.close(code: code, reason: reason)
        }
    }

    func closed(_ connection: any PhoneConnection) {
        let wasStreaming = isStreaming
        if clients.removeValue(forKey: ObjectIdentifier(connection)) != nil {
            changed(wasStreaming: wasStreaming)
        }
        onConnectionClosed?(connection)
    }

    func broadcast(_ snapshot: Snapshot) {
        let message = ServerMessage.snapshot(snapshot)
        for client in clients.values where client.access.streaming {
            client.connection.send(message)
        }
    }

    /// A new pairing key: every phone has to scan the new QR code.
    func replaceKey(_ newKey: PairingKey) {
        key = newKey
        for client in clients.values {
            client.connection.close(code: Session.authFailedCode, reason: "pairing reset")
        }
    }

    /// An iPhone was just plugged in. In cable mode, phones that are connected over Wi-Fi are asked to
    /// reconnect so that they come back over the cable.
    func iPhonePluggedIn() {
        guard mode == .cable, !usbInterfaces().isEmpty else { return }
        for client in clients.values where client.session.isAuthenticated && !client.onUSB {
            client.connection.close(code: Self.reconnectCode, reason: "use the cable")
        }
    }

    private func refreshAccess() {
        let wasStreaming = isStreaming
        for (id, var client) in clients where client.session.isAuthenticated {
            let access = AccessPolicy.decide(mode: mode, clientOnUSB: client.onUSB, authenticated: true)
            guard access != client.access else { continue }
            client.access = access
            clients[id] = client
            client.connection.send(.access(access))
        }
        changed(wasStreaming: wasStreaming)
    }

    private func changed(wasStreaming: Bool) {
        if isStreaming != wasStreaming { onStreamingChange?(isStreaming) }
        let streaming = clients.values.filter { $0.access.streaming }.count
        let waiting = clients.values.filter { $0.access.reason == Access.notOnCable.reason }.count
        onClientsChange?(streaming, waiting)
    }
}
```

`Sources/PhoneBox/CommandRunner.swift`:

```swift
import Foundation
import PhoneBoxCore

/// Runs the phone's commands on the Mac (design §7). The commands themselves arrive in a later task; until then
/// every signed, allowed command is answered `unsupported` and nothing runs.
@MainActor
final class CommandRunner: CommandRunning {
    func run(_ command: Command, completion: @escaping @MainActor (CommandResult) -> Void) {
        completion(.failed(.unsupported))
    }
}
```

`Sources/PhoneBox/ClientConnection.swift`:

Dosyanın sonuna ekle:

```swift
extension ClientConnection: PhoneConnection {}
```

`Sources/PhoneBox/AppDelegate.swift`:

Bul (1/2):

```swift
    private let qrWindow = QRWindowController()
    private let loaded = PairingStore.loadOrCreate()
```

Şununla değiştir:

```swift
    private let qrWindow = QRWindowController()
    private let commandRunner = CommandRunner()
    private let loaded = PairingStore.loadOrCreate()
```

Bul (2/2):

```swift
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        hub = DashboardHub(mode: settings.mode, key: key, appName: "PhoneBox \(version)", hostName: Settings.computerName())
        let webDirectory = Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true)
```

Şununla değiştir:

```swift
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        hub = DashboardHub(mode: settings.mode, key: key, appName: "PhoneBox \(version)", hostName: Settings.computerName(),
                           commands: commandRunner)
        let webDirectory = Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true)
```

- [ ] **Step 4: Testleri çalıştır**

Run: `make test FILTER="DashboardHubTests"` → Expected: 9 test geçer.
Run: `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"` → Expected: çıktı yok.
Run: `make test` → Expected: iki satır: `Test run with 9 tests in 1 suite passed` ve
`Test run with 131 tests in 25 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/PhoneBox/DashboardHub.swift Sources/PhoneBox/CommandRunner.swift \
  Sources/PhoneBox/ClientConnection.swift Sources/PhoneBox/AppDelegate.swift Tests/PhoneBoxTests/DashboardHubTests.swift
git commit -m "Route signed commands through a testable hub"
```

---

### Task 6: Mac'in ses seviyesi ve sessiz durumu

**Files:**
- Create: `Sources/PhoneBox/SystemAudio.swift`, `Sources/PhoneBox/Collectors/AudioCollector.swift`
- Create: `Tests/PhoneBoxTests/SystemAudioLiveTests.swift` (sadece `PHONEBOX_LIVE=1` ile çalışır)
- Modify: `Sources/PhoneBox/Sampler.swift`

**Interfaces:**
- Consumes: `AudioSample`, `Double.finiteOrNil`.
- Produces: `SystemAudio.volume() -> Double?`, `SystemAudio.isMuted() -> Bool?`, `SystemAudio.setVolume(_:) -> Bool`,
  `SystemAudio.setMuted(_:) -> Bool`; `AudioCollector.sample() -> AudioSample?`; snapshot'ta her saniye `audio`.

- [ ] **Step 1: CoreAudio**

`Sources/PhoneBox/SystemAudio.swift`:

```swift
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

    private static func write<Value: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, _ value: Value) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = outputAddress(selector)
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue
        else { return false }
        var value = value
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Value>.size), &value) == noErr
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

    /// False when the output's volume cannot be set.
    static func setVolume(_ level: Double) -> Bool {
        guard level.isFinite else { return false }
        return write(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(min(1, max(0, level))))
    }

    /// False when the output cannot be muted.
    static func setMuted(_ on: Bool) -> Bool {
        write(kAudioDevicePropertyMute, UInt32(on ? 1 : 0))
    }
}
```

`Sources/PhoneBox/Collectors/AudioCollector.swift`:

```swift
import PhoneBoxCore

/// The default output's volume for the page's slider (design §6); nil for an output without volume control.
final class AudioCollector {
    func sample() -> AudioSample? {
        guard let volume = SystemAudio.volume() else { return nil }
        return AudioSample(volume: (volume * 100).rounded() / 100, muted: SystemAudio.isMuted() ?? false)
    }
}
```

`Tests/PhoneBoxTests/SystemAudioLiveTests.swift`:

```swift
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
        #expect(SystemAudio.setVolume(volume))
        let after = try #require(SystemAudio.volume())
        #expect(abs(after - volume) < 0.01)
        let muted = try #require(SystemAudio.isMuted())
        #expect(SystemAudio.setMuted(muted))
        #expect(SystemAudio.isMuted() == muted)
        #expect(AudioCollector().sample() != nil)
    }
}
```

- [ ] **Step 2: Örnekleyiciye ekle**

`Sources/PhoneBox/Sampler.swift`:

Bul (1/2):

```swift
    private let apps = AppsCollector()

    var isRunning: Bool { timer != nil }
```

Şununla değiştir:

```swift
    private let apps = AppsCollector()
    private let audio = AudioCollector()

    var isRunning: Bool { timer != nil }
```

Bul (2/2):

```swift
            power: power.sample(), net: network.sample(), disk: disk.sample(), battery: battery.sample(),
            apps: tickCount % Self.appsEvery == 0 ? apps.sample() : nil))
    }
```

Şununla değiştir:

```swift
            power: power.sample(), net: network.sample(), disk: disk.sample(), battery: battery.sample(),
            apps: tickCount % Self.appsEvery == 0 ? apps.sample() : nil, audio: audio.sample()))
    }
```

- [ ] **Step 3: Derle ve test et**

Run: `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"` → Expected: çıktı yok (`BitwiseCopyable`
kısıtı kalkarsa "forming 'UnsafeMutableRawPointer' …" uyarısı çıkar).
Run: `make test` → Expected: `Test run with 10 tests in 2 suites passed` (canlı test "skipped" yazar) ve
`Test run with 131 tests in 25 suites passed`. `PHONEBOX_LIVE=1` testini çalıştırmayın (Görev 9'da kontrolcü çalıştırır).

- [ ] **Step 4: Commit**

```bash
git add Sources/PhoneBox/SystemAudio.swift Sources/PhoneBox/Collectors/AudioCollector.swift Sources/PhoneBox/Sampler.swift \
  Tests/PhoneBoxTests/SystemAudioLiveTests.swift
git commit -m "Read the Mac's volume and mute"
```

---

### Task 7: Çalan şarkı (mediaremote-adapter)

**Files:**
- Create: alt modül `Vendor/mediaremote-adapter` (`.gitmodules`), `scripts/build-adapter.sh`, `THIRD_PARTY_NOTICES.md`
- Modify: `scripts/bundle.sh` (dosyanın tamamı), `Makefile`
- Create: `Sources/PhoneBox/ShortProcess.swift`, `Sources/PhoneBox/NowPlayingService.swift`
- Modify: `Sources/PhoneBox/Sampler.swift`

**Interfaces:**
- Consumes: `NowPlayingStream`, `LineAssembler`, `NowPlayingState`, `MediaSample`, `CommandResult`, `AppUsage.displayName`.
- Produces: `AdapterLocation.inAppBundle(_:) -> AdapterLocation?`, `AdapterLocation.arguments(_:)`;
  `NowPlayingService(location:)` (`start()`, `stop()`, `current() -> MediaSample?`, `send(_ action:
  Command.MediaAction, completion: @escaping @MainActor (CommandResult) -> Void)`); `ShortProcess.run(_ executable:
  String, _ arguments: [String], timeout: TimeInterval = 5, completion: @escaping @MainActor (Bool) -> Void)`;
  `Sampler.nowPlaying` (örnekleyiciyle başlar ve durur; snapshot'ta `media`).

- [ ] **Step 1: Adaptörü projeye ekle**

```bash
git submodule add https://github.com/ungive/mediaremote-adapter.git Vendor/mediaremote-adapter
git -C Vendor/mediaremote-adapter checkout e3ff502
```

Run: `git -C Vendor/mediaremote-adapter log --oneline -1` → Expected:
`e3ff502 Add --allow-missing-title option for sessions without metadata (#40)`.

`scripts/build-adapter.sh` (sonra `chmod +x scripts/build-adapter.sh`):

```bash
#!/usr/bin/env bash
# Builds MediaRemoteAdapter.framework from the vendored submodule with plain clang (no CMake), as NotchBox does.
# Output (ad-hoc signed): build/adapter/MediaRemoteAdapter.framework (versioned layout).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Vendor/mediaremote-adapter"
OUT="$ROOT/build/adapter"
FW="$OUT/MediaRemoteAdapter.framework"

if [ ! -f "$SRC/bin/mediaremote-adapter.pl" ]; then
  echo "error: adapter sources missing. Run: git submodule update --init" >&2
  exit 1
fi

rm -rf "$FW"
mkdir -p "$FW/Versions/A/Resources"

cd "$SRC"
shopt -s nullglob
# Same source set as ADAPTER_SOURCES in the upstream CMakeLists.txt.
SOURCES=(src/adapter/*.m src/private/*.m src/utility/*.m)
if [ ${#SOURCES[@]} -eq 0 ]; then
  echo "error: no adapter sources found in $SRC/src" >&2
  exit 1
fi

clang -dynamiclib \
  -fobjc-arc -fmodules -fvisibility=default \
  -arch arm64 -mmacosx-version-min=14.0 \
  -Iinclude -Isrc \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name "@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter" \
  -o "$FW/Versions/A/MediaRemoteAdapter" \
  "${SOURCES[@]}"

cat > "$FW/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
  <key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>MediaRemoteAdapter</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
</dict>
</plist>
PLIST

ln -s A "$FW/Versions/Current"
ln -s Versions/Current/MediaRemoteAdapter "$FW/MediaRemoteAdapter"
ln -s Versions/Current/Resources "$FW/Resources"

codesign --force --sign - "$FW"
echo "Built $FW"
```

`scripts/bundle.sh`:

```bash
#!/usr/bin/env bash
# Builds build/PhoneBox.app (release): binary, Info.plist, translations, dashboard files, the keep-awake video and
# mediaremote-adapter (script + framework). Ad-hoc signed, like NotchBox.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/PhoneBox.app"

"$ROOT/scripts/build-adapter.sh"
swift build --package-path "$ROOT" -c release
BIN_DIR="$(swift build --package-path "$ROOT" -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BIN_DIR/PhoneBox" "$APP/Contents/MacOS/PhoneBox"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# Translations go straight into Contents/Resources so that Bundle.main finds them.
ditto "$ROOT/Resources/en.lproj" "$APP/Contents/Resources/en.lproj"
ditto "$ROOT/Resources/tr.lproj" "$APP/Contents/Resources/tr.lproj"
ditto "$ROOT/Resources/web" "$APP/Contents/Resources/web"
cp "$ROOT/Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/mediaremote-adapter.pl"
ditto "$ROOT/build/adapter/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
swiftc -O -suppress-warnings "$ROOT/scripts/make-video.swift" -o "$ROOT/build/make-video"
"$ROOT/build/make-video" "$APP/Contents/Resources/web/keepawake.mp4"

xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
```

`Makefile`:

Bul (1/2):

```
endif

.PHONY: build test app run clean

build:
```

Şununla değiştir:

```
endif

.PHONY: build test adapter app run clean

build:
```

Bul (2/2):

```
	swift test $(TEST_FLAGS) $(if $(FILTER),--filter '$(FILTER)',)

app:
```

Şununla değiştir:

```
	swift test $(TEST_FLAGS) $(if $(FILTER),--filter '$(FILTER)',)

adapter:
	scripts/build-adapter.sh

app:
```

`THIRD_PARTY_NOTICES.md` (lisans metni `Vendor/mediaremote-adapter/LICENSE` ile aynı):

````markdown
# Third-party notices

PhoneBox bundles [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) v0.7.7 (commit `e3ff502`,
vendored as a git submodule in `Vendor/mediaremote-adapter`): the script `mediaremote-adapter.pl` and
`MediaRemoteAdapter.framework`, built by `scripts/build-adapter.sh`. PhoneBox uses it to read what the Mac is
playing and to send play/pause, next and previous.

```text
BSD 3-Clause License

Copyright (c) 2025, Jonas van den Berg and contributors

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
````

- [ ] **Step 2: Kısa süreçler ve çalan şarkı servisi**

`Sources/PhoneBox/ShortProcess.swift`:

```swift
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
```

`Sources/PhoneBox/NowPlayingService.swift`:

```swift
import AppKit
import PhoneBoxCore

/// Where scripts/bundle.sh puts mediaremote-adapter inside PhoneBox.app.
struct AdapterLocation {
    let scriptPath: String
    let frameworkPath: String

    /// Nil when the app was built without the adapter (e.g. `swift run`): then the snapshot has no `media` and
    /// media commands answer `unsupported`.
    static func inAppBundle(_ bundle: Bundle = .main) -> AdapterLocation? {
        guard let script = bundle.path(forResource: "mediaremote-adapter", ofType: "pl"),
              let frameworks = bundle.privateFrameworksPath
        else { return nil }
        let framework = frameworks + "/MediaRemoteAdapter.framework"
        guard FileManager.default.fileExists(atPath: framework) else { return nil }
        return AdapterLocation(scriptPath: script, frameworkPath: framework)
    }

    func arguments(_ command: [String]) -> [String] {
        [scriptPath, frameworkPath] + command
    }
}

/// What the Mac is playing, and play/pause, next and previous (design §6, §7), through mediaremote-adapter
/// (vendored, see THIRD_PARTY_NOTICES.md). The adapter runs under `/usr/bin/perl`, which MediaRemote still answers
/// on current macOS, and streams one JSON line per change. It runs only while a phone receives data.
@MainActor
final class NowPlayingService {
    static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    static let streamArguments = ["stream", "--no-diff", "--no-artwork", "--debounce=100"]
    /// Waits before restarting an adapter that exited; the last one repeats.
    static let restartDelays: [TimeInterval] = [1, 2, 5, 10, 30]

    private let location: AdapterLocation?
    private var process: Process?
    private var assembler = LineAssembler()
    private var state = NowPlayingState()
    private var running = false
    private var failures = 0
    private var names: [String: String] = [:]

    init(location: AdapterLocation? = .inAppBundle()) {
        self.location = location
    }

    func start() {
        guard !running else { return }
        running = true
        failures = 0
        launch()
    }

    func stop() {
        running = false
        let old = process
        process = nil
        old?.terminate()
        state.clear()
        assembler.reset()
    }

    /// For the snapshot: nil while nothing is playing, or without the adapter.
    func current() -> MediaSample? {
        guard let track = state.current(at: Date()) else { return nil }
        return MediaSample(title: track.title, artist: track.artist, app: appName(for: track.bundleId), playing: track.playing)
    }

    /// `mediaremote-adapter.pl … send <id>` (MediaRemote command numbers). `unsupported` without the adapter.
    func send(_ action: Command.MediaAction, completion: @escaping @MainActor (CommandResult) -> Void) {
        guard let location else { return completion(.failed(.unsupported)) }
        let id = switch action {
        case .playPause: "2"
        case .next: "4"
        case .previous: "5"
        }
        ShortProcess.run(Self.perl.path, location.arguments(["send", id])) { completion($0 ? .ok : .failed(.failed)) }
    }

    private func launch() {
        guard running, let location else { return }
        let process = Process()
        let output = Pipe()
        process.executableURL = Self.perl
        process.arguments = location.arguments(Self.streamArguments)
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.received(data, from: process) }
            }
        }
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.exited(finished) }
            }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            Log.app.error("Could not start the media adapter: \(error.localizedDescription, privacy: .public)")
            scheduleRestart()
        }
    }

    private func received(_ data: Data, from source: Process) {
        guard source === process, !data.isEmpty else { return }
        for line in assembler.append(data) {
            let parsed = NowPlayingStream.parse(line)
            if parsed != .invalid { failures = 0 }
            state.received(parsed, at: Date())
        }
    }

    private func exited(_ finished: Process) {
        guard finished === process else { return }
        process = nil
        state.clear()
        assembler.reset()
        Log.app.notice("The media adapter exited with status \(finished.terminationStatus)")
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard running else { return }
        let delay = Self.restartDelays[min(failures, Self.restartDelays.count - 1)]
        failures += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.running, self.process == nil else { return }
                self.launch()
            }
        }
    }

    /// "Spotify" for `com.spotify.client`; the player is running, so its name is at hand. Cached: players are few.
    private func appName(for bundleId: String) -> String {
        if let name = names[bundleId] { return name }
        let raw = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.localizedName ?? bundleId
        let name = AppUsage.displayName(raw)
        names[bundleId] = name
        return name
    }
}
```

- [ ] **Step 3: Örnekleyiciye bağla**

`Sources/PhoneBox/Sampler.swift`:

Bul (1/3):

```swift
    var onSnapshot: ((Snapshot) -> Void)?

    private var timer: Timer?
```

Şununla değiştir:

```swift
    var onSnapshot: ((Snapshot) -> Void)?
    /// Also sends the media commands, so the command runner shares it.
    let nowPlaying = NowPlayingService()

    private var timer: Timer?
```

Bul (2/3):

```swift
                                                             reason: "Streaming to iPhone")
        } else {
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
```

Şununla değiştir:

```swift
                                                             reason: "Streaming to iPhone")
            nowPlaying.start()
        } else {
            nowPlaying.stop()
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
```

Bul (3/3):

```swift
            power: power.sample(), net: network.sample(), disk: disk.sample(), battery: battery.sample(),
            apps: tickCount % Self.appsEvery == 0 ? apps.sample() : nil, audio: audio.sample()))
    }
```

Şununla değiştir:

```swift
            power: power.sample(), net: network.sample(), disk: disk.sample(), battery: battery.sample(),
            apps: tickCount % Self.appsEvery == 0 ? apps.sample() : nil, media: nowPlaying.current(), audio: audio.sample()))
    }
```

- [ ] **Step 4: Derle, test et, paketle**

Run: `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"` → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 10 tests in 2 suites passed` ve `Test run with 131 tests in 25 suites passed`.
Run: `make app 2>&1 | tail -1` → Expected: `Built …/build/PhoneBox.app`.
Run: `ls build/PhoneBox.app/Contents/Frameworks build/PhoneBox.app/Contents/Resources/mediaremote-adapter.pl` →
Expected: `MediaRemoteAdapter.framework` ve betiğin yolu.
Run: `codesign --verify --strict --deep build/PhoneBox.app && echo ok` → Expected: `ok`.
Uygulamayı başlatmayın.

- [ ] **Step 5: Commit**

```bash
git add .gitmodules Vendor/mediaremote-adapter scripts/build-adapter.sh scripts/bundle.sh Makefile THIRD_PARTY_NOTICES.md \
  Sources/PhoneBox/ShortProcess.swift Sources/PhoneBox/NowPlayingService.swift Sources/PhoneBox/Sampler.swift
git commit -m "Stream what the Mac is playing with mediaremote-adapter"
```

---

### Task 8: Komutları Mac'te çalıştır

**Files:**
- Create: `Sources/PhoneBoxCore/QuitRule.swift`, `Tests/PhoneBoxCoreTests/QuitRuleTests.swift`
- Modify: `Sources/PhoneBox/Collectors/PrivateSymbols.swift`, `Sources/PhoneBox/Collectors/AppsCollector.swift`
- Modify: `Sources/PhoneBox/CommandRunner.swift` (dosyanın tamamı), `Sources/PhoneBox/AppDelegate.swift`
- Create: `Tests/PhoneBoxTests/CommandRunnerLiveTests.swift` (sadece `PHONEBOX_LIVE=1` ile çalışır)

**Interfaces:**
- Consumes: `Command`, `CommandResult`, `CommandRunning`, `SystemAudio`, `ShortProcess`, `NowPlayingService.send`,
  `Sampler.nowPlaying`, `PrivateSymbols.function`.
- Produces: `RunningApp(pid:bundleId:regular:)`; `QuitRule.isQuittable(_:ownPid:)`, `QuitRule.targets(bundleId:among:ownPid:)`;
  `PrivateSymbols.login`; `CommandRunner(nowPlaying:)` bütün komutları çalıştırır.

- [ ] **Step 1: Kapatma kuralının testleri**

`Tests/PhoneBoxCoreTests/QuitRuleTests.swift`:

```swift
import Testing
@testable import PhoneBoxCore

struct QuitRuleTests {
    let ownPid: Int32 = 500
    let apps = [
        RunningApp(pid: 10, bundleId: "com.google.Chrome", regular: true),
        RunningApp(pid: 11, bundleId: "com.google.Chrome", regular: true),
        RunningApp(pid: 12, bundleId: "com.google.Chrome.helper", regular: false),
        RunningApp(pid: 20, bundleId: "com.apple.finder", regular: true),
        RunningApp(pid: 30, bundleId: "com.apple.Spotlight", regular: false),
        RunningApp(pid: 500, bundleId: "com.example.Self", regular: true),
        RunningApp(pid: 40, bundleId: nil, regular: true),
    ]

    @Test func quitsEveryRegularInstanceOfTheBundle() {
        #expect(QuitRule.targets(bundleId: "com.google.Chrome", among: apps, ownPid: ownPid) == [10, 11])
    }

    @Test func neverQuitsFinderBackgroundAppsOrItself() {
        #expect(QuitRule.targets(bundleId: "com.apple.finder", among: apps, ownPid: ownPid).isEmpty)
        #expect(QuitRule.targets(bundleId: "com.apple.Spotlight", among: apps, ownPid: ownPid).isEmpty)
        #expect(QuitRule.targets(bundleId: "com.example.Self", among: apps, ownPid: ownPid).isEmpty)
    }

    @Test func anAppThatIsGoneHasNoTargets() {
        #expect(QuitRule.targets(bundleId: "com.example.Gone", among: apps, ownPid: ownPid).isEmpty)
    }

    @Test func quittableMatchesTheTargets() {
        #expect(QuitRule.isQuittable(apps[0], ownPid: ownPid))
        #expect(!QuitRule.isQuittable(apps[2], ownPid: ownPid))
        #expect(!QuitRule.isQuittable(apps[3], ownPid: ownPid))
        #expect(!QuitRule.isQuittable(apps[5], ownPid: ownPid))
    }
}
```

Run: `make test FILTER="QuitRuleTests"` → Expected: derleme hatası (`RunningApp`, `QuitRule` yok).

- [ ] **Step 2: Kapatma kuralı**

`Sources/PhoneBoxCore/QuitRule.swift`:

```swift
/// A running app as `NSWorkspace` lists it.
public struct RunningApp: Equatable, Sendable {
    public var pid: Int32
    public var bundleId: String?
    /// `activationPolicy == .regular`: a Dock app with a menu bar.
    public var regular: Bool
    public init(pid: Int32, bundleId: String?, regular: Bool) {
        self.pid = pid
        self.bundleId = bundleId
        self.regular = regular
    }
}

/// Which apps the phone may quit (design §7): the app list's `quittable` and the `quitApp` command use the same
/// rule. Only Dock apps; never Finder (it is part of the desktop and relaunches) or PhoneBox itself.
public enum QuitRule {
    public static let finder = "com.apple.finder"

    public static func isQuittable(_ app: RunningApp, ownPid: Int32) -> Bool {
        app.regular && app.bundleId != finder && app.pid != ownPid
    }

    /// Every quittable instance of `bundleId`: the phone's row merges an app's instances. Empty when there is
    /// none, which the phone hears as `app-changed`.
    public static func targets(bundleId: String, among apps: [RunningApp], ownPid: Int32) -> [Int32] {
        apps.filter { $0.bundleId == bundleId && isQuittable($0, ownPid: ownPid) }.map(\.pid)
    }
}
```

Run: `make test FILTER="QuitRuleTests"` → Expected: 4 test geçer.

- [ ] **Step 3: Uygulama listesi aynı kuralı kullanır**

`Sources/PhoneBox/Collectors/AppsCollector.swift`:

Bul:

```swift
            guard let path = app.bundleURL?.path else { continue }
            let quittable = app.activationPolicy == .regular && app.bundleIdentifier != "com.apple.finder"
                && app.processIdentifier != ownPID
            apps[path] = AppInfo(pid: app.processIdentifier, bundleId: app.bundleIdentifier,
```

Şununla değiştir:

```swift
            guard let path = app.bundleURL?.path else { continue }
            let quittable = QuitRule.isQuittable(RunningApp(pid: app.processIdentifier, bundleId: app.bundleIdentifier,
                                                            regular: app.activationPolicy == .regular), ownPid: ownPID)
            apps[path] = AppInfo(pid: app.processIdentifier, bundleId: app.bundleIdentifier,
```

- [ ] **Step 4: Komut çalıştırıcı**

`Sources/PhoneBox/Collectors/PrivateSymbols.swift`:

Bul:

```swift
    static let ioReport = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW)
}
```

Şununla değiştir:

```swift
    static let ioReport = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW)
    static let login = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW)
}
```

`Sources/PhoneBox/CommandRunner.swift`:

```swift
import AppKit
import PhoneBoxCore

/// Runs the phone's commands on the Mac (design §7). Spike 7: none of them asks for a permission.
@MainActor
final class CommandRunner: CommandRunning {
    /// Seconds between answering `sleep` and sleeping, so that the `ack` reaches the phone first.
    static let sleepDelay: TimeInterval = 1
    static let pmset = "/usr/bin/pmset"

    private let nowPlaying: NowPlayingService

    init(nowPlaying: NowPlayingService) {
        self.nowPlaying = nowPlaying
    }

    func run(_ command: Command, completion: @escaping @MainActor (CommandResult) -> Void) {
        switch command {
        case let .quitApp(bundleId, force):
            completion(Self.quit(bundleId: bundleId, force: force))
        case let .media(action):
            nowPlaying.send(action, completion: completion)
        case let .volume(level):
            completion(SystemAudio.setVolume(level) ? .ok : .failed(.unsupported))
        case let .mute(on):
            completion(SystemAudio.setMuted(on) ? .ok : .failed(.unsupported))
        case .lock:
            if let lockScreen = Self.lockScreen {
                _ = lockScreen()
                completion(.ok)
            } else {
                // Without the private function the display at least goes dark (and locks if a password is required).
                ShortProcess.run(Self.pmset, ["displaysleepnow"]) { completion($0 ? .ok : .failed(.failed)) }
            }
        case .displaySleep:
            ShortProcess.run(Self.pmset, ["displaysleepnow"]) { completion($0 ? .ok : .failed(.failed)) }
        case .sleep:
            completion(.ok)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.sleepDelay) {
                MainActor.assumeIsolated {
                    ShortProcess.run(Self.pmset, ["sleepnow"]) { ok in
                        if !ok { Log.app.error("pmset sleepnow failed") }
                    }
                }
            }
        }
    }

    /// Asks every quittable instance of the app to quit (`terminate`, which may let the app ask to save) or
    /// quits it at once (`forceTerminate`).
    private static func quit(bundleId: String, force: Bool) -> CommandResult {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        let apps = running.map {
            RunningApp(pid: $0.processIdentifier, bundleId: $0.bundleIdentifier, regular: $0.activationPolicy == .regular)
        }
        let targets = Set(QuitRule.targets(bundleId: bundleId, among: apps, ownPid: ProcessInfo.processInfo.processIdentifier))
        guard !targets.isEmpty else { return .failed(.appChanged) }
        var asked = false
        for app in running where targets.contains(app.processIdentifier) {
            if force ? app.forceTerminate() : app.terminate() { asked = true }
        }
        return asked ? .ok : .failed(.failed)
    }

    /// `SACLockScreenImmediate` from the private login.framework: what the menu's Lock Screen item does (spike 7).
    private static let lockScreen = PrivateSymbols.function(PrivateSymbols.login, "SACLockScreenImmediate",
                                                            as: (@convention(c) () -> Int32).self)
}
```

`Sources/PhoneBox/AppDelegate.swift`:

Bul:

```swift
    private let qrWindow = QRWindowController()
    private let commandRunner = CommandRunner()
    private let loaded = PairingStore.loadOrCreate()
```

Şununla değiştir:

```swift
    private let qrWindow = QRWindowController()
    private lazy var commandRunner = CommandRunner(nowPlaying: sampler.nowPlaying)
    private let loaded = PairingStore.loadOrCreate()
```

`Tests/PhoneBoxTests/CommandRunnerLiveTests.swift`:

```swift
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
```

- [ ] **Step 5: Derle ve test et**

Run: `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"` → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 13 tests in 3 suites passed` (4 canlı test "skipped") ve
`Test run with 135 tests in 26 suites passed`. Canlı testleri çalıştırmayın: Satranç'ı açıp kapatır (Görev 9).
Run: `make app 2>&1 | tail -1` → Expected: `Built …/build/PhoneBox.app`. Uygulamayı başlatmayın.

- [ ] **Step 6: Commit**

```bash
git add Sources/PhoneBoxCore/QuitRule.swift Sources/PhoneBox/Collectors/PrivateSymbols.swift \
  Sources/PhoneBox/Collectors/AppsCollector.swift Sources/PhoneBox/CommandRunner.swift Sources/PhoneBox/AppDelegate.swift \
  Tests/PhoneBoxCoreTests/QuitRuleTests.swift Tests/PhoneBoxTests/CommandRunnerLiveTests.swift
git commit -m "Run the phone's commands on the Mac"
```

---

### Task 9: Mac'te deneme ve sonuçlar (kontrolcü, inline)

Kontrolcü yapar; kullanıcının PhoneBox'ı kısa süre yeni sürümle değiştirilir (aynı anahtar ve ayarlar), sonunda
dalın son sürümü çalışır halde bırakılır.

- [ ] **Step 1:** `make run`. Mac'in tarayıcı panelinde kişisel bağlantıyı aç (`http://localhost:<port>/#k=…`), bir
  WebSocket aç, kimlik doğrula ve şunlara bak:
  - `ready`: `host` Mac'in adı; `access.cable: false`; "Her zaman" modunda `commands: false`.
  - İmzalı `mute` ve bilinmeyen bir komut: ikisi de `ack` `not-allowed`.
  - Snapshot'ta `audio`; Mac'te bir şey çalıyorsa ya da duraklatılmışsa `media`.
- [ ] **Step 2:** `nc` ile yükseltme: doğru `Origin` → `101`; `Origin: http://evil.example` → `403 Forbidden`.
- [ ] **Step 3:** `top -l 11 -s 3` ile PhoneBox ve adaptörün CPU'su (veri giderken). Hedef: PhoneBox %1'in altında.
- [ ] **Step 4:** `PHONEBOX_LIVE=1 make test FILTER="SystemAudioLiveTests|CommandRunnerLiveTests"` → 4 test geçer;
  Satranç açılıp kapanır.
- [ ] **Step 5:** `docs/manual-testing.md`:
  - "Komutlar (kablodan; Plan 4'te telefonla)" listesini ekle. Her komut için ayrı bir madde: kapat, zorla kapat,
    medya, ses, sessiz, kilit, ekranı kapat, uyut.
  - Ayrıca iki madde: Wi-Fi'de `not-allowed`; Finder kapatılamaz.
  - "Sonuçlar"a Plan 3B'nin Mac sonuçlarını yaz.
- [ ] **Step 6: Commit**

```bash
git add docs/manual-testing.md
git commit -m "Record the Plan 3B Mac check"
```
