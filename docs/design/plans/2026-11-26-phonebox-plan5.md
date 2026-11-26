# PhoneBox Plan 5 — Dağıtım

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Bu plan için not:** Görev 1–6 Mac'te tek başına yürütülebilir. Uygulamayı başlatmaz, kullanıcının PhoneBox'ını
> durdurmaz, `defaults`'a, eşleştirme anahtarına ve `/Applications`'a dokunmaz; canlı testleri (`PHONEBOX_LIVE=1`)
> ve GitHub'a yayını yalnız kontrolcü yapar (Görev 7, inline).

**Goal:** PhoneBox'ı NotchBox gibi dağıtılabilir hale getirmek (design §8 "Menü çubuğu", §12): menüden port seçimi,
güncelleme denetimi ve yükleme, giriş öğesi onayı; uygulama simgesi, lisans ve bildirimler uygulamanın içinde;
`curl | bash` kurulum, güncelleme ve kaldırma; `make dist` ve `make release`; son kullanıcı için iki dilli README.
Ayrıca önceki planlardan Plan 5'e ertelenen sağlamlık düzeltmeleri.

**Architecture:** Sürüm karşılaştırma, GitHub yanıtını okuma ve yazılan portu denetleme saf ve `PhoneBoxCore`'da
test edilir. Uygulama tarafı NotchBox'ın `UpdateService`'inin aynısıdır: GitHub'ın "latest release" yanıtına bakar,
kurulum komutunu PhoneBox'tan bağımsız bir kabukta çalıştırır. Kurulum, sürüm ve zip betikleri NotchBox'ınkilerin
PhoneBox'a uyarlanmışıdır. Simge CoreGraphics ile `make app` sırasında çizilir.

**Tech Stack:** Swift 6 araç zinciri (Swift 5 dil modu), Swift Testing, AppKit (`NSAlert`, `NSMenu`),
ServiceManagement, IOKit.ps, CoreGraphics/ImageIO, `iconutil`, bash, `curl`, `ditto`, `codesign`.

## Global Constraints

- Depo `cyesaa/phone-box`, paket kimliği `com.phonebox.PhoneBox`, sürüm dosyası `PhoneBox.zip`. Kurulum komutu:
  `curl -fsSL https://raw.githubusercontent.com/cyesaa/phone-box/main/install.sh | bash`; kaldırma aynı komut ve
  `bash -s -- --uninstall`.
- Gereksinim: Apple Silicon, macOS 14+. Uygulama ad-hoc imzalı, notarize değil.
- Port 1024–65535; varsayılan 4747. Güncelleme denetimi açılıştan 15 sn sonra, sonra 12 saatte bir.
- Menü ve uyarı metinleri İngilizce ve Türkçe (`Resources/{en,tr}.lproj/Localizable.strings`), iki dosyada aynı
  anahtarlar ve aynı yer tutucular.
- Kaldırma: uygulama, `defaults`, `~/Library/Application Support/PhoneBox` (eşleştirme anahtarı),
  `~/Library/Logs/PhoneBox`, izinler (`tccutil`). Deneme kurulumu (`PHONEBOX_DEST`) başka yerden çalışan PhoneBox'a
  dokunmaz.
- README önce Türkçe, sonra İngilizce; son kullanıcı için.
- Kod yorumları İngilizce. Commit mesajları İngilizce, emir kipinde; her `git commit`'e commit'i yapan ortamın
  istediği `Co-Authored-By: …` satırı ikinci bir `-m` olarak eklenir.
- Testler `make test FILTER="<Suite>|<Suite>"` ile (tırnaklar kalsın). İki uyarı denetimi de çıktı vermemeli:
  `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"` ve
  `make test 2>&1 | grep -E "warning:" | grep -v "ld: warning"`.

## Planlama sırasında doğrulananlar (2026-11-26)

Kodun tamamı `main`'in (967b81d, Plan 4B birleşmiş) bir kopyasında görev görev yazıldı; her görevin sonunda derleme ve test uyarısızdı.
Sonda: `PhoneBoxCoreTests` 37 takımda 203 test, `PhoneBoxTests` 7 takımda 20 test.

- `make app` simgeli paketi kurdu (`AppIcon.icns`, `LICENSE`, `THIRD_PARTY_NOTICES.md` `Contents/Resources`'ta),
  `codesign --verify --strict` geçti. Simge ve Ana Ekran simgesi gözle kontrol edildi.
- `make dist` zip'i yaptı ve imzasını doğruladı. `PHONEBOX_ZIP=dist/PhoneBox-0.1.0.zip PHONEBOX_DEST=<geçici>
  PHONEBOX_NO_OPEN=1 ./install.sh` kurdu, `PHONEBOX_DEST=<geçici> ./install.sh --uninstall` kaldırdı; kullanıcının
  başka klasörden çalışan PhoneBox'ı açık kaldı.
- `PHONEBOX_LIVE=1 make test FILTER="PhoneBatteryLiveTests"`: değişen okuyucuyla kablodaki iPhone'un pili okundu.

## Dosya yapısı

| Dosya | Görev | İş |
|---|---|---|
| `Sources/PhoneBoxCore/UpdateCheck.swift` | 1 | `AppVersion`, `LatestRelease`, `UpdateCheck` |
| `Sources/PhoneBoxCore/PortChoice.swift` | 1 | yazılan portu denetler |
| `Sources/PhoneBox/UpdateService.swift` | 2 | güncelleme denetimi ve yükleme |
| `Sources/PhoneBox/MenuBarController.swift` | 2 | Port…, güncelleme öğeleri, giriş öğesi onayı |
| `Sources/PhoneBox/{L10n,Settings,DashboardServer,AppDelegate}.swift` | 2, 4 | metinler, port ayarı, dinleyici değişimi, bağlama |
| `Tests/PhoneBoxTests/LocalizationTests.swift` | 2 | iki dilin anahtarları ve yer tutucuları |
| `scripts/make-icon.swift`, `scripts/bundle.sh`, `Resources/Info.plist`, `LICENSE` | 3 | simge, lisans |
| `Sources/PhoneBox/Collectors/{BatteryCollector,PhoneBatteryReader}.swift`, `NowPlayingService.swift` | 4 | sağlamlık |
| `install.sh`, `scripts/dist.sh`, `scripts/release.sh`, `Makefile` | 5 | dağıtım |
| `README.md`, design doc | 6 | belgeler |
| `Sources/PhoneBoxCore/WebBuild.swift`, `Messages.swift`, `connection.js`, `app.js` | 7 | sayfa güncellemeyi alır |

---

### Task 1: Sürüm, GitHub yanıtı ve port denetimi

**Files:**
- Create: `Sources/PhoneBoxCore/UpdateCheck.swift`, `Sources/PhoneBoxCore/PortChoice.swift`,
  `Tests/PhoneBoxCoreTests/UpdateCheckTests.swift`, `Tests/PhoneBoxCoreTests/PortChoiceTests.swift`

**Interfaces:**
- Produces: `AppVersion(_ string:)` (`Comparable`, `description`); `LatestRelease(version:pageURL:)`,
  `LatestRelease.parse(_ data: Data) -> LatestRelease?`; `UpdateCheck.repository`, `.launchDelay`, `.interval`,
  `.latestReleaseURL`, `.installCommand`, `.availableUpdate(current:latest:)`; `PortChoice.range`,
  `PortChoice.parse(_ text: String) -> UInt16?`.

- [ ] **Step 1: Testleri yaz**

`Tests/PhoneBoxCoreTests/UpdateCheckTests.swift`:

```swift
import Foundation
import Testing
@testable import PhoneBoxCore

struct AppVersionTests {
    @Test func readsTagsAndBundleVersions() {
        #expect(AppVersion("0.1.0")?.description == "0.1.0")
        #expect(AppVersion("v1.2.3")?.description == "1.2.3")
        #expect(AppVersion("V2.0")?.description == "2.0.0")
        #expect(AppVersion(" 3 ")?.description == "3.0.0")
    }

    @Test func refusesWhatIsNotAVersion() {
        for text in ["", "latest", "1.x", "1.2.3.4", "1.2.3-beta", "1..2", "١.٢"] {
            #expect(AppVersion(text) == nil, "\(text)")
        }
    }

    @Test func comparesNumericallyPartByPart() throws {
        let v = { (s: String) throws -> AppVersion in try #require(AppVersion(s)) }
        #expect(try v("0.1.0") < v("0.1.1"))
        #expect(try v("0.1.9") < v("0.10.0"))
        #expect(try v("0.9.9") < v("1.0.0"))
        #expect(try v("1.0") == v("1.0.0"))
        #expect(try !(v("0.1.0") < v("0.1.0")))
    }
}

struct LatestReleaseTests {
    func json(_ fields: String) -> Data { Data("{\(fields)}".utf8) }

    @Test func readsTheTagAndThePage() {
        let release = LatestRelease.parse(json(#""tag_name": "v0.2.0", "html_url": "https://github.com/cyesaa/phone-box/releases/tag/v0.2.0", "draft": false, "prerelease": false"#))
        #expect(release?.version.description == "0.2.0")
        #expect(release?.pageURL.absoluteString == "https://github.com/cyesaa/phone-box/releases/tag/v0.2.0")
    }

    @Test func skipsDraftsPrereleasesAndJunk() {
        #expect(LatestRelease.parse(json(#""tag_name": "v0.2.0", "html_url": "https://x.y", "draft": true"#)) == nil)
        #expect(LatestRelease.parse(json(#""tag_name": "v0.2.0", "html_url": "https://x.y", "prerelease": true"#)) == nil)
        #expect(LatestRelease.parse(json(#""tag_name": "nightly", "html_url": "https://x.y""#)) == nil)
        #expect(LatestRelease.parse(json(#""tag_name": "v0.2.0", "html_url": "file:///etc/passwd""#)) == nil)
        #expect(LatestRelease.parse(json(#""message": "Not Found""#)) == nil)
        #expect(LatestRelease.parse(Data("not json".utf8)) == nil)
    }
}

struct UpdateCheckTests {
    let current = AppVersion("0.1.0")!

    func release(_ version: String) -> LatestRelease {
        LatestRelease(version: AppVersion(version)!, pageURL: URL(string: "https://example.com")!)
    }

    @Test func onlyANewerReleaseIsAnUpdate() {
        #expect(UpdateCheck.availableUpdate(current: current, latest: release("0.2.0")) == release("0.2.0"))
        #expect(UpdateCheck.availableUpdate(current: current, latest: release("0.1.0")) == nil)
        #expect(UpdateCheck.availableUpdate(current: current, latest: release("0.0.9")) == nil)
        #expect(UpdateCheck.availableUpdate(current: current, latest: nil) == nil)
    }

    @Test func checksSoonAfterLaunchThenTwiceADay() {
        #expect(UpdateCheck.launchDelay == 15)
        #expect(UpdateCheck.interval == 12 * 60 * 60)
    }

    @Test func pointsAtThisRepository() {
        #expect(UpdateCheck.latestReleaseURL.absoluteString == "https://api.github.com/repos/cyesaa/phone-box/releases/latest")
        #expect(UpdateCheck.installCommand == "curl -fsSL https://raw.githubusercontent.com/cyesaa/phone-box/main/install.sh | bash")
    }
}
```

`Tests/PhoneBoxCoreTests/PortChoiceTests.swift`:

```swift
import Testing
@testable import PhoneBoxCore

struct PortChoiceTests {
    @Test func readsAPortInTheAllowedRange() {
        #expect(PortChoice.parse("4747") == 4747)
        #expect(PortChoice.parse(" 8080\n") == 8080)
        #expect(PortChoice.parse("1024") == 1024)
        #expect(PortChoice.parse("65535") == 65535)
    }

    @Test func refusesEverythingElse() {
        for text in ["", " ", "80", "1023", "65536", "99999", "123456", "-4747", "+4747", "47 47", "4747a", "0x12AB",
                     "4747.0", "٤٧٤٧", "00004747"] {
            #expect(PortChoice.parse(text) == nil, "\(text)")
        }
    }
}
```

- [ ] **Step 2: Testlerin derlenmediğini gör**

Run: `make test FILTER="AppVersionTests|LatestReleaseTests|UpdateCheckTests|PortChoiceTests"` → Expected: derleme
hatası (`AppVersion`, `PortChoice` yok).

- [ ] **Step 3: Kodu yaz**

`Sources/PhoneBoxCore/UpdateCheck.swift`:

```swift
import Foundation

/// A release version: up to three numbers ("0.4.0", "v1.2"); missing parts count as 0.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        while numbers.count < 3 { numbers.append(0) }
        (major, minor, patch) = (numbers[0], numbers[1], numbers[2])
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// The newest published release on GitHub.
public struct LatestRelease: Equatable, Sendable {
    public let version: AppVersion
    /// The release page, with its notes.
    public let pageURL: URL

    public init(version: AppVersion, pageURL: URL) {
        self.version = version
        self.pageURL = pageURL
    }

    /// Reads GitHub's "latest release" answer; nil for drafts, pre-releases and anything unexpected.
    public static func parse(_ data: Data) -> LatestRelease? {
        struct Response: Decodable {
            let tag_name: String
            let html_url: String
            let draft: Bool?
            let prerelease: Bool?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              response.draft != true, response.prerelease != true,
              let version = AppVersion(response.tag_name),
              let url = URL(string: response.html_url), url.scheme == "https"
        else { return nil }
        return LatestRelease(version: version, pageURL: url)
    }
}

/// When and where PhoneBox looks for a newer release, and how it installs one (design §8 "Menü çubuğu", §12).
public enum UpdateCheck {
    public static let repository = "cyesaa/phone-box"
    /// The first check waits a little after launch, then one runs twice a day.
    public static let launchDelay: TimeInterval = 15
    public static let interval: TimeInterval = 12 * 60 * 60

    public static var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    /// The one-line installer; running it again updates PhoneBox in place.
    public static var installCommand: String {
        "curl -fsSL https://raw.githubusercontent.com/\(repository)/main/install.sh | bash"
    }

    public static func availableUpdate(current: AppVersion, latest: LatestRelease?) -> LatestRelease? {
        guard let latest, current < latest.version else { return nil }
        return latest
    }
}
```

`Sources/PhoneBoxCore/PortChoice.swift`:

```swift
/// The port the dashboard listens on, as typed into the menu's "Port…" dialog (design §8 "Menü çubuğu").
public enum PortChoice {
    /// Below 1024 needs root; 4747 is the default.
    public static let range: ClosedRange<Int> = 1024...65535

    /// The port in `text` (spaces around it are fine), or nil when it is not a whole number in `range`.
    public static func parse(_ text: String) -> UInt16? {
        let digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !digits.isEmpty, digits.count <= 5, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(digits), range.contains(number)
        else { return nil }
        return UInt16(number)
    }
}
```

- [ ] **Step 4: Testleri çalıştır**

Run: `make test FILTER="AppVersionTests|LatestReleaseTests|UpdateCheckTests|PortChoiceTests"` → Expected:
`Test run with 10 tests in 4 suites passed`.
Run: iki uyarı denetimi → Expected: çıktı yok.

- [ ] **Step 5: Commit**

```bash
git add Sources/PhoneBoxCore/UpdateCheck.swift Sources/PhoneBoxCore/PortChoice.swift \
  Tests/PhoneBoxCoreTests/UpdateCheckTests.swift Tests/PhoneBoxCoreTests/PortChoiceTests.swift
git commit -m "Compare release versions and read GitHub's latest release; check a typed port"
```

---

### Task 2: Menüde port, güncelleme ve giriş öğesi onayı

**Files:**
- Create: `Sources/PhoneBox/UpdateService.swift`, `Tests/PhoneBoxTests/LocalizationTests.swift`
- Replace: `Sources/PhoneBox/MenuBarController.swift`
- Modify: `Sources/PhoneBox/L10n.swift`, `Resources/en.lproj/Localizable.strings`,
  `Resources/tr.lproj/Localizable.strings`, `Sources/PhoneBox/Settings.swift`, `Sources/PhoneBox/DashboardServer.swift`,
  `Sources/PhoneBox/AppDelegate.swift`

**Interfaces:**
- Consumes: Görev 1'in `UpdateCheck`, `LatestRelease`, `AppVersion`, `PortChoice`.
- Produces: `UpdateService()` (`start()`, `check(userInitiated:)`, `installWithConfirmation()`, `availableRelease`,
  `status`, `onChange`); `MenuBarController(mode:port:updates:)`, `onPortChange: ((UInt16) -> Void)?`, `port`;
  `Settings.port` artık yazılabilir.

- [ ] **Step 1: İki dilin testini yaz**

`Tests/PhoneBoxTests/LocalizationTests.swift`:

```swift
import Foundation
import Testing

/// The menu and its dialogs exist in English and Turkish (design §8 "Menü çubuğu"): both files must have the same
/// keys, and each text the same placeholders, or `String(format:)` would read the wrong argument.
struct LocalizationTests {
    static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources", isDirectory: true)

    static func strings(_ language: String) throws -> [String: String] {
        let url = resources.appendingPathComponent("\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    static func placeholders(_ text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%[@dfs]")
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) }
    }

    @Test func englishAndTurkishHaveTheSameKeysAndPlaceholders() throws {
        let english = try Self.strings("en")
        let turkish = try Self.strings("tr")
        #expect(Set(english.keys) == Set(turkish.keys))
        #expect(english.count == 40)
        for (key, text) in english {
            #expect(Self.placeholders(text) == Self.placeholders(turkish[key] ?? ""), "\(key)")
        }
    }
}
```

- [ ] **Step 2: Testin düştüğünü gör**

Run: `make test FILTER="LocalizationTests"` → Expected: `english.count == 40` beklentisi düşer (şimdi 20 metin).

- [ ] **Step 3: Metinler**

`Resources/en.lproj/Localizable.strings`:

Bul:

```
"menu.mode.always" = "Always, Also over Wi-Fi";
"menu.launchAtLogin" = "Open at Login";
"menu.resetPairing" = "Reset Pairing…";
"menu.quit" = "Quit PhoneBox";

"reset.title" = "Reset pairing?";
```

Şununla değiştir:

```
"menu.mode.always" = "Always, Also over Wi-Fi";
"menu.port" = "Port: %d…";
"menu.launchAtLogin" = "Open at Login";
"menu.resetPairing" = "Reset Pairing…";
"menu.checkForUpdates" = "Check for Updates…";
"menu.installUpdate" = "Install PhoneBox %@…";
"menu.quit" = "Quit PhoneBox";

"port.title" = "Choose the dashboard's port";
"port.message" = "A number from 1024 to 65535. The phone's link changes with it: scan the new QR code afterwards.";
"port.invalid" = "That is not a port PhoneBox can use. Type a number from 1024 to 65535.";
"port.use" = "Use";

"login.approvalTitle" = "Allow PhoneBox to open at login";
"login.approvalMessage" = "macOS wants your approval in System Settings → General → Login Items.";
"login.openSettings" = "Open Login Items";

"update.upToDate" = "PhoneBox %@ is up to date.";
"update.checkFailed" = "Could not check for updates.";
"update.checkFailedHint" = "Check the internet connection and try again later.";
"update.availableTitle" = "PhoneBox %@ is available";
"update.availableInfo" = "You have %@. Installing quits PhoneBox, puts the new version in place and opens it again; the phone reconnects by itself.";
"update.install" = "Install";
"update.releaseNotes" = "Release Notes";
"update.later" = "Later";
"update.installFailed" = "The update could not be installed.";
"update.installFailedHint" = "The install command is on the clipboard: paste it into Terminal. The log is in ~/Library/Logs/PhoneBox.";

"reset.title" = "Reset pairing?";
```

`Resources/tr.lproj/Localizable.strings`:

Bul:

```
"menu.mode.always" = "Her zaman, Wi-Fi'de de";
"menu.launchAtLogin" = "Girişte başlat";
"menu.resetPairing" = "Eşleştirmeyi sıfırla…";
"menu.quit" = "PhoneBox'tan çık";

"reset.title" = "Eşleştirme sıfırlansın mı?";
```

Şununla değiştir:

```
"menu.mode.always" = "Her zaman, Wi-Fi'de de";
"menu.port" = "Port: %d…";
"menu.launchAtLogin" = "Girişte başlat";
"menu.resetPairing" = "Eşleştirmeyi sıfırla…";
"menu.checkForUpdates" = "Güncellemeleri denetle…";
"menu.installUpdate" = "PhoneBox %@ sürümünü yükle…";
"menu.quit" = "PhoneBox'tan çık";

"port.title" = "Dashboard'un portunu seç";
"port.message" = "1024 ile 65535 arasında bir sayı. Telefondaki bağlantı da değişir: sonra yeni QR kodunu okut.";
"port.invalid" = "PhoneBox bu portu kullanamaz. 1024 ile 65535 arasında bir sayı yaz.";
"port.use" = "Kullan";

"login.approvalTitle" = "PhoneBox'ın girişte açılmasına izin ver";
"login.approvalMessage" = "macOS, Sistem Ayarları → Genel → Giriş Öğeleri'nde onayını istiyor.";
"login.openSettings" = "Giriş Öğeleri'ni aç";

"update.upToDate" = "PhoneBox %@ güncel.";
"update.checkFailed" = "Güncellemeler denetlenemedi.";
"update.checkFailedHint" = "İnternet bağlantısını kontrol edip sonra yeniden dene.";
"update.availableTitle" = "PhoneBox %@ çıktı";
"update.availableInfo" = "Sende %@ var. Yükleme PhoneBox'ı kapatır, yeni sürümü yerine koyar ve yeniden açar; telefon kendiliğinden yeniden bağlanır.";
"update.install" = "Yükle";
"update.releaseNotes" = "Sürüm notları";
"update.later" = "Sonra";
"update.installFailed" = "Güncelleme yüklenemedi.";
"update.installFailedHint" = "Kurulum komutu panoda: Terminal'e yapıştır. Kayıt ~/Library/Logs/PhoneBox içinde.";

"reset.title" = "Eşleştirme sıfırlansın mı?";
```

`Sources/PhoneBox/L10n.swift`:

Bul:

```swift
    static var modeAlways: String { text("menu.mode.always") }
    static var launchAtLogin: String { text("menu.launchAtLogin") }
    static var resetPairing: String { text("menu.resetPairing") }
    static var quit: String { text("menu.quit") }

    static var resetTitle: String { text("reset.title") }
```

Şununla değiştir:

```swift
    static var modeAlways: String { text("menu.mode.always") }
    static func portItem(_ port: UInt16) -> String { String(format: text("menu.port"), Int(port)) }
    static var launchAtLogin: String { text("menu.launchAtLogin") }
    static var resetPairing: String { text("menu.resetPairing") }
    static var checkForUpdates: String { text("menu.checkForUpdates") }
    static func installUpdate(_ version: String) -> String { String(format: text("menu.installUpdate"), version) }
    static var quit: String { text("menu.quit") }

    static var portTitle: String { text("port.title") }
    static var portMessage: String { text("port.message") }
    static var portInvalid: String { text("port.invalid") }
    static var portUse: String { text("port.use") }

    static var loginApprovalTitle: String { text("login.approvalTitle") }
    static var loginApprovalMessage: String { text("login.approvalMessage") }
    static var loginOpenSettings: String { text("login.openSettings") }

    static func updateUpToDate(_ version: String) -> String { String(format: text("update.upToDate"), version) }
    static var updateCheckFailed: String { text("update.checkFailed") }
    static var updateCheckFailedHint: String { text("update.checkFailedHint") }
    static func updateAvailableTitle(_ version: String) -> String { String(format: text("update.availableTitle"), version) }
    static func updateAvailableInfo(_ version: String) -> String { String(format: text("update.availableInfo"), version) }
    static var updateInstall: String { text("update.install") }
    static var updateReleaseNotes: String { text("update.releaseNotes") }
    static var updateLater: String { text("update.later") }
    static var updateInstallFailed: String { text("update.installFailed") }
    static var updateInstallFailedHint: String { text("update.installFailedHint") }

    static var resetTitle: String { text("reset.title") }
```

- [ ] **Step 4: Güncelleme servisi** (NotchBox'ınkinin PhoneBox'a uyarlanmışı)

`Sources/PhoneBox/UpdateService.swift`:

```swift
import AppKit
import PhoneBoxCore

/// Looks for a newer PhoneBox release on GitHub soon after launch and twice a day, and installs it by running the
/// one-line installer, which quits this copy, puts the new one in place and opens it (design §8 "Menü çubuğu").
/// `defaults write com.phonebox.PhoneBox CheckForUpdatesAutomatically -bool false` turns the automatic checks off;
/// "Check for Updates…" still works.
@MainActor
final class UpdateService {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(LatestRelease)
        case installing
        case failed
    }

    private static let automaticKey = "CheckForUpdatesAutomatically"
    /// For testing: `defaults write com.phonebox.PhoneBox UpdateFeedURL file:///path/release.json` reads that file
    /// instead of GitHub, and `UpdateInstallCommand '<shell command>'` runs that instead of the installer.
    private static let feedOverrideKey = "UpdateFeedURL"
    private static let installOverrideKey = "UpdateInstallCommand"

    private(set) var status: Status = .idle {
        didSet { if status != oldValue { onChange?() } }
    }
    var onChange: (() -> Void)?
    let currentVersion: AppVersion?
    private let session: URLSession
    private var timer: Timer?

    init(bundle: Bundle = .main) {
        currentVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap(AppVersion.init)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    private var feedURL: URL {
        UserDefaults.standard.string(forKey: Self.feedOverrideKey).flatMap(URL.init(string:))
            ?? UpdateCheck.latestReleaseURL
    }

    private var installCommand: String {
        UserDefaults.standard.string(forKey: Self.installOverrideKey) ?? UpdateCheck.installCommand
    }

    private var checksAutomatically: Bool {
        UserDefaults.standard.object(forKey: Self.automaticKey) as? Bool ?? true
    }

    var availableRelease: LatestRelease? {
        if case let .available(release) = status { return release }
        return nil
    }

    func start() {
        guard checksAutomatically, timer == nil else { return }
        let first = Timer(timeInterval: UpdateCheck.launchDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.check(userInitiated: false)
                let repeating = Timer(timeInterval: UpdateCheck.interval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.check(userInitiated: false) }
                }
                repeating.tolerance = 10 * 60
                RunLoop.main.add(repeating, forMode: .common)
                self.timer = repeating
            }
        }
        RunLoop.main.add(first, forMode: .common)
        timer = first
    }

    /// Asks GitHub for the latest release. A check from the menu answers in an alert.
    func check(userInitiated: Bool) {
        guard status != .checking, status != .installing, let currentVersion else { return }
        status = .checking
        var request = URLRequest(url: feedURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PhoneBox/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { data, response, error in
            // A file:// feed (testing) has no HTTP status.
            let code = (response as? HTTPURLResponse)?.statusCode ?? (data == nil ? 0 : 200)
            let release = code == 200 ? data.flatMap(LatestRelease.parse) : nil
            let failed = error != nil || code != 200
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.finishCheck(release: release, failed: failed, code: code, userInitiated: userInitiated)
                }
            }
        }.resume()
    }

    private func finishCheck(release: LatestRelease?, failed: Bool, code: Int, userInitiated: Bool) {
        guard let currentVersion else { return }
        if failed {
            Log.app.notice("Update check failed (HTTP \(code, privacy: .public))")
            status = .failed
        } else if let update = UpdateCheck.availableUpdate(current: currentVersion, latest: release) {
            Log.app.notice("Update available: \(update.version.description, privacy: .public)")
            status = .available(update)
        } else {
            status = .upToDate
        }
        guard userInitiated else { return }
        switch status {
        case .available: installWithConfirmation()
        case .upToDate: alert(L10n.updateUpToDate(currentVersion.description), info: nil)
        default: alert(L10n.updateCheckFailed, info: L10n.updateCheckFailedHint)
        }
    }

    /// Asks once more, then runs the installer.
    func installWithConfirmation() {
        guard let release = availableRelease, let currentVersion else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = L10n.updateAvailableTitle(release.version.description)
        alert.informativeText = L10n.updateAvailableInfo(currentVersion.description)
        alert.addButton(withTitle: L10n.updateInstall)
        alert.addButton(withTitle: L10n.updateReleaseNotes)
        alert.addButton(withTitle: L10n.updateLater)
        switch alert.runModal() {
        case .alertFirstButtonReturn: install()
        case .alertSecondButtonReturn: NSWorkspace.shared.open(release.pageURL)
        default: break
        }
    }

    /// Runs the installer in a shell that outlives this process: the installer quits PhoneBox, replaces the app and
    /// opens the new one. Its output goes to ~/Library/Logs/PhoneBox/update.log.
    private func install() {
        let logFolder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/PhoneBox", isDirectory: true)
        try? FileManager.default.createDirectory(at: logFolder, withIntermediateDirectories: true)
        let logFile = logFolder.appendingPathComponent("update.log")
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "set -o pipefail; \(installCommand)"]
        if let handle = try? FileHandle(forWritingTo: logFile) {
            process.standardOutput = handle
            process.standardError = handle
        }
        process.terminationHandler = { process in
            // A successful install quits PhoneBox first, so this runs only when the installer failed.
            let code = process.terminationStatus
            guard code != 0 else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.installFailed(code: code, log: logFile) }
            }
        }
        do {
            try process.run()
            status = .installing
            Log.app.notice("Running the installer")
        } catch {
            Log.app.error("Could not start the installer: \(error.localizedDescription, privacy: .public)")
            installFailed(code: -1, log: logFile)
        }
    }

    private func installFailed(code: Int32, log: URL) {
        Log.app.error("Installer exited with \(code, privacy: .public)")
        status = .failed
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(UpdateCheck.installCommand, forType: .string)
        alert(L10n.updateInstallFailed, info: L10n.updateInstallFailedHint)
        NSWorkspace.shared.activateFileViewerSelecting([log])
    }

    private func alert(_ message: String, info: String?) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = message
        if let info { alert.informativeText = info }
        alert.runModal()
    }
}
```

- [ ] **Step 5: Menü** (dosyanın tamamı)

`Sources/PhoneBox/MenuBarController.swift`:

```swift
import AppKit
import PhoneBoxCore
import ServiceManagement

/// The menu bar icon and its menu (design §8 "Menü çubuğu"). Gray phone: nobody is receiving data;
/// green phone: at least one phone is.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    var onShowQR: (() -> Void)?
    var onModeChange: ((AccessMode) -> Void)?
    var onPortChange: ((UInt16) -> Void)?
    var onResetPairing: (() -> Void)?
    /// The port shown in the "Port…" item and offered in its dialog.
    var port: UInt16

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusLine = NSMenuItem()
    private let cableItem = NSMenuItem()
    private let alwaysItem = NSMenuItem()
    private let portItem = NSMenuItem()
    private let loginItem = NSMenuItem()
    private let installItem = NSMenuItem()
    private let updates: UpdateService
    private var mode: AccessMode

    init(mode: AccessMode, port: UInt16, updates: UpdateService) {
        self.mode = mode
        self.port = port
        self.updates = updates
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "PhoneBox")
        statusLine.isEnabled = false

        let qrItem = NSMenuItem(title: L10n.showQR, action: #selector(showQR), keyEquivalent: "")
        let modeHeader = NSMenuItem(title: L10n.modeHeader, action: nil, keyEquivalent: "")
        modeHeader.isEnabled = false
        cableItem.title = L10n.modeCable
        cableItem.action = #selector(chooseCable)
        alwaysItem.title = L10n.modeAlways
        alwaysItem.action = #selector(chooseAlways)
        portItem.action = #selector(choosePort)
        loginItem.title = L10n.launchAtLogin
        loginItem.action = #selector(toggleLaunchAtLogin)
        let resetItem = NSMenuItem(title: L10n.resetPairing, action: #selector(resetPairing), keyEquivalent: "")
        installItem.action = #selector(installUpdate)
        installItem.isHidden = true
        let checkItem = NSMenuItem(title: L10n.checkForUpdates, action: #selector(checkForUpdates), keyEquivalent: "")
        let quitItem = NSMenuItem(title: L10n.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        for item in [qrItem, cableItem, alwaysItem, portItem, loginItem, resetItem, installItem, checkItem] {
            item.target = self
        }

        let menu = NSMenu()
        menu.delegate = self
        for item in [statusLine, .separator(), qrItem, .separator(), modeHeader, cableItem, alwaysItem, .separator(),
                     portItem, loginItem, resetItem, .separator(), installItem, checkItem, .separator(), quitItem] {
            menu.addItem(item)
        }
        statusItem.menu = menu
        update(status: L10n.statusWaiting, active: false)
    }

    func update(status: String, active: Bool) {
        statusLine.title = status
        statusItem.button?.contentTintColor = active ? .systemGreen : .secondaryLabelColor
        statusItem.button?.toolTip = "PhoneBox: \(status)"
    }

    func menuWillOpen(_ menu: NSMenu) {
        cableItem.state = mode == .cable ? .on : .off
        alwaysItem.state = mode == .always ? .on : .off
        portItem.title = L10n.portItem(port)
        switch SMAppService.mainApp.status {
        case .enabled: loginItem.state = .on
        case .requiresApproval: loginItem.state = .mixed
        default: loginItem.state = .off
        }
        if let release = updates.availableRelease {
            installItem.title = L10n.installUpdate(release.version.description)
            installItem.isHidden = false
        } else {
            installItem.isHidden = true
        }
    }

    @objc private func showQR() { onShowQR?() }
    @objc private func chooseCable() { setMode(.cable) }
    @objc private func chooseAlways() { setMode(.always) }

    private func setMode(_ newMode: AccessMode) {
        mode = newMode
        onModeChange?(newMode)
    }

    /// Asks for a port until a valid one is typed or the dialog is cancelled.
    @objc private func choosePort() {
        var text = String(port)
        var message = L10n.portMessage
        while true {
            let alert = NSAlert()
            alert.messageText = L10n.portTitle
            alert.informativeText = message
            alert.addButton(withTitle: L10n.portUse)
            alert.addButton(withTitle: L10n.cancel)
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
            field.stringValue = text
            field.placeholderString = String(Settings.defaultPort)
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            text = field.stringValue
            guard let chosen = PortChoice.parse(text) else {
                message = L10n.portInvalid
                continue
            }
            if chosen != port { onPortChange?(chosen) }
            return
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            Log.app.error("Open at Login failed: \(error.localizedDescription, privacy: .public)")
        }
        // macOS may want the user to allow it in System Settings first (design §8 "Menü çubuğu").
        guard service.status == .requiresApproval else { return }
        let alert = NSAlert()
        alert.messageText = L10n.loginApprovalTitle
        alert.informativeText = L10n.loginApprovalMessage
        alert.addButton(withTitle: L10n.loginOpenSettings)
        alert.addButton(withTitle: L10n.cancel)
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { SMAppService.openSystemSettingsLoginItems() }
    }

    @objc private func resetPairing() {
        let alert = NSAlert()
        alert.messageText = L10n.resetTitle
        alert.informativeText = L10n.resetMessage
        alert.addButton(withTitle: L10n.resetConfirm)
        alert.addButton(withTitle: L10n.cancel)
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { onResetPairing?() }
    }

    @objc private func installUpdate() { updates.installWithConfirmation() }
    @objc private func checkForUpdates() { updates.check(userInitiated: true) }
}
```

- [ ] **Step 6: Port ayarı, dinleyici değişimi ve bağlama**

`Sources/PhoneBox/Settings.swift`:

Bul:

```swift
    }

    /// `defaults write com.phonebox.PhoneBox port -int 4848` until the menu gets a port item (Plan 5).
    var port: UInt16 {
        let value = defaults.integer(forKey: "port")
        return (1024...65535).contains(value) ? UInt16(value) : Self.defaultPort
    }
```

Şununla değiştir:

```swift
    }

    /// Chosen in the menu's "Port…" dialog; 4747 when nothing (or something out of range) is saved.
    var port: UInt16 {
        get {
            let value = defaults.integer(forKey: "port")
            return PortChoice.range.contains(value) ? UInt16(value) : Self.defaultPort
        }
        set {
            if newValue == Self.defaultPort {
                defaults.removeObject(forKey: "port")
            } else {
                defaults.set(Int(newValue), forKey: "port")
            }
        }
    }
```

`Sources/PhoneBox/DashboardServer.swift` (eski dinleyicinin geç gelen durumu yok sayılır):

Bul (1/2):

```swift
        }
        listener.stateUpdateHandler = { [weak self] newState in
            MainActor.assumeIsolated {
                switch newState {
```

Şununla değiştir:

```swift
        }
        listener.stateUpdateHandler = { [weak self, weak listener] newState in
            MainActor.assumeIsolated {
                // A listener replaced by a newer one (another port) may still report; only the current one counts.
                guard let self, let listener, self.listener === listener else { return }
                switch newState {
```

Bul (2/2):

```swift
                    Log.server.info("Listening on port \(port)")
                    self?.state = .listening(port)
                case let .failed(error):
                    Log.server.error("Listener failed: \(error.localizedDescription, privacy: .public)")
                    self?.state = .failed(port: port, message: error.localizedDescription)
                default:
```

Şununla değiştir:

```swift
                    Log.server.info("Listening on port \(port)")
                    self.state = .listening(port)
                case let .failed(error):
                    Log.server.error("Listener failed: \(error.localizedDescription, privacy: .public)")
                    self.state = .failed(port: port, message: error.localizedDescription)
                default:
```

`Sources/PhoneBox/AppDelegate.swift`:

Bul (1/4):

```swift
    private let qrWindow = QRWindowController()
    private lazy var commandRunner = CommandRunner(nowPlaying: sampler.nowPlaying)
```

Şununla değiştir:

```swift
    private let qrWindow = QRWindowController()
    private let updates = UpdateService()
    private lazy var commandRunner = CommandRunner(nowPlaying: sampler.nowPlaying)
```

Bul (2/4):

```swift
        server = DashboardServer(webDirectory: webDirectory, hub: hub)
        menuBar = MenuBarController(mode: settings.mode)

        hub.onStreamingChange = { [weak self] streaming in self?.sampler.setRunning(streaming) }
```

Şununla değiştir:

```swift
        server = DashboardServer(webDirectory: webDirectory, hub: hub)
        menuBar = MenuBarController(mode: settings.mode, port: settings.port, updates: updates)

        hub.onStreamingChange = { [weak self] streaming in self?.sampler.setRunning(streaming) }
```

Bul (3/4):

```swift
        }
        menuBar.onResetPairing = { [weak self] in
```

Şununla değiştir:

```swift
        }
        menuBar.onPortChange = { [weak self] port in
            guard let self else { return }
            settings.port = port
            menuBar.port = port
            server.start(port: port)
            // The phone's link names the port: it has to scan the new code.
            showQR()
        }
        menuBar.onResetPairing = { [weak self] in
```

Bul (4/4):

```swift
        server.start(port: settings.port)

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
```

Şununla değiştir:

```swift
        server.start(port: settings.port)
        updates.start()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
```

- [ ] **Step 7: Testleri çalıştır**

Run: `make test FILTER="LocalizationTests"` → Expected: geçer.
Run: iki uyarı denetimi → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 20 tests in 7 suites passed` ve `Test run with 199 tests in 36 suites passed`.

- [ ] **Step 8: Commit**

```bash
git add Sources/PhoneBox/UpdateService.swift Sources/PhoneBox/MenuBarController.swift Sources/PhoneBox/L10n.swift \
  Sources/PhoneBox/Settings.swift Sources/PhoneBox/DashboardServer.swift Sources/PhoneBox/AppDelegate.swift \
  Resources/en.lproj/Localizable.strings Resources/tr.lproj/Localizable.strings Tests/PhoneBoxTests/LocalizationTests.swift
git commit -m "Choose the port, check for updates and ask for login item approval from the menu"
```

---

### Task 3: Uygulama simgesi, lisans ve bildirimler

**Files:**
- Create: `scripts/make-icon.swift`, `LICENSE`
- Modify: `scripts/bundle.sh`, `Resources/Info.plist`, `scripts/make-touch-icon.swift`

**Interfaces:**
- Produces: `make app` → `Contents/Resources/AppIcon.icns`, `LICENSE`, `THIRD_PARTY_NOTICES.md`;
  `CFBundleIconFile` = `AppIcon`.

- [ ] **Step 1: Simgeyi çizen betik**

`scripts/make-icon.swift`:

```swift
// Draws PhoneBox's app icon (design §12): a dark ocean tile with a phone whose screen shows the dashboard's CPU and
// RAM rings, in the page's colours. Writes an .iconset folder for `iconutil` (scripts/bundle.sh makes AppIcon.icns).
// Usage: swiftc -O make-icon.swift -o make-icon && ./make-icon <output.iconset>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// The icon at 1024 × 1024 points, scaled to `pixels`. The tile follows Apple's macOS grid: 824 points with a
/// 100-point margin and a soft shadow below.
func draw(pixels: Int) -> CGImage {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fail("no drawing context") }
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)

    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.45))
    context.addPath(tilePath)
    context.setFillColor(color(0x04101f))
    context.fillPath()
    context.restoreGState()

    // The tile: deep ocean, lighter at the top.
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let ocean = CGGradient(colorsSpace: space, colors: [color(0x0d3557), color(0x041222)] as CFArray,
                           locations: [0, 1])!
    context.drawLinearGradient(ocean, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // A faint glow behind the phone.
    let glow = CGGradient(colorsSpace: space, colors: [color(0x00c2ff, 0.28), color(0x00c2ff, 0)] as CFArray,
                          locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 512), endRadius: 400, options: [])
    context.restoreGState()

    // The phone: a dark screen in a light frame.
    let phone = CGRect(x: 512 - 190, y: 512 - 320, width: 380, height: 640)
    let body = CGPath(roundedRect: phone, cornerWidth: 78, cornerHeight: 78, transform: nil)
    context.addPath(body)
    context.setFillColor(color(0x01060d))
    context.fillPath()
    context.addPath(body)
    context.setLineWidth(18)
    context.setStrokeColor(color(0xbfe6ff, 0.92))
    context.strokePath()
    // The Dynamic Island.
    let island = CGRect(x: 512 - 52, y: phone.maxY - 62, width: 104, height: 28)
    context.addPath(CGPath(roundedRect: island, cornerWidth: 14, cornerHeight: 14, transform: nil))
    context.setFillColor(color(0xbfe6ff, 0.92))
    context.fillPath()

    // The dashboard's rings: CPU outside, RAM inside, each a track and a bright arc from 12 o'clock.
    let center = CGPoint(x: 512, y: 512)
    func ring(radius: CGFloat, fraction: CGFloat, hex: UInt32) {
        context.setLineWidth(46)
        context.setLineCap(.butt)
        context.setStrokeColor(color(hex, 0.2))
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()
        context.setLineCap(.round)
        context.setStrokeColor(color(hex))
        let top = CGFloat.pi / 2
        context.addArc(center: center, radius: radius, startAngle: top, endAngle: top - fraction * 2 * .pi,
                       clockwise: true)
        context.strokePath()
    }
    ring(radius: 128, fraction: 0.7, hex: 0x00c2ff)  // CPU
    ring(radius: 72, fraction: 0.45, hex: 0x3d6bff)  // RAM

    guard let image = context.makeImage() else { fail("no image") }
    return image
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("cannot create \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(url.path)") }
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: output)
do {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
} catch {
    fail("cannot create \(output.path)")
}
for points in [16, 32, 128, 256, 512] {
    write(draw(pixels: points), to: output.appendingPathComponent("icon_\(points)x\(points).png"))
    write(draw(pixels: points * 2), to: output.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
```

- [ ] **Step 2: Lisans**

`LICENSE`:

```
MIT License

Copyright (c) 2026 Recep Eren VATANDAŞLAR

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Paket, Info.plist ve Ana Ekran simgesinin renkleri**

`scripts/bundle.sh`:

Bul (1/2):

```bash
#!/usr/bin/env bash
# Builds build/PhoneBox.app (release): binary, Info.plist, translations, dashboard files, the keep-awake video, the
# Home Screen icon and mediaremote-adapter (script + framework). Ad-hoc signed, like NotchBox.
set -euo pipefail
```

Şununla değiştir:

```bash
#!/usr/bin/env bash
# Builds build/PhoneBox.app (release): binary, Info.plist, the app icon, translations, dashboard files, the keep-awake
# video, the Home Screen icon, mediaremote-adapter (script + framework), the licence and the third-party notices.
# Ad-hoc signed, like NotchBox.
set -euo pipefail
```

Bul (2/2):

```bash
"$ROOT/build/make-touch-icon" "$APP/Contents/Resources/web/apple-touch-icon.png"

xattr -cr "$APP"
```

Şununla değiştir:

```bash
"$ROOT/build/make-touch-icon" "$APP/Contents/Resources/web/apple-touch-icon.png"
swiftc -O -suppress-warnings "$ROOT/scripts/make-icon.swift" -o "$ROOT/build/make-icon"
"$ROOT/build/make-icon" "$ROOT/build/AppIcon.iconset"
iconutil -c icns "$ROOT/build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"

xattr -cr "$APP"
```

`Resources/Info.plist`:

Bul (1/2):

```
	<string>PhoneBox</string>
	<key>CFBundleIdentifier</key>
```

Şununla değiştir:

```
	<string>PhoneBox</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
```

Bul (2/2):

```
	<true/>
	<key>NSLocalNetworkUsageDescription</key>
```

Şununla değiştir:

```
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>© 2026 Recep Eren VATANDAŞLAR · MIT License</string>
	<key>NSLocalNetworkUsageDescription</key>
```

`scripts/make-touch-icon.swift`:

Bul (1/4):

```swift
// Draws the dashboard's Home Screen icon (design §8 "Ana ekran"): black, with a green and a blue ring like the
// page's CPU and RAM rings. iOS rounds the corners itself.
// Usage: swiftc -O make-touch-icon.swift -o make-touch-icon && ./make-touch-icon <output.png>
```

Şununla değiştir:

```swift
// Draws the dashboard's Home Screen icon (design §8 "Ana ekran"): the page's dark background with its CPU and RAM
// rings in their colours, like the Mac app's icon (scripts/make-icon.swift). iOS rounds the corners itself.
// Usage: swiftc -O make-touch-icon.swift -o make-touch-icon && ./make-touch-icon <output.png>
```

Bul (2/4):

```swift
else { fail("no drawing context") }

context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
```

Şununla değiştir:

```swift
else { fail("no drawing context") }

context.setFillColor(CGColor(red: 0.004, green: 0.024, blue: 0.051, alpha: 1))  // #01060d, the page's background
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
```

Bul (3/4):

```swift
    context.setLineWidth(18)
    context.setStrokeColor(CGColor(red: 0.173, green: 0.173, blue: 0.18, alpha: 1))
    context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
```

Şununla değiştir:

```swift
    context.setLineWidth(18)
    context.setStrokeColor(CGColor(red: red, green: green, blue: blue, alpha: 0.2))
    context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
```

Bul (4/4):

```swift
}

ring(radius: 62, fraction: 0.68, red: 0.188, green: 0.82, blue: 0.345)  // CPU green #30d158
ring(radius: 36, fraction: 0.45, red: 0.039, green: 0.518, blue: 1)     // RAM blue #0a84ff

guard let image = context.makeImage(),
```

Şununla değiştir:

```swift
}

ring(radius: 62, fraction: 0.7, red: 0, green: 0.761, blue: 1)        // CPU #00c2ff
ring(radius: 36, fraction: 0.45, red: 0.239, green: 0.42, blue: 1)    // RAM #3d6bff

guard let image = context.makeImage(),
```

- [ ] **Step 4: Paketi kur ve denetle**

Run: `make app 2>&1 | tail -1` → Expected: `Built …/build/PhoneBox.app`.
Run: `ls build/PhoneBox.app/Contents/Resources/` → Expected: `AppIcon.icns`, `LICENSE`, `THIRD_PARTY_NOTICES.md` var.
Run: `codesign --verify --strict build/PhoneBox.app && echo ok` → Expected: `ok`.
Uygulamayı açma.

- [ ] **Step 5: Commit**

```bash
git add scripts/make-icon.swift LICENSE scripts/bundle.sh Resources/Info.plist scripts/make-touch-icon.swift
git commit -m "Give PhoneBox an app icon and ship its licence and notices inside the app" -m "The Home Screen icon takes the page's colours too."
```

---

### Task 4: Ertelenen sağlamlık düzeltmeleri

**Files:**
- Modify: `Sources/PhoneBox/Collectors/BatteryCollector.swift`, `Sources/PhoneBox/AppDelegate.swift`,
  `Sources/PhoneBox/NowPlayingService.swift`, `Sources/PhoneBox/Collectors/PhoneBatteryReader.swift`

**Interfaces:**
- Produces: `BatteryCollector.hasInternalBattery() -> Bool`; `NowPlayingService.healthyRun`;
  `MobileDeviceAPI.shared`; `PhoneBatteryReader.retryDelay`, `.maxRetries`.

Üç düzeltme (Plan 4A ve 4C son incelemeleri):
- Dizüstü Mac, pil o an okunamasa da dizüstü sayılır (güç sınırı "Mac'in tamamı" sütunundan).
- Medya adaptörü her açılışta bir satır yazıp çökse de yeniden başlatmalar yavaşlar; sayaç yalnız 30 sn çalışmış bir
  adaptörde sıfırlanır.
- Telefonun pil okuyucusu: MobileDevice ilk kullanımda yüklenir; `subscribe` sürerken bildirilen telefonlar alınır;
  olmayan okuma 10 sn sonra yeniden denenir (en çok 3 kez); iki telefondan biri çıkınca kalan okunur; bildirim bir gün
  ana iş parçacığı dışında gelirse aygıt tutulup ana iş parçacığına geçilir.

- [ ] **Step 1: Pil, adaptör ve okuyucu**

`Sources/PhoneBox/Collectors/BatteryCollector.swift`:

Bul:

```swift
final class BatteryCollector {
    func sample() -> BatterySample? {
```

Şununla değiştir:

```swift
final class BatteryCollector {
    /// True on a Mac with an internal battery, even when its values cannot be read right now: decides whether the
    /// power figure is the whole Mac's or only the GPU's (design §6).
    static func hasInternalBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }
        return sources.contains { source in
            let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            return description?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }

    func sample() -> BatterySample? {
```

`Sources/PhoneBox/AppDelegate.swift`:

Bul:

```swift
        // A Mac with a battery reports its whole power draw; a desktop Mac only the GPU's.
        let powerLimits = PowerLimits.forChip(Settings.chipName(), wholeMac: BatteryCollector().sample() != nil)
        hub = DashboardHub(mode: settings.mode, key: key, appName: "PhoneBox \(version)", hostName: Settings.computerName(),
```

Şununla değiştir:

```swift
        // A Mac with a battery reports its whole power draw; a desktop Mac only the GPU's.
        let powerLimits = PowerLimits.forChip(Settings.chipName(), wholeMac: BatteryCollector.hasInternalBattery())
        hub = DashboardHub(mode: settings.mode, key: key, appName: "PhoneBox \(version)", hostName: Settings.computerName(),
```

`Sources/PhoneBox/NowPlayingService.swift`:

Bul (1/5):

```swift
    static let restartDelays: [TimeInterval] = [1, 2, 5, 10, 30]

    private let location: AdapterLocation?
```

Şununla değiştir:

```swift
    static let restartDelays: [TimeInterval] = [1, 2, 5, 10, 30]
    /// An adapter that ran this long before it exited counts as healthy: the next restart waits only 1 s again.
    static let healthyRun: TimeInterval = 30

    private let location: AdapterLocation?
```

Bul (2/5):

```swift
    private var failures = 0
    private var names: [String: String] = [:]
```

Şununla değiştir:

```swift
    private var failures = 0
    private var startedAt = Date.distantPast
    private var names: [String: String] = [:]
```

Bul (3/5):

```swift
            self.process = process
        } catch {
```

Şununla değiştir:

```swift
            self.process = process
            startedAt = Date()
        } catch {
```

Bul (4/5):

```swift
        for line in assembler.append(data) {
            let parsed = NowPlayingStream.parse(line)
            if parsed != .invalid { failures = 0 }
            state.received(parsed, at: Date())
        }
```

Şununla değiştir:

```swift
        for line in assembler.append(data) {
            state.received(NowPlayingStream.parse(line), at: Date())
        }
```

Bul (5/5):

```swift
        Log.app.notice("The media adapter exited with status \(finished.terminationStatus)")
        scheduleRestart()
```

Şununla değiştir:

```swift
        Log.app.notice("The media adapter exited with status \(finished.terminationStatus)")
        if Date().timeIntervalSince(startedAt) >= Self.healthyRun { failures = 0 }
        scheduleRestart()
```

`Sources/PhoneBox/Collectors/PhoneBatteryReader.swift`:

Bul (1/9):

```swift
    let copyValue: CopyValue

    static func load() -> MobileDeviceAPI? {
```

Şununla değiştir:

```swift
    let copyValue: CopyValue

    /// Loaded on first use (the framework is not opened at launch); nil if it is missing.
    static let shared = load()

    static func load() -> MobileDeviceAPI? {
```

Bul (2/9):

```swift
/// Reads the battery of the iPhone plugged in over USB (design §6 `phone`): a moment after it is plugged in and
/// then once a minute, only between `start()` and `stop()` (while the sampler runs). Reads run on their own queue,
/// one at a time, so they never hold up a snapshot. With two iPhones plugged in there is no "the" phone and
/// `latest` is nil.
@MainActor
```

Şununla değiştir:

```swift
/// Reads the battery of the iPhone plugged in over USB (design §6 `phone`): a moment after it is plugged in and
/// then once a minute, only between `start()` and `stop()` (while the sampler runs). A failed read (the phone still
/// waking, or asking whether to trust this Mac) is tried again after 10 s, up to 3 times. Reads run on their own
/// queue, one at a time, so they never hold up a snapshot. With two iPhones plugged in there is no "the" phone and
/// `latest` is nil; unplugging one reads the other.
@MainActor
```

Bul (3/9):

```swift
    static let settleDelay: TimeInterval = 2

    private let api = MobileDeviceAPI.load()
    private let queue = DispatchQueue(label: "com.phonebox.PhoneBox.phone-battery", qos: .utility)
```

Şununla değiştir:

```swift
    static let settleDelay: TimeInterval = 2
    static let retryDelay: TimeInterval = 10
    static let maxRetries = 3

    private var api: MobileDeviceAPI? { MobileDeviceAPI.shared }
    private let queue = DispatchQueue(label: "com.phonebox.PhoneBox.phone-battery", qos: .utility)
```

Bul (4/9):

```swift
    private var reading = false

    /// The last good reading of the one iPhone on USB, at most 5 minutes old.
```

Şununla değiştir:

```swift
    private var reading = false
    /// Failed reads in a row since the last good one or the last plug-in.
    private var retries = 0
    /// True while `subscribe` runs: phones already plugged in may be reported before it returns.
    private var subscribing = false

    /// The last good reading of the one iPhone on USB, at most 5 minutes old.
```

Bul (5/9):

```swift
            let reader = Unmanaged<PhoneBatteryReader>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { reader.deviceChanged(device, message: message) }
        }
        var subscription: UnsafeMutableRawPointer?
        guard api.subscribe(callback, 0, 0, context, &subscription) == 0 else {
```

Şununla değiştir:

```swift
            let reader = Unmanaged<PhoneBatteryReader>.fromOpaque(context).takeUnretainedValue()
            if Thread.isMainThread {
                MainActor.assumeIsolated { reader.deviceChanged(device, message: message) }
                return
            }
            // Not the main thread after all: keep the device alive until the main thread has seen it.
            guard let api = MobileDeviceAPI.shared else { return }
            _ = api.retain(device.pointer)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { reader.deviceChanged(device, message: message) }
                api.release(device.pointer)
            }
        }
        var subscription: UnsafeMutableRawPointer?
        subscribing = true
        defer { subscribing = false }
        guard api.subscribe(callback, 0, 0, context, &subscription) == 0 else {
```

Bul (6/9):

```swift
    private func deviceChanged(_ device: DeviceRef, message: UInt32) {
        guard let api, subscription != nil else { return }
        switch message {
```

Şununla değiştir:

```swift
    private func deviceChanged(_ device: DeviceRef, message: UInt32) {
        guard let api, subscription != nil || subscribing else { return }
        switch message {
```

Bul (7/9):

```swift
            memory.forget()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
                MainActor.assumeIsolated { self?.read() }
            }
        case MobileDeviceAPI.disconnected:
```

Şununla değiştir:

```swift
            memory.forget()
            retries = 0
            read(after: Self.settleDelay)
        case MobileDeviceAPI.disconnected:
```

Bul (8/9):

```swift
            memory.forget()
        default:
            break
        }
```

Şununla değiştir:

```swift
            memory.forget()
            // Two phones were plugged in and one is left: it is "the" phone now.
            if devices.count == 1 {
                retries = 0
                read(after: Self.settleDelay)
            }
        default:
            break
        }
    }

    private func read(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.read() }
        }
```

Bul (9/9):

```swift
        // The phone may have been unplugged, or another one plugged in, while it was read.
        guard let sample, devices == [device] else { return }
        memory.remember(sample, at: Date())
```

Şununla değiştir:

```swift
        // The phone may have been unplugged, or another one plugged in, while it was read.
        guard subscription != nil, devices == [device] else { return }
        guard let sample else {
            guard retries < Self.maxRetries else { return }
            retries += 1
            read(after: Self.retryDelay)
            return
        }
        retries = 0
        memory.remember(sample, at: Date())
```

- [ ] **Step 2: Testleri çalıştır**

Bu üçü donanıma bağlı; birim testi yok (pil okuyucusunun canlı testini kontrolcü çalıştırır).
Run: iki uyarı denetimi → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 20 tests in 7 suites passed` ve `Test run with 199 tests in 36 suites passed`.

- [ ] **Step 3: Commit**

```bash
git add Sources/PhoneBox/Collectors/BatteryCollector.swift Sources/PhoneBox/AppDelegate.swift \
  Sources/PhoneBox/NowPlayingService.swift Sources/PhoneBox/Collectors/PhoneBatteryReader.swift
git commit -m "Keep the phone battery, the media adapter and the power limit steady through hiccups"
```

---

### Task 5: Kurulum, zip ve sürüm betikleri

**Files:**
- Create: `install.sh`, `scripts/dist.sh`, `scripts/release.sh` (üçü de çalıştırılabilir: `chmod +x`)
- Modify: `Makefile`

**Interfaces:**
- Produces: `install.sh` (`--uninstall`; `PHONEBOX_ZIP`, `PHONEBOX_DEST`, `PHONEBOX_NO_OPEN`, `PHONEBOX_VERSION`);
  `make dist` → `dist/PhoneBox-<sürüm>.zip`; `make release VERSION=x.y.z` (`DRY_RUN=1`).

- [ ] **Step 1: Kurulum betiği**

`install.sh`:

```bash
#!/bin/bash
# Installs, updates or removes PhoneBox.
#
#   Install or update:  curl -fsSL https://raw.githubusercontent.com/cyesaa/phone-box/main/install.sh | bash
#   A given version:    curl -fsSL https://raw.githubusercontent.com/cyesaa/phone-box/main/install.sh | PHONEBOX_VERSION=0.1.0 bash
#   Uninstall:          curl -fsSL https://raw.githubusercontent.com/cyesaa/phone-box/main/install.sh | bash -s -- --uninstall
#
# Files downloaded with curl are not quarantined, so macOS does not block the (not notarized) app.
# For testing: PHONEBOX_ZIP=<local zip> uses that file instead of downloading, PHONEBOX_DEST=<dir> installs somewhere
# else, PHONEBOX_NO_OPEN=1 does not start the app afterwards.
set -euo pipefail

REPO="cyesaa/phone-box"
BUNDLE_ID="com.phonebox.PhoneBox"
APP="PhoneBox.app"
ASSET="PhoneBox.zip"

WORK=""
cleanup() { [ -z "$WORK" ] || rm -rf "$WORK"; }
trap cleanup EXIT

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

check_mac() {
  [ "$(uname -s)" = "Darwin" ] || fail "PhoneBox runs only on macOS."
  [ "$(uname -m)" = "arm64" ] || fail "PhoneBox needs a Mac with Apple silicon (M1 or later)."
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [ "$major" -ge 14 ] || fail "PhoneBox needs macOS 14 or later (this Mac has $(sw_vers -productVersion))."
}

# /Applications when it is writable, otherwise ~/Applications (no admin rights needed).
destination() {
  if [ -n "${PHONEBOX_DEST:-}" ]; then
    echo "$PHONEBOX_DEST"
  elif [ -w /Applications ]; then
    echo /Applications
  else
    echo "$HOME/Applications"
  fi
}

# -a: pgrep and pkill skip their own ancestors by default, and when PhoneBox runs this script to update itself,
# PhoneBox is one of them.
quit_running_app() {
  pgrep -ax PhoneBox >/dev/null || return 0
  say "Quitting the running PhoneBox"
  pkill -ax PhoneBox || true
  for _ in $(seq 1 50); do
    pgrep -ax PhoneBox >/dev/null || return 0
    sleep 0.1
  done
  fail "PhoneBox did not quit. Quit it from its menu bar icon and run this again."
}

# A test install (PHONEBOX_DEST) leaves a PhoneBox that runs from another folder alone.
should_quit() {
  [ -n "${PHONEBOX_DEST:-}" ] || return 0
  local pid path
  for pid in $(pgrep -ax PhoneBox || true); do
    path="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
    case "$path" in "$1"/*) return 0 ;; esac
  done
  return 1
}

install() {
  check_mac
  local dest zip
  dest="$(destination)"
  WORK="$(mktemp -d)"

  if [ -n "${PHONEBOX_ZIP:-}" ]; then
    zip="$PHONEBOX_ZIP"
    say "Using $zip"
  else
    local url
    if [ -n "${PHONEBOX_VERSION:-}" ]; then
      url="https://github.com/$REPO/releases/download/v${PHONEBOX_VERSION#v}/$ASSET"
    else
      url="https://github.com/$REPO/releases/latest/download/$ASSET"
    fi
    zip="$WORK/$ASSET"
    say "Downloading PhoneBox ${PHONEBOX_VERSION:-(latest)}"
    curl -fL --progress-bar "$url" -o "$zip" || fail "Download failed: $url (is there such a release?)"
  fi

  ditto -x -k "$zip" "$WORK/unpacked" || fail "The download is not a valid zip."
  [ -d "$WORK/unpacked/$APP" ] || fail "The zip does not contain $APP."
  codesign --verify --deep --strict "$WORK/unpacked/$APP" 2>/dev/null || fail "$APP failed its signature check."

  if should_quit "$dest"; then quit_running_app; fi
  mkdir -p "$dest"
  rm -rf "${dest:?}/$APP"
  ditto "$WORK/unpacked/$APP" "$dest/$APP"
  # Only browsers add this, but a zip someone passed along may carry it.
  xattr -dr com.apple.quarantine "$dest/$APP" 2>/dev/null || true

  local version
  version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$dest/$APP/Contents/Info.plist" 2>/dev/null || echo "?")"
  say "Installed PhoneBox $version in $dest"
  if [ -z "${PHONEBOX_NO_OPEN:-}" ]; then
    open "$dest/$APP"
    say "PhoneBox is running: look for the phone icon in the menu bar."
  fi
  echo "    Plug in your iPhone with its cable; the QR code opens the first time. Scan it with the iPhone's camera."
  echo "    If macOS asks whether PhoneBox may accept incoming connections, allow it: that is how the iPhone reaches it."
}

uninstall() {
  local removed=0 dir dirs
  # With PHONEBOX_DEST (a test install) only that copy goes; settings, the pairing key and permissions stay.
  if [ -n "${PHONEBOX_DEST:-}" ]; then
    dirs=("$PHONEBOX_DEST")
  else
    dirs=(/Applications "$HOME/Applications")
  fi
  for dir in "${dirs[@]}"; do
    if should_quit "$dir"; then quit_running_app; break; fi
  done
  for dir in "${dirs[@]}"; do
    [ -d "$dir/$APP" ] || continue
    rm -rf "${dir:?}/$APP"
    say "Removed $dir/$APP"
    removed=1
  done
  [ "$removed" = 1 ] || say "PhoneBox was not installed in ${dirs[*]}."
  [ -z "${PHONEBOX_DEST:-}" ] || return 0
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  rm -rf "$HOME/Library/Application Support/PhoneBox" "$HOME/Library/Logs/PhoneBox"
  tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1 || true
  say "Removed PhoneBox's settings, pairing key and permissions. On the iPhone, delete its Home Screen icon."
}

case "${1:-}" in
  --uninstall) uninstall ;;
  "") install ;;
  *) fail "Unknown option: $1 (use --uninstall to remove PhoneBox)" ;;
esac
```

- [ ] **Step 2: Zip ve sürüm betikleri**

`scripts/dist.sh`:

```bash
#!/usr/bin/env bash
# Zips build/PhoneBox.app into dist/PhoneBox-<version>.zip for GitHub Releases.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/PhoneBox.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
ZIP="$ROOT/dist/PhoneBox-$VERSION.zip"

if [ ! -d "$APP" ]; then
  echo "error: $APP not found. Run: make app" >&2
  exit 1
fi

mkdir -p "$ROOT/dist"
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"

CHECK="$(mktemp -d)"
if ! { ditto -x -k "$ZIP" "$CHECK" && codesign --verify --deep --strict "$CHECK/PhoneBox.app"; }; then
  rm -rf "$CHECK"
  echo "error: $ZIP failed signature verification" >&2
  exit 1
fi
rm -rf "$CHECK"
echo "Created $ZIP"
```

`scripts/release.sh`:

```bash
#!/usr/bin/env bash
# Publishes PhoneBox <version> on GitHub Releases: make release VERSION=0.2.0
#
# From a clean main that matches origin/main, this sets the version in Resources/Info.plist, runs the
# tests, builds dist/PhoneBox-<version>.zip, commits "Release <version>", tags v<version>, pushes both,
# creates the GitHub release with generated notes and uploads the zip as PhoneBox.zip (the stable name
# install.sh downloads). Works while the repository is private too; install.sh only works while it is public.
#
# Token: $GITHUB_TOKEN if set, otherwise the GitHub CLI's (`gh auth token`), otherwise the github.com credential git
# already uses (Keychain).
# DRY_RUN=1 does every check and build but changes nothing in git or on GitHub.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/Resources/Info.plist"
VERSION="${1:-}"
DRY_RUN="${DRY_RUN:-}"

fail() { echo "error: $*" >&2; exit 1; }
say() { printf '\033[1m==>\033[0m %s\n' "$*"; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "usage: make release VERSION=x.y.z"
cd "$ROOT"

# owner/name from the origin URL (https or ssh).
REPO="$(git remote get-url origin | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##')"
[[ "$REPO" =~ ^[^/]+/[^/]+$ ]] || fail "origin is not a GitHub repository: $(git remote get-url origin)"

[ -z "$(git status --porcelain)" ] || fail "commit or stash your changes first"
[ "$(git branch --show-current)" = "main" ] || fail "switch to main first"
git fetch --quiet --tags origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main is not the same as origin/main; pull or push first"
! git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || fail "tag v$VERSION already exists"

CURRENT="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")"
say "PhoneBox $CURRENT (build $BUILD) -> $VERSION (build $((BUILD + 1)))"

restore_plist() { git checkout -- "$PLIST"; }
[ -z "$DRY_RUN" ] || trap restore_plist EXIT
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $((BUILD + 1))" "$PLIST"

say "Testing"
make test >/dev/null
say "Building"
make dist >/dev/null
ZIP="$ROOT/dist/PhoneBox-$VERSION.zip"
[ -f "$ZIP" ] || fail "$ZIP was not built"

if [ -n "$DRY_RUN" ]; then
  say "Dry run: built $ZIP; would commit, tag v$VERSION, push and publish to $REPO"
  exit 0
fi

TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$TOKEN" ] && command -v gh >/dev/null; then
  TOKEN="$(gh auth token 2>/dev/null || true)"
fi
if [ -z "$TOKEN" ]; then
  TOKEN="$(printf 'protocol=https\nhost=github.com\n\n' | GIT_TERMINAL_PROMPT=0 git credential fill 2>/dev/null | sed -n 's/^password=//p')"
fi
[ -n "$TOKEN" ] || fail "no GitHub token: set GITHUB_TOKEN or sign in to github.com with git"

say "Committing and tagging v$VERSION"
git commit --quiet -m "Release $VERSION" -- "$PLIST"
git tag -a "v$VERSION" -m "PhoneBox $VERSION"
git push --quiet origin main "v$VERSION"

api() {
  curl -fsS -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" "$@"
}

say "Creating the GitHub release"
BODY="$(cat <<EOF
Install or update with one command in Terminal:

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash
\`\`\`

Or download PhoneBox.zip below, unzip it, move PhoneBox.app to /Applications and run
\`xattr -dr com.apple.quarantine /Applications/PhoneBox.app\` before opening it.

Needs a Mac with Apple silicon and macOS 14 or later, and an iPhone with its USB cable. Nothing is installed on the
iPhone: the dashboard opens in Safari.
EOF
)"
PAYLOAD="$(TAG="v$VERSION" NAME="PhoneBox $VERSION" BODY="$BODY" /usr/bin/python3 -c \
  'import json, os; print(json.dumps({"tag_name": os.environ["TAG"], "name": os.environ["NAME"], "body": os.environ["BODY"], "generate_release_notes": True}))')"
RELEASE="$(api -X POST "https://api.github.com/repos/$REPO/releases" -d "$PAYLOAD")"
RELEASE_ID="$(printf '%s' "$RELEASE" | /usr/bin/python3 -c 'import json, sys; print(json.load(sys.stdin)["id"])')"
RELEASE_URL="$(printf '%s' "$RELEASE" | /usr/bin/python3 -c 'import json, sys; print(json.load(sys.stdin)["html_url"])')"

say "Uploading PhoneBox.zip"
api -X POST -H "Content-Type: application/zip" --data-binary "@$ZIP" \
  "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=PhoneBox.zip" >/dev/null

say "Published $RELEASE_URL"
```

`Makefile`:

Bul (1/2):

```
endif

.PHONY: build test adapter app run clean

build:
```

Şununla değiştir:

```
endif

.PHONY: build test adapter app run dist release clean

build:
```

Bul (2/2):

```
	open build/PhoneBox.app

clean:
	rm -rf .build build
```

Şununla değiştir:

```
	open build/PhoneBox.app

# build/PhoneBox.app zipped into dist/PhoneBox-<version>.zip, its signature checked.
dist: app
	scripts/dist.sh

# Publishes a GitHub release from a clean, pushed main: make release VERSION=0.2.0 (DRY_RUN=1 to rehearse).
release:
	scripts/release.sh $(VERSION)

clean:
	rm -rf .build build dist
```

Run: `chmod +x install.sh scripts/dist.sh scripts/release.sh`

- [ ] **Step 3: Geçici bir klasöre kur ve kaldır** (kullanıcının PhoneBox'ına dokunmaz)

Run: `bash -n install.sh && bash -n scripts/dist.sh && bash -n scripts/release.sh && echo ok` → Expected: `ok`.
Run: `make dist 2>&1 | tail -1` → Expected: `Created …/dist/PhoneBox-0.1.0.zip`.
Run:
```bash
T=$(mktemp -d) && PHONEBOX_ZIP=dist/PhoneBox-0.1.0.zip PHONEBOX_DEST=$T PHONEBOX_NO_OPEN=1 ./install.sh && ls $T \
  && PHONEBOX_DEST=$T ./install.sh --uninstall && ls -A $T; rm -rf $T
```
Expected: "Installed PhoneBox 0.1.0 in …", `PhoneBox.app`, sonra "Removed …/PhoneBox.app" ve boş klasör. Başka yerden
çalışan bir PhoneBox varsa açık kalır (`pgrep -x PhoneBox` önce ve sonra aynı).
`make release` çalıştırma.

- [ ] **Step 4: Commit**

```bash
git add install.sh scripts/dist.sh scripts/release.sh Makefile
git commit -m "Install, update and remove PhoneBox with one command, and publish releases"
```

---

### Task 6: README ve tasarım

**Files:**
- Create: `README.md`
- Modify: `docs/design/2026-11-25-phonebox-design.md`

- [ ] **Step 1: README** (önce Türkçe, sonra İngilizce; `docs/images/dashboard.png`'yi kontrolcü ekler)

`README.md`:

````markdown
# PhoneBox

**Türkçe** · [English](#english)

Mac'inin canlı durumunu iPhone'unda gösteren bir menü çubuğu uygulaması. iPhone'u kabloyla Mac'e tak, telefonu
masanın yanına koy: CPU, RAM, GPU, sıcaklık, güç, ağ, disk, pil, en çok kaynak kullanan uygulamalar ve çalan
şarkı bir bakışta görünür. Bir değer sınırına yaklaştıkça kızarır, sınırda kalınca ekranın kenarı kırmızı yanar.

Telefona hiçbir şey kurulmaz: dashboard, Mac'teki PhoneBox'ın sunduğu bir web sayfasıdır ve Safari'de (ya da
Chrome'da) açılır. Veri iPhone takılıyken USB kablosu üzerinden gider.

![PhoneBox dashboard'u iPhone'da](docs/images/dashboard.png)

## Neler var

- **Halkalar:** CPU ve RAM; RAM, macOS'un bellek baskısına göre kızarır.
- **Son 60 saniyenin grafiği:** bir halkaya ya da kutucuğa dokununca grafik o metriğe geçer.
- **Kutucuklar:** GPU, sıcaklık, Mac'in çektiği güç, ağ hızı, boş disk, pil.
- **Uygulamalar:** en çok CPU ya da bellek kullananlar. Birine dokun: kapat ya da zorla kapat.
- **Şimdi çalıyor:** önceki / oynat-duraklat / sonraki, ses seviyesi, sessiz.
- **"⋯" menüsü:** Mac'i kilitle, ekranı kapat, uyut (uyutmadan önce sorar).
- **Saat, tarih ve telefonun pili** köşede; telefon yatayken bütün değerler bir arada, dikeyken "tek bakış" düzeni.
- Türkçe ve İngilizce, telefonun ve Mac'in diline göre.

## Gereksinimler

- Apple Silicon'lu (M1 ya da sonrası) bir Mac, macOS 14 ya da üstü.
- Bir iPhone ve kablosu. iPhone'un bu Mac'e "Güven" demiş olması yeterli.

## Kurulum

Terminal'i aç ve şunu yapıştır:

```bash
curl -fsSL https://raw.githubusercontent.com/cyesaa/phone-box/main/install.sh | bash
```

PhoneBox `/Applications` klasörüne kurulur (yazılamıyorsa `~/Applications`) ve açılır; menü çubuğunda bir telefon
simgesi belirir. Uygulama Apple tarafından onaylanmış (notarize) değildir; `curl` ile indirilen dosya karantinaya
alınmadığı için macOS onu engellemez.

## İlk kullanım

1. iPhone'u kabloyla Mac'e tak. İlk seferde Mac'te bir QR kodu açılır (sonra menüden "QR kodunu göster…").
2. QR kodunu iPhone'un kamerasıyla okut; dashboard tarayıcıda açılır.
3. "Başlat"a bir kez dokun: ekran açık kalır.
4. Paylaş → **Ana Ekrana Ekle**. Ana ekrandaki simgeden açınca dashboard tam ekran olur.
5. Telefonu yan çevir ve bir standa koy.

Dashboard'un "⋯" menüsündeki **Kurulum rehberi** bu adımları telefonda da gösterir. Kablo takılınca dashboard'un
kendiliğinden açılması için isteğe bağlı bir Kestirmeler otomasyonu da orada anlatılır.

## Menü çubuğu

| Öğe | Ne yapar |
|---|---|
| Durum satırı | "iPhone bağlı · 1 cihaz", "Telefon Wi-Fi'de: kabloyu tak" gibi |
| QR kodunu göster… | Eşleştirme bağlantısı; başka bir telefonu eklemek için |
| Veri gönder | **Sadece kablo takılıyken** (varsayılan) ya da **Her zaman, Wi-Fi'de de** |
| Port: 4747… | Dashboard'un portu; değiştirince telefonun yeni QR kodunu okutması gerekir |
| Girişte başlat | Mac açılınca PhoneBox da açılır |
| Eşleştirmeyi sıfırla… | Yeni anahtar: eşleşmiş bütün telefonların bağlantısı kesilir |
| Güncellemeleri denetle… | Yeni sürüm varsa yükler (aşağıya bak) |

## Güvenlik ve gizlilik

- Eşleştirme anahtarı QR kodundaki bağlantının `#` sonrasında durur ve hiçbir zaman sunucuya gönderilmez. Telefon
  her bağlantıda bu anahtarla kimliğini kanıtlar; her komut da bu anahtarla imzalanır.
- Komutlar (uygulama kapatma, medya, ses, kilitleme, uyutma) **yalnızca kablodan** kabul edilir; Wi-Fi'deki bir
  telefon sadece izler.
- Sayfa düz HTTP ile sunulur. "Her zaman" modunda aynı Wi-Fi'deki biri CPU değerlerini ve uygulama adlarını görebilir;
  bu yüzden varsayılan mod "sadece kablo takılıyken"dir.
- PhoneBox internete yalnızca güncellemeleri denetlemek için çıkar (GitHub, günde iki kez). Kapatmak için:
  `defaults write com.phonebox.PhoneBox CheckForUpdatesAutomatically -bool false`

## Güncelleme

PhoneBox yeni bir sürüm çıkınca menüde "PhoneBox x.y.z sürümünü yükle…" gösterir; "Güncellemeleri denetle…" ile
elle de bakabilirsin. Yükleme PhoneBox'ı kapatır, yenisini yerine koyar ve açar; telefon kendiliğinden yeniden
bağlanır. Kurulum komutunu yeniden çalıştırmak da günceller.

## Kaldırma

```bash
curl -fsSL https://raw.githubusercontent.com/cyesaa/phone-box/main/install.sh | bash -s -- --uninstall
```

Uygulamayı, ayarlarını, eşleştirme anahtarını ve kayıtlarını siler. Telefondaki ana ekran simgesini elle sil.

## Sorun giderme

- **Dashboard "Kabloyu tak" diyor:** telefon Wi-Fi'den bağlı. Kabloyu tak ya da menüden "Her zaman, Wi-Fi'de de"yi
  seç.
- **QR kodu okuttum ama sayfa açılmıyor:** iPhone ile Mac aynı ağda olmalı ya da iPhone kabloyla takılı olmalı.
  macOS PhoneBox'ın gelen bağlantıları kabul etmesini sorduysa izin ver (Sistem Ayarları → Ağ → Güvenlik Duvarı).
- **"Port 4747 kullanımda":** menüden başka bir port seç ve yeni QR kodunu okut.
- **Müzik, ses ya da uygulama komutları çalışmıyor:** komutlar yalnızca kablodan çalışır; kablonun takılı olduğuna
  bak.
- **Ekran kararıyor:** dashboard'u açtıktan sonra "Başlat"a dokun. Olmazsa Ayarlar → Ekran ve Parlaklık → Otomatik
  Kilit'i "Asla" yap.

## Kaynaktan derleme

Xcode'un Komut Satırı Araçları yeterli (`xcode-select --install`).

```bash
git clone --recurse-submodules https://github.com/cyesaa/phone-box.git
cd phone-box
make app      # build/PhoneBox.app
make run      # derler ve açar
make test
```

Daha önce alt modülsüz klonladıysan: `git submodule update --init`. Tasarım ve planlar `docs/design/` altında
(Türkçe).

## Lisans

MIT, bkz. [LICENSE](LICENSE). PhoneBox, çalan şarkıyı okumak için
[mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)'ı (BSD 3-Clause) içerir; bkz.
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

<a id="english"></a>

# PhoneBox (English)

A menu bar app that shows your Mac's live state on your iPhone. Plug the iPhone into the Mac with its cable and set
it beside the desk: CPU, RAM, GPU, temperature, power, network, disk, battery, the busiest apps and the song that is
playing, at a glance. A value turns red as it nears its limit, and the screen's edge lights up red while it stays
there.

Nothing is installed on the phone: the dashboard is a web page that PhoneBox serves from the Mac, opened in Safari
(or Chrome). While the iPhone is plugged in, the data travels over the USB cable.

## What it shows

- **Rings:** CPU and RAM; RAM turns red by macOS's memory pressure.
- **The last 60 seconds as a graph:** tap a ring or a tile to graph that metric.
- **Tiles:** GPU, temperature, the Mac's power draw, network speed, free disk, battery.
- **Apps:** the ones using the most CPU or memory. Tap one to quit or force quit it.
- **Now playing:** previous / play-pause / next, volume, mute.
- **The "⋯" menu:** lock the Mac, turn its display off, put it to sleep (it asks first).
- **Clock, date and the phone's own battery** in the corner; everything at once in landscape, a single-glance layout
  in portrait.
- English and Turkish, following the phone's and the Mac's language.

## Requirements

- A Mac with Apple silicon (M1 or later), macOS 14 or later.
- An iPhone and its cable. The iPhone only has to trust this Mac.

## Install

Open Terminal and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/cyesaa/phone-box/main/install.sh | bash
```

PhoneBox is installed in `/Applications` (or `~/Applications` when that is not writable) and opened; a phone icon
appears in the menu bar. The app is not notarized by Apple; files downloaded with `curl` are not quarantined, so macOS
does not block it.

## First run

1. Plug the iPhone into the Mac. The first time, a QR code opens on the Mac (later: "Show QR Code…" in the menu).
2. Scan it with the iPhone's camera; the dashboard opens in the browser.
3. Tap "Start" once: the screen stays on.
4. Share → **Add to Home Screen**. Opened from the Home Screen icon, the dashboard is full screen.
5. Turn the phone sideways and put it on a stand.

**Setup guide** in the dashboard's "⋯" menu shows these steps on the phone, along with an optional Shortcuts
automation that opens the dashboard when the cable is plugged in.

## Menu bar

| Item | What it does |
|---|---|
| Status line | e.g. "iPhone connected · 1", "Phone on Wi-Fi: plug in the cable" |
| Show QR Code… | The pairing link, to add another phone |
| Send data | **Only While the Cable Is Plugged In** (default) or **Always, Also over Wi-Fi** |
| Port: 4747… | The dashboard's port; after a change the phone scans the new QR code |
| Open at Login | PhoneBox starts with the Mac |
| Reset Pairing… | A new key: every paired phone is disconnected |
| Check for Updates… | Installs a newer version if there is one (see below) |

## Security and privacy

- The pairing key sits after the `#` of the QR code's link and is never sent to a server. The phone proves itself with
  it on every connection, and every command is signed with it.
- Commands (quitting apps, media, volume, lock, sleep) are accepted **only over the cable**; a phone on Wi-Fi only
  watches.
- The page is served over plain HTTP. In "Always" mode someone on the same Wi-Fi could see the CPU figures and app
  names, which is why the default is "only while the cable is plugged in".
- PhoneBox goes online only to check for updates (GitHub, twice a day). To turn that off:
  `defaults write com.phonebox.PhoneBox CheckForUpdatesAutomatically -bool false`

## Updating

When a new version is out, the menu shows "Install PhoneBox x.y.z…"; "Check for Updates…" looks right away. Installing
quits PhoneBox, puts the new version in place and opens it; the phone reconnects by itself. Running the install
command again updates too.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/cyesaa/phone-box/main/install.sh | bash -s -- --uninstall
```

This removes the app, its settings, the pairing key and its logs. Delete the Home Screen icon on the phone by hand.

## Troubleshooting

- **The dashboard says "Plug in the cable":** the phone is connected over Wi-Fi. Plug in the cable, or choose
  "Always, Also over Wi-Fi" in the menu.
- **The QR code opens nothing:** the iPhone has to be on the Mac's network or plugged into it. If macOS asked whether
  PhoneBox may accept incoming connections, allow it (System Settings → Network → Firewall).
- **"Port 4747 is in use":** choose another port in the menu and scan the new QR code.
- **Music, volume or app commands do nothing:** commands work only over the cable; check that it is plugged in.
- **The screen goes dark:** tap "Start" after opening the dashboard. If it still does, set Settings → Display &
  Brightness → Auto-Lock to "Never".

## Building from source

The Xcode Command Line Tools are enough (`xcode-select --install`).

```bash
git clone --recurse-submodules https://github.com/cyesaa/phone-box.git
cd phone-box
make app      # build/PhoneBox.app
make run      # builds and opens it
make test
```

If you cloned without submodules: `git submodule update --init`. The design and plans are in `docs/design/`
(in Turkish).

## License

MIT, see [LICENSE](LICENSE). PhoneBox includes [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
(BSD 3-Clause) to read what is playing; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
````

- [ ] **Step 2: Tasarım**

`docs/design/2026-11-25-phonebox-design.md`:

Bul (1/5):

```markdown
  | Uygulama satırı | %60 | %200 | uygulamanın CPU'su (iki çekirdek dolu = %200) |

  Güç sınırı (watt, `power.system` için; masaüstü Mac'te `power.gpu` için ikinci sütun). Değerler tahmindir, README'de
  "topluluk testine açık" diye belirtilir; M4'te telefon denemesinde gerçek yükle kontrol edilir:

  | Çip (`machdep.cpu.brand_string`) | Mac'in tamamı | Yalnız GPU |
```

Şununla değiştir:

```markdown
  | Uygulama satırı | %60 | %200 | uygulamanın CPU'su (iki çekirdek dolu = %200) |

  Güç sınırı (watt, `power.system` için; masaüstü Mac'te `power.gpu` için ikinci sütun). Dahili pili olan Mac
  (pilin değerleri o an okunamasa da) "Mac'in tamamı" sütununu kullanır. Değerler tahmindir; M4'te telefon denemesinde
  gerçek yükle kontrol edilir:

  | Çip (`machdep.cpu.brand_string`) | Mac'in tamamı | Yalnız GPU |
```

Bul (2/5):

```markdown
  alanı varsa görünür; Wi-Fi'deki sayfada yerinde "Wi-Fi" yazar.

### Sayfa kodu
```

Şununla değiştir:

```markdown
  alanı varsa görünür; Wi-Fi'deki sayfada yerinde "Wi-Fi" yazar.
- **Pilin okunması (Mac):** MobileDevice ilk kullanımda yüklenir. Telefon takılınca 2 sn sonra, sonra dakikada bir
  okunur; okuma olmazsa (telefon uyanıyor ya da "Güven" soruyor) 10 sn sonra yeniden denenir, en çok 3 kez. İki
  telefondan biri çıkarılınca kalan okunur.

### Sayfa kodu
```

Bul (3/5):

```markdown
- Mod: ● Kablo takılıyken / ○ Her zaman
- Port: 4747… (Plan 5; o zamana kadar `defaults write com.phonebox.PhoneBox port -int <port>`)
- Girişte başlat (ServiceManagement)
- Eşleştirmeyi sıfırla
- Güncelleme (NotchBox'taki gibi)
- Çık

## 9. Hata yönetimi
```

Şununla değiştir:

```markdown
- Mod: ● Kablo takılıyken / ○ Her zaman
- Port: 4747…: 1024–65535 arası bir sayı sorar (`PortChoice`); geçersizse sebebini söyleyip yeniden sorar. Yeni port
  hemen dinlenir, eski dinleyicinin geç gelen durumu yok sayılır; telefonun bağlantısı portu içerdiği için QR penceresi
  açılır. 4747 seçilince ayar silinir.
- Girişte başlat (ServiceManagement). macOS onay isterse (`requiresApproval`) öğe yarım işaretli görünür ve bir uyarı
  "Giriş Öğeleri'ni aç" düğmesiyle Sistem Ayarları'na götürür.
- Eşleştirmeyi sıfırla
- "PhoneBox x.y.z sürümünü yükle…" (yalnız yeni sürüm varken) ve "Güncellemeleri denetle…" (NotchBox'taki gibi):
  açılıştan 15 sn sonra ve günde iki kez GitHub'ın "latest release" yanıtına bakılır (taslak ve ön sürüm sayılmaz).
  Yükle, kurulum komutunu PhoneBox'tan bağımsız bir kabukta çalıştırır: PhoneBox kapanır, yenisi yerine konup açılır,
  çıktısı `~/Library/Logs/PhoneBox/update.log`'a yazılır. Kurulum başarısızsa komut panoya konur ve kayıt gösterilir.
  `defaults write com.phonebox.PhoneBox CheckForUpdatesAutomatically -bool false` otomatik denetimi kapatır.
- Çık

Menü ve pencereler İngilizce ve Türkçe (`Resources/{en,tr}.lproj/Localizable.strings`); iki dosyanın anahtarları ve
her metnin yer tutucuları aynı olmalı (`LocalizationTests`).

## 9. Hata yönetimi
```

Bul (4/5):

```markdown
- Kurulum: `curl -fsSL https://raw.githubusercontent.com/cyesaa/phone-box/main/install.sh | bash`
  (`curl` ile inen dosya karantinaya alınmaz, imzasız uygulama engellenmez); kaldırma `… | bash -s -- --uninstall`.
- `make app` (ad-hoc imzalı `build/PhoneBox.app`), `make test`, `make release VERSION=x.y.z` (GitHub Releases'a
  `PhoneBox.zip`).
- Gereksinim: Apple Silicon, macOS 14+. README önce Türkçe, sonra İngilizce, son kullanıcı için yazılır.
```

Şununla değiştir:

```markdown
- Kurulum: `curl -fsSL https://raw.githubusercontent.com/cyesaa/phone-box/main/install.sh | bash`
  (`curl` ile inen dosya karantinaya alınmaz, imzasız uygulama engellenmez). Apple Silicon ve macOS 14+ denetlenir,
  imza doğrulanır, çalışan PhoneBox kapatılır, uygulama `/Applications`'a (yazılamıyorsa `~/Applications`) konup
  açılır. `PHONEBOX_VERSION=x.y.z` belirli bir sürümü kurar. Denemek için `PHONEBOX_ZIP` (yerel zip), `PHONEBOX_DEST`
  (başka klasör; başka yerden çalışan PhoneBox'a dokunulmaz) ve `PHONEBOX_NO_OPEN=1`.
- Kaldırma `… | bash -s -- --uninstall`: uygulama, ayarlar (`defaults`), eşleştirme anahtarı
  (`~/Library/Application Support/PhoneBox`), kayıtlar (`~/Library/Logs/PhoneBox`) ve izinler (`tccutil`) silinir.
- `make app` (ad-hoc imzalı `build/PhoneBox.app`; simge `scripts/make-icon.swift` ile çizilir, `LICENSE` ve
  `THIRD_PARTY_NOTICES.md` uygulamanın içine konur), `make test`, `make dist` (`dist/PhoneBox-<sürüm>.zip`, imzası
  denetlenir), `make release VERSION=x.y.z` (temiz ve `origin/main` ile aynı `main`'den: sürüm numarası, test, zip,
  "Release x.y.z" commit'i, `vx.y.z` etiketi, push, GitHub Releases'a `PhoneBox.zip`; `DRY_RUN=1` prova eder).
- Gereksinim: Apple Silicon, macOS 14+. README önce Türkçe, sonra İngilizce, son kullanıcı için yazılır.
```

Bul (5/5):

```markdown
Package.swift  Makefile  install.sh  LICENSE  THIRD_PARTY_NOTICES.md  README.md
scripts/                  bundle.sh, build-adapter.sh, dist.sh, release.sh, make-icon.swift
Sources/PhoneBoxCore/     modeller, hesaplar, protokol, HMAC, AccessPolicy
Sources/PhoneBox/         uygulama, Collectors, Sampler, USBWatcher, Server, Pairing, CommandRunner, MenuBar
Resources/                Info.plist, AppIcon.icns, en.lproj, tr.lproj
Resources/web/            index.html, styles.css, sha256.js, i18n.js, format.js, history.js, metrics.js, heat.js,
```

Şununla değiştir:

```markdown
Package.swift  Makefile  install.sh  LICENSE  THIRD_PARTY_NOTICES.md  README.md
scripts/                  bundle.sh, build-adapter.sh, dist.sh, release.sh, make-icon.swift, make-touch-icon.swift,
                          make-video.swift
Sources/PhoneBoxCore/     modeller, hesaplar, protokol, HMAC, AccessPolicy
Sources/PhoneBox/         uygulama, Collectors, Sampler, USBWatcher, Server, Pairing, CommandRunner, MenuBar
Resources/                Info.plist, en.lproj, tr.lproj (AppIcon.icns `make app` sırasında çizilir)
Resources/web/            index.html, styles.css, sha256.js, i18n.js, format.js, history.js, metrics.js, heat.js,
```

- [ ] **Step 3: Commit**

```bash
git add README.md docs/design/2026-11-25-phonebox-design.md
git commit -m "Describe PhoneBox for its users in Turkish and English, and the design what Plan 5 built"
```

---

### Task 7: Açık sayfa yeni sürümü kendiliğinden yükler

**Files:**
- Create: `Sources/PhoneBoxCore/WebBuild.swift`, `Tests/PhoneBoxCoreTests/WebBuildTests.swift`
- Modify: `Sources/PhoneBoxCore/Messages.swift`, `Tests/PhoneBoxCoreTests/MessagesTests.swift`,
  `Sources/PhoneBox/DashboardHub.swift`, `Sources/PhoneBox/AppDelegate.swift`, `Resources/web/connection.js`,
  `Resources/web/app.js`, `Tests/PhoneBoxCoreTests/WebConnectionTests.swift`, design doc

**Interfaces:**
- Produces: `WebBuild.fingerprint(_ files: [String: Data]) -> String` (12 hex);
  `ServerMessage.ready(mode:host:powerLimits:access:build:)` (`build` varsayılanı `""`, boşsa JSON'a yazılmaz);
  `DashboardHub(…, powerLimits:, build:, commands:, …)`; sayfada `PhoneBox.BuildWatch` (`changed(build) -> Bool`).

Telefonda açık kalan sayfa, PhoneBox güncellenince eski kodla çalışmaya devam ediyordu (Plan 4B telefon denemesinde
görüldü). Artık `ready` sayfa dosyalarının adını taşır; sayfa ilk adı hatırlar, başka bir ad gelince kendini yeniden
yükler.

- [ ] **Step 1: Testleri yaz**

`Tests/PhoneBoxCoreTests/WebBuildTests.swift`:

```swift
import Foundation
import Testing
@testable import PhoneBoxCore

struct WebBuildTests {
    let files = ["index.html": Data("<html>".utf8), "app.js": Data("run()".utf8)]

    @Test func namesTheSameFilesTheSameWay() {
        let name = WebBuild.fingerprint(files)
        #expect(name.count == 12)
        #expect(name.allSatisfy { "0123456789abcdef".contains($0) })
        #expect(WebBuild.fingerprint(["app.js": Data("run()".utf8), "index.html": Data("<html>".utf8)]) == name)
        #expect(WebBuild.fingerprint([:]) == "e3b0c44298fc")
    }

    @Test func anyChangeGivesAnotherName() {
        let name = WebBuild.fingerprint(files)
        var edited = files
        edited["app.js"] = Data("run();".utf8)
        var renamed = files
        renamed["main.js"] = renamed.removeValue(forKey: "app.js")
        var added = files
        added["new.css"] = Data()
        // Moving a byte from one file's end to the next file's start must count too.
        let moved = ["a": Data("xy".utf8), "b": Data("z".utf8)]
        let shifted = ["a": Data("x".utf8), "b": Data("yz".utf8)]
        #expect(Set([name, WebBuild.fingerprint(edited), WebBuild.fingerprint(renamed), WebBuild.fingerprint(added)]).count == 4)
        #expect(WebBuild.fingerprint(moved) != WebBuild.fingerprint(shifted))
    }
}
```

`Tests/PhoneBoxCoreTests/MessagesTests.swift`:

Bul:

```swift
            == #"{"access":{"cable":false,"commands":false,"reason":"not-on-cable","streaming":false},"host":"Eren's MacBook Pro","limits":{"power":[15,35.5]},"mode":"cable","type":"ready","v":1}"#)
    }
```

Şununla değiştir:

```swift
            == #"{"access":{"cable":false,"commands":false,"reason":"not-on-cable","streaming":false},"host":"Eren's MacBook Pro","limits":{"power":[15,35.5]},"mode":"cable","type":"ready","v":1}"#)
    }

    @Test func readyNamesTheDashboardsFilesWhenItKnowsThem() {
        let ready = ServerMessage.ready(mode: .always, host: "Mac", powerLimits: PowerLimits(start: 15, full: 35),
                                        access: .overWiFi, build: "0123456789ab")
        #expect(ready.json()
            == #"{"access":{"cable":false,"commands":false,"reason":"ok","streaming":true},"build":"0123456789ab","host":"Mac","limits":{"power":[15,35]},"mode":"always","type":"ready","v":1}"#)
    }
```

`Tests/PhoneBoxCoreTests/WebConnectionTests.swift`:

Bul:

```swift
    func string(_ code: String) -> String? { context.evaluateScript(code)?.toString() }

    @Test func backsOffOneTwoFiveSecondsAndKeepsTheOfflineCardUp() {
```

Şununla değiştir:

```swift
    func string(_ code: String) -> String? { context.evaluateScript(code)?.toString() }

    @Test func reloadsOnlyWhenALaterReadyNamesOtherFiles() {
        #expect(string("""
            var watch = new PhoneBox.BuildWatch();
            [watch.changed("0123456789ab"), watch.changed("0123456789ab"), watch.changed(undefined), watch.changed(""),
             watch.changed("ba9876543210")].join(",")
            """) == "false,false,false,false,true")
    }

    @Test func backsOffOneTwoFiveSecondsAndKeepsTheOfflineCardUp() {
```

- [ ] **Step 2: Testlerin derlenmediğini gör**

Run: `make test FILTER="WebBuildTests|MessagesTests|WebConnectionTests"` → Expected: derleme hatası (`WebBuild` yok,
`ready`'de `build` yok).

- [ ] **Step 3: Mac tarafı**

`Sources/PhoneBoxCore/WebBuild.swift`:

```swift
import CryptoKit
import Foundation

/// Names one set of dashboard files (design §8 "Menü çubuğu", güncelleme): `ready` carries it, and a page that stays
/// open across an update sees another name and reloads, so it never runs old code against a newer Mac side.
public enum WebBuild {
    /// The first 12 hex digits of a SHA-256 over every file's path, size and contents, in path order.
    public static func fingerprint(_ files: [String: Data]) -> String {
        var hasher = SHA256()
        for path in files.keys.sorted() {
            let contents = files[path] ?? Data()
            hasher.update(data: Data("\(path)\n\(contents.count)\n".utf8))
            hasher.update(data: contents)
        }
        return hasher.finalize().prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}
```

`Sources/PhoneBoxCore/Messages.swift`:

Bul (1/4):

```swift
    case hello(nonce: String, app: String)
    case ready(mode: AccessMode, host: String, powerLimits: PowerLimits, access: Access)
    case access(Access)
```

Şununla değiştir:

```swift
    case hello(nonce: String, app: String)
    /// `build` names the dashboard's files (`WebBuild`); an empty one is left out.
    case ready(mode: AccessMode, host: String, powerLimits: PowerLimits, access: Access, build: String = "")
    case access(Access)
```

Bul (2/4):

```swift
    private enum Keys: String, CodingKey {
        case v, type, nonce, app, mode, host, limits, access, streaming, commands, cable, reason, t, cpu, mem, gpu, temp, power, net, disk,
             battery, apps, media, audio, phone, seq, ok, error
    }
```

Şununla değiştir:

```swift
    private enum Keys: String, CodingKey {
        case v, type, nonce, app, mode, host, limits, access, build, streaming, commands, cable, reason, t, cpu, mem, gpu, temp, power,
             net, disk, battery, apps, media, audio, phone, seq, ok, error
    }
```

Bul (3/4):

```swift
            try container.encode(app, forKey: .app)
        case let .ready(mode, host, powerLimits, access):
            try container.encode("ready", forKey: .type)
```

Şununla değiştir:

```swift
            try container.encode(app, forKey: .app)
        case let .ready(mode, host, powerLimits, access, build):
            try container.encode("ready", forKey: .type)
```

Bul (4/4):

```swift
            try container.encode(access, forKey: .access)
        case let .access(access):
```

Şununla değiştir:

```swift
            try container.encode(access, forKey: .access)
            if !build.isEmpty { try container.encode(build, forKey: .build) }
        case let .access(access):
```

`Sources/PhoneBox/DashboardHub.swift`:

Bul (1/4):

```swift
    private let powerLimits: PowerLimits
    private let commands: any CommandRunning
```

Şununla değiştir:

```swift
    private let powerLimits: PowerLimits
    /// The dashboard files' name (`WebBuild`), sent in `ready`.
    private let build: String
    private let commands: any CommandRunning
```

Bul (2/4):

```swift
    init(mode: AccessMode, key: PairingKey, appName: String, hostName: String, powerLimits: PowerLimits = .standard,
         commands: any CommandRunning, usbInterfaces: @escaping () -> Set<String> = USBLinks.iPhoneInterfaceNames) {
        self.mode = mode
```

Şununla değiştir:

```swift
    init(mode: AccessMode, key: PairingKey, appName: String, hostName: String, powerLimits: PowerLimits = .standard,
         build: String = "", commands: any CommandRunning,
         usbInterfaces: @escaping () -> Set<String> = USBLinks.iPhoneInterfaceNames) {
        self.mode = mode
```

Bul (3/4):

```swift
        self.powerLimits = powerLimits
        self.commands = commands
```

Şununla değiştir:

```swift
        self.powerLimits = powerLimits
        self.build = build
        self.commands = commands
```

Bul (4/4):

```swift
            clients[id] = client
            connection.send(.ready(mode: mode, host: hostName, powerLimits: powerLimits, access: client.access))
            onAuthenticated?()
```

Şununla değiştir:

```swift
            clients[id] = client
            connection.send(.ready(mode: mode, host: hostName, powerLimits: powerLimits, access: client.access,
                                   build: build))
            onAuthenticated?()
```

`Sources/PhoneBox/AppDelegate.swift`:

Bul (1/2):

```swift
        let powerLimits = PowerLimits.forChip(Settings.chipName(), wholeMac: BatteryCollector.hasInternalBattery())
        hub = DashboardHub(mode: settings.mode, key: key, appName: "PhoneBox \(version)", hostName: Settings.computerName(),
                           powerLimits: powerLimits, commands: commandRunner)
        let webDirectory = Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true)
        server = DashboardServer(webDirectory: webDirectory, hub: hub)
```

Şununla değiştir:

```swift
        let powerLimits = PowerLimits.forChip(Settings.chipName(), wholeMac: BatteryCollector.hasInternalBattery())
        let webDirectory = Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true)
        hub = DashboardHub(mode: settings.mode, key: key, appName: "PhoneBox \(version)", hostName: Settings.computerName(),
                           powerLimits: powerLimits, build: Self.webBuild(webDirectory), commands: commandRunner)
        server = DashboardServer(webDirectory: webDirectory, hub: hub)
```

Bul (2/2):

```swift
    }

    private func showQR() {
```

Şununla değiştir:

```swift
    }

    /// The name of the dashboard files in `directory` (`WebBuild`): an update changes it, and a page left open reloads.
    private static func webBuild(_ directory: URL) -> String {
        var files: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  let data = try? Data(contentsOf: url)
            else { continue }
            files[String(url.path.dropFirst(directory.path.count))] = data
        }
        return WebBuild.fingerprint(files)
    }

    private func showQR() {
```

- [ ] **Step 4: Sayfa**

`Resources/web/connection.js`:

Bul (1/2):

```js
  }

  global.PhoneBox = global.PhoneBox || {};
```

Şununla değiştir:

```js
  }

  /// Remembers which PhoneBox files the page runs (the `build` of its first `ready`). A later `ready` that names
  /// other files means PhoneBox was updated while the page stayed open: the page has to load the new ones.
  class BuildWatch {
    constructor() {
      this.build = null;
    }

    /// True when the page should reload. A `ready` without a build (an older Mac side) changes nothing.
    changed(build) {
      if (typeof build !== "string" || build === "") return false;
      if (this.build === null) {
        this.build = build;
        return false;
      }
      return build !== this.build;
    }
  }

  global.PhoneBox = global.PhoneBox || {};
```

Bul (2/2):

```js
  global.PhoneBox.Connection = Connection;
})(typeof window !== "undefined" ? window : globalThis);
```

Şununla değiştir:

```js
  global.PhoneBox.Connection = Connection;
  global.PhoneBox.BuildWatch = BuildWatch;
})(typeof window !== "undefined" ? window : globalThis);
```

`Resources/web/app.js`:

Bul (1/2):

```js
  const history = new PB.History(63);
  const selectedKey = "phonebox-metric";
```

Şununla değiştir:

```js
  const history = new PB.History(63);
  const builds = new PB.BuildWatch();
  const selectedKey = "phonebox-metric";
```

Bul (2/2):

```js
    onReady: (ready) => {
      view.setHost(ready.host);
```

Şununla değiştir:

```js
    onReady: (ready) => {
      // PhoneBox was updated while this page stayed open: load its new files (the page then asks for "Start" again).
      if (builds.changed(ready.build)) {
        global.location.reload();
        return;
      }
      view.setHost(ready.host);
```

`docs/design/2026-11-25-phonebox-design.md`:

Bul:

```markdown
| telefon → Mac | `{"type":"auth","mac":"<HMAC-SHA256(k, "auth:"+nonce) hex>"}` | Yanlışsa bağlantı 4001 ile kapanır (sayfa durur, "Eşleşmedi"); 5 sn içinde gelmezse 4003 ile kapanır (sayfa yeniden dener; telefon kilitliyken açılan bir bağlantı böyle kapanabilir) |
| Mac → telefon | `{"type":"ready","mode":"cable"\|"always","host":"<Mac'in adı>","limits":{"power":[15,35]},"access":{"streaming":bool,"commands":bool,"cable":bool,"reason":"…"}}` | Kimlik doğrulandı; `host` bilgisayarın adı ("⋯" menüsünün başlığında görünür); `limits.power` güç kutusunun kızarmaya başladığı ve kıpkırmızı olduğu watt (bölüm 8, Mac çipine göre seçer); `access` alanı bir alttaki `access` mesajıyla aynı |
| Mac → telefon | `{"type":"access","streaming":bool,"commands":bool,"cable":bool,"reason":"ok"\|"not-on-cable"}` | Erişim değiştiğinde; `cable` bu bağlantının USB'den gelip gelmediği ("kablo" / "Wi-Fi") |
```

Şununla değiştir:

```markdown
| telefon → Mac | `{"type":"auth","mac":"<HMAC-SHA256(k, "auth:"+nonce) hex>"}` | Yanlışsa bağlantı 4001 ile kapanır (sayfa durur, "Eşleşmedi"); 5 sn içinde gelmezse 4003 ile kapanır (sayfa yeniden dener; telefon kilitliyken açılan bir bağlantı böyle kapanabilir) |
| Mac → telefon | `{"type":"ready","mode":"cable"\|"always","host":"<Mac'in adı>","limits":{"power":[15,35]},"access":{"streaming":bool,"commands":bool,"cable":bool,"reason":"…"},"build":"<12 hex>"}` | Kimlik doğrulandı; `host` bilgisayarın adı ("⋯" menüsünün başlığında görünür); `limits.power` güç kutusunun kızarmaya başladığı ve kıpkırmızı olduğu watt (bölüm 8, Mac çipine göre seçer); `access` alanı bir alttaki `access` mesajıyla aynı; `build` sayfa dosyalarının adı (`WebBuild`: yolların, boyların ve içeriklerin SHA-256'sının ilk 12 hanesi). Sayfa ilk `ready`'deki adı hatırlar; sonraki bir `ready` başka ad getirirse (PhoneBox güncellendi) kendini yeniden yükler ve "Başlat" yeniden ister |
| Mac → telefon | `{"type":"access","streaming":bool,"commands":bool,"cable":bool,"reason":"ok"\|"not-on-cable"}` | Erişim değiştiğinde; `cable` bu bağlantının USB'den gelip gelmediği ("kablo" / "Wi-Fi") |
```

- [ ] **Step 5: Testleri çalıştır**

Run: `make test FILTER="WebBuildTests|MessagesTests|WebConnectionTests"` → Expected: geçer.
Run: iki uyarı denetimi → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 20 tests in 7 suites passed` ve `Test run with 203 tests in 37 suites passed`.

- [ ] **Step 6: Commit**

```bash
git add Sources/PhoneBoxCore/WebBuild.swift Tests/PhoneBoxCoreTests/WebBuildTests.swift Sources/PhoneBoxCore/Messages.swift \
  Tests/PhoneBoxCoreTests/MessagesTests.swift Sources/PhoneBox/DashboardHub.swift Sources/PhoneBox/AppDelegate.swift \
  Resources/web/connection.js Resources/web/app.js Tests/PhoneBoxCoreTests/WebConnectionTests.swift \
  docs/design/2026-11-25-phonebox-design.md
git commit -m "Reload an open dashboard when PhoneBox's files change"
```

---

### Task 8: Kontrol ve yayın (kontrolcü, inline)

- [ ] **Step 1:** `PHONEBOX_LIVE=1 make test FILTER="PhoneBatteryLiveTests"`.
- [ ] **Step 2:** Dalın uygulamasıyla (kullanıcının PhoneBox'ı yerine): menü öğeleri iki dilde; Port… geçersiz
  değerde sebebini söyleyip yeniden soruyor, geçerli değerde QR penceresi yeni portla açılıyor, sonra 4747'ye dönülüyor;
  "Güncellemeleri denetle…" (`UpdateFeedURL` ile yerel bir yanıt: daha yeni sürüm → yükleme sorusu, Sonra; aynı sürüm →
  "güncel"), sonra `defaults delete com.phonebox.PhoneBox UpdateFeedURL`; Finder'da simge.
- [ ] **Step 3:** README'nin ekran görüntüsü (sahte veriyle deneme sayfasından) `docs/images/dashboard.png`.
- [ ] **Step 4:** `main`'e birleştir; `cyesaa/phone-box` herkese açık depo, `main`'i gönder, `make release VERSION=0.1.0`;
  temiz bir yerden `curl … | bash` kurulumu ve uygulamanın açıldığı, telefonun bağlandığı.
- [ ] **Step 5:** `docs/manual-testing.md`'ye Plan 5 sonuçları.
