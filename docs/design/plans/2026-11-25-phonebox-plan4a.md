# PhoneBox Plan 4A — İzleme arayüzü

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Bu plan için not:** Görev 1–4 Mac'te tek başına yürütülebilir; uygulamayı başlatmaz, kullanıcının PhoneBox'ını
> durdurmaz, `defaults`'a ve eşleştirme anahtarına dokunmaz. Görev 5 kontrolcü tarafından (inline) yapılır: sayfayı
> Mac'te dört iPhone ölçüsünde dener, sonra kullanıcıyla telefonda kısa bir kontrol yapar. Komut arayüzü (kontrol
> şeridinin medya ve ses düğmeleri, uygulama paneli, "⋯" komutları, onay, bildirim) Plan 4B'dedir.

**Goal:** Telefondaki sayfayı onaylanan tasarıma (design §8) göre yeniden yazmak: yatayda üç sütunlu yerleşim, dikeyde
tek bakış, halkalar, seçilebilir 60 saniyelik grafik, kutucuklar, uygulama listesi, çalan şarkı kartı, durum satırı ve
durum kartları, Başlat ekranı, ilk açılış rehberi, OLED kayması ve ana ekran simgesi.

**Architecture:** Sayfa sade HTML/CSS/JS olarak küçük dosyalara bölünür. Hesap yapan parçalar (`i18n`, `format`,
`history`, `metrics`, `chart` ölçeği) DOM'a dokunmaz ve Swift testleriyle JavaScriptCore'da denenir. Bağlantı
(`connection.js`) bugünkü `app.js`'ten taşınır ve sayfaya sadece geri çağrılarla haber verir. `view.js` veriyi
yerleştirir, `ui.js` ekran davranışlarını taşır, `app.js` hepsini bağlar. Mac tarafında sadece ekrana giden adlar
temizlenir.

**Tech Stack:** HTML, CSS (grid, `@property`, `dvh`, `env(safe-area-inset-*)`), sade JavaScript (sınıf, `??`, Intl),
`<canvas>`; Swift Testing + JavaScriptCore; CoreGraphics (ana ekran simgesi).

## Global Constraints

- Sayfa sade HTML/CSS/JS: dış kütüphane ve derleme adımı yok. Her dosya klasik `<script>` ile sırayla yüklenir ve
  `globalThis.PhoneBox` altına yazar (ES modül `import`'u yok); saf dosyalar DOM'a dokunmaz ki JavaScriptCore'da
  test edilebilsin.
- Hedef iOS 16.4+ WebKit (Safari ve iOS Chrome): `@property`, `dvh`, `??`, `env(safe-area-inset-*)` kullanılır.
- Ekrana giden her metin `textContent` ile yazılır; `innerHTML` yok (uygulama ve şarkı adları başka uygulamalardan
  ve web sayfalarından gelir).
- Yerleşim (design §8): yatayda üç sütun (halkalar | grafik + 3×2 kutucuk + kontrol şeridi | durum satırı + şarkı
  kartı + uygulamalar); dikeyde yukarıdan aşağı durum, halkalar, grafik, kutucuklar, uygulamalar, şarkı, şerit.
  Kaydırma yok; iPhone SE'den Pro Max'e kadar her şey sığar. Kenarlarda güvenli alan payları bırakılır.
- Stil: siyah zemin `#000`, kartlar `#1c1c1e`, 16 px köşe, sistem fontu. Renkler: CPU `#30d158`, RAM `#0a84ff`, GPU
  `#bf5af2`, sıcaklık `#ff9f0a`, güç `#ffd60a`, ağ `#64d2ff`, disk `#8e8e93`, pil `#30d158`.
- Grafik: seçili metriğin son 60 saniyesi, sadece telefonun belleğinde; değer gelmeyen saniye boşluk olur. Ölçek:
  yüzdeler 0–100; sıcaklık 5'in katlarıyla en az 20 °C; güç, ağ, disk 0'dan 1/2/5×10ⁿ tavana. Seçim
  `localStorage` `phonebox-metric`'te; ilk açılışta CPU.
- Sayılar `Intl.NumberFormat` ile telefonun dilinde (Türkçe "%64", İngilizce "64%"); birim yuvarlamadan sonra seçilir
  (999,6 KB/s → "1,0 MB/s"); eksik ya da sonlu olmayan değer "—". Uygulama belleği ve RAM ikili birim (GB = 2³⁰),
  disk Finder gibi ondalık.
- Bağlantı (design §5): yeniden deneme 1, 2, 5 sn (sonra 5 sn); 3 sn snapshot gelmezse değerler soluk; yayın
  sırasında 5 sn sessizlikte soket yenilenir; yayın yokken 10 sn'de bir yeniden bağlanılır; 4001'de durur, 4002'de
  250 ms, 4003'te 1 sn sonra yeniden bağlanır.
- Ekranı açık tutma (spike V4) değişmez: sesi açık, döngüsüz `keepawake.mp4`, `navigator.audioSession.type =
  "ambient"`, 3 sn'de bir "duruyorsa başlat"; ilk dokunuşla başlar.
- Plan 4B'ye kalanlar: şeritte medya ve ses düğmeleri, uygulamaya dokununca panel, "⋯" menüsündeki komutlar, onay,
  bildirim. 4A'da şerit sadece "⋯" düğmesini, menü sadece "Kurulum rehberi"ni taşır; uygulama satırlarına dokunmak bir
  şey yapmaz.
- Kod yorumları İngilizce. Commit mesajları İngilizce, emir kipinde. Aşağıdaki her `git commit` komutuna, commit'i
  yapan ortamın istediği `Co-Authored-By: …` satırı ikinci bir `-m` olarak eklenir (commit'i yapan modeli adlandırır).
- Testler `make test FILTER="<Suite>|<Suite>"` ile (tırnaklar kalsın). Derleme uyarısı denetimi iki adımdır:
  `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"` ve
  `make test 2>&1 | grep -E "warning:" | grep -v "ld: warning"`; ikisi de çıktı vermemeli.

## Planlama sırasında doğrulananlar (2026-11-25)

Kodun tamamı `main`'in (08ce7bd) bir kopyasında görev görev yazıldı; her görevin sonunda derleme ve test uyarısız,
testler geçti. Sonda: `PhoneBoxCoreTests` 27 takımda 151 test (13'ü JavaScriptCore'da sayfa testleri),
`PhoneBoxTests` 4 takımda 17 test.

- Derlenen uygulama kullanıcının PhoneBox'ının yerine kısa süre çalıştırıldı; sayfa Mac'in tarayıcı panelinde gerçek
  veriyle şu ölçülerde denendi:
  - 734×372: standart iPhone'un yataydaki kullanılabilir alanı.
  - 393×759: aynı telefon dikey.
  - 667×375 ve 375×647: iPhone SE, yatay ve dikey.
  - 814×409: Pro Max, yatay.
- Hiçbir ölçüde ekran dışına taşan öğe ya da kesilen kutucuk/başlık metni yok. SE dikeyde grafik 63 px, 4 uygulama
  satırı; halkalar 110–128 px.
- Etkileşimler:
  - "Başlat" bir dokunuşla videoyu başlattı ve ekran açıldı.
  - Kutucuğa dokunmak grafiği ve başlığı değiştirdi; seçim hatırlandı.
  - "⋯" menüsü düğmesinin üstünde açıldı; rehber açıldı (bağlantı alanı, "Kapat").
  - "Kabloyu tak" kartı soluk değerlerin üstünde göründü.
- Yeniden bağlanma: PhoneBox 22 sn durdurulunca sayfa +1, +3, +8, +13, +18 sn'de denedi (1/2/5/5/5), uygulama
  açılınca kendiliğinden döndü. Plan 2'den ertelenen "3 sn'lik sayaç geri çekilmeyi kısaltıyor" hatası bununla
  kapandı.
- Ana ekran simgesi derlemede 180×180 PNG olarak çizildi; siyah zemin üstünde yeşil ve mavi halka.

## Dosya yapısı

```
Sources/PhoneBoxCore/AppUsage.swift           ad temizleme, yedek adlar, eşitlikte sabit sıra (değişir)
Sources/PhoneBox/NowPlayingService.swift      çalan uygulamanın adı sadece bulununca saklanır (değişir)
Resources/web/  i18n.js, format.js, history.js, metrics.js, chart.js        saf parçalar (yeni)
                connection.js, view.js, ui.js                                sayfa parçaları (yeni)
                index.html, styles.css, app.js                               (baştan yazılır)
scripts/make-touch-icon.swift                 ana ekran simgesi (yeni); scripts/bundle.sh (değişir)
Tests/PhoneBoxCoreTests/AppUsageTests.swift   (değişir), WebPageTests.swift (yeni)
```

"Bul / Şununla değiştir" adımlarında "Bul" metni dosyada tam olarak bir kez geçer; Edit aracıyla birebir değiştirin.

---

### Task 1: Ekrana giden adlar

**Files:**
- Modify: `Sources/PhoneBoxCore/AppUsage.swift`, `Tests/PhoneBoxCoreTests/AppUsageTests.swift`
- Modify: `Sources/PhoneBox/NowPlayingService.swift`

**Interfaces:**
- Consumes: mevcut `AppUsage.displayName(_:)`, `AppUsage.top(previousCPU:current:elapsedNanos:apps:)`.
- Produces: `displayName` artık metnin içindeki kontrol karakterlerini, satır/paragraf ayırıcılarını ve boşluk
  dizilerini tek boşluğa çevirir, görünmez biçim karakterlerini (yön işaretleri, sıfır genişlikli boşluklar) siler;
  `AppUsage.name(app:bundle:executable:) -> String` (boş kalırsa sırayla paket adı, çalıştırılabilir dosya adı, "?");
  `AppUsage.busier(_:_:)`, `AppUsage.larger(_:_:)` (eşitlikte ada, sonra pid'e göre sabit sıra).

- [ ] **Step 1: Testleri yaz**

`Tests/PhoneBoxCoreTests/AppUsageTests.swift`:

Bul:

```swift
        #expect(AppUsage.displayName("çğıöşü") == "çğıöşü")
    }
```

Şununla değiştir:

```swift
        #expect(AppUsage.displayName("çğıöşü") == "çğıöşü")
    }

    @Test func flattensControlCharactersSeparatorsAndInvisibleMarks() {
        #expect(AppUsage.displayName("Line\nbreak\tand\u{2028}separator") == "Line break and separator")
        #expect(AppUsage.displayName("zero\u{200B}width\u{FEFF}") == "zerowidth")
        #expect(AppUsage.displayName("  many   spaces\u{00A0} ") == "many spaces")
        #expect(AppUsage.displayName("\u{0007}\u{200E}\n ") == "")
    }

    @Test func fallsBackToTheBundleOrExecutableName() {
        #expect(AppUsage.name(app: "\u{200E} ", bundle: "/Applications/Notes.app", executable: "/x/Notes") == "Notes")
        #expect(AppUsage.name(app: nil, bundle: "/Applications/My.app.Tools.app", executable: "/x/y") == "My.app.Tools")
        #expect(AppUsage.name(app: nil, bundle: nil, executable: "/usr/bin/node") == "node")
        #expect(AppUsage.name(app: "", bundle: nil, executable: "") == "?")
    }

    @Test func keepsTiesInAStableOrder() {
        let tied = (1...4).map { AppSample(pid: Int32(10 - $0), bundleId: nil, name: ["d", "b", "c", "a"][$0 - 1], cpu: 0,
                                         mem: 5, quittable: false) }
        #expect(tied.sorted(by: AppUsage.busier).map(\.name) == ["a", "b", "c", "d"])
        #expect(tied.shuffled().sorted(by: AppUsage.larger).map(\.name) == ["a", "b", "c", "d"])
    }
```

- [ ] **Step 2: Testlerin derlenmediğini gör**

Run: `make test FILTER="AppUsageTests"` → Expected: derleme hatası (`AppUsage.name`, `busier`, `larger` yok).

- [ ] **Step 3: Ad temizleme, yedek adlar ve sabit sıra**

`Sources/PhoneBoxCore/AppUsage.swift`:

Bul (1/3):

```swift
    public static let maxNameLength = 80

    /// Removes the invisible direction marks some apps put in their names (WhatsApp starts with U+200E), trims, and
    /// keeps at most `maxNameLength` characters.
    public static func displayName(_ raw: String) -> String {
        let marks: Set<Unicode.Scalar> = ["\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}",
                                          "\u{202E}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}"]
        let kept = raw.unicodeScalars.filter { !marks.contains($0) }
        let trimmed = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxNameLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
```

Şununla değiştir:

```swift
    public static let maxNameLength = 80

    /// Cleans a name that an app or a web page chose before it reaches the phone: invisible format characters
    /// (direction marks such as WhatsApp's leading U+200E, zero-width spaces) are removed; control characters, line
    /// and paragraph separators and runs of white space become one space; the result is trimmed and keeps at most
    /// `maxNameLength` characters.
    public static func displayName(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in raw.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .format:
                continue
            case .control, .lineSeparator, .paragraphSeparator, .spaceSeparator:
                pendingSpace = true
            default:
                if pendingSpace, !scalars.isEmpty { scalars.append(" ") }
                pendingSpace = false
                scalars.append(scalar)
            }
        }
        return String(String(scalars).prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
    }

    /// The first of the app's own name, its bundle's file name and the executable's file name that is not empty
    /// after cleaning.
    static func name(app: String?, bundle: String?, executable: String) -> String {
        let candidates = [app, bundle.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension },
                          (executable as NSString).lastPathComponent]
        for case let candidate? in candidates {
            let cleaned = displayName(candidate)
            if !cleaned.isEmpty { return cleaned }
        }
        return "?"
    }

    /// Busiest first; equal rows keep a stable order (by name, then pid) so the phone's list does not flicker.
    static func busier(_ a: AppSample, _ b: AppSample) -> Bool {
        if a.cpu != b.cpu { return a.cpu > b.cpu }
        if a.mem != b.mem { return a.mem > b.mem }
        if a.name != b.name { return a.name < b.name }
        return a.pid < b.pid
    }

    static func larger(_ a: AppSample, _ b: AppSample) -> Bool {
        a.mem != b.mem ? a.mem > b.mem : busier(a, b)
    }
```

Bul (2/3):

```swift
                if let bundle, let info = apps[bundle] {
                    return Group(pid: info.pid, bundleId: info.bundleId, name: displayName(info.name),
                                 quittable: info.quittable)
                }
                let fallback = bundle.map { ($0 as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "") }
                return Group(pid: process.pid, bundleId: nil,
                             name: displayName(fallback ?? (process.path as NSString).lastPathComponent), quittable: false)
            }()
```

Şununla değiştir:

```swift
                if let bundle, let info = apps[bundle] {
                    return Group(pid: info.pid, bundleId: info.bundleId,
                                 name: name(app: info.name, bundle: bundle, executable: process.path), quittable: info.quittable)
                }
                return Group(pid: process.pid, bundleId: nil, name: name(app: nil, bundle: bundle, executable: process.path),
                             quittable: false)
            }()
```

Bul (3/3):

```swift
        }
        let byCPU = samples.sorted { ($0.cpu, $0.mem) > ($1.cpu, $1.mem) }.prefix(topCount)
        let byMemory = samples.sorted { $0.mem > $1.mem }.prefix(topCount)
        var result = Array(byCPU)
```

Şununla değiştir:

```swift
        }
        let byCPU = samples.sorted(by: busier).prefix(topCount)
        let byMemory = samples.sorted(by: larger).prefix(topCount)
        var result = Array(byCPU)
```

`Sources/PhoneBox/NowPlayingService.swift`:

Bul:

```swift
    }

    /// "Spotify" for `com.spotify.client`; the player is running, so its name is at hand. Cached: players are few.
    private func appName(for bundleId: String) -> String {
        if let name = names[bundleId] { return name }
        let raw = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.localizedName ?? bundleId
        let name = AppUsage.displayName(raw)
        names[bundleId] = name
```

Şununla değiştir:

```swift
    }

    /// "Spotify" for `com.spotify.client`; the player is running, so its name is at hand. Found names are cached
    /// (players are few); the bundle identifier stands in until macOS lists the player.
    private func appName(for bundleId: String) -> String {
        if let name = names[bundleId] { return name }
        guard let raw = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.localizedName
        else { return bundleId }
        let name = AppUsage.displayName(raw)
        guard !name.isEmpty else { return bundleId }
        names[bundleId] = name
```

- [ ] **Step 4: Testleri çalıştır**

Run: `make test FILTER="AppUsageTests|NowPlayingStreamTests"` → Expected: geçer.
Run: iki uyarı denetimi (Global Constraints) → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 17 tests in 4 suites passed` ve `Test run with 138 tests in 26 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/PhoneBoxCore/AppUsage.swift Sources/PhoneBox/NowPlayingService.swift Tests/PhoneBoxCoreTests/AppUsageTests.swift
git commit -m "Clean names before they reach the phone and keep the app list order stable"
```

---

### Task 2: Sayfanın saf parçaları

**Files:**
- Create: `Resources/web/i18n.js`, `Resources/web/format.js`, `Resources/web/history.js`, `Resources/web/metrics.js`,
  `Resources/web/chart.js`
- Create: `Tests/PhoneBoxCoreTests/WebPageTests.swift`

**Interfaces:**
- Consumes: yok (bugünkü sayfa bu görevde değişmez; yeni dosyalar Görev 3'te yüklenir).
- Produces (`globalThis.PhoneBox` altında):
  - `i18n = { texts: {tr, en}, pick(tag) -> "tr"|"en", language, t }` (`t` seçili dilin metinleri; `t.metric[...]`
    metrik adları).
  - `format(language) -> { dash, percent, decimal, celsius, watts, speed, speedShort, gibibytes, memory, gigabytes }`.
  - `History(seconds = 60)`: `push(timeMillis, values)`, `series(key) -> [number|null] × seconds`, `clear()`.
  - `metrics = { colors, order, values(snapshot), lines(metric), scale(metric), tile(metric, snapshot, format),
    header(metric, snapshot, format, t) -> {value, detail}, axisLabel(metric, range, format) }`.
  - `chart = { niceCeil(value), range(kind, seriesList) -> {min, max}, draw(canvas, lines, bounds, label) }`.

- [ ] **Step 1: Testleri yaz**

`Tests/PhoneBoxCoreTests/WebPageTests.swift`:

```swift
import Foundation
import JavaScriptCore
import Testing

/// Runs the dashboard's pure scripts (`Resources/web/i18n.js`, `format.js`, `history.js`, `metrics.js`, `chart.js`)
/// in JavaScriptCore, the engine behind Safari and iOS Chrome. No browser, Node or npm needed.
struct WebPageTests {
    static let webDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/web")

    let context: JSContext

    init() throws {
        context = try #require(JSContext())
        context.exceptionHandler = { _, exception in Issue.record("JavaScript error: \(exception?.toString() ?? "?")") }
        for name in ["i18n.js", "format.js", "history.js", "metrics.js", "chart.js"] {
            context.evaluateScript(try String(contentsOf: Self.webDirectory.appendingPathComponent(name), encoding: .utf8))
        }
        context.evaluateScript("""
            var tr = PhoneBox.format("tr"), en = PhoneBox.format("en"), T = PhoneBox.i18n.texts.tr;
            var GiB = 1073741824, MiB = 1048576;
            var snapshot = { t: 5000, cpu: { total: 63.6, cores: [], pCores: 4, load: [3.21, 2, 1] },
              mem: { used: 12884901888, total: 17179869184 }, gpu: { util: 17.4 }, temp: { avg: 45.6, max: 54.2 },
              power: { gpu: 0.41, system: 21.94 }, net: { rx: 1234567, tx: 84000, iface: "en0" },
              disk: { free: 21.6e9, total: 494.4e9, read: 20.6e6, write: 3.3e6 },
              battery: { percent: 80, charging: true } };
            """)
    }

    func string(_ code: String) -> String? { context.evaluateScript(code)?.toString() }

    @Test func picksTurkishOnlyForTurkish() {
        #expect(string(#"PhoneBox.i18n.pick("tr-TR")"#) == "tr")
        #expect(string(#"PhoneBox.i18n.pick("TR")"#) == "tr")
        #expect(string(#"PhoneBox.i18n.pick("en-GB")"#) == "en")
        #expect(string("PhoneBox.i18n.pick(undefined)") == "en")
    }

    @Test func bothLanguagesHaveTheSameTexts() {
        let check = """
            (function () {
              var tr = PhoneBox.i18n.texts.tr, en = PhoneBox.i18n.texts.en, bad = [];
              function compare(a, b, path) {
                Object.keys(a).concat(Object.keys(b)).forEach(function (key) {
                  if (!(key in a) || !(key in b) || typeof a[key] !== typeof b[key]) bad.push(path + key);
                  else if (typeof a[key] === "object") compare(a[key], b[key], path + key + ".");
                });
              }
              compare(tr, en, "");
              return bad.join(",");
            })()
            """
        #expect(string(check) == "")
    }

    @Test func formatsNumbersForTheLanguage() {
        #expect(string("tr.percent(63.6)") == "%64")
        #expect(string("en.percent(63.6)") == "64%")
        #expect(string("tr.decimal(3.21)") == "3,2")
        #expect(string("en.decimal(3.21)") == "3.2")
        #expect(string("tr.celsius(45.6)") == "46 °C")
        #expect(string("tr.watts(21.94)") == "21,9 W")
        #expect(string("tr.gibibytes(16 * GiB)") == "16")
        #expect(string("tr.gibibytes(13743895347)") == "12,8")
        #expect(string("tr.gigabytes(494.4e9)") == "494,4")
    }

    @Test func switchesUnitsAfterRounding() {
        #expect(string("tr.speed(512)") == "512 B/s")
        #expect(string("tr.speed(999.6)") == "1 KB/s")
        #expect(string("tr.speed(84000)") == "84 KB/s")
        #expect(string("tr.speed(999499)") == "999 KB/s")
        #expect(string("tr.speed(999600)") == "1,0 MB/s")
        #expect(string("en.speed(1234567)") == "1.2 MB/s")
        #expect(string("tr.speed(2.5e9)") == "2,5 GB/s")
        #expect(string("tr.speedShort(1234567)") == "1,2M")
        #expect(string("tr.speedShort(84000)") == "84K")
        #expect(string("tr.speedShort(12)") == "12B")
        #expect(string("tr.memory(640 * MiB)") == "640 MB")
        #expect(string("tr.memory(1023.6 * MiB)") == "1 GB")
        #expect(string("tr.memory(5.3 * GiB)") == "5,3 GB")
    }

    @Test func showsADashForMissingOrBrokenValues() {
        for call in ["tr.percent(null)", "tr.percent(NaN)", "tr.speed(undefined)", "tr.speed(-1)", "tr.watts(Infinity)",
                     "tr.memory(-5)", "tr.celsius('40')", "tr.speedShort(NaN)", "tr.gibibytes(null)"] {
            #expect(string(call) == "—", "\(call)")
        }
    }

    @Test func historyKeepsSixtySecondsWithGaps() {
        let result = string("""
            (function () {
              var h = new PhoneBox.History(60);
              h.push(1000, { cpu: 10 }); h.push(2500, { cpu: 20 }); h.push(4000, { cpu: NaN });
              var s = h.series("cpu");
              return [s.length, s[56], s[57], s[58], s[59], h.series("ram")[59]].join(",");
            })()
            """)
        #expect(result == "60,10,20,,,")
    }

    @Test func historyDropsOldSecondsAndStartsOverAfterAClockJump() {
        let result = string("""
            (function () {
              var h = new PhoneBox.History(3);
              h.push(1000, { cpu: 1 }); h.push(2000, { cpu: 2 }); h.push(5000, { cpu: 5 });
              var kept = h.series("cpu").join("|");
              h.push(1000000, { cpu: 9 });
              return kept + " / " + h.series("cpu").join("|");
            })()
            """)
        #expect(result == "||5 / ||9")
    }

    @Test func keepsTheNumbersOfASnapshot() {
        #expect(string("JSON.stringify(PhoneBox.metrics.values(snapshot))")
            == #"{"cpu":63.6,"ram":75,"gpu":17.4,"tempAvg":45.6,"tempMax":54.2,"power":21.94,"netRx":1234567,"netTx":84000,"diskRead":20600000,"diskWrite":3300000,"battery":80}"#)
        #expect(string("JSON.stringify(PhoneBox.metrics.values({ t: 1, mem: { used: 1, total: 0 }, power: { gpu: 2 } }))")
            == #"{"cpu":null,"ram":null,"gpu":null,"tempAvg":null,"tempMax":null,"power":2,"netRx":null,"netTx":null,"diskRead":null,"diskWrite":null,"battery":null}"#)
    }

    @Test func writesTheTiles() {
        let tiles = string("""
            ["gpu", "temp", "power", "net", "disk", "battery"].map(function (m) { return PhoneBox.metrics.tile(m, snapshot, tr); }).join(" | ")
            """)
        #expect(tiles == "%17 | 46 °C | 21,9 W | ↓1,2M ↑84K | 21,6 GB | %80 ⚡")
        #expect(string(#"PhoneBox.metrics.tile("net", { t: 1 }, tr)"#) == "—")
    }

    @Test func writesTheGraphHeader() {
        func header(_ metric: String) -> String? {
            string(#"(function (h) { return h.value + " | " + h.detail; })(PhoneBox.metrics.header("\#(metric)", snapshot, tr, T))"#)
        }
        #expect(header("cpu") == "%64 | yük 3,2")
        #expect(header("ram") == "%75 | 12 / 16 GB")
        #expect(header("gpu") == "%17 | 0,4 W GPU gücü")
        #expect(header("temp") == "46 °C | en yüksek 54 °C")
        #expect(header("power") == "21,9 W | Mac'in tamamı")
        #expect(header("net") == "↓ 1,2 MB/s | ↑ 84 KB/s · en0")
        #expect(header("disk") == "okuma 20,6 MB/s | yazma 3,3 MB/s · 21,6 / 494,4 GB boş")
        #expect(header("battery") == "%80 | şarj oluyor")
        #expect(string(#"PhoneBox.metrics.header("temp", { t: 1 }, tr, T).value"#) == "—")
    }

    @Test func describesBatteryTime() {
        #expect(string(#"PhoneBox.metrics.header("battery", { battery: { percent: 50, charging: false, minutesLeft: 135 } }, tr, T).detail"#)
            == "2 sa 15 dk kaldı")
        #expect(string(#"PhoneBox.metrics.header("battery", { battery: { percent: 99, charging: false } }, tr, T).detail"#) == "prizde")
    }

    @Test func choosesRoundGraphRanges() {
        #expect(string("[0, 0.03, 1.2, 7, 500, 1234].map(PhoneBox.chart.niceCeil).join(',')") == "1,0.05,2,10,500,2000")
        #expect(string(#"JSON.stringify(PhoneBox.chart.range("percent", [[5, 200]]))"#) == #"{"min":0,"max":100}"#)
        #expect(string(#"JSON.stringify(PhoneBox.chart.range("temperature", [[46, null], [54.2]]))"#) == #"{"min":40,"max":60}"#)
        #expect(string(#"JSON.stringify(PhoneBox.chart.range("temperature", [[12, 71]]))"#) == #"{"min":5,"max":80}"#)
        #expect(string(#"JSON.stringify(PhoneBox.chart.range("temperature", [[]]))"#) == #"{"min":30,"max":60}"#)
        #expect(string(#"JSON.stringify(PhoneBox.chart.range("fromZero", [[null, 3e6], [8e5]]))"#) == #"{"min":0,"max":5000000}"#)
        #expect(string(#"JSON.stringify(PhoneBox.chart.range("fromZero", [[null]]))"#) == #"{"min":0,"max":1}"#)
    }

    @Test func describesEachMetricsGraph() {
        #expect(string(#"PhoneBox.metrics.lines("temp").map(function (l) { return l.key; }).join(",")"#) == "tempAvg,tempMax")
        #expect(string(#"PhoneBox.metrics.lines("net").map(function (l) { return l.key; }).join(",")"#) == "netRx,netTx")
        #expect(string(#"PhoneBox.metrics.lines("cpu")[0].color"#) == "#30d158")
        #expect(string(#"["cpu", "temp", "net", "power", "battery"].map(PhoneBox.metrics.scale).join(",")"#)
            == "percent,temperature,fromZero,fromZero,percent")
        #expect(string(#"PhoneBox.metrics.axisLabel("net", { min: 0, max: 5e6 }, tr)"#) == "5,0 MB/s")
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `make test FILTER="WebPageTests"` → Expected: başarısız (betik dosyaları yok; "JavaScript error" ve beklenti
hataları).

- [ ] **Step 3: Metinler ve sayı biçimleri**

`Resources/web/i18n.js`:

```js
// Dashboard texts in Turkish and English, chosen by the phone's language (design §8 "Dil").
(function (global) {
  "use strict";

  const texts = {
    tr: {
      connecting: "Bağlanıyor…",
      mac: "Mac",
      cable: "kablo",
      wifi: "Wi-Fi",
      stateCable: "Kabloyu tak",
      stateCableText: "Bu telefon Wi-Fi üzerinden bağlı. Veri için iPhone'u Mac'e kabloyla tak.",
      stateOffline: "Mac'e ulaşılamıyor",
      stateOfflineText: "PhoneBox açık mı, telefon kabloyla takılı ya da aynı Wi-Fi'de mi? Arka planda yeniden deneniyor.",
      stateUnpaired: "Eşleşmedi",
      stateUnpairedText: "Mac'teki QR kodunu okut, açılan sayfayı yeniden Ana Ekrana Ekle, eski simgeyi sil.",
      stateNoKeyText: "Bu sayfanın anahtarı yok. iPhone'u Mac'e kabloyla tak ve Mac'te çıkan QR kodunu okut.",
      stateNoData: "Veri yok",
      stateNoDataText: "Mac şu an veri göndermiyor.",
      start: "Başlat",
      startNote: "Ekranı açık tutmak için bir kez dokun",
      metric: { cpu: "CPU", ram: "RAM", gpu: "GPU", temp: "Sıcaklık", power: "Güç", net: "Ağ", disk: "Disk", battery: "Pil" },
      diskTile: "Disk boş",
      lastMinute: "son 60 sn",
      load: (value) => `yük ${value}`,
      memory: (used, total) => `${used} / ${total} GB`,
      hottest: (value) => `en yüksek ${value}`,
      systemPower: "Mac'in tamamı",
      gpuPower: "sadece GPU",
      gpuWatts: (value) => `${value} GPU gücü`,
      upload: (speed, iface) => `↑ ${speed}` + (iface ? ` · ${iface}` : ""),
      diskRead: (speed) => `okuma ${speed}`,
      diskDetail: (write, free, total) => `yazma ${write} · ${free} / ${total} GB boş`,
      charging: "şarj oluyor",
      onPower: "prizde",
      untilEmpty: (time) => `${time} kaldı`,
      untilFull: (time) => `dolmasına ${time}`,
      duration: (hours, minutes) => (hours ? `${hours} sa ` : "") + `${minutes} dk`,
      apps: "Uygulamalar",
      more: "Diğer",
      guideItem: "Kurulum rehberi",
      guideTitle: "Kurulum",
      guide1Title: "Ana Ekrana Ekle → tam ekran",
      guide1Chrome: "Chrome'da adres çubuğundaki Paylaş düğmesine, sonra Ana Ekrana Ekle'ye dokun. Simgeden açınca sayfa tam ekran olur.",
      guide1Safari: "Safari'de Paylaş düğmesine, sonra Ana Ekrana Ekle'ye dokun. Simgeden açınca sayfa tam ekran olur.",
      guide1Done: "Ana ekrandan açtın; tam ekran hazır.",
      guide2Title: "İsteğe bağlı: kablo takılınca açılsın",
      guide2Text: "Kestirmeler → Otomasyon → Şarj Aleti → Bağlandığında → URL'yi Aç → aşağıdaki bağlantı → Hemen Çalıştır. Bu yol sayfayı tam ekran değil tarayıcıda açar; henüz denenmedi.",
      copy: "Kopyala",
      copied: "Kopyalandı",
      guide3Title: "Telefonu yan çevir",
      guide3Text: "Yatayda bütün değerler bir arada görünür; bir stand önerilir.",
      close: "Kapat",
    },
    en: {
      connecting: "Connecting…",
      mac: "Mac",
      cable: "cable",
      wifi: "Wi-Fi",
      stateCable: "Plug in the cable",
      stateCableText: "This phone is connected over Wi-Fi. Plug the iPhone into the Mac to see data.",
      stateOffline: "Cannot reach the Mac",
      stateOfflineText: "Is PhoneBox running, and is the phone plugged in or on the same Wi-Fi? Retrying in the background.",
      stateUnpaired: "Not paired",
      stateUnpairedText: "Scan the QR code on the Mac, add the page that opens to the Home Screen again, and delete the old icon.",
      stateNoKeyText: "This page has no key. Plug the iPhone into the Mac and scan the QR code the Mac shows.",
      stateNoData: "No data",
      stateNoDataText: "The Mac is not sending data right now.",
      start: "Start",
      startNote: "Tap once to keep the screen on",
      metric: { cpu: "CPU", ram: "RAM", gpu: "GPU", temp: "Temperature", power: "Power", net: "Network", disk: "Disk", battery: "Battery" },
      diskTile: "Disk free",
      lastMinute: "last 60 s",
      load: (value) => `load ${value}`,
      memory: (used, total) => `${used} / ${total} GB`,
      hottest: (value) => `hottest ${value}`,
      systemPower: "whole Mac",
      gpuPower: "GPU only",
      gpuWatts: (value) => `${value} GPU power`,
      upload: (speed, iface) => `↑ ${speed}` + (iface ? ` · ${iface}` : ""),
      diskRead: (speed) => `read ${speed}`,
      diskDetail: (write, free, total) => `write ${write} · ${free} of ${total} GB free`,
      charging: "charging",
      onPower: "on power",
      untilEmpty: (time) => `${time} left`,
      untilFull: (time) => `${time} to full`,
      duration: (hours, minutes) => (hours ? `${hours} h ` : "") + `${minutes} min`,
      apps: "Apps",
      more: "More",
      guideItem: "Setup guide",
      guideTitle: "Setup",
      guide1Title: "Add to Home Screen → full screen",
      guide1Chrome: "In Chrome, tap Share in the address bar, then Add to Home Screen. Opened from the icon, the page is full screen.",
      guide1Safari: "In Safari, tap Share, then Add to Home Screen. Opened from the icon, the page is full screen.",
      guide1Done: "You opened it from the Home Screen; full screen is ready.",
      guide2Title: "Optional: open when the cable is plugged in",
      guide2Text: "Shortcuts → Automation → Charger → Is Connected → Open URL → the link below → Run Immediately. This opens the page in the browser, not full screen; not tested yet.",
      copy: "Copy",
      copied: "Copied",
      guide3Title: "Turn the phone sideways",
      guide3Text: "In landscape every value fits on one screen; a stand helps.",
      close: "Close",
    },
  };

  /// "tr" for any Turkish language tag, otherwise "en".
  function pick(languageTag) {
    return String(languageTag || "en").toLowerCase().startsWith("tr") ? "tr" : "en";
  }

  const navigator = global.navigator;
  const language = pick(navigator && navigator.language);
  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.i18n = { texts, pick, language, t: texts[language] };
})(typeof window !== "undefined" ? window : globalThis);
```

`Resources/web/format.js`:

```js
// Number formats for the dashboard (design §8 "Dil ve sayı biçimi"). A value that is missing or not a finite number
// shows as "—". A unit switches after rounding, so 999.6 KB/s reads "1,0 MB/s", never "1.000 KB/s".
(function (global) {
  "use strict";

  const GiB = 1073741824;
  const MiB = 1048576;
  const dash = "—";
  const ok = (value) => typeof value === "number" && Number.isFinite(value);

  function make(language) {
    const one = new Intl.NumberFormat(language, { minimumFractionDigits: 1, maximumFractionDigits: 1 });
    const upToOne = new Intl.NumberFormat(language, { maximumFractionDigits: 1 });
    const whole = new Intl.NumberFormat(language, { maximumFractionDigits: 0 });
    const percentStyle = new Intl.NumberFormat(language, { style: "percent", maximumFractionDigits: 0 });

    // [divisor, unit, formatter, fraction digits], smallest first.
    function scaled(value, steps) {
      for (let index = 0; index < steps.length; index += 1) {
        const [divisor, unit, formatter, digits] = steps[index];
        const shown = Math.round((value / divisor) * 10 ** digits) / 10 ** digits;
        if (shown < 1000 || index === steps.length - 1) return formatter.format(value / divisor) + unit;
      }
      return dash;
    }

    return {
      dash,
      /// 64 → "%64" in Turkish, "64%" in English.
      percent: (value) => (ok(value) ? percentStyle.format(value / 100) : dash),
      /// One decimal: 3.21 → "3,2".
      decimal: (value) => (ok(value) ? one.format(value) : dash),
      celsius: (value) => (ok(value) ? whole.format(value) + " °C" : dash),
      watts: (value) => (ok(value) && value >= 0 ? one.format(value) + " W" : dash),
      /// Bytes per second: "512 B/s", "84 KB/s", "1,2 MB/s".
      speed(bytesPerSecond) {
        if (!ok(bytesPerSecond) || bytesPerSecond < 0) return dash;
        return scaled(bytesPerSecond, [[1, " B/s", whole, 0], [1e3, " KB/s", whole, 0], [1e6, " MB/s", one, 1],
                                        [1e9, " GB/s", one, 1]]);
      },
      /// The tiles' short form: "512B", "84K", "1,2M".
      speedShort(bytesPerSecond) {
        if (!ok(bytesPerSecond) || bytesPerSecond < 0) return dash;
        return scaled(bytesPerSecond, [[1, "B", whole, 0], [1e3, "K", whole, 0], [1e6, "M", one, 1], [1e9, "G", one, 1]]);
      },
      /// Binary gigabytes like the RAM ring and Activity Monitor: 16 GiB → "16", 13.74e9 bytes → "12,8".
      gibibytes: (bytes) => (ok(bytes) && bytes >= 0 ? upToOne.format(bytes / GiB) : dash),
      /// An app's memory, binary units like Activity Monitor: "640 MB", "5,3 GB".
      memory(bytes) {
        if (!ok(bytes) || bytes < 0) return dash;
        return Math.round(bytes / MiB) < 1000 ? whole.format(bytes / MiB) + " MB" : upToOne.format(bytes / GiB) + " GB";
      },
      /// Disk capacity in decimal gigabytes like Finder: "494,4".
      gigabytes: (bytes) => (ok(bytes) && bytes >= 0 ? upToOne.format(bytes / 1e9) : dash),
    };
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.format = make;
})(typeof window !== "undefined" ? window : globalThis);
```

- [ ] **Step 4: Geçmiş, metrikler ve grafik**

`Resources/web/history.js`:

```js
// The graph's last 60 seconds, kept only in the phone's memory (design §8 "Grafik"). One slot per second of the Mac's
// clock; a second without a snapshot stays empty, so the line shows a gap instead of a made-up value.
(function (global) {
  "use strict";

  class History {
    constructor(seconds = 60) {
      this.seconds = seconds;
      this.samples = new Map();
      this.latest = null;
    }

    /// `time` is the snapshot's `t` (milliseconds); `values` maps a series key to a number or null.
    push(time, values) {
      const second = Math.floor(time / 1000);
      // The Mac's clock jumped (set by hand, or a long sleep): start over rather than draw nonsense.
      if (this.latest !== null && (second <= this.latest - this.seconds || second > this.latest + 3600)) this.clear();
      if (this.latest === null || second > this.latest) this.latest = second;
      this.samples.set(second, values);
      for (const key of this.samples.keys()) {
        if (key <= this.latest - this.seconds) this.samples.delete(key);
      }
    }

    /// `seconds` values, oldest first, ending at the newest second; null where nothing (or nothing finite) arrived.
    series(key) {
      const values = [];
      for (let index = this.seconds - 1; index >= 0; index -= 1) {
        const sample = this.latest === null ? undefined : this.samples.get(this.latest - index);
        const value = sample ? sample[key] : null;
        values.push(typeof value === "number" && Number.isFinite(value) ? value : null);
      }
      return values;
    }

    clear() {
      this.samples.clear();
      this.latest = null;
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.History = History;
})(typeof window !== "undefined" ? window : globalThis);
```

`Resources/web/metrics.js`:

```js
// What each metric shows (design §6, §8): the values the history keeps, the graph's lines and scale, the tile text and
// the graph header. Pure functions of a snapshot, so they are tested in JavaScriptCore.
(function (global) {
  "use strict";

  const num = (value) => (typeof value === "number" && Number.isFinite(value) ? value : null);
  const GiB = 1073741824;

  const colors = {
    cpu: "#30d158", ram: "#0a84ff", gpu: "#bf5af2", temp: "#ff9f0a", power: "#ffd60a", net: "#64d2ff",
    disk: "#8e8e93", battery: "#30d158",
  };
  const order = ["cpu", "ram", "gpu", "temp", "power", "net", "disk", "battery"];

  /// The numbers the history keeps for one snapshot.
  function values(snapshot) {
    const { cpu, mem, gpu, temp, power, net, disk, battery } = snapshot;
    return {
      cpu: cpu ? num(cpu.total) : null,
      ram: mem && mem.total > 0 ? num((mem.used / mem.total) * 100) : null,
      gpu: gpu ? num(gpu.util) : null,
      tempAvg: temp ? num(temp.avg) : null,
      tempMax: temp ? num(temp.max) : null,
      power: power ? num(power.system ?? power.gpu) : null,
      netRx: net ? num(net.rx) : null,
      netTx: net ? num(net.tx) : null,
      diskRead: disk ? num(disk.read) : null,
      diskWrite: disk ? num(disk.write) : null,
      battery: battery ? num(battery.percent) : null,
    };
  }

  /// The graph's lines for a metric: history key, colour, width, and whether the area under it is filled.
  function lines(metric) {
    const color = colors[metric];
    switch (metric) {
      case "temp":
        return [{ key: "tempAvg", color, width: 2.2, fill: true }, { key: "tempMax", color, width: 1, fill: false, alpha: 0.55 }];
      case "net":
        return [{ key: "netRx", color, width: 2.2, fill: true }, { key: "netTx", color: "#bf5af2", width: 1.6, fill: false }];
      case "disk":
        return [{ key: "diskRead", color: "#d1d1d6", width: 2.2, fill: true }, { key: "diskWrite", color: "#ff9f0a", width: 1.6, fill: false }];
      default:
        return [{ key: metric, color, width: 2.2, fill: true }];
    }
  }

  /// How the graph's vertical axis is chosen (see `PhoneBox.chart.range`).
  function scale(metric) {
    if (metric === "temp") return "temperature";
    if (metric === "power" || metric === "net" || metric === "disk") return "fromZero";
    return "percent";
  }

  /// The big text on a tile.
  function tile(metric, snapshot, format) {
    const { gpu, temp, power, net, disk, battery } = snapshot;
    switch (metric) {
      case "gpu": return gpu ? format.percent(gpu.util) : format.dash;
      case "temp": return temp ? format.celsius(temp.avg) : format.dash;
      case "power": return power ? format.watts(power.system ?? power.gpu) : format.dash;
      case "net": return net ? `↓${format.speedShort(net.rx)} ↑${format.speedShort(net.tx)}` : format.dash;
      case "disk": return disk ? format.gigabytes(disk.free) + " GB" : format.dash;
      case "battery": return battery ? format.percent(battery.percent) + (battery.charging ? " ⚡" : "") : format.dash;
      default: return format.dash;
    }
  }

  function batteryDetail(battery, t) {
    const time = (minutes) => t.duration(Math.floor(minutes / 60), minutes % 60);
    if (battery.minutesLeft != null) return battery.charging ? t.untilFull(time(battery.minutesLeft)) : t.untilEmpty(time(battery.minutesLeft));
    return battery.charging ? t.charging : t.onPower;
  }

  /// The graph header's value and detail for the selected metric.
  function header(metric, snapshot, format, t) {
    const { cpu, mem, gpu, temp, power, net, disk, battery } = snapshot;
    const none = { value: format.dash, detail: "" };
    switch (metric) {
      case "cpu":
        if (!cpu) return none;
        return { value: format.percent(cpu.total), detail: cpu.load && cpu.load.length ? t.load(format.decimal(cpu.load[0])) : "" };
      case "ram":
        if (!mem || !(mem.total > 0)) return none;
        return { value: format.percent((mem.used / mem.total) * 100), detail: t.memory(format.gibibytes(mem.used), format.gibibytes(mem.total)) };
      case "gpu":
        if (!gpu) return none;
        return { value: format.percent(gpu.util), detail: power && num(power.gpu) !== null ? t.gpuWatts(format.watts(power.gpu)) : "" };
      case "temp":
        if (!temp) return none;
        return { value: format.celsius(temp.avg), detail: temp.max - temp.avg >= 1 ? t.hottest(format.celsius(temp.max)) : "" };
      case "power":
        if (!power || num(power.system ?? power.gpu) === null) return none;
        return { value: format.watts(power.system ?? power.gpu), detail: num(power.system) !== null ? t.systemPower : t.gpuPower };
      case "net":
        if (!net) return none;
        return { value: "↓ " + format.speed(net.rx), detail: t.upload(format.speed(net.tx), net.iface) };
      case "disk":
        if (!disk) return none;
        return { value: t.diskRead(format.speed(disk.read)),
                 detail: t.diskDetail(format.speed(disk.write), format.gigabytes(disk.free), format.gigabytes(disk.total)) };
      case "battery":
        if (!battery) return none;
        return { value: format.percent(battery.percent), detail: batteryDetail(battery, t) };
      default:
        return none;
    }
  }

  /// The top-of-axis label for a graph's range.
  function axisLabel(metric, range, format) {
    switch (scale(metric)) {
      case "temperature": return format.celsius(range.max);
      case "fromZero": return metric === "power" ? format.watts(range.max) : format.speed(range.max);
      default: return format.percent(range.max);
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.metrics = { colors, order, values, lines, scale, tile, header, axisLabel, GiB };
})(typeof window !== "undefined" ? window : globalThis);
```

`Resources/web/chart.js`:

```js
// The 60-second graph on a <canvas> (design §8 "Grafik"). `range` is pure and tested; `draw` is checked by eye.
(function (global) {
  "use strict";

  /// The smallest 1, 2 or 5 × 10ⁿ that is at least `value` (1 for nothing positive).
  function niceCeil(value) {
    if (!(value > 0) || !Number.isFinite(value)) return 1;
    const power = 10 ** Math.floor(Math.log10(value));
    for (const step of [1, 2, 5, 10]) {
      if (value <= step * power * (1 + 1e-9)) return step * power;
    }
    return 10 * power;
  }

  /// The vertical range: "percent" is 0…100; "temperature" spans at least 20 °C around the values in steps of 5;
  /// "fromZero" starts at 0 and ends at a round number above the largest value.
  function range(kind, seriesList) {
    if (kind === "percent") return { min: 0, max: 100 };
    const values = [].concat(...seriesList).filter((value) => value !== null);
    if (kind === "temperature") {
      if (!values.length) return { min: 30, max: 60 };
      const min = Math.max(0, Math.floor(Math.min(...values) / 5) * 5 - 5);
      const max = Math.max(Math.ceil(Math.max(...values) / 5) * 5 + 5, min + 20);
      return { min, max };
    }
    return { min: 0, max: niceCeil(Math.max(0, ...values) * 1.1) };
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
      canvas.width = Math.round(width * ratio);
      canvas.height = Math.round(height * ratio);
    }
    const g = canvas.getContext("2d");
    g.setTransform(ratio, 0, 0, ratio, 0, 0);
    g.clearRect(0, 0, width, height);

    g.strokeStyle = "#2c2c2e";
    g.lineWidth = 1;
    g.setLineDash([3, 4]);
    g.beginPath();
    g.moveTo(0, Math.round(height / 2) + 0.5);
    g.lineTo(width, Math.round(height / 2) + 0.5);
    g.stroke();
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
          if (run.length) runs.push(run);
          run = [];
        } else {
          run.push([x(index), y(value)]);
        }
      });
      if (run.length) runs.push(run);
      g.globalAlpha = line.alpha ?? 1;
      for (const points of runs) {
        if (points.length === 1) {
          g.fillStyle = line.color;
          g.beginPath();
          g.arc(points[0][0], points[0][1], line.width, 0, Math.PI * 2);
          g.fill();
          continue;
        }
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
          g.fill();
        }
        g.strokeStyle = line.color;
        g.lineWidth = line.width;
        g.lineJoin = "round";
        g.lineCap = "round";
        g.beginPath();
        points.forEach(([px, py], index) => (index ? g.lineTo(px, py) : g.moveTo(px, py)));
        g.stroke();
      }
      g.globalAlpha = 1;
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.chart = { niceCeil, range, draw };
})(typeof window !== "undefined" ? window : globalThis);
```

- [ ] **Step 5: Testleri çalıştır**

Run: `make test FILTER="WebPageTests"` → Expected: 13 test geçer.
Run: iki uyarı denetimi → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 17 tests in 4 suites passed` ve `Test run with 151 tests in 27 suites passed`.

- [ ] **Step 6: Commit**

```bash
git add Resources/web/i18n.js Resources/web/format.js Resources/web/history.js Resources/web/metrics.js \
  Resources/web/chart.js Tests/PhoneBoxCoreTests/WebPageTests.swift
git commit -m "Add the dashboard's texts, number formats, history and graph scale with tests"
```

---

### Task 3: Yeni sayfa

**Files:**
- Modify (dosyanın tamamı): `Resources/web/index.html`, `Resources/web/styles.css`, `Resources/web/app.js`
- Create: `Resources/web/connection.js`, `Resources/web/view.js`, `Resources/web/ui.js`

**Interfaces:**
- Consumes: Görev 2'nin `PhoneBox.i18n`, `format`, `History`, `metrics`, `chart`; `PBCrypto` (`sha256.js`).
- Produces:
  - `PhoneBox.readKey()`.
  - `PhoneBox.Connection(key, handlers)`: `start()`, `send(message) -> Bool`. `handlers` şunlardır: `onState(kind)`
    (`connecting`, `streaming`, `cable`, `offline`, `unpaired`, `nodata`), `onStale(bool)`, `onReady(ready)`,
    `onAccess(access)`, `onSnapshot(snapshot)` ve 4B için `onAck(ack)`.
  - `PhoneBox.View(t, format)`: `fillTexts`, `setHost`, `setAccess`, `setState`, `setStale`, `render(snapshot)`,
    `select(metric)`, `renderGraph(history)`, `renderApps`, `toggleSort`.
  - `PhoneBox.ui`: `setup(t)`, `openGuide()`, `closeMenu()`, `isStarted()`.
  - `PhoneBox.connection`: çalışan bağlantı, 4B'nin komutları göndermesi için.
  - Sayfadaki kimlikler: `#more`, `#menu`, `#strip`, `.strip-space`, `#app-list`, `#now-playing`. 4B bunları kullanır.

- [ ] **Step 1: Sayfanın iskeleti ve stili**

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
<link rel="apple-touch-icon" href="apple-touch-icon.png">
<title>PhoneBox</title>
<link rel="stylesheet" href="styles.css">
</head>
<body>
<main id="dashboard" class="dashboard stale">
  <header class="top">
    <span class="brand">PhoneBox</span>
    <span id="status" class="status" role="status" aria-live="polite"><span class="dot"></span><span id="status-text"></span></span>
  </header>

  <section class="rings">
    <button class="ring-button" data-metric="cpu" type="button">
      <span class="ring"><span class="ring-inner"><span class="ring-value" id="cpu-ring">—</span><span class="ring-label">CPU</span></span></span>
      <span class="ring-sub" id="cpu-sub"></span>
    </button>
    <button class="ring-button" data-metric="ram" type="button">
      <span class="ring"><span class="ring-inner"><span class="ring-value" id="ram-ring">—</span><span class="ring-label">RAM</span></span></span>
      <span class="ring-sub" id="ram-sub"></span>
    </button>
  </section>

  <section class="graph card">
    <div class="graph-head"><span class="graph-title" id="graph-title"></span><span class="graph-value" id="graph-value">—</span></div>
    <div class="graph-detail" id="graph-detail"></div>
    <canvas id="graph" aria-hidden="true"></canvas>
  </section>

  <section class="tiles">
    <button class="tile card" data-metric="gpu" type="button"><span class="tile-label"><i></i><span data-metric-label="gpu"></span></span><span class="tile-value" id="gpu-tile">—</span></button>
    <button class="tile card" data-metric="temp" type="button"><span class="tile-label"><i></i><span data-metric-label="temp"></span></span><span class="tile-value" id="temp-tile">—</span></button>
    <button class="tile card" data-metric="power" type="button"><span class="tile-label"><i></i><span data-metric-label="power"></span></span><span class="tile-value" id="power-tile">—</span></button>
    <button class="tile card" data-metric="net" type="button"><span class="tile-label"><i></i><span data-metric-label="net"></span></span><span class="tile-value" id="net-tile">—</span></button>
    <button class="tile card" data-metric="disk" type="button"><span class="tile-label"><i></i><span data-text="diskTile"></span></span><span class="tile-value" id="disk-tile">—</span></button>
    <button class="tile card" data-metric="battery" type="button"><span class="tile-label"><i></i><span data-metric-label="battery"></span></span><span class="tile-value" id="battery-tile">—</span></button>
  </section>

  <section class="now-playing card" id="now-playing" hidden>
    <span class="np-icon" aria-hidden="true">♪</span>
    <span class="np-text"><span class="np-title" id="np-title"></span><span class="np-sub" id="np-sub"></span></span>
  </section>

  <section class="apps">
    <div class="apps-head"><span data-text="apps"></span><button id="app-sort" class="app-sort" type="button"></button></div>
    <ol id="app-list" class="app-list"></ol>
  </section>

  <section class="strip card">
    <span class="strip-space"></span>
    <button id="more" class="strip-button" type="button" aria-haspopup="menu">⋯</button>
  </section>
</main>

<div id="state" class="state" hidden><div class="state-card"><h2 id="state-title"></h2><p id="state-text"></p></div></div>

<div id="menu-backdrop" class="menu-backdrop" hidden></div>
<div id="menu" class="menu" role="menu" hidden>
  <button id="menu-guide" type="button" role="menuitem" data-text="guideItem"></button>
</div>

<div id="guide" class="overlay guide" hidden>
  <div class="guide-card">
    <h2 data-text="guideTitle"></h2>
    <ol class="guide-steps">
      <li><strong data-text="guide1Title"></strong><p id="guide1-text"></p></li>
      <li>
        <strong data-text="guide2Title"></strong><p data-text="guide2Text"></p>
        <span class="link-row"><input id="guide-link" readonly><button id="guide-copy" type="button" data-text="copy"></button></span>
      </li>
      <li><strong data-text="guide3Title"></strong><p data-text="guide3Text"></p></li>
    </ol>
    <button id="guide-done" class="primary" type="button"></button>
  </div>
</div>

<div id="start" class="overlay start" hidden>
  <button id="start-button" class="primary" type="button" data-text="start"></button>
  <p data-text="startNote"></p>
</div>

<video id="keepawake" playsinline preload="auto" src="keepawake.mp4"></video>
<script src="sha256.js"></script>
<script src="i18n.js"></script>
<script src="format.js"></script>
<script src="history.js"></script>
<script src="metrics.js"></script>
<script src="chart.js"></script>
<script src="connection.js"></script>
<script src="view.js"></script>
<script src="ui.js"></script>
<script src="app.js"></script>
</body>
</html>
```

`Resources/web/styles.css`:

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
  --bad: #ff453a;
  --accent: #0a84ff;
  color-scheme: dark;
}

@property --p {
  syntax: "<number>";
  inherits: false;
  initial-value: 0;
}

* { box-sizing: border-box; }
[hidden] { display: none !important; }

html, body {
  margin: 0;
  height: 100%;
  overflow: hidden;
  background: var(--bg);
  color: var(--text);
  font: 14px/1.3 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
  -webkit-text-size-adjust: 100%;
  -webkit-user-select: none;
  user-select: none;
}

button {
  font: inherit;
  color: inherit;
  background: none;
  border: 0;
  padding: 0;
  margin: 0;
  text-align: inherit;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

h2 { font-size: 17px; margin: 0 0 6px; }
p { margin: 0; }
.card { background: var(--card); border-radius: 16px; }

[data-metric="cpu"] { --color: var(--cpu); }
[data-metric="ram"] { --color: var(--ram); }
[data-metric="gpu"] { --color: var(--gpu); }
[data-metric="temp"] { --color: var(--temp); }
[data-metric="power"] { --color: var(--power); }
[data-metric="net"] { --color: var(--net); }
[data-metric="disk"] { --color: var(--disk); }
[data-metric="battery"] { --color: var(--battery); }

/* ---- Layout ---- */
.dashboard {
  position: fixed;
  inset: 0;
  display: grid;
  gap: 8px 12px;
  padding: calc(env(safe-area-inset-top) + 8px) calc(env(safe-area-inset-right) + 12px)
           calc(env(safe-area-inset-bottom) + 6px) calc(env(safe-area-inset-left) + 12px);
  transform: translate(var(--dx, 0px), var(--dy, 0px));
  transition: transform 2s ease, opacity 0.3s, filter 0.3s;
}
.dashboard.stale { opacity: 0.4; filter: grayscale(0.5); }

.top { grid-area: top; display: flex; align-items: center; justify-content: space-between; gap: 8px; min-width: 0; }
.rings { grid-area: rings; display: flex; align-items: center; }
.graph { grid-area: graph; }
.tiles { grid-area: tiles; }
.now-playing { grid-area: playing; }
.apps { grid-area: apps; }
.strip { grid-area: strip; }

@media (orientation: landscape) {
  .dashboard {
    --ring: clamp(84px, calc((100dvh - env(safe-area-inset-top) - env(safe-area-inset-bottom) - 72px) / 2.25), 128px);
    --row: 34px;
    grid-template-columns: calc(var(--ring) + 8px) minmax(0, 1fr) clamp(176px, 26vw, 240px);
    grid-template-rows: auto auto minmax(0, 1fr) auto auto;
    grid-template-areas:
      "rings graph top"
      "rings graph playing"
      "rings graph apps"
      "rings tiles apps"
      "rings strip apps";
  }
  .brand { display: none; }
  .top { justify-content: flex-end; }
  .rings { flex-direction: column; justify-content: space-around; }
}

@media (orientation: portrait) {
  .dashboard {
    --ring: clamp(84px, min(31vw, 17dvh), 128px);
    --row: 34px;
    grid-template-columns: minmax(0, 1fr);
    grid-template-rows: auto auto clamp(110px, 19dvh, 160px) auto minmax(0, 1fr) auto auto;
    grid-template-areas: "top" "rings" "graph" "tiles" "apps" "playing" "strip";
  }
  .rings { flex-direction: row; justify-content: space-around; }
  .np-text { flex-direction: row; gap: 6px; align-items: baseline; }
  .np-sub::before { content: "· "; }
  .np-icon { width: 24px; height: 24px; font-size: 13px; }
}

/* ---- Status ---- */
.brand { font-weight: 600; font-size: 15px; }
.status { display: flex; align-items: center; gap: 6px; color: var(--muted); font-size: 12px; white-space: nowrap; min-width: 0; }
#status-text { overflow: hidden; text-overflow: ellipsis; }
.dot { width: 7px; height: 7px; border-radius: 50%; background: var(--muted); flex: none; }
.status.streaming .dot { background: var(--ok); }
.status.wifi .dot { background: var(--warn); }
.status.problem .dot { background: var(--bad); }

/* ---- Rings ---- */
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
  flex-direction: column;
  align-items: center;
  justify-content: center;
}
.ring-value { font-size: calc(var(--ring) * 0.22); font-weight: 700; line-height: 1; font-variant-numeric: tabular-nums; }
.ring-label, .graph-title, .tile-label, .apps-head {
  font-size: 10.5px;
  color: var(--muted);
  text-transform: uppercase;
  letter-spacing: 0.07em;
}
.ring-label { margin-top: 3px; }
.ring-sub { font-size: 11.5px; color: var(--muted); margin-top: 4px; white-space: nowrap; }
.ring-button.selected .ring { box-shadow: 0 0 0 2px var(--bg), 0 0 0 4px var(--color); }

/* ---- Graph ---- */
.graph { display: flex; flex-direction: column; padding: 10px 12px 8px; min-height: 0; min-width: 0; }
.graph-head { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; }
.graph-title { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.graph-value { font-size: 19px; font-weight: 700; color: var(--color, var(--text)); white-space: nowrap; font-variant-numeric: tabular-nums; }
.graph-detail { font-size: 11.5px; color: var(--muted); min-height: 15px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; text-align: right; }
#graph { flex: 1; min-height: 0; width: 100%; margin-top: 2px; }

/* ---- Tiles ---- */
.tiles { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 6px; }
.tile { display: flex; flex-direction: column; gap: 2px; padding: 7px 10px; min-width: 0; }
.tile-label { display: flex; align-items: center; gap: 6px; white-space: nowrap; overflow: hidden; }
.tile-label i { width: 7px; height: 7px; border-radius: 50%; background: var(--color); flex: none; }
.tile-value { font-size: 16px; font-weight: 700; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; font-variant-numeric: tabular-nums; }
.tile.selected { box-shadow: inset 0 0 0 2px var(--color); }

/* ---- Now playing ---- */
.now-playing { display: flex; align-items: center; gap: 9px; padding: 7px 9px; min-width: 0; }
.np-icon { width: 34px; height: 34px; border-radius: 8px; background: var(--raised); display: grid; place-items: center; flex: none; font-size: 16px; }
.np-text { display: flex; flex-direction: column; min-width: 0; line-height: 1.25; }
.np-title { font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.np-sub { font-size: 11.5px; color: var(--muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

/* ---- Apps ---- */
.apps { display: flex; flex-direction: column; min-height: 0; min-width: 0; }
.apps-head { display: flex; justify-content: space-between; align-items: center; margin: 0 2px 2px; }
.app-sort { color: var(--muted); padding: 2px 0 2px 12px; }
.app-list { list-style: none; margin: 0; padding: 0; flex: 1; min-height: 0; overflow: hidden; }
.app-list li {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  height: var(--row);
  padding: 0 2px;
  border-bottom: 1px solid var(--line);
}
.app-list li:last-child { border-bottom: 0; }
.app-name { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; min-width: 0; }
.app-figures { color: var(--muted); white-space: nowrap; font-variant-numeric: tabular-nums; }
.app-list li.dim .app-name { color: var(--muted); }

/* ---- Strip ---- */
.strip { display: flex; align-items: center; gap: 4px; height: 52px; padding: 0 8px; }
.strip-space { flex: 1; }
.strip-button { width: 44px; height: 44px; border-radius: 12px; display: grid; place-items: center; font-size: 20px; flex: none; }
.strip-button:active { background: var(--raised); }

/* ---- Menu ---- */
.menu-backdrop { position: fixed; inset: 0; }
.menu { position: fixed; min-width: 220px; background: var(--raised); border-radius: 14px; overflow: hidden; box-shadow: 0 8px 30px rgba(0, 0, 0, 0.6); }
.menu button { display: flex; align-items: center; width: 100%; height: 44px; padding: 0 14px; border-bottom: 1px solid #3a3a3c; }
.menu button:last-child { border-bottom: 0; }
.menu button:active { background: #3a3a3c; }

/* ---- State card ---- */
.state { position: fixed; inset: 0; display: grid; place-items: center; padding: 24px; pointer-events: none; }
.state-card {
  max-width: 340px;
  padding: 16px 18px;
  border-radius: 16px;
  background: rgba(44, 44, 46, 0.96);
  text-align: center;
  box-shadow: 0 8px 30px rgba(0, 0, 0, 0.6);
}
.state-card p { color: #d1d1d6; font-size: 13.5px; line-height: 1.4; }

/* ---- Overlays ---- */
.overlay {
  position: fixed;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 14px;
  padding: calc(env(safe-area-inset-top) + 16px) calc(env(safe-area-inset-right) + 16px)
           calc(env(safe-area-inset-bottom) + 16px) calc(env(safe-area-inset-left) + 16px);
  background: var(--bg);
  text-align: center;
}
.primary { background: var(--accent); color: #fff; font-weight: 600; font-size: 17px; border-radius: 14px; padding: 14px 40px; text-align: center; }
.start p { color: var(--muted); font-size: 14px; max-width: 420px; }

.guide { background: rgba(0, 0, 0, 0.92); }
.guide-card {
  width: min(560px, 100%);
  max-height: 100%;
  overflow-y: auto;
  padding: 18px 18px 16px;
  border-radius: 18px;
  background: var(--card);
  text-align: left;
  -webkit-user-select: text;
  user-select: text;
}
.guide-steps { margin: 4px 0 14px; padding-left: 20px; display: flex; flex-direction: column; gap: 12px; }
.guide-steps p { color: #d1d1d6; font-size: 13.5px; line-height: 1.4; margin-top: 3px; }
.guide-steps p.done { color: var(--ok); }
.link-row { display: flex; gap: 8px; margin-top: 8px; }
.link-row input {
  flex: 1;
  min-width: 0;
  font: 12px ui-monospace, Menlo, monospace;
  color: var(--text);
  background: var(--raised);
  border: 0;
  border-radius: 10px;
  padding: 9px 10px;
}
.link-row button { background: var(--raised); border-radius: 10px; padding: 0 14px; font-weight: 600; }
.guide-card .primary { display: block; width: 100%; }

#keepawake { position: fixed; right: 0; bottom: 0; width: 2px; height: 2px; opacity: 0.01; pointer-events: none; }
```

- [ ] **Step 2: Bağlantı**

`Resources/web/connection.js` (bugünkü `app.js`'teki bağlantı mantığı; geri çekilme artık 1 sn'lik sayaçla
kısalmıyor):

```js
// The WebSocket to the Mac (design §5): pairing key, authentication, reconnection and dead-socket detection.
// It reports what the page should show through `handlers`; it never touches the page itself.
(function (global) {
  "use strict";

  /// The key from the personal link's fragment (#k=…), else from localStorage on later visits.
  function readKey() {
    const decode = (text) => {
      try {
        const bytes = text ? global.PBCrypto.base64UrlToBytes(text) : null;
        return bytes && bytes.length === 32 ? bytes : null;
      } catch (error) {
        return null;
      }
    };
    const fromLink = new URLSearchParams(global.location.hash.slice(1)).get("k");
    const linkBytes = decode(fromLink);
    if (linkBytes) {
      try {
        global.localStorage.setItem("phonebox-key", fromLink);
      } catch (error) {}
      return linkBytes;
    }
    let stored = null;
    try {
      stored = global.localStorage.getItem("phonebox-key");
    } catch (error) {}
    return decode(stored);
  }

  const retryDelays = [1000, 2000, 5000];
  /// A snapshot is due every second; without one for this long the values are stale.
  const staleAfter = 3000;
  /// Silence for this long while streaming means the socket is dead (iOS keeps such sockets "open" after a lock).
  const deadAfter = 5000;
  /// Not streaming (e.g. on Wi-Fi in cable mode): reconnect this often so the phone moves to the cable by itself.
  const recheckAfter = 10000;

  /// handlers: onState(kind) with kind "connecting" | "streaming" | "cable" | "offline" | "unpaired" | "nodata";
  /// onStale(stale); onReady({host, mode, access}); onAccess(access); onSnapshot(snapshot); onAck(ack).
  class Connection {
    constructor(key, handlers) {
      this.key = key;
      this.handlers = handlers;
      this.socket = null;
      this.nonce = null;
      this.retries = 0;
      this.stopped = false;
      this.access = null;
      this.accessSetAt = 0;
      this.lastMessageAt = 0;
      this.lastSnapshotAt = 0;
      this.openedAt = 0;
      this.nextAttemptAt = 0;
      this.stale = true;
    }

    start() {
      global.setInterval(() => this.tick(), 1000);
      for (const name of ["visibilitychange", "pageshow", "focus"]) global.addEventListener(name, () => this.resume());
      this.connect();
    }

    /// True when the message went out on an open socket.
    send(message) {
      if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return false;
      this.socket.send(JSON.stringify(message));
      return true;
    }

    visible() {
      return global.document.visibilityState === "visible";
    }

    // Every second: mark stale values, replace a dead socket, and reconnect once the back-off delay has passed.
    tick() {
      if (this.stopped) return;
      if (this.access && this.access.streaming && Date.now() - this.lastSnapshotAt > staleAfter) this.setStale(true);
      this.replaceIfDead();
      if (Date.now() >= this.nextAttemptAt) this.connect();
    }

    // The page came back (unlock, tab switch): check the socket at once instead of waiting for the back-off.
    resume() {
      if (this.stopped || !this.visible()) return;
      // The three events often fire together; a socket opened less than 1 s ago is kept.
      if (Date.now() - this.openedAt >= 1000) {
        if (this.access && !this.access.streaming && this.socket) this.replace();
        else this.replaceIfDead();
      }
      this.nextAttemptAt = 0;
      this.connect();
    }

    connect() {
      if (this.stopped || !this.visible()) return;
      if (this.socket && this.socket.readyState <= WebSocket.OPEN) return;
      if (!this.lastSnapshotAt) this.handlers.onState("connecting");
      const socket = new WebSocket(`ws://${global.location.host}/ws`);
      this.socket = socket;
      this.lastMessageAt = Date.now();
      this.openedAt = Date.now();
      socket.onmessage = (event) => {
        this.lastMessageAt = Date.now();
        let message;
        try {
          message = JSON.parse(event.data);
        } catch (error) {
          return;
        }
        this.handle(message);
      };
      socket.onclose = (event) => this.closed(socket, event.code);
    }

    retryIn(delay) {
      this.nextAttemptAt = Date.now() + delay;
      global.setTimeout(() => {
        if (Date.now() >= this.nextAttemptAt) this.connect();
      }, delay);
    }

    closed(socket, code) {
      if (this.socket === socket) this.socket = null;
      this.setStale(true);
      if (code === 4001) {
        // Wrong key or a pairing reset: retrying cannot help.
        this.stopped = true;
        this.handlers.onState("unpaired");
        return;
      }
      if (code === 4003) {
        // Authentication came too late (e.g. the phone was locked): retry, it is not a bad key.
        this.handlers.onState("connecting");
        this.retryIn(1000);
        return;
      }
      if (code === 4002) {
        // The Mac asked for a fresh connection (an iPhone was plugged in); a short pause keeps repeats from spinning.
        this.retryIn(250);
        return;
      }
      // A close while the page is hidden (phone locked) is not a failure; the page reconnects when it returns.
      if (this.visible()) this.retries += 1;
      this.handlers.onState(this.retries >= 3 ? "offline" : "connecting");
      this.retryIn(retryDelays[Math.min(Math.max(this.retries, 1), retryDelays.length) - 1]);
    }

    replaceIfDead() {
      if (!this.visible()) return;
      const socket = this.socket;
      if (!socket || socket.readyState !== WebSocket.OPEN) return;
      if (!(this.access && this.access.streaming)) {
        if (this.access && Date.now() - this.accessSetAt >= recheckAfter) this.replace();
        return;
      }
      if (Date.now() - this.lastMessageAt > deadAfter) this.replace();
    }

    replace() {
      const socket = this.socket;
      this.accessSetAt = Date.now();
      if (socket) {
        socket.onmessage = null;
        socket.onclose = null;
        try {
          socket.close();
        } catch (error) {}
      }
      this.socket = null;
      this.setStale(true);
      this.nextAttemptAt = 0;
      this.connect();
    }

    handle(message) {
      switch (message.type) {
        case "hello":
          this.nonce = message.nonce;
          this.send({ v: 1, type: "auth", mac: global.PBCrypto.hmacHex(this.key, "auth:" + message.nonce) });
          break;
        case "ready":
          this.retries = 0;
          if (this.handlers.onReady) this.handlers.onReady(message);
          this.applyAccess(message.access);
          break;
        case "access":
          this.applyAccess(message);
          break;
        case "snapshot":
          this.lastSnapshotAt = Date.now();
          this.setStale(false);
          this.handlers.onSnapshot(message);
          break;
        case "ack":
          if (this.handlers.onAck) this.handlers.onAck(message);
          break;
      }
    }

    applyAccess(access) {
      if (!access) return;
      this.access = access;
      this.accessSetAt = Date.now();
      this.handlers.onAccess(access);
      if (access.streaming) {
        this.handlers.onState("streaming");
      } else {
        this.setStale(true);
        this.handlers.onState(access.reason === "not-on-cable" ? "cable" : "nodata");
      }
    }

    setStale(stale) {
      if (stale === this.stale) return;
      this.stale = stale;
      this.handlers.onStale(stale);
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.readKey = readKey;
  global.PhoneBox.Connection = Connection;
})(typeof window !== "undefined" ? window : globalThis);
```

- [ ] **Step 3: Görünüm ve ekran davranışları**

`Resources/web/view.js`:

```js
// Puts the Mac's data on the page (design §8): rings, tiles, the graph and its header, the app list, the now-playing
// card, the status line and the state card. Text always goes in with textContent: names come from other apps.
(function (global) {
  "use strict";

  const $ = (id) => global.document.getElementById(id);
  const metrics = () => global.PhoneBox.metrics;

  class View {
    constructor(t, format) {
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

    render(snapshot) {
      this.snapshot = snapshot;
      const { cpu, mem } = snapshot;
      const f = this.format;
      const t = this.t;
      this.ring("cpu", cpu ? cpu.total : null, cpu && cpu.load && cpu.load.length ? t.load(f.decimal(cpu.load[0])) : "");
      const memoryOK = mem && mem.total > 0;
      this.ring("ram", memoryOK ? (mem.used / mem.total) * 100 : null,
                memoryOK ? t.memory(f.gibibytes(mem.used), f.gibibytes(mem.total)) : "");
      for (const metric of ["gpu", "temp", "power", "net", "disk", "battery"]) {
        $(metric + "-tile").textContent = metrics().tile(metric, snapshot, f);
      }
      this.renderHeader();
      const playingBefore = !$("now-playing").hidden;
      this.renderNowPlaying(snapshot.media);
      if (snapshot.apps) this.apps = snapshot.apps;
      // A new app list arrives every 3 s; the card appearing or going changes how many rows fit.
      if (snapshot.apps || playingBefore !== !$("now-playing").hidden) this.renderApps();
    }

    ring(metric, percent, sub) {
      const ok = typeof percent === "number" && Number.isFinite(percent);
      const ring = global.document.querySelector(`.ring-button[data-metric="${metric}"] .ring`);
      ring.style.setProperty("--p", ok ? Math.max(0, Math.min(100, percent)).toFixed(1) : "0");
      $(metric + "-ring").textContent = this.format.percent(ok ? percent : null);
      $(metric + "-sub").textContent = sub;
    }

    select(metric) {
      this.selected = metric;
      for (const element of global.document.querySelectorAll(".ring-button, .tile")) {
        element.classList.toggle("selected", element.dataset.metric === metric);
      }
      global.document.querySelector(".graph").dataset.metric = metric;
      this.renderHeader();
    }

    renderHeader() {
      const { value, detail } = metrics().header(this.selected, this.snapshot, this.format, this.t);
      $("graph-title").textContent = `${this.t.metric[this.selected]} · ${this.t.lastMinute}`;
      $("graph-value").textContent = value;
      $("graph-detail").textContent = detail;
    }

    renderGraph(history) {
      const m = metrics();
      const lines = m.lines(this.selected).map((line) => Object.assign({}, line, { values: history.series(line.key) }));
      const range = global.PhoneBox.chart.range(m.scale(this.selected), lines.map((line) => line.values));
      global.PhoneBox.chart.draw($("graph"), lines, range, m.axisLabel(this.selected, range, this.format));
    }

    renderNowPlaying(media) {
      $("now-playing").hidden = !media;
      if (!media) return;
      $("np-title").textContent = media.title;
      $("np-sub").textContent = media.artist ? `${media.artist} · ${media.app}` : media.app;
    }

    toggleSort() {
      this.sortBy = this.sortBy === "cpu" ? "mem" : "cpu";
      this.renderApps();
    }

    // Only as many rows as fit without cutting one off; grey rows are apps the phone cannot quit.
    renderApps() {
      $("app-sort").textContent = (this.sortBy === "cpu" ? "CPU" : "RAM") + " ▾";
      const list = $("app-list");
      if (!this.apps) {
        list.replaceChildren();
        return;
      }
      const key = this.sortBy;
      const other = key === "cpu" ? "mem" : "cpu";
      const sorted = this.apps.slice().sort((a, b) => b[key] - a[key] || b[other] - a[other] || String(a.name).localeCompare(String(b.name)));
      const rowHeight = parseFloat(global.getComputedStyle(list).getPropertyValue("--row")) || 34;
      const fits = Math.max(1, Math.floor((list.clientHeight + 1) / rowHeight));
      list.replaceChildren(...sorted.slice(0, fits).map((app) => {
        const item = global.document.createElement("li");
        if (!app.quittable) item.className = "dim";
        const name = global.document.createElement("span");
        name.className = "app-name";
        name.textContent = app.name;
        const figures = global.document.createElement("span");
        figures.className = "app-figures";
        figures.textContent = `${this.format.percent(app.cpu)} · ${this.format.memory(app.mem)}`;
        item.append(name, figures);
        return item;
      }));
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.View = View;
})(typeof window !== "undefined" ? window : globalThis);
```

`Resources/web/ui.js`:

```js
// Screen-level behaviour (design §8): keeping the screen on, the Start screen, the first-run guide, the "⋯" menu and
// the OLED shift.
(function (global) {
  "use strict";

  const $ = (id) => global.document.getElementById(id);
  const guideDoneKey = "phonebox-guide-done";
  let t = null;
  let started = false;

  // ---- Keep the screen on (spike V4): an unmuted, silent video that never loops, in an "ambient" audio session so
  // music on the phone keeps playing. A tap must start it.
  const video = $("keepawake");
  video.addEventListener("timeupdate", () => {
    if (video.currentTime > 0.5) video.currentTime = Math.random() * 0.4;
  });

  function keepAwake() {
    try {
      if (global.navigator.audioSession) global.navigator.audioSession.type = "ambient";
    } catch (error) {}
    video.muted = false;
    video.loop = false;
    return video.play();
  }

  // Chrome does not fire visibilitychange when the phone is unlocked, and WebKit pauses media while the page is
  // hidden: restart the video every few seconds if it stopped.
  global.setInterval(() => {
    if (started && global.document.visibilityState === "visible" && video.paused) keepAwake().catch(() => {});
  }, 3000);

  /// Resolves true once the video plays (the screen then stays on).
  function begin() {
    return keepAwake().then(() => {
      started = true;
      return true;
    }, () => false);
  }

  // ---- Start screen: shown on every visit (the video needs a tap).
  $("start-button").addEventListener("click", () => {
    begin().then((ok) => {
      $("start").hidden = ok;
    });
  });

  // ---- First-run guide (also from "⋯ → Kurulum rehberi").
  function guideDone() {
    try {
      return global.localStorage.getItem(guideDoneKey) === "1";
    } catch (error) {
      return false;
    }
  }

  function openGuide() {
    const standalone = global.navigator.standalone === true || global.matchMedia("(display-mode: standalone)").matches;
    const step1 = $("guide1-text");
    step1.textContent = standalone ? t.guide1Done : /CriOS/.test(global.navigator.userAgent) ? t.guide1Chrome : t.guide1Safari;
    step1.classList.toggle("done", standalone);
    $("guide-link").value = global.location.href;
    $("guide-copy").textContent = t.copy;
    $("guide-done").textContent = started ? t.close : t.start;
    $("guide").hidden = false;
  }

  $("guide-done").addEventListener("click", () => {
    try {
      global.localStorage.setItem(guideDoneKey, "1");
    } catch (error) {}
    if (started) {
      $("guide").hidden = true;
      return;
    }
    begin().then((ok) => {
      $("guide").hidden = true;
      $("start").hidden = ok;
    });
  });

  // Plain http:// has no Clipboard API on iOS; copying the selected text still works inside a tap.
  $("guide-copy").addEventListener("click", () => {
    const input = $("guide-link");
    input.focus();
    input.setSelectionRange(0, input.value.length);
    let copied = false;
    try {
      copied = global.document.execCommand("copy");
    } catch (error) {}
    input.blur();
    if (copied) {
      $("guide-copy").textContent = t.copied;
      global.setTimeout(() => {
        $("guide-copy").textContent = t.copy;
      }, 2000);
    }
  });

  // ---- "⋯" menu: opens above its button.
  function openMenu() {
    const menu = $("menu");
    menu.hidden = false;
    $("menu-backdrop").hidden = false;
    const button = $("more").getBoundingClientRect();
    menu.style.left = Math.max(8, Math.min(button.right - menu.offsetWidth, global.innerWidth - menu.offsetWidth - 8)) + "px";
    menu.style.top = Math.max(8, button.top - menu.offsetHeight - 8) + "px";
  }

  function closeMenu() {
    $("menu").hidden = true;
    $("menu-backdrop").hidden = true;
  }

  $("more").addEventListener("click", openMenu);
  $("menu-backdrop").addEventListener("click", closeMenu);
  global.addEventListener("resize", closeMenu);
  $("menu-guide").addEventListener("click", () => {
    closeMenu();
    openGuide();
  });

  // ---- OLED: every 3 minutes the whole page moves by up to 2 px.
  const offsets = [[0, 0], [2, 1], [-1, 2], [-2, -1], [1, -2]];
  let step = 0;
  global.setInterval(() => {
    step = (step + 1) % offsets.length;
    $("dashboard").style.setProperty("--dx", offsets[step][0] + "px");
    $("dashboard").style.setProperty("--dy", offsets[step][1] + "px");
  }, 180000);

  /// The first visit gets the guide (its button starts the screen keeping); later visits the Start screen.
  function setup(texts) {
    t = texts;
    if (guideDone()) $("start").hidden = false;
    else openGuide();
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.ui = { setup, openGuide, closeMenu, isStarted: () => started };
})(typeof window !== "undefined" ? window : globalThis);
```

- [ ] **Step 4: Bağlama**

`Resources/web/app.js`:

```js
// PhoneBox dashboard: wires the connection, the history and the view together (design §8 "Sayfa kodu").
(function (global) {
  "use strict";

  const PB = global.PhoneBox;
  const $ = (id) => global.document.getElementById(id);
  const { t, language } = PB.i18n;
  const format = PB.format(language);
  const view = new PB.View(t, format);
  const history = new PB.History(60);
  const selectedKey = "phonebox-metric";

  global.document.documentElement.lang = language;
  view.fillTexts();

  // The metric in the graph: CPU at first, then the last one chosen.
  let selected = "cpu";
  try {
    const saved = global.localStorage.getItem(selectedKey);
    if (PB.metrics.order.includes(saved)) selected = saved;
  } catch (error) {}
  view.select(selected);

  for (const element of global.document.querySelectorAll(".ring-button, .tile")) {
    element.addEventListener("click", () => {
      view.select(element.dataset.metric);
      view.renderGraph(history);
      try {
        global.localStorage.setItem(selectedKey, element.dataset.metric);
      } catch (error) {}
    });
  }
  $("app-sort").addEventListener("click", () => view.toggleSort());
  global.addEventListener("resize", () => {
    view.renderGraph(history);
    view.renderApps();
  });
  global.addEventListener("hashchange", () => global.location.reload());
  view.renderApps();
  view.renderGraph(history);

  const key = PB.readKey();
  if (!key) {
    view.setState("nokey");
    return;
  }
  PB.ui.setup(t);

  const connection = new PB.Connection(key, {
    onState: (kind) => view.setState(kind),
    onStale: (stale) => view.setStale(stale),
    onReady: (ready) => view.setHost(ready.host),
    onAccess: (access) => view.setAccess(access),
    onSnapshot: (snapshot) => {
      history.push(snapshot.t, PB.metrics.values(snapshot));
      view.render(snapshot);
      view.renderGraph(history);
    },
  });
  connection.start();
  PB.connection = connection;
})(window);
```

- [ ] **Step 5: Derle ve test et**

Run: iki uyarı denetimi → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 17 tests in 4 suites passed` ve `Test run with 151 tests in 27 suites passed`
(`WebPageTests` saf dosyaları yükler; yeni sayfa dosyaları onları bozmamalı).
Run: `grep -n "innerHTML\|insertAdjacentHTML\|outerHTML" Resources/web/*.js` → Expected: çıktı yok.
Run: `make app 2>&1 | tail -1` → Expected: `Built …/build/PhoneBox.app`. Uygulamayı başlatmayın; sayfayı kontrolcü
Görev 5'te dener.

- [ ] **Step 6: Commit**

```bash
git add Resources/web/index.html Resources/web/styles.css Resources/web/app.js Resources/web/connection.js \
  Resources/web/view.js Resources/web/ui.js
git commit -m "Lay out the dashboard as designed: rings, graph, tiles, apps and now playing"
```

---

### Task 4: Ana ekran simgesi

**Files:**
- Create: `scripts/make-touch-icon.swift`
- Modify: `scripts/bundle.sh`

**Interfaces:**
- Consumes: `index.html`'deki `<link rel="apple-touch-icon" href="apple-touch-icon.png">` (Görev 3).
- Produces: `build/PhoneBox.app/Contents/Resources/web/apple-touch-icon.png` (180×180).

- [ ] **Step 1: Simgeyi çizen betik**

`scripts/make-touch-icon.swift`:

```swift
// Draws the dashboard's Home Screen icon (design §8 "Ana ekran"): black, with a green and a blue ring like the
// page's CPU and RAM rings. iOS rounds the corners itself.
// Usage: swiftc -O make-touch-icon.swift -o make-touch-icon && ./make-touch-icon <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let size = 180
let output = CommandLine.arguments.dropFirst().first ?? "apple-touch-icon.png"
guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fail("no drawing context") }

context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
let center = CGPoint(x: size / 2, y: size / 2)

/// A grey track with a coloured arc that starts at 12 o'clock and runs clockwise for `fraction` of the circle.
func ring(radius: CGFloat, fraction: CGFloat, red: CGFloat, green: CGFloat, blue: CGFloat) {
    context.setLineWidth(18)
    context.setStrokeColor(CGColor(red: 0.173, green: 0.173, blue: 0.18, alpha: 1))
    context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.strokePath()
    context.setLineCap(.round)
    context.setStrokeColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
    let top = CGFloat.pi / 2
    context.addArc(center: center, radius: radius, startAngle: top, endAngle: top - fraction * 2 * .pi, clockwise: true)
    context.strokePath()
}

ring(radius: 62, fraction: 0.68, red: 0.188, green: 0.82, blue: 0.345)  // CPU green #30d158
ring(radius: 36, fraction: 0.45, red: 0.039, green: 0.518, blue: 1)     // RAM blue #0a84ff

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL,
                                                        UTType.png.identifier as CFString, 1, nil)
else { fail("cannot create \(output)") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fail("cannot write \(output)") }
```

- [ ] **Step 2: Paketlemeye ekle**

`scripts/bundle.sh`:

Bul (1/2):

```bash
#!/usr/bin/env bash
# Builds build/PhoneBox.app (release): binary, Info.plist, translations, dashboard files, the keep-awake video and
# mediaremote-adapter (script + framework). Ad-hoc signed, like NotchBox.
set -euo pipefail
```

Şununla değiştir:

```bash
#!/usr/bin/env bash
# Builds build/PhoneBox.app (release): binary, Info.plist, translations, dashboard files, the keep-awake video, the
# Home Screen icon and mediaremote-adapter (script + framework). Ad-hoc signed, like NotchBox.
set -euo pipefail
```

Bul (2/2):

```bash
"$ROOT/build/make-video" "$APP/Contents/Resources/web/keepawake.mp4"

xattr -cr "$APP"
```

Şununla değiştir:

```bash
"$ROOT/build/make-video" "$APP/Contents/Resources/web/keepawake.mp4"
swiftc -O -suppress-warnings "$ROOT/scripts/make-touch-icon.swift" -o "$ROOT/build/make-touch-icon"
"$ROOT/build/make-touch-icon" "$APP/Contents/Resources/web/apple-touch-icon.png"

xattr -cr "$APP"
```

- [ ] **Step 3: Paketle ve bak**

Run: `make app 2>&1 | tail -1` → Expected: `Built …/build/PhoneBox.app`.
Run: `sips -g pixelWidth -g pixelHeight build/PhoneBox.app/Contents/Resources/web/apple-touch-icon.png` → Expected:
`pixelWidth: 180`, `pixelHeight: 180`.
Run: `codesign --verify --strict --deep build/PhoneBox.app && echo ok` → Expected: `ok`. Uygulamayı başlatmayın.

- [ ] **Step 4: Commit**

```bash
git add scripts/make-touch-icon.swift scripts/bundle.sh
git commit -m "Draw a Home Screen icon for the dashboard"
```

---

### Task 5: Mac'te ve telefonda kontrol (kontrolcü, inline)

- [ ] **Step 1:** `make run`. Mac'in tarayıcı panelinde kişisel bağlantı; `resize_window` ile 734×372, 393×759,
  667×375, 375×647, 814×409. Her ölçüde:
  - ekran dışına taşan öğe yok;
  - kesilen kutucuk ya da başlık yok;
  - grafik çiziliyor;
  - halkaya ya da kutucuğa dokunmak grafiği değiştiriyor;
  - "⋯ → Kurulum rehberi" açılıyor;
  - konsolda JavaScript hatası yok.
- [ ] **Step 2:** PhoneBox'ı ~20 sn durdurup başlat: sayfa 1/2/5 sn arayla deniyor, kendiliğinden dönüyor.
- [ ] **Step 3:** Kullanıcıyla telefonda, kabloyla:
  - Ana ekran simgesini silip yeniden ekle; yeni simge görünüyor.
  - Simgeden aç: rehber, sonra "Başlat".
  - Yatayda ve dikeyde kesilen ya da taşan bir şey yok.
  - Bir kutucuğa dokununca grafik değişiyor.
  - Çalan şarkı kartı Mac'te bir şey çalarken görünüyor.
  - Kabloyu çıkar-tak.
- [ ] **Step 4:** `docs/manual-testing.md`'deki listeye arayüz maddelerini, "Sonuçlar"a Plan 4A'yı yaz.
- [ ] **Step 5: Commit**

```bash
git add docs/manual-testing.md
git commit -m "Record the Plan 4A checks"
```
