# PhoneBox Plan 4B — Komut arayüzü

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Bu plan için not:** Görev 1–5 Mac'te tek başına yürütülebilir. Uygulamayı başlatmaz, kullanıcının PhoneBox'ını
> durdurmaz, `defaults`'a ve eşleştirme anahtarına dokunmaz; canlı testleri (`PHONEBOX_LIVE=1`) yalnız kontrolcü
> çalıştırır. Görev 6'yı kontrolcü yapar (inline): sahte veriyle tarayıcıda, sonra iPhone Yansıtma üzerinden gerçek
> telefonda; Kilitle ve Ekranı kapat en sonda (kullanıcının izniyle), Uyut hiç denenmez.

**Goal:** Telefondan Mac'e komut göndermeyi tasarımdaki gibi (design §7, §8 "Kontrol şeridi", "Komut etkileşimleri")
sayfaya eklemek: medya düğmeleri, ses kaydırıcısı, sessiz, uygulama paneli (Kapat, Zorla kapat), "⋯" menüsünde
Kilitle / Ekranı kapat / Uyut, onaylar ve 2 saniyelik bildirim. Ayrıca önceki planlardan 4B'ye ertelenen düzeltmeler.

**Architecture:** Komutların imzası, numarası, cevap eşlemesi, zaman aşımı ve ses kaydırıcısının hız sınırı DOM'a
dokunmayan `commands.js`'tedir ve JavaScriptCore'da Swift'in `MessageAuth`'u ile karşılaştırılarak test edilir.
Ekran tarafı (şerit, panel, menü komutları, onay, bildirim) `controls.js`'tedir. Mac tarafında yalnız ses yazmanın
sonucu ayrılır: kontrol yoksa `unsupported`, değeri almadıysa `failed`.

**Tech Stack:** Swift 6 araç zinciri (Swift 5 dil modu), Swift Testing, CoreAudio, JavaScriptCore; sade JavaScript
(sınıf, `??`, Pointer Events), satır içi SVG, CSS (`:has`, geçişler).

## Global Constraints

- Sayfa sade HTML/CSS/JS: dış kütüphane ve derleme adımı yok; klasik `<script>`'ler `globalThis.PhoneBox` altına
  yazar; saf dosyalar yüklenirken DOM'a dokunmaz; ekrana giden her metin `textContent` ile (`innerHTML` yok).
- Protokol (design §5): `{"v":1,"type":"cmd","seq":n,"name":"…","args":"<JSON metni>","mac":"<HMAC(k,
  "cmd:"+nonce+":"+seq+":"+name+":"+args) hex>"}`; `seq` her bağlantıda kesin artar (sayfada hep artar); cevap
  `{"type":"ack","seq":n,"ok":true}` ya da `error`: `not-allowed`, `app-changed`, `unsupported`, `failed`.
- Komutlar yalnız kablodan (design §5 AccessPolicy). `access.commands` false iken şerit, panel düğmeleri ve menü
  komutları soluk; dokununca kırmızı "Komutlar sadece kabloyla çalışır". `audio` yoksa kaydırıcı ve sessiz soluk.
- Onay yalnız "Zorla kapat" ve "Uyut" için. "Uyut" metni: bağlantı kesilecek, Mac'i klavyesine ya da trackpad'ine
  dokunarak uyandır, dashboard kendiliğinden bağlanır.
- Bildirim 2 sn, üstte. Başarıda yeşil tik yalnız uygulama ve "⋯" komutlarında; medya, ses ve sessizde başarı
  bildirimi yok. Hata her zaman kırmızı ve sebebiyle; 5 sn içinde cevap gelmeyen komut "Olmadı".
- Ses kaydırıcısı: en çok saniyede 4 `volume` (250 ms), bırakınca son değer; bıraktıktan sonra 1,5 sn Mac'in eski
  değeri gösterilmez. Sunucunun sınırı saniyede 10 komut.
- Dokunma alanları en az 44×44 pt. Simgeler satır içi SVG. Hareketler Plan 4C'nin diliyle: panel alttan kayar
  (0,35 sn), onay ölçeklenerek gelir (0,3 sn), menü açılırken büyür (0,22 sn), bildirim yukarıdan kayar (0,35 sn);
  Hareketi Azalt'ta geçişler kapalı.
- Kod yorumları İngilizce. Commit mesajları İngilizce, emir kipinde; her `git commit`'e commit'i yapan ortamın
  istediği `Co-Authored-By: …` satırı ikinci bir `-m` olarak eklenir.
- Testler `make test FILTER="<Suite>|<Suite>"` ile (tırnaklar kalsın). İki uyarı denetimi de çıktı vermemeli:
  `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"` ve
  `make test 2>&1 | grep -E "warning:" | grep -v "ld: warning"`.

## Planlama sırasında doğrulananlar (2026-11-26)

Kodun tamamı `main`'in (ccce633) bir kopyasında görev görev yazıldı; her görevin sonunda derleme ve test uyarısızdı.
Sonda: `PhoneBoxCoreTests` 32 takımda 186 test, `PhoneBoxTests` 6 takımda 19 test. `make app` paketi kurdu.

- `PHONEBOX_LIVE=1 make test FILTER="SystemAudioLiveTests"`: ses seviyesi ve sessiz okunup aynen yazıldı (`.done`).
- Sahte veriyle (Plan 4C'nin deneme sayfası, komutlara `ack` veren sahte Mac ile), 734×372 ve 393×759:
  - Önceki / oynat-duraklat / sonraki ve sessiz doğru komutları gönderdi; oynat simgesi ve sessiz simgesi değişti.
  - Kaydırıcıda 320 ms'lik bir sürükleme 3 değer gönderdi (0 ms, 250 ms, bırakınca).
  - "⋯ → Kilitle" → yeşil "Mac kilitlendi"; "Uyut" önce onay penceresi; Vazgeç komut göndermedi.
  - Sahte Mac `unsupported` dönünce kırmızı "Bu çıkışta ses kontrolü yok"; `app-changed` dönünce "Uygulama değişmiş,
    liste yenilendi".
  - Uygulama satırı panel açtı; Kapat ve onaylı Zorla kapat doğru `quitApp`'i gönderdi; kapatılamayan satır yalnız
    "Bu süreç buradan kapatılamaz." dedi.
  - Wi-Fi'de bütün komutlar soluk, dokununca "Komutlar sadece kabloyla çalışır", hiçbir komut gitmedi.
  - RAM baskısı "critical": "▲ RAM kritik", grafik çerçevesi atıyor, başlık kırmızı, RAM grafiği kızarmıyor.
  - Şarkı yokken yatayda 8, dikeyde 6 uygulama satırı (boş satır ve boşluk yok); sıralama düğmesi ilk satıra binmiyor.
- Bulunup düzeltilenler: `setPointerCapture` aktif olmayan bir dokunuşta hata atabiliyordu (korumaya alındı);
  telefon yansıtmasında saatin altındaki tarih çok soluktu (12 px, daha açık renk).

## Dosya yapısı

```
Sources/PhoneBox/SystemAudio.swift, CommandRunner.swift   ses yazmanın sonucu: done / unsupported / failed
Resources/web/commands.js        imza, numara, cevap eşleme, 5 sn zaman aşımı, kaydırıcı hız sınırı (yeni, saf)
Resources/web/controls.js        şerit, uygulama paneli, menü komutları, onay, bildirim (yeni)
Resources/web/index.html, styles.css, i18n.js, view.js, app.js, metrics.js   (değişir)
Tests/PhoneBoxCoreTests/WebCommandTests.swift (yeni); CommandTests, WebConnectionTests, WebMotionTests (değişir)
Tests/PhoneBoxTests/CommandRunnerTests.swift (yeni); SystemAudioLiveTests (değişir)
docs/design/2026-11-25-phonebox-design.md  (Görev 5)
```

"Bul / Şununla değiştir" adımlarında "Bul" metni dosyada tam olarak bir kez geçer; Edit aracıyla birebir değiştirin.

---

### Task 1: Ses komutunda "kontrol yok" ile "olmadı" ayrımı

**Files:**
- Modify: `Sources/PhoneBox/SystemAudio.swift`, `Sources/PhoneBox/CommandRunner.swift`,
  `Tests/PhoneBoxTests/SystemAudioLiveTests.swift`, `Tests/PhoneBoxCoreTests/CommandTests.swift`
- Create: `Tests/PhoneBoxTests/CommandRunnerTests.swift`

**Interfaces:**
- Consumes: mevcut `SystemAudio.write`, `CommandRunner.run`, `CommandResult`.
- Produces: `SystemAudio.Write` (`.done`, `.unsupported`, `.failed`); `setVolume(_:) -> Write`, `setMuted(_:) -> Write`;
  `CommandRunner.result(of: SystemAudio.Write) -> CommandResult`.

- [ ] **Step 1: Testleri yaz**

`Tests/PhoneBoxTests/CommandRunnerTests.swift`:

```swift
import Testing
@testable import PhoneBox
import PhoneBoxCore

@MainActor
struct CommandRunnerTests {
    @Test func tellsAMissingAudioControlFromARefusedValue() {
        #expect(CommandRunner.result(of: .done) == .ok)
        #expect(CommandRunner.result(of: .unsupported) == .failed(.unsupported))
        #expect(CommandRunner.result(of: .failed) == .failed(.failed))
    }
}
```

`Tests/PhoneBoxCoreTests/CommandTests.swift` (iki yeni yanlış biçim):

Bul (1/2):

```swift
            ("quitApp", #"{"bundleId":"a","force":0}"#),                // 0 is not a boolean
            ("quitApp", #"{"bundleId":7,"force":false}"#),
```

Şununla değiştir:

```swift
            ("quitApp", #"{"bundleId":"a","force":0}"#),                // 0 is not a boolean
            ("quitApp", #"{"bundleId":"a","force":1.0}"#),              // nor is 1.0
            ("quitApp", #"{"bundleId":7,"force":false}"#),
```

Bul (2/2):

```swift
            ("volume", #"{"level":"0.5"}"#),
            ("mute", #"{"on":1}"#),
```

Şununla değiştir:

```swift
            ("volume", #"{"level":"0.5"}"#),
            ("volume", #"{"level":1e999}"#),                            // overflows to infinity
            ("mute", #"{"on":1}"#),
```

`Tests/PhoneBoxTests/SystemAudioLiveTests.swift`:

Bul (1/2):

```swift
        #expect((0...1).contains(volume))
        #expect(SystemAudio.setVolume(volume))
        let after = try #require(SystemAudio.volume())
```

Şununla değiştir:

```swift
        #expect((0...1).contains(volume))
        #expect(SystemAudio.setVolume(volume) == .done)
        let after = try #require(SystemAudio.volume())
```

Bul (2/2):

```swift
        let muted = try #require(SystemAudio.isMuted() as Bool?)
        #expect(SystemAudio.setMuted(muted))
        #expect(SystemAudio.isMuted() == muted)
```

Şununla değiştir:

```swift
        let muted = try #require(SystemAudio.isMuted() as Bool?)
        #expect(SystemAudio.setMuted(muted) == .done)
        #expect(SystemAudio.isMuted() == muted)
```

- [ ] **Step 2: Testlerin derlenmediğini gör**

Run: `make test FILTER="CommandRunnerTests"` → Expected: derleme hatası (`CommandRunner.result`, `SystemAudio.Write` yok).

- [ ] **Step 3: Sonucu ayır**

`Sources/PhoneBox/SystemAudio.swift`:

Bul (1/4):

```swift
    }

    private static func write<Value: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, _ value: Value) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = outputAddress(selector)
```

Şununla değiştir:

```swift
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
```

Bul (2/4):

```swift
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue
        else { return false }
        var value = value
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Value>.size), &value) == noErr
    }
```

Şununla değiştir:

```swift
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue
        else { return .unsupported }
        var value = value
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Value>.size), &value)
        return status == noErr ? .done : .failed
    }
```

Bul (3/4):

```swift
    }

    /// False when the output's volume cannot be set.
    static func setVolume(_ level: Double) -> Bool {
        guard level.isFinite else { return false }
        return write(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(min(1, max(0, level))))
```

Şununla değiştir:

```swift
    }

    static func setVolume(_ level: Double) -> Write {
        guard level.isFinite else { return .failed }
        return write(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(min(1, max(0, level))))
```

Bul (4/4):

```swift
    }

    /// False when the output cannot be muted.
    static func setMuted(_ on: Bool) -> Bool {
        write(kAudioDevicePropertyMute, UInt32(on ? 1 : 0))
```

Şununla değiştir:

```swift
    }

    static func setMuted(_ on: Bool) -> Write {
        write(kAudioDevicePropertyMute, UInt32(on ? 1 : 0))
```

`Sources/PhoneBox/CommandRunner.swift`:

Bul (1/2):

```swift
    }

    func run(_ command: Command, completion: @escaping @MainActor (CommandResult) -> Void) {
```

Şununla değiştir:

```swift
    }

    /// `unsupported` only when the output has no such control (the phone then greys the slider); a value the control
    /// did not take is a plain failure.
    static func result(of write: SystemAudio.Write) -> CommandResult {
        switch write {
        case .done: return .ok
        case .unsupported: return .failed(.unsupported)
        case .failed: return .failed(.failed)
        }
    }

    func run(_ command: Command, completion: @escaping @MainActor (CommandResult) -> Void) {
```

Bul (2/2):

```swift
        case let .volume(level):
            completion(SystemAudio.setVolume(level) ? .ok : .failed(.unsupported))
        case let .mute(on):
            completion(SystemAudio.setMuted(on) ? .ok : .failed(.unsupported))
        case .lock:
```

Şununla değiştir:

```swift
        case let .volume(level):
            completion(Self.result(of: SystemAudio.setVolume(level)))
        case let .mute(on):
            completion(Self.result(of: SystemAudio.setMuted(on)))
        case .lock:
```

- [ ] **Step 4: Testleri çalıştır**

Run: `make test FILTER="CommandRunnerTests|CommandTests"` → Expected: geçer.
Run: iki uyarı denetimi → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 19 tests in 6 suites passed` ve `Test run with 180 tests in 31 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/PhoneBox/SystemAudio.swift Sources/PhoneBox/CommandRunner.swift Tests/PhoneBoxTests/CommandRunnerTests.swift \
  Tests/PhoneBoxTests/SystemAudioLiveTests.swift Tests/PhoneBoxCoreTests/CommandTests.swift
git commit -m "Tell a missing audio control from a refused value"
```

---

### Task 2: Komutların imzası, numarası, cevabı ve kaydırıcının hız sınırı

**Files:**
- Create: `Resources/web/commands.js`, `Tests/PhoneBoxCoreTests/WebCommandTests.swift`
- Modify: `Tests/PhoneBoxCoreTests/WebConnectionTests.swift`

**Interfaces:**
- Consumes: `PBCrypto.hmacHex(keyBytes, message)` (`sha256.js`); `MessageAuth.hmacHex/commandMessage/isValid` (testte).
- Produces: `PhoneBox.Commands(link, {later})` — `link = { key, nonce() -> string|null, send(message) -> bool }`;
  `run(name, args, done) -> seq | 0` (`done(result)`: `"ok"` ya da hata adı ya da `"failed"`), `acked(ack)`.
  `PhoneBox.Throttle(interval, send, {now, later})` — `push(value)`, `flush()`. (Sayfa bunları Görev 3'te yükler.)

- [ ] **Step 1: Testleri yaz**

`Tests/PhoneBoxCoreTests/WebCommandTests.swift`:

```swift
import Foundation
import JavaScriptCore
import Testing
@testable import PhoneBoxCore

/// Runs the dashboard's `Resources/web/commands.js` in JavaScriptCore with a fake link and fake timers: the signature
/// must be exactly what `MessageAuth` checks, each answer must reach its command, and the volume slider must keep to
/// 4 values a second.
struct WebCommandTests {
    let context: JSContext

    init() throws {
        context = try #require(JSContext())
        context.exceptionHandler = { _, exception in Issue.record("JavaScript error: \(exception?.toString() ?? "?")") }
        for name in ["sha256.js", "commands.js"] {
            context.evaluateScript(try String(contentsOf: WebPageTests.webDirectory.appendingPathComponent(name), encoding: .utf8))
        }
        context.evaluateScript("""
            var now = 0, timers = [], sent = [], results = [], open = true, nonce = "6e6f6e6365";
            function later(fn, ms) { timers.push({ at: now + ms, fn: fn }); }
            function advance(ms) {
              now += ms;
              var due = timers.filter(function (t) { return t.at <= now; });
              timers = timers.filter(function (t) { return t.at > now; });
              due.forEach(function (t) { t.fn(); });
            }
            var key = new Uint8Array(32); for (var i = 0; i < 32; i += 1) key[i] = i;
            var commands = new PhoneBox.Commands({ key: key, nonce: function () { return open ? nonce : null; },
              send: function (m) { if (!open) return false; sent.push(m); return true; } }, { later: later });
            function done(label) { return function (result) { results.push(label + ":" + result); }; }
            """)
    }

    func string(_ code: String) -> String? { context.evaluateScript(code)?.toString() }

    @Test func signsCommandsExactlyAsTheMacChecks() throws {
        let message = string("""
            commands.run("volume", { level: 0.5 }, null);
            JSON.stringify(sent[0])
            """)
        let key = Data((0..<32).map { UInt8($0) })
        let args = #"{"level":0.5}"#
        let mac = MessageAuth.hmacHex(key: key, message: MessageAuth.commandMessage(nonce: "6e6f6e6365", seq: 1, name: "volume", args: args))
        #expect(message == #"{"v":1,"type":"cmd","seq":1,"name":"volume","args":"{\"level\":0.5}","mac":"\#(mac)"}"#)
        #expect(MessageAuth.isValid(signature: mac, key: key, message: "cmd:6e6f6e6365:1:volume:" + args))
    }

    @Test func matchesEachAnswerToItsCommand() {
        let result = string("""
            var a = commands.run("lock", {}, done("lock"));
            var b = commands.run("quitApp", { bundleId: "com.apple.Chess", force: false }, done("quit"));
            commands.acked({ seq: b, ok: false, error: "app-changed" });
            commands.acked({ seq: a, ok: true });
            commands.acked({ seq: a, ok: true });            // a second answer is ignored
            commands.acked({ seq: 99, ok: true });           // and so is one for no command
            [a, b, results.join(" ")].join(" ")
            """)
        #expect(result == "1 2 quit:app-changed lock:ok")
    }

    @Test func failsAtOnceWhenItCannotGoOutAndKeepsTheNumber() {
        let result = string("""
            open = false;
            var a = commands.run("sleep", {}, done("sleep"));
            open = true;
            var b = commands.run("lock", {}, done("lock"));
            [a, b, sent.length, results.join(" ")].join(" ")
            """)
        #expect(result == "0 1 1 sleep:failed")
    }

    @Test func failsWhenNoAnswerComesWithinFiveSeconds() {
        let result = string("""
            var a = commands.run("displaySleep", {}, done("display"));
            advance(4900);
            var early = results.length;
            advance(200);
            commands.acked({ seq: a, ok: true });            // too late
            [early, results.join(" ")].join(" ")
            """)
        #expect(result == "0 display:failed")
    }

    @Test func keepsTheVolumeToFourValuesASecondAndSendsTheLast() {
        let result = string("""
            var out = [];
            var throttle = new PhoneBox.Throttle(250, function (v) { out.push(now + "=" + v); },
                                                 { now: function () { return now; }, later: later });
            throttle.push(0.1);              // goes at once
            advance(100); throttle.push(0.2);
            advance(100); throttle.push(0.3);  // replaces 0.2, still waiting
            advance(50);                     // 250 ms after the first: 0.3 goes
            advance(50); throttle.push(0.4);   // waits until 500
            advance(20); throttle.flush();     // let go at 320: 0.4 goes now
            advance(200);                    // the timer at 500 sends nothing new
            throttle.flush();                // nothing left
            out.join(" ")
            """)
        #expect(result == "0=0.1 250=0.3 320=0.4")
    }
}
```

`Tests/PhoneBoxCoreTests/WebConnectionTests.swift` (Plan 4A'dan ertelenen: yenilenen soket yeniden doğrulanmadan
komut göndermez):

Bul:

```swift
    }

    @Test func reconnectsQuicklyWhenTheMacAsks() {
```

Şununla değiştir:

```swift
    }

    @Test func aReplacedSocketMustAuthenticateAgainBeforeCommands() {
        let result = string("""
            handshake(last(), { streaming: true, commands: true, cable: true, reason: "ok" });
            var before = connection.send({ type: "cmd" });
            connection.replace();
            var replaced = connection.send({ type: "cmd" });
            var s = last(); open(s);
            receive(s, { v: 1, type: "hello", nonce: "m" });
            var afterHello = connection.send({ type: "cmd" });
            receive(s, { v: 1, type: "ready", mode: "cable", host: "Mac", access: { streaming: true, commands: true, cable: true, reason: "ok" } });
            [before, replaced, afterHello, connection.send({ type: "cmd" }), connection.nonce, sockets.length].join(" ")
            """)
        #expect(result == "true false false true m 2")
    }

    @Test func reconnectsQuicklyWhenTheMacAsks() {
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `make test FILTER="WebCommandTests"` → Expected: başarısız (`commands.js` yok: "JavaScript error").

- [ ] **Step 3: commands.js**

`Resources/web/commands.js`:

```js
// The page's commands to the Mac (design §5, §7): each one numbered and signed with the pairing key, its answer
// (`ack`) matched back to it, and the volume slider held to 4 values a second. Pure: the connection, the clock and the
// timers come in from outside, so the Swift tests run it in JavaScriptCore with fakes.
(function (global) {
  "use strict";

  /// A command with no answer after this long counts as failed (the socket may have dropped on the way).
  const answerWithin = 5000;

  class Commands {
    /// `link`: `key` (the pairing key's bytes), `nonce()` (the authenticated socket's nonce, or null) and
    /// `send(message)` (true when it went out). `options.later(fn, ms)` replaces `setTimeout` in tests.
    constructor(link, options = {}) {
      this.link = link;
      this.later = options.later || ((fn, ms) => global.setTimeout(fn, ms));
      this.seq = 0;
      this.pending = new Map();
    }

    /// Sends `name` with `args` (an object). `done(result)` gets "ok", the ack's error ("not-allowed",
    /// "app-changed", "unsupported", "failed"), or "failed" when it could not go out or no answer came in 5 s.
    /// Returns the command's number, or 0 when it did not go out.
    run(name, args, done) {
      const nonce = this.link.nonce();
      const text = JSON.stringify(args || {});
      // Numbers only grow, also across reconnects: the Mac wants them strictly increasing on each socket.
      const seq = this.seq + 1;
      const message = {
        v: 1, type: "cmd", seq, name, args: text,
        mac: global.PBCrypto.hmacHex(this.link.key, `cmd:${nonce}:${seq}:${name}:${text}`),
      };
      if (nonce === null || !this.link.send(message)) {
        if (done) done("failed");
        return 0;
      }
      this.seq = seq;
      this.pending.set(seq, done || null);
      this.later(() => this.settle(seq, "failed"), answerWithin);
      return seq;
    }

    /// The Mac's `ack`; one for a command that already timed out is ignored.
    acked(ack) {
      this.settle(ack.seq, ack.ok ? "ok" : String(ack.error || "failed"));
    }

    settle(seq, result) {
      if (!this.pending.has(seq)) return;
      const done = this.pending.get(seq);
      this.pending.delete(seq);
      if (done) done(result);
    }
  }

  /// At most one value every `interval` ms while a control is dragged, and the last value always goes out: the volume
  /// slider sends at most 4 a second, then its final value when let go (design §7).
  class Throttle {
    constructor(interval, send, options = {}) {
      this.interval = interval;
      this.send = send;
      this.now = options.now || (() => Date.now());
      this.later = options.later || ((fn, ms) => global.setTimeout(fn, ms));
      this.sentAt = -Infinity;
      this.waiting = false;
      this.value = undefined;
      this.sent = undefined;
    }

    push(value) {
      this.value = value;
      const wait = this.sentAt + this.interval - this.now();
      if (wait <= 0) {
        this.fire();
      } else if (!this.waiting) {
        this.waiting = true;
        this.later(() => {
          this.waiting = false;
          this.fire();
        }, wait);
      }
    }

    /// Let go: the last value goes out now, unless it already has.
    flush() {
      this.fire();
    }

    fire() {
      if (this.value === this.sent) return;
      this.sentAt = this.now();
      this.sent = this.value;
      this.send(this.value);
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.Commands = Commands;
  global.PhoneBox.Throttle = Throttle;
})(typeof window !== "undefined" ? window : globalThis);
```

- [ ] **Step 4: Testleri çalıştır**

Run: `make test FILTER="WebCommandTests|WebConnectionTests"` → Expected: 12 test geçer.
Run: iki uyarı denetimi → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 19 tests in 6 suites passed` ve `Test run with 186 tests in 32 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Resources/web/commands.js Tests/PhoneBoxCoreTests/WebCommandTests.swift Tests/PhoneBoxCoreTests/WebConnectionTests.swift
git commit -m "Sign, number and answer the page's commands and keep the volume to 4 values a second"
```

---

### Task 3: Kontrol şeridi, menü komutları, Uyut onayı ve bildirim

**Files:**
- Create: `Resources/web/controls.js`
- Modify: `Resources/web/index.html`, `Resources/web/view.js`, `Resources/web/app.js`, `Resources/web/i18n.js`,
  `Resources/web/styles.css`

**Interfaces:**
- Consumes: Görev 2'nin `Commands`, `Throttle`; `PhoneBox.ui.closeMenu()`; `connection.ready/nonce/send/key`,
  `handlers.onAck`.
- Produces: `PhoneBox.Controls(t, format, commands)` — `setAccess(access)`, `setSnapshot(snapshot)`, `allowed()`,
  `render()`, `ready(name)`, `run(name, args, doneText)`, `toast(text, ok)`, `confirm(title, text, action, then)`;
  sayfada `#media-previous`, `#media-play`, `#media-next`, `#volume`, `#mute`, `#confirm…`, `#toast…`, menüde
  `[data-command]`; `PhoneBox.controls`. Görev 4 `openApp`'i ekler.

- [ ] **Step 1: controls.js**

`Resources/web/controls.js`:

```js
// The command side of the page (design §7, §8 "Komut etkileşimleri"): the control strip (previous, play/pause, next,
// the volume slider, mute), the "⋯" menu's Mac commands, the confirmation that Sleep asks for, and the 2-second
// toast. Commands go only from the cable; elsewhere the controls are dim and a tap says why. Checked by eye.
(function (global) {
  "use strict";

  const $ = (id) => global.document.getElementById(id);
  /// After the slider is let go, the Mac's own volume is shown again only after this long, so the knob does not jump
  /// back to the old value before the Mac has taken the new one.
  const settleAfterDrag = 1500;

  class Controls {
    constructor(t, format, commands) {
      this.t = t;
      this.format = format;
      this.commands = commands;
      this.access = null;
      this.audio = null;
      this.media = null;
      this.dragging = false;
      this.quietUntil = 0;
      this.toastTimer = null;
      this.onConfirm = null;
      this.throttle = new global.PhoneBox.Throttle(250, (level) => this.run("volume", { level }, null));
      this.wire();
      this.render();
    }

    setAccess(access) {
      this.access = access;
      this.render();
    }

    /// The Mac's audio and what is playing, from each snapshot.
    setSnapshot(snapshot) {
      this.audio = snapshot.audio || null;
      this.media = snapshot.media || null;
      this.render();
    }

    /// Commands may go out: the Mac allows them (cable) and the socket is authenticated.
    allowed() {
      return Boolean(this.access && this.access.commands) && this.commands.link.nonce() !== null;
    }

    render() {
      const allowed = this.allowed();
      for (const id of ["media-previous", "media-play", "media-next"]) $(id).classList.toggle("off", !allowed);
      $("media-play").classList.toggle("playing", Boolean(this.media && this.media.playing));
      const audio = allowed && Boolean(this.audio);
      $("volume").classList.toggle("off", !audio);
      $("mute").classList.toggle("off", !audio);
      $("mute").classList.toggle("muted", Boolean(this.audio && this.audio.muted));
      if (this.audio && !this.dragging && Date.now() >= this.quietUntil) this.paintVolume(this.audio.volume);
      for (const item of global.document.querySelectorAll("#menu [data-command]")) item.classList.toggle("off", !allowed);
    }

    paintVolume(level) {
      const slider = $("volume");
      slider.style.setProperty("--volume", `${(Math.max(0, Math.min(1, level)) * 100).toFixed(1)}%`);
      slider.setAttribute("aria-valuenow", String(Math.round(level * 100)));
    }

    /// True when `name` may go out now; otherwise a red toast says why.
    ready(name) {
      if (!this.allowed()) {
        this.toast(this.access && this.access.commands ? this.t.errorFailed : this.t.errorNotAllowed, false);
        return false;
      }
      if ((name === "volume" || name === "mute") && !this.audio) {
        this.toast(this.t.errorAudio, false);
        return false;
      }
      return true;
    }

    /// Sends a command. A failure always shows a red toast; success shows `done` (a text) in green, or nothing when
    /// the screen already shows the change (media, volume, mute).
    run(name, args, done) {
      if (!this.ready(name)) return;
      this.commands.run(name, args, (result) => {
        if (result === "ok") {
          if (done) this.toast(done, true);
          return;
        }
        this.toast(this.failure(name, result), false);
      });
    }

    failure(name, result) {
      const t = this.t;
      switch (result) {
        case "not-allowed": return t.errorNotAllowed;
        case "app-changed": return t.errorAppChanged;
        case "unsupported": return name === "volume" || name === "mute" ? t.errorAudio : t.errorUnsupported;
        default: return t.errorFailed;
      }
    }

    /// A message at the top for 2 seconds: a green tick for success, red for a failure.
    toast(text, ok) {
      const toast = $("toast");
      $("toast-icon").textContent = ok ? "✓" : "!";
      $("toast-text").textContent = text;
      toast.classList.toggle("ok", ok);
      toast.classList.toggle("bad", !ok);
      toast.classList.add("show");
      global.clearTimeout(this.toastTimer);
      this.toastTimer = global.setTimeout(() => toast.classList.remove("show"), 2000);
    }

    /// A question with a red action button; `then` runs only on that button.
    confirm(title, text, action, then) {
      $("confirm-title").textContent = title;
      $("confirm-text").textContent = text;
      $("confirm-ok").textContent = action;
      this.onConfirm = then;
      $("confirm").classList.add("show");
    }

    closeConfirm(accepted) {
      $("confirm").classList.remove("show");
      const then = this.onConfirm;
      this.onConfirm = null;
      if (accepted && then) then();
    }

    wire() {
      const t = this.t;
      for (const button of global.document.querySelectorAll("[data-media]")) {
        button.addEventListener("click", () => this.run("media", { action: button.dataset.media }, null));
      }
      $("mute").addEventListener("click", () => {
        if (!this.ready("mute")) return;
        const on = !this.audio.muted;
        // Shown at once; the next snapshot confirms it.
        this.audio = Object.assign({}, this.audio, { muted: on });
        this.render();
        this.run("mute", { on }, null);
      });

      const slider = $("volume");
      const level = (event) => {
        const box = slider.getBoundingClientRect();
        return Math.max(0, Math.min(1, (event.clientX - box.left) / box.width));
      };
      const slide = (value) => {
        this.paintVolume(value);
        this.throttle.push(Math.round(value * 100) / 100);
      };
      slider.addEventListener("pointerdown", (event) => {
        if (!this.ready("volume")) return;
        this.dragging = true;
        slider.classList.add("dragging");
        // Keeps the drag on the slider when the finger slides off it; refused for a pointer that is not down.
        try {
          slider.setPointerCapture(event.pointerId);
        } catch (error) {}
        slide(level(event));
      });
      slider.addEventListener("pointermove", (event) => {
        if (this.dragging) slide(level(event));
      });
      const end = () => {
        if (!this.dragging) return;
        this.dragging = false;
        slider.classList.remove("dragging");
        this.throttle.flush();
        this.quietUntil = Date.now() + settleAfterDrag;
      };
      slider.addEventListener("pointerup", end);
      slider.addEventListener("pointercancel", end);

      const done = { lock: t.doneLock, displaySleep: t.doneDisplay, sleep: t.doneSleep };
      for (const item of global.document.querySelectorAll("#menu [data-command]")) {
        item.addEventListener("click", () => {
          global.PhoneBox.ui.closeMenu();
          const name = item.dataset.command;
          if (!this.ready(name)) return;
          if (name === "sleep") {
            this.confirm(t.confirmSleepTitle, t.confirmSleepText, t.sleep, () => this.run(name, {}, done[name]));
          } else {
            this.run(name, {}, done[name]);
          }
        });
      }
      $("confirm-ok").addEventListener("click", () => this.closeConfirm(true));
      $("confirm-cancel").addEventListener("click", () => this.closeConfirm(false));
      $("confirm").addEventListener("click", (event) => {
        if (event.target === $("confirm")) this.closeConfirm(false);
      });
    }
  }

  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.Controls = Controls;
})(typeof window !== "undefined" ? window : globalThis);
```

- [ ] **Step 2: Sayfa, metinler ve bağlama**

`Resources/web/index.html`:

Bul (1/3):

```html
  <section id="strip" class="strip card">
    <span class="strip-space"></span>
    <button id="more" class="strip-button" type="button" aria-haspopup="menu">⋯</button>
```

Şununla değiştir:

```html
  <section id="strip" class="strip card">
    <button id="media-previous" class="strip-button" type="button" data-media="previous" data-label="previous">
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6h2v12H6zM9.5 12 18 6v12z"/></svg>
    </button>
    <button id="media-play" class="strip-button" type="button" data-media="playPause" data-label="playPause">
      <svg class="icon-play" viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5v14l11-7z"/></svg>
      <svg class="icon-pause" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 5h4v14H6zM14 5h4v14h-4z"/></svg>
    </button>
    <button id="media-next" class="strip-button" type="button" data-media="next" data-label="next">
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M16 6h2v12h-2zM6 18l8.5-6L6 6z"/></svg>
    </button>
    <div id="volume" class="volume" role="slider" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0" data-label="volume">
      <span class="volume-track"><span class="volume-fill"></span><span class="volume-thumb"></span></span>
    </div>
    <button id="mute" class="strip-button" type="button" data-label="mute">
      <svg class="icon-speaker" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9v6h4l5 4V5L8 9z"/><path d="M16 8.5a4.5 4.5 0 0 1 0 7" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
      <svg class="icon-muted" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9v6h4l5 4V5L8 9z"/><path d="M16 9.5l5 5m0-5-5 5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
    </button>
    <button id="more" class="strip-button" type="button" aria-haspopup="menu">⋯</button>
```

Bul (2/3):

```html
  <div id="menu-host" class="menu-host"></div>
  <button id="menu-guide" type="button" role="menuitem" data-text="guideItem"></button>
</div>

<div id="guide" class="overlay guide" hidden>
```

Şununla değiştir:

```html
  <div id="menu-host" class="menu-host"></div>
  <button type="button" role="menuitem" data-command="lock" data-text="lock"></button>
  <button type="button" role="menuitem" data-command="displaySleep" data-text="displaySleep"></button>
  <button type="button" role="menuitem" data-command="sleep" data-text="sleep"></button>
  <div class="menu-gap"></div>
  <button id="menu-guide" type="button" role="menuitem" data-text="guideItem"></button>
</div>

<div id="confirm" class="confirm">
  <div class="confirm-card" role="alertdialog" aria-modal="true" aria-labelledby="confirm-title">
    <h2 id="confirm-title"></h2>
    <p id="confirm-text"></p>
    <div class="confirm-buttons">
      <button id="confirm-cancel" type="button" data-text="cancel"></button>
      <button id="confirm-ok" class="danger" type="button"></button>
    </div>
  </div>
</div>

<div id="toast" class="toast" role="status" aria-live="polite"><span id="toast-icon" aria-hidden="true"></span><span id="toast-text"></span></div>

<div id="guide" class="overlay guide" hidden>
```

Bul (3/3):

```html
<script src="connection.js"></script>
<script src="view.js"></script>
<script src="ui.js"></script>
<script src="app.js"></script>
```

Şununla değiştir:

```html
<script src="connection.js"></script>
<script src="commands.js"></script>
<script src="view.js"></script>
<script src="ui.js"></script>
<script src="controls.js"></script>
<script src="app.js"></script>
```

`Resources/web/view.js`:

Bul:

```js
      $("more").setAttribute("aria-label", this.t.more);
    }
```

Şununla değiştir:

```js
      $("more").setAttribute("aria-label", this.t.more);
      for (const element of global.document.querySelectorAll("[data-label]")) {
        element.setAttribute("aria-label", this.t[element.dataset.label]);
      }
    }
```

`Resources/web/app.js`:

Bul (1/4):

```js
  }

  const connection = new PB.Connection(key, {
```

Şununla değiştir:

```js
  }

  // Commands go through the authenticated socket; `connection` is set below, before anything can be tapped.
  const commands = new PB.Commands({
    key,
    nonce: () => (connection.ready ? connection.nonce : null),
    send: (message) => connection.send(message),
  });
  const controls = new PB.Controls(t, format, commands);

  const connection = new PB.Connection(key, {
```

Bul (2/4):

```js
    },
    onAccess: (access) => view.setAccess(access),
    onSnapshot: (snapshot) => {
```

Şununla değiştir:

```js
    },
    onAccess: (access) => {
      view.setAccess(access);
      controls.setAccess(access);
    },
    onSnapshot: (snapshot) => {
```

Bul (3/4):

```js
      view.renderGraph(history);
    },
  });
```

Şununla değiştir:

```js
      view.renderGraph(history);
      controls.setSnapshot(snapshot);
    },
    onAck: (ack) => commands.acked(ack),
  });
```

Bul (4/4):

```js
  PB.connection = connection;
})(window);
```

Şununla değiştir:

```js
  PB.connection = connection;
  PB.controls = controls;
})(window);
```

`Resources/web/i18n.js`:

Bul (1/2):

```js
      close: "Kapat",
    },
```

Şununla değiştir:

```js
      close: "Kapat",
      previous: "Önceki",
      playPause: "Oynat / duraklat",
      next: "Sonraki",
      volume: "Ses",
      mute: "Sessiz",
      lock: "Kilitle",
      displaySleep: "Ekranı kapat",
      sleep: "Uyut",
      cancel: "Vazgeç",
      confirmSleepTitle: "Mac uyutulsun mu?",
      confirmSleepText: "Bağlantı kesilecek. Mac'i klavyesine ya da trackpad'ine dokunarak uyandır; dashboard kendiliğinden bağlanır.",
      doneLock: "Mac kilitlendi",
      doneDisplay: "Ekran kapatıldı",
      doneSleep: "Mac uyuyor",
      errorNotAllowed: "Komutlar sadece kabloyla çalışır",
      errorAppChanged: "Uygulama değişmiş, liste yenilendi",
      errorAudio: "Bu çıkışta ses kontrolü yok",
      errorUnsupported: "Bu komut desteklenmiyor",
      errorFailed: "Olmadı",
    },
```

Bul (2/2):

```js
      close: "Close",
    },
```

Şununla değiştir:

```js
      close: "Close",
      previous: "Previous",
      playPause: "Play / pause",
      next: "Next",
      volume: "Volume",
      mute: "Mute",
      lock: "Lock",
      displaySleep: "Turn off display",
      sleep: "Sleep",
      cancel: "Cancel",
      confirmSleepTitle: "Put the Mac to sleep?",
      confirmSleepText: "The connection will drop. Wake the Mac by touching its keyboard or trackpad; the dashboard reconnects by itself.",
      doneLock: "Mac locked",
      doneDisplay: "Display off",
      doneSleep: "Mac is going to sleep",
      errorNotAllowed: "Commands work only over the cable",
      errorAppChanged: "The app changed; the list was refreshed",
      errorAudio: "This output has no volume control",
      errorUnsupported: "This command is not supported",
      errorFailed: "That didn't work",
    },
```

- [ ] **Step 3: Stil**

`Resources/web/styles.css`:

Bul (1/3):

```css
/* ---- Strip ---- */
.strip { display: flex; align-items: center; gap: 4px; height: 52px; padding: 0 8px; }
.strip-space { flex: 1; }
.strip-button { width: 44px; height: 44px; border-radius: 12px; display: grid; place-items: center; font-size: 20px; flex: none; }
.strip-button:active { background: var(--raised); }

/* ---- Menu ---- */
```

Şununla değiştir:

```css
/* ---- Strip ---- */
.strip { display: flex; align-items: center; gap: 2px; height: 52px; padding: 0 6px; }
.strip-button {
  width: 44px;
  height: 44px;
  border-radius: 12px;
  display: grid;
  place-items: center;
  font-size: 20px;
  flex: none;
  color: var(--text);
  transition: opacity 0.3s, background-color 0.2s, transform 0.15s;
}
.strip-button svg { width: 22px; height: 22px; fill: currentColor; }
.strip-button:active { background: var(--raised); transform: scale(0.92); }
#media-play .icon-pause, #media-play.playing .icon-play { display: none; }
#media-play.playing .icon-pause { display: block; }
#mute .icon-muted, #mute.muted .icon-speaker { display: none; }
#mute.muted .icon-muted { display: block; }
/* The volume: a track the finger slides along; the Mac's level glides in when it changes. */
.volume { flex: 1; min-width: 60px; height: 44px; display: flex; align-items: center; padding: 0 12px; touch-action: none; cursor: pointer; transition: opacity 0.3s; }
.volume-track { position: relative; flex: 1; height: 6px; border-radius: 3px; background: rgba(109, 138, 163, 0.35); }
.volume-fill {
  position: absolute;
  left: 0;
  top: 0;
  bottom: 0;
  width: var(--volume, 0%);
  border-radius: 3px;
  background: linear-gradient(90deg, var(--ram), var(--cpu));
  transition: width 0.4s cubic-bezier(0.2, 0.8, 0.2, 1);
}
.volume-thumb {
  position: absolute;
  top: 50%;
  left: var(--volume, 0%);
  width: 18px;
  height: 18px;
  margin: -9px 0 0 -9px;
  border-radius: 50%;
  background: var(--text);
  box-shadow: 0 0 10px rgba(0, 194, 255, 0.6);
  transition: left 0.4s cubic-bezier(0.2, 0.8, 0.2, 1), transform 0.15s;
}
.volume.dragging .volume-fill, .volume.dragging .volume-thumb { transition: none; }
.volume.dragging .volume-thumb { transform: scale(1.2); }
/* Commands that cannot go now (Wi-Fi, no volume control): dim, and a tap says why. */
.off { opacity: 0.35; }

/* ---- Menu ---- */
```

Bul (2/3):

```css
.menu-backdrop { position: fixed; inset: 0; }
.menu-host { padding: 10px 14px 8px; font-size: 12px; color: var(--muted); border-bottom: 1px solid #3a3a3c; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.menu { position: fixed; min-width: 220px; background: var(--raised); border-radius: 14px; overflow: hidden; box-shadow: 0 8px 30px rgba(0, 0, 0, 0.6); }
.menu button { display: flex; align-items: center; width: 100%; height: 44px; padding: 0 14px; border-bottom: 1px solid #3a3a3c; }
.menu button:last-child { border-bottom: 0; }
.menu button:active { background: #3a3a3c; }

/* ---- Alarm: a red light around the screen's edge, above the page and below the cards; it never takes a tap. */
```

Şununla değiştir:

```css
.menu-backdrop { position: fixed; inset: 0; }
.menu-host { padding: 10px 14px 8px; font-size: 12px; color: var(--muted); border-bottom: 1px solid rgba(109, 138, 163, 0.2); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.menu {
  position: fixed;
  min-width: 220px;
  background: var(--raised);
  border-radius: 14px;
  overflow: hidden;
  box-shadow: 0 8px 30px rgba(0, 0, 0, 0.6);
  transform-origin: bottom right;
  animation: pop-in 0.22s cubic-bezier(0.2, 0.8, 0.2, 1);
}
@keyframes pop-in { from { opacity: 0; transform: scale(0.9); } }
.menu button { display: flex; align-items: center; width: 100%; height: 44px; padding: 0 14px; border-bottom: 1px solid rgba(109, 138, 163, 0.2); }
.menu button:last-child { border-bottom: 0; }
.menu button:active { background: rgba(109, 138, 163, 0.25); }
.menu-gap { height: 6px; background: rgba(0, 0, 0, 0.3); }

/* ---- Confirmation (Sleep, Force quit) ---- */
.confirm {
  position: fixed;
  inset: 0;
  display: grid;
  place-items: center;
  padding: 24px;
  background: rgba(1, 6, 13, 0.7);
  opacity: 0;
  pointer-events: none;
  transition: opacity 0.25s;
}
.confirm.show { opacity: 1; pointer-events: auto; }
.confirm-card {
  width: min(360px, 100%);
  padding: 18px 18px 16px;
  border-radius: 18px;
  background: var(--raised);
  text-align: center;
  box-shadow: 0 12px 40px rgba(0, 0, 0, 0.6);
  transform: scale(0.92);
  transition: transform 0.3s cubic-bezier(0.2, 0.8, 0.2, 1);
}
.confirm.show .confirm-card { transform: none; }
.confirm-card p { color: #c9d6e2; font-size: 13.5px; line-height: 1.4; margin-bottom: 14px; }
.confirm-buttons { display: flex; gap: 10px; }
.confirm-buttons button { flex: 1; height: 44px; border-radius: 12px; background: rgba(109, 138, 163, 0.2); font-weight: 600; text-align: center; }
.confirm-buttons .danger { background: #ff3b30; color: #fff; }

/* ---- Toast: 2 s at the top after a command ---- */
.toast {
  position: fixed;
  left: 50%;
  top: calc(env(safe-area-inset-top) + 10px);
  display: flex;
  align-items: center;
  gap: 8px;
  max-width: min(90vw, 440px);
  padding: 10px 16px;
  border-radius: 14px;
  background: rgba(20, 38, 58, 0.97);
  box-shadow: 0 8px 30px rgba(0, 0, 0, 0.5);
  font-size: 14px;
  font-weight: 600;
  opacity: 0;
  transform: translate(-50%, -150%);
  transition: transform 0.35s cubic-bezier(0.2, 0.8, 0.2, 1), opacity 0.35s;
  pointer-events: none;
}
.toast.show { opacity: 1; transform: translate(-50%, 0); }
.toast.ok #toast-icon { color: var(--ok); }
.toast.bad { background: rgba(140, 24, 30, 0.97); }

/* ---- Alarm: a red light around the screen's edge, above the page and below the cards; it never takes a tap. */
```

Bul (3/3):

```css
  .clock-colon { animation: none; }
}
```

Şununla değiştir:

```css
  .clock-colon { animation: none; }
  .menu { animation: none; }
  .confirm, .confirm-card, .toast, .volume-fill, .volume-thumb, .strip-button { transition: none; }
}
```

- [ ] **Step 4: Derle ve test et**

Run: iki uyarı denetimi → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 19 tests in 6 suites passed` ve `Test run with 186 tests in 32 suites passed`
(`bothLanguagesHaveTheSameTexts` yeni metinleri iki dilde arar).
Run: `grep -n "innerHTML\|insertAdjacentHTML\|outerHTML" Resources/web/*.js` → Expected: çıktı yok.
Run: `make app 2>&1 | tail -1` → Expected: `Built …/build/PhoneBox.app`. Uygulamayı başlatmayın.

- [ ] **Step 5: Commit**

```bash
git add Resources/web/controls.js Resources/web/index.html Resources/web/view.js Resources/web/app.js \
  Resources/web/i18n.js Resources/web/styles.css
git commit -m "Add the control strip, the menu's Mac commands, the Sleep confirmation and the toast"
```

---

### Task 4: Uygulama paneli

**Files:**
- Modify: `Resources/web/index.html`, `Resources/web/view.js`, `Resources/web/controls.js`, `Resources/web/app.js`,
  `Resources/web/i18n.js`, `Resources/web/styles.css`

**Interfaces:**
- Consumes: Görev 3'ün `Controls` (`ready`, `run`, `confirm`, `render`, `allowed`); `View.renderApps` (satırlar
  `bundleId || name` + `#pid` kimliğiyle tutulur).
- Produces: satırlarda `data-id`; `View.appAt(id)`; `Controls.openApp(app)`, `closeApp()`, `quit(force)`; sayfada
  `#sheet`, `#sheet-name`, `#sheet-figures`, `#sheet-note`, `#sheet-quit`, `#sheet-force`, `#sheet-cancel`.

- [ ] **Step 1: Sayfa ve görünüm**

`Resources/web/index.html`:

Bul:

```html
</div>

<div id="confirm" class="confirm">
```

Şununla değiştir:

```html
</div>

<div id="sheet" class="sheet">
  <div class="sheet-card" role="dialog" aria-modal="true" aria-labelledby="sheet-name">
    <div class="sheet-head"><strong id="sheet-name"></strong><span id="sheet-figures"></span></div>
    <p id="sheet-note" class="sheet-note" data-text="notQuittable"></p>
    <button id="sheet-quit" class="sheet-button" type="button" data-text="quit"></button>
    <button id="sheet-force" class="sheet-button danger" type="button" data-text="forceQuit"></button>
    <button id="sheet-cancel" class="sheet-button" type="button" data-text="cancel"></button>
  </div>
</div>

<div id="confirm" class="confirm">
```

`Resources/web/view.js`:

Bul (1/5):

```js
      this.rows = new Map();
      this.white = heat.rgb("#eaf6ff");
```

Şununla değiştir:

```js
      this.rows = new Map();
      /// The app shown in each row, by the row's `data-id`, for a tap.
      this.rowApps = new Map();
      this.white = heat.rgb("#eaf6ff");
```

Bul (2/5):

```js
    }

    toggleSort() {
```

Şununla değiştir:

```js
    }

    /// The app in the row with this `data-id`, as of the last list.
    appAt(id) {
      return this.rowApps.get(id) || null;
    }

    toggleSort() {
```

Bul (3/5):

```js
        this.rows.clear();
        return;
```

Şununla değiştir:

```js
        this.rows.clear();
        this.rowApps.clear();
        return;
```

Bul (4/5):

```js
      const rows = new Map();
      const items = apps.map((app) => {
```

Şununla değiştir:

```js
      const rows = new Map();
      this.rowApps.clear();
      const items = apps.map((app) => {
```

Bul (5/5):

```js
        item.children[2].style.width = `${Math.max(2, ((app[key] || 0) / top) * 100).toFixed(1)}%`;
        rows.set(id, item);
```

Şununla değiştir:

```js
        item.children[2].style.width = `${Math.max(2, ((app[key] || 0) / top) * 100).toFixed(1)}%`;
        item.dataset.id = id;
        this.rowApps.set(id, app);
        rows.set(id, item);
```

- [ ] **Step 2: Panel ve dokunma**

`Resources/web/controls.js`:

Bul (1/4):

```js
// The command side of the page (design §7, §8 "Komut etkileşimleri"): the control strip (previous, play/pause, next,
// the volume slider, mute), the "⋯" menu's Mac commands, the confirmation that Sleep asks for, and the 2-second
// toast. Commands go only from the cable; elsewhere the controls are dim and a tap says why. Checked by eye.
(function (global) {
```

Şununla değiştir:

```js
// The command side of the page (design §7, §8 "Komut etkileşimleri"): the control strip (previous, play/pause, next,
// the volume slider, mute), the app panel (Quit, Force quit), the "⋯" menu's Mac commands, the confirmation that
// Sleep and Force quit ask for, and the 2-second toast. Commands go only from the cable; elsewhere the controls are
// dim and a tap says why. Checked by eye.
(function (global) {
```

Bul (2/4):

```js
      this.onConfirm = null;
      this.throttle = new global.PhoneBox.Throttle(250, (level) => this.run("volume", { level }, null));
```

Şununla değiştir:

```js
      this.onConfirm = null;
      /// The app whose panel is open.
      this.app = null;
      this.throttle = new global.PhoneBox.Throttle(250, (level) => this.run("volume", { level }, null));
```

Bul (3/4):

```js
      for (const item of global.document.querySelectorAll("#menu [data-command]")) item.classList.toggle("off", !allowed);
    }
```

Şununla değiştir:

```js
      for (const item of global.document.querySelectorAll("#menu [data-command]")) item.classList.toggle("off", !allowed);
      $("sheet-quit").classList.toggle("off", !allowed);
      $("sheet-force").classList.toggle("off", !allowed);
    }

    /// A tap on an app row: its panel with Quit, Force quit and Cancel. A row the phone cannot quit (grey) only says
    /// so: `quitApp` needs a regular app with a bundle identifier (design §7).
    openApp(app) {
      if (!app) return;
      this.app = app;
      const quittable = Boolean(app.quittable && app.bundleId);
      $("sheet-name").textContent = app.name;
      $("sheet-figures").textContent = `${this.format.percent(app.cpu)} · ${this.format.memory(app.mem)}`;
      $("sheet-note").hidden = quittable;
      $("sheet-quit").hidden = !quittable;
      $("sheet-force").hidden = !quittable;
      this.render();
      $("sheet").classList.add("show");
    }

    closeApp() {
      $("sheet").classList.remove("show");
    }

    /// Quit at once; Force quit only after a confirmation (unsaved work is lost).
    quit(force) {
      const app = this.app;
      const t = this.t;
      if (!app || !this.ready("quitApp")) return;
      this.closeApp();
      const go = () => this.run("quitApp", { bundleId: app.bundleId, force }, force ? t.doneForce(app.name) : t.doneQuit(app.name));
      if (force) this.confirm(t.confirmForceTitle(app.name), t.confirmForceText, t.forceQuit, go);
      else go();
    }
```

Bul (4/4):

```js
      }
      $("confirm-ok").addEventListener("click", () => this.closeConfirm(true));
```

Şununla değiştir:

```js
      }
      $("sheet-quit").addEventListener("click", () => this.quit(false));
      $("sheet-force").addEventListener("click", () => this.quit(true));
      $("sheet-cancel").addEventListener("click", () => this.closeApp());
      $("sheet").addEventListener("click", (event) => {
        if (event.target === $("sheet")) this.closeApp();
      });
      $("confirm-ok").addEventListener("click", () => this.closeConfirm(true));
```

`Resources/web/app.js`:

Bul:

```js
  });
  connection.start();
```

Şununla değiştir:

```js
  });
  $("app-list").addEventListener("click", (event) => {
    const row = event.target.closest("li");
    if (row) controls.openApp(view.appAt(row.dataset.id));
  });
  connection.start();
```

`Resources/web/i18n.js`:

Bul (1/2):

```js
      doneSleep: "Mac uyuyor",
      errorNotAllowed: "Komutlar sadece kabloyla çalışır",
```

Şununla değiştir:

```js
      doneSleep: "Mac uyuyor",
      quit: "Kapat",
      forceQuit: "Zorla kapat",
      notQuittable: "Bu süreç buradan kapatılamaz.",
      confirmForceTitle: (name) => `${name} zorla kapatılsın mı?`,
      confirmForceText: "Kaydedilmemiş değişiklikler kaybolur.",
      doneQuit: (name) => `${name} kapatıldı`,
      doneForce: (name) => `${name} zorla kapatıldı`,
      errorNotAllowed: "Komutlar sadece kabloyla çalışır",
```

Bul (2/2):

```js
      doneSleep: "Mac is going to sleep",
      errorNotAllowed: "Commands work only over the cable",
```

Şununla değiştir:

```js
      doneSleep: "Mac is going to sleep",
      quit: "Quit",
      forceQuit: "Force quit",
      notQuittable: "This process can't be quit from here.",
      confirmForceTitle: (name) => `Force quit ${name}?`,
      confirmForceText: "Unsaved changes will be lost.",
      doneQuit: (name) => `${name} quit`,
      doneForce: (name) => `${name} was force quit`,
      errorNotAllowed: "Commands work only over the cable",
```

`Resources/web/styles.css`:

Bul (1/3):

```css
.app-list li:last-child { border-bottom: 0; }
.app-list li.enter { animation: row-in 0.5s ease-out; }
```

Şununla değiştir:

```css
.app-list li:last-child { border-bottom: 0; }
.app-list li { cursor: pointer; -webkit-tap-highlight-color: transparent; }
.app-list li:active { background: rgba(109, 138, 163, 0.15); }
.app-list li.enter { animation: row-in 0.5s ease-out; }
```

Bul (2/3):

```css
.menu-gap { height: 6px; background: rgba(0, 0, 0, 0.3); }

/* ---- Confirmation (Sleep, Force quit) ---- */
```

Şununla değiştir:

```css
.menu-gap { height: 6px; background: rgba(0, 0, 0, 0.3); }

/* ---- App panel: slides up from the bottom ---- */
.sheet {
  position: fixed;
  inset: 0;
  display: flex;
  align-items: flex-end;
  justify-content: center;
  padding: 0 calc(env(safe-area-inset-right) + 12px) calc(env(safe-area-inset-bottom) + 10px) calc(env(safe-area-inset-left) + 12px);
  background: rgba(1, 6, 13, 0.6);
  opacity: 0;
  pointer-events: none;
  transition: opacity 0.25s;
}
.sheet.show { opacity: 1; pointer-events: auto; }
.sheet-card {
  width: min(420px, 100%);
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 14px;
  border-radius: 20px;
  background: var(--raised);
  box-shadow: 0 -8px 40px rgba(0, 0, 0, 0.5);
  transform: translateY(110%);
  transition: transform 0.35s cubic-bezier(0.2, 0.8, 0.2, 1);
}
.sheet.show .sheet-card { transform: none; }
.sheet-head { display: flex; justify-content: space-between; align-items: baseline; gap: 10px; padding: 2px 4px 4px; }
.sheet-head strong { font-size: 17px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; min-width: 0; }
#sheet-figures { color: var(--muted); font-size: 13px; white-space: nowrap; font-variant-numeric: tabular-nums; }
.sheet-note { color: #c9d6e2; font-size: 13.5px; padding: 0 4px 4px; }
.sheet-button { height: 46px; border-radius: 12px; background: rgba(109, 138, 163, 0.2); font-weight: 600; text-align: center; }
.sheet-button:active { background: rgba(109, 138, 163, 0.35); }
.sheet-button.danger { color: #ff6b6b; }

/* ---- Confirmation (Sleep, Force quit) ---- */
```

Bul (3/3):

```css
  .menu { animation: none; }
  .confirm, .confirm-card, .toast, .volume-fill, .volume-thumb, .strip-button { transition: none; }
}
```

Şununla değiştir:

```css
  .menu { animation: none; }
  .confirm, .confirm-card, .toast, .volume-fill, .volume-thumb, .strip-button, .sheet, .sheet-card { transition: none; }
}
```

- [ ] **Step 3: Derle ve test et**

Run: iki uyarı denetimi → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 19 tests in 6 suites passed` ve `Test run with 186 tests in 32 suites passed`.
Run: `grep -n "innerHTML\|insertAdjacentHTML\|outerHTML" Resources/web/*.js` → Expected: çıktı yok.
Run: `make app 2>&1 | tail -1` → Expected: `Built …/build/PhoneBox.app`. Uygulamayı başlatmayın.

- [ ] **Step 4: Commit**

```bash
git add Resources/web/index.html Resources/web/view.js Resources/web/controls.js Resources/web/app.js \
  Resources/web/i18n.js Resources/web/styles.css
git commit -m "Open an app's panel from its row to quit or force quit it"
```

---

### Task 5: Ertelenen düzeltmeler ve tasarım

Önceki planlardan 4B'ye kalanlar:
- Grafik geçişinde A→B→A yarışı (4C).
- Dikeyde ekolayzerin boyutu, CSS sırası yüzünden hiç uygulanmıyordu (4A/4C).
- Şarkı yokken boş satırın bıraktığı boşluk (4A).
- Sıralama düğmesinin ilk satıra binmesi (4A); satıra dokunmak artık panel açtığı için önemli.
- RAM alarmında grafik çerçevesi ve başlık; "▲ RAM" yüzde yerine baskıyı yazıyor (4C).
- Bayatlama sınırında ilk karenin kaçması (4C).
- Saatin altındaki tarihin okunurluğu (telefon denemesi).

**Files:**
- Modify: `Resources/web/metrics.js`, `Tests/PhoneBoxCoreTests/WebMotionTests.swift`, `Resources/web/view.js`,
  `Resources/web/i18n.js`, `Resources/web/styles.css`, `docs/design/2026-11-25-phonebox-design.md`

**Interfaces:**
- Produces: `metrics.headerHeat(metric)` (disk için null, RAM dahil); `t.pressure` (`normal`, `warn`, `critical`).

- [ ] **Step 1: Test**

`Tests/PhoneBoxCoreTests/WebMotionTests.swift`:

Bul:

```swift
            == ",,net")
    }
```

Şununla değiştir:

```swift
            == ",,net")
        #expect(string("['disk', 'ram', 'cpu'].map(PhoneBox.metrics.headerHeat).join(',')") == ",ram,cpu")
    }
```

Run: `make test FILTER="WebMotionTests"` → Expected: başarısız (`headerHeat` yok).

- [ ] **Step 2: Kod**

`Resources/web/metrics.js`:

Bul (1/2):

```js
    return metric === "disk" || metric === "ram" ? null : metric;
  }
```

Şununla değiştir:

```js
    return metric === "disk" || metric === "ram" ? null : metric;
  }

  /// Which metric's heat and alarm the graph's header value and frame follow: the graph's own metric, RAM included
  /// (by memory pressure), but not disk, whose header shows reading speed, not free space.
  function headerHeat(metric) {
    return metric === "disk" ? null : metric;
  }
```

Bul (2/2):

```js
  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.metrics = { colors, light, order, values, heatValues, graphHeat, lines, scale, tile, header, axisLabel, GiB };
})(typeof window !== "undefined" ? window : globalThis);
```

Şununla değiştir:

```js
  global.PhoneBox = global.PhoneBox || {};
  global.PhoneBox.metrics = { colors, light, order, values, heatValues, graphHeat, headerHeat, lines, scale, tile, header, axisLabel, GiB };
})(typeof window !== "undefined" ? window : globalThis);
```

`Resources/web/view.js`:

Bul (1/7):

```js
      this.rows = new Map();
      /// The app shown in each row, by the row's `data-id`, for a tap.
```

Şununla değiştir:

```js
      this.rows = new Map();
      /// The metric the graph is fading to, and its timer: a tap during the fade replaces it.
      this.switching = null;
      this.switchTimer = 0;
      /// The app shown in each row, by the row's `data-id`, for a tap.
```

Bul (2/7):

```js
      this.stale = stale;
      $("dashboard").classList.toggle("stale", stale);
```

Şununla değiştir:

```js
      this.stale = stale;
      // The first frame after a change is drawn at once.
      this.staleFrameAt = -Infinity;
      $("dashboard").classList.toggle("stale", stale);
```

Bul (3/7):

```js
      this.renderHeader(shown, levels);
      const graphKey = PB().metrics.graphHeat(this.selected);
      this.drawGraph(graph, graphSize, now, still, graphKey ? glow(graphKey) : 0);
      this.renderTop(shown, levels, ringing, loud, pulse, still);
```

Şununla değiştir:

```js
      this.renderHeader(shown, levels);
      const alarmKey = PB().metrics.headerHeat(this.selected);
      this.drawGraph(graph, graphSize, now, still, alarmKey ? glow(alarmKey) : 0);
      this.renderTop(shown, levels, ringing, loud, pulse, still);
```

Bul (4/7):

```js
      }
      const value = (metric) => (metric === "cpu" || metric === "ram"
        ? metrics.header(metric, shown, this.format, this.t).value
        : metrics.tile(metric, shown, this.format));
      const name = (metric) => (metric === "disk" ? this.t.diskTile : this.t.metric[metric]);
```

Şununla değiştir:

```js
      }
      // RAM rings by memory pressure, so its line names the pressure, not the percentage used.
      const value = (metric) => {
        if (metric === "ram" && shown.mem && this.t.pressure[shown.mem.pressure]) return this.t.pressure[shown.mem.pressure];
        return metric === "cpu" || metric === "ram"
          ? metrics.header(metric, shown, this.format, this.t).value
          : metrics.tile(metric, shown, this.format);
      };
      const name = (metric) => (metric === "disk" ? this.t.diskTile : this.t.metric[metric]);
```

Bul (5/7):

```js
    switchTo(metric, history) {
      if (metric === this.selected) return;
      const canvas = $("graph");
      if (PB().motion.reduced()) {
        this.select(metric);
```

Şununla değiştir:

```js
    switchTo(metric, history) {
      // During a fade the metric being faded to counts: tapping A, B, then A again ends on A.
      if (metric === (this.switching ?? this.selected)) return;
      const canvas = $("graph");
      global.clearTimeout(this.switchTimer);
      if (PB().motion.reduced()) {
        this.switching = null;
        this.select(metric);
```

Bul (6/7):

```js
      }
      canvas.classList.add("switching");
      global.setTimeout(() => {
        this.select(metric);
```

Şununla değiştir:

```js
      }
      this.switching = metric;
      canvas.classList.add("switching");
      this.switchTimer = global.setTimeout(() => {
        this.switching = null;
        this.select(metric);
```

Bul (7/7):

```js
      const { value, detail } = metrics.header(this.selected, shown, this.format, this.t);
      const key = metrics.graphHeat(this.selected);
      const color = heat.color(metrics.colors[this.selected], key ? levels[key] ?? 0 : 0);
```

Şununla değiştir:

```js
      const { value, detail } = metrics.header(this.selected, shown, this.format, this.t);
      const key = metrics.headerHeat(this.selected);
      const color = heat.color(metrics.colors[this.selected], key ? levels[key] ?? 0 : 0);
```

`Resources/web/i18n.js`:

Bul (1/2):

```js
      lastMinute: "son 60 sn",
      limit: "SINIR",
```

Şununla değiştir:

```js
      lastMinute: "son 60 sn",
      pressure: { normal: "normal", warn: "uyarı", critical: "kritik" },
      limit: "SINIR",
```

Bul (2/2):

```js
      lastMinute: "last 60 s",
      limit: "LIMIT",
```

Şununla değiştir:

```js
      lastMinute: "last 60 s",
      pressure: { normal: "normal", warn: "warning", critical: "critical" },
      limit: "LIMIT",
```

`Resources/web/styles.css`:

Bul (1/4):

```css
  .clock { font-size: calc(var(--side) * 0.16); }
  .rings { flex-direction: column; justify-content: space-around; }
```

Şununla değiştir:

```css
  .clock { font-size: calc(var(--side) * 0.16); }
  /* No song: the app list takes its place instead of an empty row and its gap. */
  .dashboard:has(#now-playing[hidden]) {
    grid-template-rows: auto minmax(0, 1fr) auto auto;
    grid-template-areas:
      "rings graph top"
      "rings graph apps"
      "rings tiles apps"
      "rings strip apps";
  }
  .rings { flex-direction: column; justify-content: space-around; }
```

Bul (2/4):

```css
  .np-sub::before { content: "· "; }
  .np-icon { width: 24px; height: 24px; padding: 6px 0; gap: 2px; }
  .np-icon i { width: 3px; height: 12px; }
}
```

Şununla değiştir:

```css
  .np-sub::before { content: "· "; }
  /* `.now-playing` in front: the base rules come later in this file and would win otherwise. */
  .now-playing .np-icon { width: 24px; height: 24px; padding: 6px 0; gap: 2px; }
  .now-playing .np-icon i { width: 3px; height: 12px; }
  /* No song: no empty row, so no extra gap. */
  .dashboard:has(#now-playing[hidden]) {
    grid-template-rows: auto auto clamp(110px, 19dvh, 160px) auto minmax(0, 1fr) auto;
    grid-template-areas: "top" "rings" "graph" "tiles" "apps" "strip";
  }
}
```

Bul (3/4):

```css
.top-side { display: flex; flex-direction: column; align-items: flex-end; gap: 5px; min-width: 0; }
.top-line { max-width: 100%; font-size: 11.5px; color: var(--muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.top-line.alert { color: #ff6b6b; font-weight: 600; }
```

Şununla değiştir:

```css
.top-side { display: flex; flex-direction: column; align-items: flex-end; gap: 5px; min-width: 0; }
/* The date under the clock: lighter than the other labels, so it reads at a glance on a phone beside the desk. */
.top-line { max-width: 100%; font-size: 12px; color: #a3b8cb; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.top-line.alert { color: #ff6b6b; font-weight: 600; }
```

Bul (4/4):

```css
.apps-head { display: flex; justify-content: space-between; align-items: center; margin: 0 2px 2px; }
.app-sort { color: var(--muted); padding: 10px 0 10px 16px; margin: -8px 0; }
.app-list { list-style: none; margin: 0; padding: 0; flex: 1; min-height: 0; overflow: hidden; }
```

Şununla değiştir:

```css
.apps-head { display: flex; justify-content: space-between; align-items: center; margin: 0 2px 2px; }
/* A wide target that does not reach into the first row (a tap there opens the app's panel). */
.app-sort { color: var(--muted); padding: 8px 0 2px 24px; margin: -8px 0 -2px; }
.app-list { list-style: none; margin: 0; padding: 0; flex: 1; min-height: 0; overflow: hidden; }
```

- [ ] **Step 3: Tasarım**

`docs/design/2026-11-25-phonebox-design.md`:

Bul (1/6):

```markdown
- Ses kaydırıcısı sürüklenirken sayfa en fazla saniyede 4 `volume` gönderir, bırakınca son değeri gönderir (sınır 10/sn).
- Ses kontrolü olmayan çıkış cihazında `volume`/`mute` `unsupported` döner ve kaydırıcı devre dışı kalır.
- Spike 7'de uygulama kapatma, sessiz, ses seviyesi, ekranı kapatma ve kilit hiçbir izin penceresi açmadan
```

Şununla değiştir:

```markdown
- Ses kaydırıcısı sürüklenirken sayfa en fazla saniyede 4 `volume` gönderir, bırakınca son değeri gönderir (sınır 10/sn).
- Ses kontrolü olmayan çıkış cihazında `volume`/`mute` `unsupported` döner ve kaydırıcı devre dışı kalır; kontrol var
  ama değeri almadıysa `failed` döner.
- Spike 7'de uygulama kapatma, sessiz, ses seviyesi, ekranı kapatma ve kilit hiçbir izin penceresi açmadan
```

Bul (2/6):

```markdown
- **Kontrol şeridi:** önceki, oynat/duraklat (çalma durumuna göre simge), sonraki, ses kaydırıcısı (Mac'in o anki
  seviyesi), sessiz (🔈/🔇), "⋯". Dokunma alanları en az 44×44 pt. `audio` alanı yoksa kaydırıcı ve sessiz soluk.
- **Komut etkileşimleri** (görsel taslaklarla seçildi):
```

Şununla değiştir:

```markdown
- **Kontrol şeridi:** önceki, oynat/duraklat (çalma durumuna göre simge), sonraki, ses kaydırıcısı (Mac'in o anki
  seviyesi), sessiz, "⋯". Simgeler sayfanın içinde SVG (emoji değil). Dokunma alanları en az 44×44 pt. `audio` alanı
  yoksa kaydırıcı ve sessiz soluk. Kaydırıcı parmakla sürüklenir: en çok saniyede 4 değer gider, bırakınca son değer
  gider; bıraktıktan sonra 1,5 sn Mac'in eski değeri gösterilmez (düğme geri sıçramasın). Sessiz düğmesi dokunur
  dokunmaz değişir, sonraki snapshot doğrular.
- **Komut etkileşimleri** (görsel taslaklarla seçildi):
```

Bul (3/6):

```markdown
    klavyesine ya da trackpad'ine dokunarak uyandırılacağını, sonra dashboard'un kendiliğinden bağlanacağını söyler.
  - Her komuttan sonra üstte 2 sn bildirim: başarıda yeşil tik; hatada kırmızı ve sebep (`not-allowed` → "Komutlar
    sadece kabloyla çalışır", `app-changed` → "Uygulama değişmiş, liste yenilendi", `unsupported` → ses
    komutlarında "Bu çıkışta ses kontrolü yok", diğerlerinde "Bu komut desteklenmiyor", `failed` → "Olmadı").
  - `access.commands` false iken (Wi-Fi) şerit, panel düğmeleri ve menüdeki komutlar soluk; dokununca "Komutlar
```

Şununla değiştir:

```markdown
    klavyesine ya da trackpad'ine dokunarak uyandırılacağını, sonra dashboard'un kendiliğinden bağlanacağını söyler.
  - Komuttan sonra üstte 2 sn bildirim. Başarıda yeşil tik yalnız uygulama ve "⋯" komutlarında ("Code kapatıldı",
    "Mac kilitlendi"); medya, ses ve sessizde başarı zaten ekranda görünür, bildirim çıkmaz. Hatada her zaman kırmızı
    ve sebep (`not-allowed` → "Komutlar sadece kabloyla çalışır", `app-changed` → "Uygulama değişmiş, liste
    yenilendi", `unsupported` → ses komutlarında "Bu çıkışta ses kontrolü yok", diğerlerinde "Bu komut
    desteklenmiyor", `failed` ya da 5 sn içinde cevap gelmemesi → "Olmadı").
  - Komutlar numaralanır (`seq` sayfa açık kaldıkça hep artar) ve imzalanır; cevap (`ack`) numarasıyla eşlenir
    (`commands.js`).
  - `access.commands` false iken (Wi-Fi) şerit, panel düğmeleri ve menüdeki komutlar soluk; dokununca "Komutlar
```

Bul (4/6):

```markdown
  - Saat başlığında tarihin yerine kırmızı "▲ CPU %100" yazar; birden fazla alarm varsa en yüksek seviyeli ikisi
    ("▲ CPU %100 · Sıcaklık 97 °C").
  - Alarm yokken bir metrik seviye 0,7'yi geçerse kenarda soluk bir ışık belirir (seviye arttıkça güçlenir).
```

Şununla değiştir:

```markdown
  - Saat başlığında tarihin yerine kırmızı "▲ CPU %100" yazar; birden fazla alarm varsa en yüksek seviyeli ikisi
    ("▲ CPU %100 · Sıcaklık 97 °C"). RAM'in alarmında yüzde değil bellek baskısı yazar ("▲ RAM kritik"). RAM grafiği
    kızarmaz ama alarmında çerçevesi atar, başlıktaki değeri kızarır.
  - Alarm yokken bir metrik seviye 0,7'yi geçerse kenarda soluk bir ışık belirir (seviye arttıkça güçlenir).
```

Bul (5/6):

```markdown
| `connection.js` | bağlantı, eşleşme, yeniden bağlanma (bugünkü `app.js`'ten) | gözle / telefonda |
| `commands.js` | komut imzası, `seq`, ses kaydırıcısının hız sınırı | imza ve hız sınırı JavaScriptCore'da |
| `view.js` | halkalar, kutucuklar, liste (satır kayması), şarkı kartı, saat başlığı, telefonun pili, alarm ve kenar ışığı, durumlar | gözle |
```

Şununla değiştir:

```markdown
| `connection.js` | bağlantı, eşleşme, yeniden bağlanma (bugünkü `app.js`'ten) | gözle / telefonda |
| `commands.js` | komut imzası, `seq`, cevap eşleme, 5 sn zaman aşımı, ses kaydırıcısının hız sınırı | imza (Swift'in `MessageAuth`'u ile), eşleme ve hız sınırı JavaScriptCore'da |
| `controls.js` | kontrol şeridi, uygulama paneli, "⋯" komutları, onay, bildirim | gözle |
| `view.js` | halkalar, kutucuklar, liste (satır kayması), şarkı kartı, saat başlığı, telefonun pili, alarm ve kenar ışığı, durumlar | gözle |
```

Bul (6/6):

```markdown
                          motion.js, rings.js, clock.js, chart.js, connection.js, commands.js, view.js, ui.js,
                          app.js, keepawake.mp4, apple-touch-icon.png
```

Şununla değiştir:

```markdown
                          motion.js, rings.js, clock.js, chart.js, connection.js, commands.js, view.js, ui.js,
                          controls.js,
                          app.js, keepawake.mp4, apple-touch-icon.png
```

- [ ] **Step 4: Derle ve test et**

Run: iki uyarı denetimi → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 19 tests in 6 suites passed` ve `Test run with 186 tests in 32 suites passed`.
Run: `make app 2>&1 | tail -1` → Expected: `Built …/build/PhoneBox.app`. Uygulamayı başlatmayın.

- [ ] **Step 5: Commit**

```bash
git add Resources/web/metrics.js Resources/web/view.js Resources/web/i18n.js Resources/web/styles.css \
  Tests/PhoneBoxCoreTests/WebMotionTests.swift docs/design/2026-11-25-phonebox-design.md
git commit -m "Fix the graph switch race, the now-playing gaps and the sort target; name RAM's pressure in its alarm"
```

---

### Task 6: Mac'te ve telefonda kontrol (kontrolcü, inline)

- [ ] **Step 1: Sahte veriyle** (Plan 4C'nin deneme sayfası; sahte Mac `cmd`'ye `ack` verir): "Planlama sırasında
  doğrulananlar"daki her madde; 734×372, 667×375, 393×759, 375×647; konsolda JavaScript hatası yok.
- [ ] **Step 2: Mac'te canlı:** `PHONEBOX_LIVE=1 make test FILTER="SystemAudioLiveTests|CommandRunnerLiveTests"`.
- [ ] **Step 3: Gerçek telefonda** (kablo, iPhone Yansıtma ile): dalın `make run`'ı; medya düğmeleri Mac'te çalan
  şeyi değiştiriyor; kaydırıcı Mac'in sesini değiştiriyor ve geri sıçramıyor; sessiz; Satranç'ı aç, telefondan
  Kapat ve (yeniden açıp) onaylı Zorla kapat; kapatılamayan satır (Finder) yalnız bilgi veriyor; Wi-Fi'de komutlar
  soluk; "Uyut"un onayı açılıyor, Vazgeç.
- [ ] **Step 4: En sonda (kullanıcının izniyle):** telefondan "Ekranı kapat", sonra "Kilitle"; ikisinin `ack`'i ve
  bildirimi. Uyut denenmez.
- [ ] **Step 5: Belgeler:** `docs/manual-testing.md`'deki "Komutlar" listesi ve "Sonuçlar"a Plan 4B.
