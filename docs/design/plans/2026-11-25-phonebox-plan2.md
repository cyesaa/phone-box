# PhoneBox Plan 2 — Uçtan uca iskelet

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Bu plan için not:** Görev 1–10 Mac'te tek başına yürütülebilir (alt ajanlarla da). Görev 11 kullanıcının
> elinde iPhone ile yanında olmasını gerektirir; o görev aynı oturumda (inline) yürütülür.

**Goal:** PhoneBox'ın çalışan ilk sürümü: menü çubuğu uygulaması, QR ile eşleştirme, imzalı WebSocket, kablo/Wi-Fi
ayrımı ve telefonda canlı CPU + RAM gösteren, ekranı açık tutan sade bir dashboard. Sonunda iPhone kabloyla
takılıp QR okutulunca CPU ve RAM kablo üzerinden canlı görünür.

**Architecture:** İki SwiftPM hedefi: `PhoneBoxCore` (sistem çağrısı yok, test edilen saf mantık: anahtar, HMAC,
erişim kuralı, mesajlar, oturum, HTTP/WebSocket ayrıştırma, CPU/RAM hesabı) ve `PhoneBox` (menü çubuğu uygulaması:
Network.framework sunucusu, usbmuxd dinleyicisi, IOKit ile iPhone USB arayüzü tespiti, Mach ile CPU/RAM okuma,
QR penceresi). Dashboard, uygulamanın içine gömülü sade HTML/CSS/JS'tir; imzaları `sha256.js` atar. Her şey
ana kuyrukta çalışır; tek arka plan iş parçacığı usbmuxd soketini okur.

**Tech Stack:** Swift 6.4 araç zinciri (Swift 5 dil modu), AppKit, Network.framework, CryptoKit, IOKit,
ServiceManagement, CoreImage, AVFoundation (sadece video üretici betik), Swift Testing, JavaScriptCore (testlerde),
sade HTML/CSS/JS, bash + make. Xcode gerekmez; Command Line Tools yeterli.

**Spec:** `docs/design/2026-11-25-phonebox-design.md` · **Deneme sonuçları:** `docs/spike-results.md`

**Sonraki planlar:** Plan 3 diğer metrikler ve komutlar; Plan 4 tam dashboard arayüzü (yerleşim C, grafikler,
rehber, OLED kaydırma); Plan 5 dağıtım (`install.sh`, sürüm, README, simge, port menüsü).

## Global Constraints

- macOS 14+, Apple Silicon; `swift-tools-version:6.0`, `swiftLanguageModes: [.v5]`; ek bağımlılık yok.
- Bundle ID `com.phonebox.PhoneBox`; sürüm `0.1.0`; `LSUIElement` true; dil İngilizce + Türkçe.
- Port varsayılanı `4747`; adres her yerde `http://<LocalHostName>.local:<port>/#k=<anahtar>` (şemasız yazılırsa
  Safari önce HTTPS dener).
- Protokol (spec §5) birebir: her mesajda `"v":1`; `hello`, `auth`, `ready`, `access`, `snapshot`, `cmd`, `ack`.
  İmzalar: `HMAC-SHA256(k, "auth:"+nonce)` ve `HMAC-SHA256(k, "cmd:"+nonce+":"+seq+":"+name+":"+args)`, küçük harf hex.
- Kapanış kodları: `4001` anahtar/kimlik hatası ve kimlik doğrulama 5 sn'de gelmezse; `4002` "kabloya geç, hemen
  yeniden bağlan"; `1008` protokol ihlali (bozuk mesaj, yanlış imza, eski `seq`, saniyede 10'dan fazla komut).
- En fazla 4 WebSocket istemcisi; 5.'ye HTTP 503.
- Kablo modu: istemci iPhone'un USB arayüzünden (`anri*`/`en*`, Apple `idVendor` 0x05AC, ürün adı iPhone/iPad)
  geliyorsa izin. Her zaman modu: kimliği doğrulanmış her istemciye izin.
- Ekranı açık tutma: sesi açık, döngüsüz, görüntü + sessiz ses izli `keepawake.mp4`, 0,5 sn'den sonra başa sarılır;
  `navigator.audioSession.type = "ambient"`; sayfa görünürken 3 sn'de bir "duruyorsa oynat" denetimi.
- Eşleştirme anahtarı `~/Library/Application Support/PhoneBox/pairing-key` (dosya `0600`, klasör `0700`). Uygulama
  `~/Documents`'a hiçbir şey yazmaz (spike: -10810). Log yalnızca `os_log` (`com.phonebox.PhoneBox`).
- Komutlar bu planda çalıştırılmaz: imzası doğru her `cmd`'ye `{"ok":false,"error":"unsupported"}` döner (Plan 3).
- Her commit İngilizce, emir kipinde ve şu satırla biter: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Planlama sırasında doğrulananlar (2026-11-25)

Bu plandaki kodun tamamı yazılmadan önce scratch bir pakette derlendi ve çalıştırıldı:

- `make test`: 13 takımda 63 test geçti (JavaScriptCore'da çalışan `sha256.js` testleri dahil).
- `scripts/bundle.sh` ad-hoc imzalı `build/PhoneBox.app` üretti; uygulama `*:4747`'yi dinledi; `/` 200, video
  `Range` isteği 206, `/../pairing-key` 404 döndü; anahtar dosyası `0600` oluştu.
- Tarayıcı panelinde kişisel bağlantı: "Her zaman" modunda kimlik doğrulandı, canlı CPU (%73–83) ve RAM
  (13,6 / 16,0 GB) geldi; "Başlat" sonrası video sesi açık ve döngüsüz oynadı. Yanlış anahtar → "Eşleşmedi"; kablo
  modunda Mac'in kendi tarayıcısı (lo0) → "Kabloyu tak".
- iPhone takılıyken IOKit `en7`, `anri1`, `en8`'i iPhone arayüzü olarak tanıdı; Network.framework bir bağlantının
  yerel ucunu `fe80::…%en8` olarak verdi. Telefonda açık kalan eski deneme sayfasının bağlantısı log'da
  `Phone connected on en8 (USB: true)` olarak göründü.

## Dosya yapısı

```
Package.swift  Makefile  .gitignore (var)
Sources/PhoneBoxCore/   Hex, PairingKey, MessageAuth, AccessPolicy, Messages, Session, HTTP, WebSocket,
                        CPULoad, MemoryUsage, Snapshot
Sources/PhoneBox/       PhoneBoxApp, AppDelegate, Settings, PairingStore, Log, L10n, USBWatcher, USBLinks,
                        ClientConnection, DashboardServer, DashboardHub, Sampler, MenuBarController, QRWindowController,
                        Collectors/CPUCollector, Collectors/MemoryCollector
Resources/              Info.plist, en.lproj/Localizable.strings, tr.lproj/Localizable.strings
Resources/web/          index.html, styles.css, app.js, sha256.js   (keepawake.mp4 derleme sırasında üretilir)
scripts/                bundle.sh, make-video.swift
Tests/PhoneBoxCoreTests/ PairingKeyTests, MessageAuthTests, WebCryptoTests, AccessPolicyTests, MessagesTests,
                        SessionTests, HTTPTests, WebSocketTests, MetricsMathTests
docs/manual-testing.md
```

---

### Task 1: Paket iskeleti, hex ve eşleştirme anahtarı

**Files:**
- Create: `Package.swift` (bu görevde sadece çekirdek ve testler; uygulama hedefi Görev 7'de eklenir)
- Create: `Makefile`
- Create: `Sources/PhoneBoxCore/Hex.swift`, `Sources/PhoneBoxCore/PairingKey.swift`
- Test: `Tests/PhoneBoxCoreTests/PairingKeyTests.swift`

**Interfaces:**
- Produces: `Hex.encode(_:) -> String`, `Hex.decode(_:) -> Data?`;
  `struct PairingKey { bytes: Data; init?(bytes:); static generate(); base64URL: String; init?(base64URL:) }`

- [ ] **Step 1: Paket tanımını yaz (geçici, sadece çekirdek)**

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
        .testTarget(name: "PhoneBoxCoreTests", dependencies: ["PhoneBoxCore"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: Makefile'ı yaz**

`Makefile` (NotchBox'takiyle aynı test bayrakları; `app` ve `run` hedefleri Görev 10'da kullanılır):

```make
# Command Line Tools ship the Swift Testing macro plugin outside the default search path.
DEV_DIR := $(shell xcode-select -p)
ifeq ($(DEV_DIR),/Library/Developer/CommandLineTools)
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc $(DEV_DIR)/usr/lib/swift/host/plugins/testing
endif

.PHONY: build test app run clean

build:
	swift build

test:
	swift test $(TEST_FLAGS) $(if $(FILTER),--filter '$(FILTER)',)

app:
	scripts/bundle.sh

run: app
	-pkill -x PhoneBox
	@tries=0; while pgrep -x PhoneBox >/dev/null; do \
		tries=$$((tries + 1)); \
		if [ $$tries -ge 50 ]; then echo "error: PhoneBox did not quit within 5 s" >&2; exit 1; fi; \
		sleep 0.1; \
	done
	open build/PhoneBox.app

clean:
	rm -rf .build build
```

- [ ] **Step 3: Başarısız testi yaz**

`Tests/PhoneBoxCoreTests/PairingKeyTests.swift`:

```swift
import Foundation
import Testing
@testable import PhoneBoxCore

struct PairingKeyTests {
    @Test func hexRoundTrips() {
        let bytes = Data([0x00, 0x0f, 0xa5, 0xff])
        #expect(Hex.encode(bytes) == "000fa5ff")
        #expect(Hex.decode("000fa5ff") == bytes)
        #expect(Hex.decode("000FA5FF") == bytes)
    }

    @Test func hexRejectsOddLengthAndNonDigits() {
        #expect(Hex.decode("abc") == nil)
        #expect(Hex.decode("zz") == nil)
    }

    @Test func generatedKeysAre32BytesAndDiffer() {
        let first = PairingKey.generate()
        let second = PairingKey.generate()
        #expect(first.bytes.count == 32)
        #expect(first != second)
    }

    @Test func base64URLRoundTripsWithoutPadding() {
        let key = PairingKey(bytes: Data((0..<32).map { UInt8($0 * 8) }))!
        #expect(!key.base64URL.contains("="))
        #expect(!key.base64URL.contains("+"))
        #expect(!key.base64URL.contains("/"))
        #expect(PairingKey(base64URL: key.base64URL) == key)
    }

    @Test func rejectsWrongLengths() {
        #expect(PairingKey(bytes: Data(count: 31)) == nil)
        #expect(PairingKey(base64URL: "c2hvcnQ") == nil)
        #expect(PairingKey(base64URL: "%%%") == nil)
    }
}
```

- [ ] **Step 4: Testin başarısız olduğunu gör**

Run: `make test FILTER=PairingKeyTests`
Expected: FAIL — derleme hatası `cannot find 'Hex' in scope` / `cannot find 'PairingKey' in scope`.

- [ ] **Step 5: Uygulamayı yaz**

`Sources/PhoneBoxCore/Hex.swift`:

```swift
import Foundation

/// Lowercase hexadecimal, as the protocol writes nonces and signatures.
public enum Hex {
    public static func encode<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Nil for an odd length or a character that is not a hex digit.
    public static func decode(_ text: String) -> Data? {
        let characters = Array(text.utf8)
        guard characters.count % 2 == 0 else { return nil }
        var data = Data(capacity: characters.count / 2)
        var index = 0
        while index < characters.count {
            guard let high = nibble(characters[index]), let low = nibble(characters[index + 1]) else { return nil }
            data.append(high << 4 | low)
            index += 2
        }
        return data
    }

    private static func nibble(_ character: UInt8) -> UInt8? {
        switch character {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): character - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): character - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): character - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}
```

`Sources/PhoneBoxCore/PairingKey.swift`:

```swift
import Foundation

/// The 32-byte secret shared with paired phones (design §5). It reaches the phone only inside the QR code's
/// URL fragment (`#k=`), which browsers never send to the server.
public struct PairingKey: Equatable, Sendable {
    public let bytes: Data

    public init?(bytes: Data) {
        guard bytes.count == 32 else { return nil }
        self.bytes = bytes
    }

    /// 32 bytes from the system's cryptographically secure generator.
    public static func generate() -> PairingKey {
        var generator = SystemRandomNumberGenerator()
        return PairingKey(bytes: Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))!
    }

    /// Base64url without padding: safe in a URL fragment and in a file.
    public var base64URL: String {
        bytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public init?(base64URL text: String) {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        self.init(bytes: data)
    }
}
```

- [ ] **Step 6: Testin geçtiğini gör**

Run: `make test FILTER=PairingKeyTests`
Expected: `Test run with 5 tests in 1 suite passed`.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Makefile Sources/PhoneBoxCore/Hex.swift Sources/PhoneBoxCore/PairingKey.swift Tests/PhoneBoxCoreTests/PairingKeyTests.swift
git commit -m "Add the package with hex helpers and the pairing key" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: HMAC imzaları ve telefondaki `sha256.js`

**Files:**
- Create: `Sources/PhoneBoxCore/MessageAuth.swift`
- Create: `Resources/web/sha256.js`
- Test: `Tests/PhoneBoxCoreTests/MessageAuthTests.swift`, `Tests/PhoneBoxCoreTests/WebCryptoTests.swift`

**Interfaces:**
- Consumes: `Hex`, `PairingKey` (Görev 1)
- Produces: `MessageAuth.hmacHex(key:message:)`, `authMessage(nonce:)`, `commandMessage(nonce:seq:name:args:)`,
  `isValid(signature:key:message:)`. JS: `PBCrypto.hmacHex(keyBytes, message)`, `PBCrypto.base64UrlToBytes(text)`,
  `PBCrypto.hexToBytes`, `PBCrypto.hex`, `PBCrypto.utf8`, `PBCrypto.sha256`.

- [ ] **Step 1: Başarısız testleri yaz**

`Tests/PhoneBoxCoreTests/MessageAuthTests.swift`:

```swift
import Foundation
import Testing
@testable import PhoneBoxCore

struct MessageAuthTests {
    /// RFC 4231 test case 1.
    @Test func matchesRFC4231Case1() {
        let key = Data(repeating: 0x0b, count: 20)
        #expect(MessageAuth.hmacHex(key: key, message: "Hi There")
            == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
    }

    /// RFC 4231 test case 2.
    @Test func matchesRFC4231Case2() {
        #expect(MessageAuth.hmacHex(key: Data("Jefe".utf8), message: "what do ya want for nothing?")
            == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
    }

    @Test func buildsTheSignedStrings() {
        #expect(MessageAuth.authMessage(nonce: "ab12") == "auth:ab12")
        #expect(MessageAuth.commandMessage(nonce: "ab12", seq: 3, name: "mute", args: #"{"on":true}"#)
            == #"cmd:ab12:3:mute:{"on":true}"#)
    }

    @Test func validatesOnlyTheRightSignature() {
        let key = PairingKey.generate().bytes
        let good = MessageAuth.hmacHex(key: key, message: "auth:1234")
        #expect(MessageAuth.isValid(signature: good, key: key, message: "auth:1234"))
        #expect(MessageAuth.isValid(signature: good.uppercased(), key: key, message: "auth:1234"))
        #expect(!MessageAuth.isValid(signature: good, key: key, message: "auth:1235"))
        #expect(!MessageAuth.isValid(signature: String(good.dropLast(2)), key: key, message: "auth:1234"))
        #expect(!MessageAuth.isValid(signature: "not hex", key: key, message: "auth:1234"))
        #expect(!MessageAuth.isValid(signature: good, key: PairingKey.generate().bytes, message: "auth:1234"))
    }
}
```

`Tests/PhoneBoxCoreTests/WebCryptoTests.swift` (`sha256.js`'i JavaScriptCore'da çalıştırır):

```swift
import Foundation
import JavaScriptCore
import Testing
@testable import PhoneBoxCore

/// Runs the dashboard's `Resources/web/sha256.js` in JavaScriptCore (the engine behind Safari) and checks it
/// signs exactly like `MessageAuth`. No Node or npm needed.
struct WebCryptoTests {
    static let scriptURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/web/sha256.js")

    func context() throws -> JSContext {
        let context = try #require(JSContext())
        context.exceptionHandler = { _, exception in Issue.record("JavaScript error: \(exception?.toString() ?? "?")") }
        context.evaluateScript(try String(contentsOf: Self.scriptURL, encoding: .utf8))
        return context
    }

    func hmac(_ context: JSContext, keyHex: String, message: String) -> String? {
        let function = context.evaluateScript("(k, m) => PBCrypto.hmacHex(PBCrypto.hexToBytes(k), m)")
        return function?.call(withArguments: [keyHex, message])?.toString()
    }

    @Test func matchesRFC4231() throws {
        let context = try context()
        #expect(hmac(context, keyHex: String(repeating: "0b", count: 20), message: "Hi There")
            == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
        #expect(hmac(context, keyHex: Hex.encode(Data("Jefe".utf8)), message: "what do ya want for nothing?")
            == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
    }

    /// RFC 4231 test case 6: a key longer than the block size is hashed first.
    @Test func hashesLongKeys() throws {
        let context = try context()
        #expect(hmac(context, keyHex: String(repeating: "aa", count: 131), message: "Test Using Larger Than Block-Size Key - Hash Key First")
            == "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
    }

    @Test func signsLikeTheMacForRealKeysAndNonUTF8Text() throws {
        let context = try context()
        for message in ["auth:0123456789abcdef0123456789abcdef", #"cmd:ab:7:quitApp:{"pid":42,"bundleId":"net.whatsapp"}"#,
                        "çğıöşü ÇĞİÖŞÜ 🌹", String(repeating: "x", count: 1_000)] {
            let key = PairingKey.generate()
            #expect(hmac(context, keyHex: Hex.encode(key.bytes), message: message) == MessageAuth.hmacHex(key: key.bytes, message: message))
        }
    }

    @Test func decodesBase64URLKeysLikePairingKey() throws {
        let context = try context()
        let key = PairingKey.generate()
        let decode = context.evaluateScript("(k) => PBCrypto.hex(PBCrypto.base64UrlToBytes(k))")
        #expect(decode?.call(withArguments: [key.base64URL])?.toString() == Hex.encode(key.bytes))
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `make test FILTER="MessageAuthTests|WebCryptoTests"`
Expected: FAIL — `cannot find 'MessageAuth' in scope`.

- [ ] **Step 3: Swift tarafını yaz**

`Sources/PhoneBoxCore/MessageAuth.swift`:

```swift
import CryptoKit
import Foundation

/// HMAC-SHA256 signatures of the WebSocket protocol (design §5). The phone signs with the same key in
/// `Resources/web/sha256.js`; the key itself never travels.
public enum MessageAuth {
    public static func hmacHex(key: Data, message: String) -> String {
        let code = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: key))
        return Hex.encode(Data(code))
    }

    /// What the phone signs to prove it holds the key: `auth:<nonce>`.
    public static func authMessage(nonce: String) -> String {
        "auth:" + nonce
    }

    /// What the phone signs for a command: `cmd:<nonce>:<seq>:<name>:<args>`, with `args` exactly as sent.
    public static func commandMessage(nonce: String, seq: Int, name: String, args: String) -> String {
        "cmd:\(nonce):\(seq):\(name):\(args)"
    }

    /// Compares in constant time. False for anything that is not 64 hex digits.
    public static func isValid(signature: String, key: Data, message: String) -> Bool {
        guard let tag = Hex.decode(signature), tag.count == 32 else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(tag, authenticating: Data(message.utf8), using: SymmetricKey(data: key))
    }
}
```

- [ ] **Step 4: JS tarafını yaz**

`Resources/web/sha256.js`:

```javascript
// SHA-256 and HMAC-SHA256 in plain JavaScript (FIPS 180-4, RFC 2104).
// Browsers hide crypto.subtle from pages served over plain http://, so the dashboard signs its messages with
// this file (design §5). It does not use TextEncoder or atob, so the Swift tests can run it in JavaScriptCore.
(function (global) {
  "use strict";

  const K = new Uint32Array([
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ]);

  function rotr(x, n) {
    return (x >>> n) | (x << (32 - n));
  }

  function sha256(bytes) {
    const bitLength = bytes.length * 8;
    const padded = new Uint8Array(((bytes.length + 9 + 63) >> 6) << 6);
    padded.set(bytes);
    padded[bytes.length] = 0x80;
    const view = new DataView(padded.buffer);
    view.setUint32(padded.length - 8, Math.floor(bitLength / 0x100000000));
    view.setUint32(padded.length - 4, bitLength >>> 0);

    const h = new Uint32Array([
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]);
    const w = new Uint32Array(64);
    for (let block = 0; block < padded.length; block += 64) {
      for (let i = 0; i < 16; i++) w[i] = view.getUint32(block + i * 4);
      for (let i = 16; i < 64; i++) {
        const s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        const s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
      }
      let a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
      for (let i = 0; i < 64; i++) {
        const s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        const ch = (e & f) ^ (~e & g);
        const t1 = (hh + s1 + ch + K[i] + w[i]) >>> 0;
        const s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        const maj = (a & b) ^ (a & c) ^ (b & c);
        const t2 = (s0 + maj) >>> 0;
        hh = g; g = f; f = e; e = (d + t1) >>> 0;
        d = c; c = b; b = a; a = (t1 + t2) >>> 0;
      }
      h[0] = (h[0] + a) >>> 0; h[1] = (h[1] + b) >>> 0; h[2] = (h[2] + c) >>> 0; h[3] = (h[3] + d) >>> 0;
      h[4] = (h[4] + e) >>> 0; h[5] = (h[5] + f) >>> 0; h[6] = (h[6] + g) >>> 0; h[7] = (h[7] + hh) >>> 0;
    }
    const out = new Uint8Array(32);
    const outView = new DataView(out.buffer);
    for (let i = 0; i < 8; i++) outView.setUint32(i * 4, h[i]);
    return out;
  }

  function hmac(keyBytes, messageBytes) {
    let key = keyBytes.length > 64 ? sha256(keyBytes) : keyBytes;
    const block = new Uint8Array(64);
    block.set(key);
    const inner = new Uint8Array(64 + messageBytes.length);
    const outer = new Uint8Array(64 + 32);
    for (let i = 0; i < 64; i++) {
      inner[i] = block[i] ^ 0x36;
      outer[i] = block[i] ^ 0x5c;
    }
    inner.set(messageBytes, 64);
    outer.set(sha256(inner), 64);
    return sha256(outer);
  }

  function utf8(text) {
    const bytes = [];
    for (let i = 0; i < text.length; i++) {
      let code = text.charCodeAt(i);
      if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
        const low = text.charCodeAt(i + 1);
        if (low >= 0xdc00 && low <= 0xdfff) {
          code = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00);
          i++;
        }
      }
      if (code < 0x80) bytes.push(code);
      else if (code < 0x800) bytes.push(0xc0 | (code >> 6), 0x80 | (code & 63));
      else if (code < 0x10000) bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63));
      else bytes.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 63), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63));
    }
    return new Uint8Array(bytes);
  }

  function hex(bytes) {
    let out = "";
    for (let i = 0; i < bytes.length; i++) out += (bytes[i] < 16 ? "0" : "") + bytes[i].toString(16);
    return out;
  }

  function hexToBytes(text) {
    const out = new Uint8Array(text.length >> 1);
    for (let i = 0; i < out.length; i++) out[i] = parseInt(text.substr(i * 2, 2), 16);
    return out;
  }

  const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

  /// The pairing key arrives as base64url without padding (PairingKey.base64URL).
  function base64UrlToBytes(text) {
    const bytes = [];
    let buffer = 0, bits = 0;
    for (let i = 0; i < text.length; i++) {
      const value = ALPHABET.indexOf(text[i]);
      if (value < 0) return null;
      buffer = (buffer << 6) | value;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        bytes.push((buffer >> bits) & 0xff);
      }
    }
    return new Uint8Array(bytes);
  }

  global.PBCrypto = {
    sha256: sha256,
    hmacHex: (keyBytes, message) => hex(hmac(keyBytes, utf8(message))),
    utf8: utf8,
    hex: hex,
    hexToBytes: hexToBytes,
    base64UrlToBytes: base64UrlToBytes,
  };
})(typeof window !== "undefined" ? window : globalThis);
```

- [ ] **Step 5: Testlerin geçtiğini gör**

Run: `make test FILTER="MessageAuthTests|WebCryptoTests"`
Expected: `Test run with 8 tests in 2 suites passed`.

- [ ] **Step 6: Commit**

```bash
git add Sources/PhoneBoxCore/MessageAuth.swift Resources/web/sha256.js Tests/PhoneBoxCoreTests/MessageAuthTests.swift Tests/PhoneBoxCoreTests/WebCryptoTests.swift
git commit -m "Sign protocol messages with HMAC-SHA256 on the Mac and in the page" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Erişim kuralı ve protokol mesajları

**Files:**
- Create: `Sources/PhoneBoxCore/AccessPolicy.swift`, `Sources/PhoneBoxCore/Snapshot.swift`,
  `Sources/PhoneBoxCore/CPULoad.swift`, `Sources/PhoneBoxCore/MemoryUsage.swift`, `Sources/PhoneBoxCore/Messages.swift`
- Test: `Tests/PhoneBoxCoreTests/AccessPolicyTests.swift`, `Tests/PhoneBoxCoreTests/MessagesTests.swift`,
  `Tests/PhoneBoxCoreTests/MetricsMathTests.swift`

(`Messages.swift` snapshot'ı, snapshot da `CPUSample` ve `MemorySample`'ı kodladığı için metrik modelleri ve
hesapları bu görevde birlikte gelir.)

**Interfaces:**
- Produces: `enum AccessMode { cable, always }`; `struct Access { streaming, commands, reason; static granted,
  notOnCable, unauthenticated }`; `AccessPolicy.decide(mode:clientOnUSB:authenticated:) -> Access`;
  `struct CPUTicks`, `struct CPUSample { total, cores, pCores, load }`, `CPULoad.usage(from:to:)`,
  `CPULoad.rounded(_:)`; `struct VMPageCounts`, `struct MemorySample { used, total, app, wired, compressed, swapUsed,
  pressure }`, `MemoryUsage.sample(counts:totalBytes:swapUsedBytes:pressureLevel:)`, `MemoryUsage.pressureName(_:)`;
  `struct Snapshot { t, cpu?, mem? }`; `enum ServerMessage { hello, ready, access, snapshot, ack }` + `json()`;
  `enum ClientMessage { auth(mac:), command(seq:name:args:mac:) }` + `parse(_:)`.

- [ ] **Step 1: Başarısız testleri yaz**

`Tests/PhoneBoxCoreTests/AccessPolicyTests.swift`:

```swift
import Testing
@testable import PhoneBoxCore

struct AccessPolicyTests {
    @Test func cableModeAllowsOnlyClientsOnTheUSBLink() {
        #expect(AccessPolicy.decide(mode: .cable, clientOnUSB: true, authenticated: true) == .granted)
        #expect(AccessPolicy.decide(mode: .cable, clientOnUSB: false, authenticated: true) == .notOnCable)
    }

    @Test func alwaysModeAllowsEveryAuthenticatedClient() {
        #expect(AccessPolicy.decide(mode: .always, clientOnUSB: true, authenticated: true) == .granted)
        #expect(AccessPolicy.decide(mode: .always, clientOnUSB: false, authenticated: true) == .granted)
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
        #expect(Access.granted.reason == "ok")
        #expect(Access.notOnCable.reason == "not-on-cable")
    }
}
```

`Tests/PhoneBoxCoreTests/MetricsMathTests.swift`:

```swift
import Testing
@testable import PhoneBoxCore

struct CPULoadTests {
    @Test func computesPerCoreAndTotalBusyPercent() {
        let before = [CPUTicks(user: 100, system: 50, idle: 850, nice: 0), CPUTicks(user: 0, system: 0, idle: 1000, nice: 0)]
        let after = [CPUTicks(user: 150, system: 75, idle: 875, nice: 0), CPUTicks(user: 10, system: 0, idle: 1090, nice: 0)]
        let usage = CPULoad.usage(from: before, to: after)
        #expect(usage?.cores == [75, 10])
        #expect(usage?.total == 42.5)
    }

    @Test func countsNiceAsBusy() {
        let usage = CPULoad.usage(from: [CPUTicks(user: 0, system: 0, idle: 0, nice: 0)],
                                  to: [CPUTicks(user: 0, system: 0, idle: 50, nice: 50)])
        #expect(usage?.total == 50)
    }

    @Test func noTicksMeansZeroNotNaN() {
        let ticks = [CPUTicks(user: 5, system: 5, idle: 5, nice: 0)]
        #expect(CPULoad.usage(from: ticks, to: ticks)?.total == 0)
    }

    @Test func startsAgainWhenCountersGoBackwardsOrCoresChange() {
        let high = [CPUTicks(user: 100, system: 100, idle: 100, nice: 0)]
        let low = [CPUTicks(user: 1, system: 1, idle: 1, nice: 0)]
        #expect(CPULoad.usage(from: high, to: low) == nil)
        #expect(CPULoad.usage(from: high, to: high + high) == nil)
        #expect(CPULoad.usage(from: [], to: []) == nil)
    }

    @Test func roundsToOneDecimal() {
        #expect(CPULoad.rounded(33.333) == 33.3)
        #expect(CPULoad.rounded(66.666) == 66.7)
    }
}

struct MemoryUsageTests {
    @Test func usedIsAppPlusWiredPlusCompressed() {
        let counts = VMPageCounts(pageSize: 16_384, internalPages: 300_000, purgeable: 20_000, wired: 100_000, compressed: 50_000)
        let sample = MemoryUsage.sample(counts: counts, totalBytes: 17_179_869_184, swapUsedBytes: 1_024, pressureLevel: 1)
        #expect(sample.app == 280_000 * 16_384)
        #expect(sample.wired == 100_000 * 16_384)
        #expect(sample.compressed == 50_000 * 16_384)
        #expect(sample.used == 430_000 * 16_384)
        #expect(sample.swapUsed == 1_024)
        #expect(sample.pressure == "normal")
    }

    @Test func neverReportsMoreThanTheMacHas() {
        let counts = VMPageCounts(pageSize: 16_384, internalPages: 2_000_000, purgeable: 0, wired: 0, compressed: 0)
        #expect(MemoryUsage.sample(counts: counts, totalBytes: 1_000, swapUsedBytes: 0, pressureLevel: 1).used == 1_000)
    }

    @Test func purgeableLargerThanInternalCountsAsZero() {
        let counts = VMPageCounts(pageSize: 4_096, internalPages: 10, purgeable: 20, wired: 0, compressed: 0)
        #expect(MemoryUsage.sample(counts: counts, totalBytes: 1 << 30, swapUsedBytes: 0, pressureLevel: 1).app == 0)
    }

    @Test func namesThePressureLevels() {
        #expect(MemoryUsage.pressureName(1) == "normal")
        #expect(MemoryUsage.pressureName(2) == "warn")
        #expect(MemoryUsage.pressureName(4) == "critical")
        #expect(MemoryUsage.pressureName(0) == "normal")
    }
}
```

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

Run: `make test FILTER="AccessPolicyTests|CPULoadTests|MemoryUsageTests|ServerMessageTests|ClientMessageTests"`
Expected: FAIL — `cannot find 'AccessPolicy' in scope` ve benzerleri.

- [ ] **Step 3: Uygulamayı yaz**

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
    /// `ok`, `not-on-cable`, or `unauthenticated` (never sent: such clients get no messages).
    public var reason: String

    public init(streaming: Bool, commands: Bool, reason: String) {
        self.streaming = streaming
        self.commands = commands
        self.reason = reason
    }

    public static let granted = Access(streaming: true, commands: true, reason: "ok")
    public static let notOnCable = Access(streaming: false, commands: false, reason: "not-on-cable")
    public static let unauthenticated = Access(streaming: false, commands: false, reason: "unauthenticated")
}

/// Design §5 "AccessPolicy". A connection on the iPhone's USB link can only come from a phone that is
/// plugged into this Mac and trusts it, so in cable mode that is the test.
public enum AccessPolicy {
    public static func decide(mode: AccessMode, clientOnUSB: Bool, authenticated: Bool) -> Access {
        guard authenticated else { return .unauthenticated }
        switch mode {
        case .always: return .granted
        case .cable: return clientOnUSB ? .granted : .notOnCable
        }
    }
}
```

`Sources/PhoneBoxCore/CPULoad.swift`:

```swift
/// One core's tick counters as `host_processor_info` reports them.
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    var busy: UInt64 { user + system + nice }
    var total: UInt64 { busy + idle }
}

/// The `cpu` field of a snapshot (design §6).
public struct CPUSample: Equatable, Codable, Sendable {
    /// Busy percentage of all cores together, 0…100.
    public var total: Double
    /// Busy percentage of each core, in the order macOS numbers them.
    public var cores: [Double]
    /// How many performance cores the Mac has (`hw.perflevel0.logicalcpu`); 0 when macOS does not say.
    public var pCores: Int
    /// Load average over 1, 5 and 15 minutes.
    public var load: [Double]

    public init(total: Double, cores: [Double], pCores: Int, load: [Double]) {
        self.total = total
        self.cores = cores
        self.pCores = pCores
        self.load = load
    }
}

public enum CPULoad {
    /// Busy percentages between two readings. Nil when the core count changed or a counter went backwards
    /// (after sleep or a counter wrap), so the caller starts again from the new reading.
    public static func usage(from previous: [CPUTicks], to current: [CPUTicks]) -> (total: Double, cores: [Double])? {
        guard !current.isEmpty, previous.count == current.count else { return nil }
        var cores: [Double] = []
        var busySum: UInt64 = 0
        var totalSum: UInt64 = 0
        for (old, new) in zip(previous, current) {
            guard new.user >= old.user, new.system >= old.system, new.idle >= old.idle, new.nice >= old.nice
            else { return nil }
            let busy = new.busy - old.busy
            let total = new.total - old.total
            cores.append(percent(busy, of: total))
            busySum += busy
            totalSum += total
        }
        return (percent(busySum, of: totalSum), cores)
    }

    private static func percent(_ part: UInt64, of whole: UInt64) -> Double {
        whole == 0 ? 0 : rounded(Double(part) / Double(whole) * 100)
    }

    /// One decimal place: enough for the dashboard and keeps the JSON short.
    public static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
```

`Sources/PhoneBoxCore/MemoryUsage.swift`:

```swift
/// The page counts from `host_statistics64(HOST_VM_INFO64)` that "Memory Used" is built from.
public struct VMPageCounts: Equatable, Sendable {
    public var pageSize: UInt64
    /// `internal_page_count`: anonymous memory of apps.
    public var internalPages: UInt64
    /// `purgeable_count`: memory apps said the system may throw away.
    public var purgeable: UInt64
    /// `wire_count`
    public var wired: UInt64
    /// `compressor_page_count`: pages the compressor holds.
    public var compressed: UInt64

    public init(pageSize: UInt64, internalPages: UInt64, purgeable: UInt64, wired: UInt64, compressed: UInt64) {
        self.pageSize = pageSize
        self.internalPages = internalPages
        self.purgeable = purgeable
        self.wired = wired
        self.compressed = compressed
    }
}

/// The `mem` field of a snapshot (design §6). Bytes.
public struct MemorySample: Equatable, Codable, Sendable {
    public var used: UInt64
    public var total: UInt64
    public var app: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var swapUsed: UInt64
    /// `normal`, `warn` or `critical`.
    public var pressure: String

    public init(used: UInt64, total: UInt64, app: UInt64, wired: UInt64, compressed: UInt64, swapUsed: UInt64, pressure: String) {
        self.used = used
        self.total = total
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.swapUsed = swapUsed
        self.pressure = pressure
    }
}

public enum MemoryUsage {
    /// "Memory Used" the way Activity Monitor counts it: app memory + wired + compressed.
    public static func sample(counts: VMPageCounts, totalBytes: UInt64, swapUsedBytes: UInt64, pressureLevel: Int) -> MemorySample {
        let appPages = counts.internalPages > counts.purgeable ? counts.internalPages - counts.purgeable : 0
        let app = appPages * counts.pageSize
        let wired = counts.wired * counts.pageSize
        let compressed = counts.compressed * counts.pageSize
        return MemorySample(
            used: min(app + wired + compressed, totalBytes), total: totalBytes, app: app, wired: wired,
            compressed: compressed, swapUsed: swapUsedBytes, pressure: pressureName(pressureLevel))
    }

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    public static func pressureName(_ level: Int) -> String {
        switch level {
        case 4: "critical"
        case 2: "warn"
        default: "normal"
        }
    }
}
```

`Sources/PhoneBoxCore/Snapshot.swift`:

```swift
/// One second of the Mac, as the phone receives it (design §6). A metric that could not be read is left out
/// of the JSON; the dashboard shows "—" for it. Plan 3 adds the other metrics as further optional fields.
public struct Snapshot: Equatable, Codable, Sendable {
    /// Milliseconds since 1970.
    public var t: Int64
    public var cpu: CPUSample?
    public var mem: MemorySample?

    public init(t: Int64, cpu: CPUSample? = nil, mem: MemorySample? = nil) {
        self.t = t
        self.cpu = cpu
        self.mem = mem
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

    /// Compact JSON with sorted keys.
    public func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try! encoder.encode(self), as: UTF8.self)
    }
}

extension ServerMessage: Encodable {
    private enum Keys: String, CodingKey {
        case v, type, nonce, app, mode, access, streaming, commands, reason, t, cpu, mem, seq, ok, error
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

Run: `make test FILTER="AccessPolicyTests|CPULoadTests|MemoryUsageTests|ServerMessageTests|ClientMessageTests"`
Expected: `Test run with 21 tests in 5 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/PhoneBoxCore/AccessPolicy.swift Sources/PhoneBoxCore/CPULoad.swift Sources/PhoneBoxCore/MemoryUsage.swift Sources/PhoneBoxCore/Snapshot.swift Sources/PhoneBoxCore/Messages.swift Tests/PhoneBoxCoreTests/AccessPolicyTests.swift Tests/PhoneBoxCoreTests/MetricsMathTests.swift Tests/PhoneBoxCoreTests/MessagesTests.swift
git commit -m "Add the access rule, CPU and memory maths and the protocol messages" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Oturum: kimlik doğrulama, imzalı komutlar, sıra ve hız sınırı

**Files:**
- Create: `Sources/PhoneBoxCore/Session.swift`
- Test: `Tests/PhoneBoxCoreTests/SessionTests.swift`

**Interfaces:**
- Consumes: `PairingKey`, `MessageAuth`, `ClientMessage`, `ServerMessage`
- Produces: `struct Session { nonce; isAuthenticated; init(nonce:); static makeNonce(); mutating receive(_:key:commandsAllowed:now:) -> Outcome }`,
  `Session.Outcome { authenticated, command(seq:name:args:), reply(ServerMessage), close(code:reason:) }`,
  sabitler `authFailedCode = 4001`, `policyViolationCode = 1008`, `maxCommandsPerSecond = 10`.

- [ ] **Step 1: Başarısız testi yaz**

`Tests/PhoneBoxCoreTests/SessionTests.swift`:

```swift
import Foundation
import Testing
@testable import PhoneBoxCore

struct SessionTests {
    let key = PairingKey.generate()
    let now = Date(timeIntervalSince1970: 1_000)

    func authMessage(_ session: Session, key: PairingKey) -> String {
        let mac = MessageAuth.hmacHex(key: key.bytes, message: MessageAuth.authMessage(nonce: session.nonce))
        return #"{"v":1,"type":"auth","mac":"\#(mac)"}"#
    }

    func commandMessage(_ session: Session, seq: Int, name: String = "mute", args: String = #"{"on":true}"#) -> String {
        let mac = MessageAuth.hmacHex(key: key.bytes,
                                      message: MessageAuth.commandMessage(nonce: session.nonce, seq: seq, name: name, args: args))
        let escapedArgs = args.replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"v":1,"type":"cmd","seq":\#(seq),"name":"\#(name)","args":"\#(escapedArgs)","mac":"\#(mac)"}"#
    }

    func authenticated() -> Session {
        var session = Session(nonce: Session.makeNonce())
        _ = session.receive(authMessage(session, key: key), key: key, commandsAllowed: true, now: now)
        return session
    }

    @Test func noncesAre32HexDigitsAndDiffer() {
        let nonce = Session.makeNonce()
        #expect(nonce.count == 32)
        #expect(Hex.decode(nonce) != nil)
        #expect(nonce != Session.makeNonce())
    }

    @Test func authenticatesWithTheRightKey() {
        var session = Session(nonce: Session.makeNonce())
        #expect(session.receive(authMessage(session, key: key), key: key, commandsAllowed: true, now: now) == .authenticated)
        #expect(session.isAuthenticated)
    }

    @Test func closesWith4001ForAWrongKey() {
        var session = Session(nonce: Session.makeNonce())
        let outcome = session.receive(authMessage(session, key: PairingKey.generate()), key: key, commandsAllowed: true, now: now)
        #expect(outcome == .close(code: 4001, reason: "bad key"))
        #expect(!session.isAuthenticated)
    }

    @Test func refusesCommandsBeforeAuthentication() {
        var session = Session(nonce: Session.makeNonce())
        #expect(session.receive(commandMessage(session, seq: 1), key: key, commandsAllowed: true, now: now)
            == .close(code: 4001, reason: "not authenticated"))
    }

    @Test func passesSignedFreshCommands() {
        var session = authenticated()
        #expect(session.receive(commandMessage(session, seq: 1), key: key, commandsAllowed: true, now: now)
            == .command(seq: 1, name: "mute", args: #"{"on":true}"#))
        #expect(session.receive(commandMessage(session, seq: 5), key: key, commandsAllowed: true, now: now)
            == .command(seq: 5, name: "mute", args: #"{"on":true}"#))
    }

    @Test func closesOnABadSignature() {
        var session = authenticated()
        let forged = commandMessage(session, seq: 1).replacingOccurrences(of: #""name":"mute""#, with: #""name":"sleep""#)
        #expect(session.receive(forged, key: key, commandsAllowed: true, now: now)
            == .close(code: 1008, reason: "bad signature"))
    }

    @Test func closesOnAReplayedOrOlderSequenceNumber() {
        var session = authenticated()
        _ = session.receive(commandMessage(session, seq: 3), key: key, commandsAllowed: true, now: now)
        #expect(session.receive(commandMessage(session, seq: 3), key: key, commandsAllowed: true, now: now)
            == .close(code: 1008, reason: "old sequence number"))
    }

    @Test func answersNotAllowedWhenAccessIsClosed() {
        var session = authenticated()
        #expect(session.receive(commandMessage(session, seq: 1), key: key, commandsAllowed: false, now: now)
            == .reply(.ack(seq: 1, ok: false, error: "not-allowed")))
    }

    @Test func closesAfterTenCommandsInOneSecond() {
        var session = authenticated()
        for seq in 1...10 {
            #expect(session.receive(commandMessage(session, seq: seq), key: key, commandsAllowed: true, now: now)
                == .command(seq: seq, name: "mute", args: #"{"on":true}"#))
        }
        #expect(session.receive(commandMessage(session, seq: 11), key: key, commandsAllowed: true, now: now)
            == .close(code: 1008, reason: "too many commands"))
    }

    @Test func theRateLimitWindowMoves() {
        var session = authenticated()
        for seq in 1...10 {
            _ = session.receive(commandMessage(session, seq: seq), key: key, commandsAllowed: true, now: now)
        }
        #expect(session.receive(commandMessage(session, seq: 11), key: key, commandsAllowed: true, now: now.addingTimeInterval(1.1))
            == .command(seq: 11, name: "mute", args: #"{"on":true}"#))
    }

    @Test func closesOnJunkAndOnASecondAuth() {
        var session = authenticated()
        #expect(session.receive("{", key: key, commandsAllowed: true, now: now) == .close(code: 1008, reason: "bad message"))
        var again = authenticated()
        #expect(again.receive(authMessage(again, key: key), key: key, commandsAllowed: true, now: now)
            == .close(code: 1008, reason: "already authenticated"))
    }
}
```

- [ ] **Step 2: Testin başarısız olduğunu gör**

Run: `make test FILTER=SessionTests`
Expected: FAIL — `cannot find 'Session' in scope`.

- [ ] **Step 3: Uygulamayı yaz**

`Sources/PhoneBoxCore/Session.swift`:

```swift
import Foundation

/// The protocol state of one WebSocket connection (design §5): authentication, command signatures,
/// increasing sequence numbers and the rate limit. Pure, so every rule is unit-tested.
public struct Session: Sendable {
    public static let authFailedCode: UInt16 = 4001
    public static let policyViolationCode: UInt16 = 1008
    public static let maxCommandsPerSecond = 10

    public let nonce: String
    public private(set) var isAuthenticated = false
    private var lastSeq = 0
    private var recentCommands: [Date] = []

    public init(nonce: String) {
        self.nonce = nonce
    }

    /// 16 random bytes as 32 hex digits.
    public static func makeNonce() -> String {
        var generator = SystemRandomNumberGenerator()
        return Hex.encode((0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    public enum Outcome: Equatable, Sendable {
        /// The phone proved it holds the key.
        case authenticated
        /// A signed, fresh command the caller should run.
        case command(seq: Int, name: String, args: String)
        /// Send this and keep the connection.
        case reply(ServerMessage)
        /// Close the connection with this WebSocket close code.
        case close(code: UInt16, reason: String)
    }

    public mutating func receive(_ text: String, key: PairingKey, commandsAllowed: Bool, now: Date) -> Outcome {
        guard let message = ClientMessage.parse(text) else {
            return .close(code: Self.policyViolationCode, reason: "bad message")
        }
        switch message {
        case let .auth(mac):
            guard !isAuthenticated else { return .close(code: Self.policyViolationCode, reason: "already authenticated") }
            guard MessageAuth.isValid(signature: mac, key: key.bytes, message: MessageAuth.authMessage(nonce: nonce)) else {
                return .close(code: Self.authFailedCode, reason: "bad key")
            }
            isAuthenticated = true
            return .authenticated

        case let .command(seq, name, args, mac):
            guard isAuthenticated else { return .close(code: Self.authFailedCode, reason: "not authenticated") }
            let signed = MessageAuth.commandMessage(nonce: nonce, seq: seq, name: name, args: args)
            guard MessageAuth.isValid(signature: mac, key: key.bytes, message: signed) else {
                return .close(code: Self.policyViolationCode, reason: "bad signature")
            }
            guard seq > lastSeq else { return .close(code: Self.policyViolationCode, reason: "old sequence number") }
            lastSeq = seq
            recentCommands = recentCommands.filter { now.timeIntervalSince($0) < 1 }
            guard recentCommands.count < Self.maxCommandsPerSecond else {
                return .close(code: Self.policyViolationCode, reason: "too many commands")
            }
            recentCommands.append(now)
            guard commandsAllowed else { return .reply(.ack(seq: seq, ok: false, error: "not-allowed")) }
            return .command(seq: seq, name: name, args: args)
        }
    }
}
```

- [ ] **Step 4: Testin geçtiğini gör**

Run: `make test FILTER=SessionTests`
Expected: `Test run with 11 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/PhoneBoxCore/Session.swift Tests/PhoneBoxCoreTests/SessionTests.swift
git commit -m "Add the per-connection protocol session" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: HTTP ve WebSocket ayrıştırma

**Files:**
- Create: `Sources/PhoneBoxCore/HTTP.swift`, `Sources/PhoneBoxCore/WebSocket.swift`
- Test: `Tests/PhoneBoxCoreTests/HTTPTests.swift`, `Tests/PhoneBoxCoreTests/WebSocketTests.swift`

**Interfaces:**
- Produces: `struct HTTPRequestHead { method, path, headers }`; `HTTPRequestParser.parse(_:) -> .incomplete | .tls |
  .invalid | .complete(HTTPRequestHead)`; `ByteRange.resolve(header:length:) -> .full | .partial(ClosedRange<Int>) |
  .unsatisfiable`; `HTTPResponse.make(...)`, `HTTPResponse.file(_:name:range:)`, `.notFound`, `.badRequest`, `.busy`;
  `WebSocketHandshake.acceptValue(for:)`, `.response(for:)`; `enum WebSocketOpcode`; `struct WebSocketFrame { opcode,
  payload, text }`; `WebSocketCodec.encode(_:_:)`, `.text(_:)`, `.close(code:reason:)`; `struct WebSocketDecoder {
  mutating append(_:) throws -> [WebSocketFrame] }`.

- [ ] **Step 1: Başarısız testleri yaz**

`Tests/PhoneBoxCoreTests/HTTPTests.swift`:

```swift
import Foundation
import Testing
@testable import PhoneBoxCore

struct HTTPRequestParserTests {
    @Test func parsesARequestHead() {
        let request = "GET /app.js?x=1 HTTP/1.1\r\nHost: mac.local:4747\r\nRange: bytes=0-1\r\n\r\n"
        #expect(HTTPRequestParser.parse(Data(request.utf8))
            == .complete(HTTPRequestHead(method: "GET", path: "/app.js", headers: ["host": "mac.local:4747", "range": "bytes=0-1"])))
    }

    @Test func waitsForTheEndOfTheHead() {
        #expect(HTTPRequestParser.parse(Data("GET / HTTP/1.1\r\nHost: x\r\n".utf8)) == .incomplete)
    }

    @Test func spotsATLSHandshake() {
        #expect(HTTPRequestParser.parse(Data([0x16, 0x03, 0x01, 0x02, 0x00])) == .tls)
    }

    @Test func rejectsJunkAndHugeHeads() {
        #expect(HTTPRequestParser.parse(Data("HELLO\r\n\r\n".utf8)) == .invalid)
        #expect(HTTPRequestParser.parse(Data("GET / HTTP/1.1\r\nno colon here\r\n\r\n".utf8)) == .invalid)
        #expect(HTTPRequestParser.parse(Data(repeating: 0x41, count: HTTPRequestParser.maxHeadBytes + 1)) == .invalid)
    }
}

struct ByteRangeTests {
    @Test func resolvesTheFormsIOSSends() {
        #expect(ByteRange.resolve(header: "bytes=0-1", length: 2854) == .partial(0...1))
        #expect(ByteRange.resolve(header: "bytes=0-2853", length: 2854) == .partial(0...2853))
        #expect(ByteRange.resolve(header: "bytes=0-", length: 2854) == .partial(0...2853))
    }

    @Test func clampsTheEndAndHandlesSuffixes() {
        #expect(ByteRange.resolve(header: "bytes=10-99999", length: 100) == .partial(10...99))
        #expect(ByteRange.resolve(header: "bytes=-10", length: 100) == .partial(90...99))
        #expect(ByteRange.resolve(header: "bytes=-500", length: 100) == .partial(0...99))
    }

    @Test func refusesRangesOutsideTheBody() {
        #expect(ByteRange.resolve(header: "bytes=100-", length: 100) == .unsatisfiable)
        #expect(ByteRange.resolve(header: "bytes=50-10", length: 100) == .unsatisfiable)
        #expect(ByteRange.resolve(header: "bytes=-0", length: 100) == .unsatisfiable)
    }

    @Test func servesTheWholeBodyOtherwise() {
        #expect(ByteRange.resolve(header: nil, length: 100) == .full)
        #expect(ByteRange.resolve(header: "bytes=0-1,5-6", length: 100) == .full)
        #expect(ByteRange.resolve(header: "items=0-1", length: 100) == .full)
    }
}

struct HTTPResponseTests {
    @Test func answersARangeWith206() {
        let response = String(decoding: HTTPResponse.file(Data("abcdef".utf8), name: "v.mp4", range: "bytes=1-2"), as: UTF8.self)
        #expect(response.hasPrefix("HTTP/1.1 206 Partial Content\r\n"))
        #expect(response.contains("Content-Type: video/mp4\r\n"))
        #expect(response.contains("Content-Range: bytes 1-2/6\r\n"))
        #expect(response.contains("Content-Length: 2\r\n"))
        #expect(response.hasSuffix("\r\n\r\nbc"))
    }

    @Test func answersWithoutARangeWith200() {
        let response = String(decoding: HTTPResponse.file(Data("<p>".utf8), name: "index.html", range: nil), as: UTF8.self)
        #expect(response.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(response.contains("Content-Type: text/html; charset=utf-8\r\n"))
        #expect(response.hasSuffix("\r\n\r\n<p>"))
    }

    @Test func answersAnImpossibleRangeWith416() {
        let response = String(decoding: HTTPResponse.file(Data("ab".utf8), name: "v.mp4", range: "bytes=5-"), as: UTF8.self)
        #expect(response.hasPrefix("HTTP/1.1 416 Range Not Satisfiable\r\n"))
        #expect(response.contains("Content-Range: bytes */2\r\n"))
    }
}
```

`Tests/PhoneBoxCoreTests/WebSocketTests.swift`:

```swift
import Foundation
import Testing
@testable import PhoneBoxCore

struct WebSocketTests {
    /// A frame as a browser sends it: final, masked.
    func clientFrame(_ opcode: UInt8, _ payload: [UInt8], mask: [UInt8] = [0x11, 0x22, 0x33, 0x44]) -> Data {
        var frame: [UInt8] = [0x80 | opcode]
        if payload.count < 126 {
            frame.append(0x80 | UInt8(payload.count))
        } else {
            frame.append(0x80 | 126)
            frame += [UInt8(payload.count >> 8), UInt8(payload.count & 0xff)]
        }
        frame += mask
        frame += payload.enumerated().map { $0.element ^ mask[$0.offset % 4] }
        return Data(frame)
    }

    /// The example in RFC 6455 section 1.3.
    @Test func computesTheAcceptValue() {
        #expect(WebSocketHandshake.acceptValue(for: "dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    @Test func encodesShortAndMediumTextFrames() {
        #expect(WebSocketCodec.text("Hi") == Data([0x81, 0x02, 0x48, 0x69]))
        let medium = WebSocketCodec.text(String(repeating: "a", count: 300))
        #expect(Array(medium.prefix(4)) == [0x81, 126, 0x01, 0x2c])
        #expect(medium.count == 304)
    }

    @Test func encodesCloseWithCode() {
        #expect(WebSocketCodec.close(code: 4001, reason: "x") == Data([0x88, 0x03, 0x0f, 0xa1, 0x78]))
    }

    @Test func decodesMaskedTextFrames() throws {
        var decoder = WebSocketDecoder()
        let frames = try decoder.append(clientFrame(0x1, Array("hello".utf8)))
        #expect(frames.map(\.text) == ["hello"])
    }

    @Test func waitsForAFrameThatArrivesInPieces() throws {
        var decoder = WebSocketDecoder()
        let frame = clientFrame(0x1, Array(String(repeating: "b", count: 200).utf8))
        #expect(try decoder.append(frame.prefix(3)).isEmpty)
        #expect(try decoder.append(frame.dropFirst(3).prefix(50)).isEmpty)
        let frames = try decoder.append(frame.dropFirst(53))
        #expect(frames.first?.text == String(repeating: "b", count: 200))
    }

    @Test func decodesSeveralFramesInOneRead() throws {
        var decoder = WebSocketDecoder()
        let frames = try decoder.append(clientFrame(0x1, Array("a".utf8)) + clientFrame(0x9, [1, 2]))
        #expect(frames.map(\.opcode) == [0x1, 0x9])
        #expect(frames[1].payload == Data([1, 2]))
    }

    @Test func rejectsUnmaskedFragmentedAndHugeFrames() {
        var unmasked = WebSocketDecoder()
        #expect(throws: WebSocketDecoder.DecodeError.unmasked) { try unmasked.append(Data([0x81, 0x01, 0x41])) }

        var fragmented = WebSocketDecoder()
        var first = clientFrame(0x1, [0x41])
        first[0] = 0x01
        #expect(throws: WebSocketDecoder.DecodeError.fragmented) { try fragmented.append(first) }

        var huge = WebSocketDecoder()
        let header = Data([0x81, 0x80 | 127, 0, 0, 0, 0, 0, 0x10, 0, 0])
        #expect(throws: WebSocketDecoder.DecodeError.tooLarge) { try huge.append(header) }
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu gör**

Run: `make test FILTER="HTTPRequestParserTests|ByteRangeTests|HTTPResponseTests|WebSocketTests"`
Expected: FAIL — `cannot find 'HTTPRequestParser' in scope` ve benzerleri.

- [ ] **Step 3: Uygulamayı yaz**

`Sources/PhoneBoxCore/HTTP.swift`:

```swift
import Foundation

/// The request line and headers of one HTTP/1.1 request.
public struct HTTPRequestHead: Equatable, Sendable {
    public var method: String
    /// Without the query string.
    public var path: String
    /// Header names lowercased.
    public var headers: [String: String]

    public init(method: String, path: String, headers: [String: String]) {
        self.method = method
        self.path = path
        self.headers = headers
    }
}

public enum HTTPRequestParser {
    public static let maxHeadBytes = 16_384

    public enum Result: Equatable, Sendable {
        case incomplete
        /// The first byte is a TLS handshake record (0x16): the browser tried HTTPS. Close at once so it
        /// falls back to http:// (spike: Safari tries HTTPS for an address typed without a scheme).
        case tls
        case invalid
        case complete(HTTPRequestHead)
    }

    public static func parse(_ data: Data) -> Result {
        if data.first == 0x16 { return .tls }
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxHeadBytes ? .invalid : .incomplete
        }
        let lines = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let target = String(parts[1])
        let path = target.firstIndex(of: "?").map { String(target[..<$0]) } ?? target
        return .complete(HTTPRequestHead(method: String(parts[0]), path: path, headers: headers))
    }
}

/// `Range: bytes=…` for the keep-awake video: iOS plays a <video> only from a server that answers byte
/// ranges with 206 (spike).
public enum ByteRange {
    public enum Result: Equatable, Sendable {
        case full
        case partial(ClosedRange<Int>)
        case unsatisfiable
    }

    /// Handles `bytes=a-b`, `bytes=a-` and `bytes=-n`. Anything else, including several ranges, gets the
    /// whole body, which HTTP allows.
    public static func resolve(header: String?, length: Int) -> Result {
        guard let header, header.hasPrefix("bytes="), length > 0 else { return .full }
        let spec = header.dropFirst(6)
        guard !spec.contains(","), let dash = spec.firstIndex(of: "-") else { return .full }
        let startText = spec[..<dash]
        let endText = spec[spec.index(after: dash)...]
        if startText.isEmpty {
            guard let suffix = Int(endText), suffix > 0 else { return .unsatisfiable }
            return .partial(max(0, length - suffix)...(length - 1))
        }
        guard let start = Int(startText), start >= 0 else { return .full }
        guard start < length else { return .unsatisfiable }
        let end = endText.isEmpty ? length - 1 : min(Int(endText) ?? length - 1, length - 1)
        guard end >= start else { return .unsatisfiable }
        return .partial(start...end)
    }
}

public enum HTTPResponse {
    public static let contentTypes = [
        "html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8", "mp4": "video/mp4", "png": "image/png", "json": "application/json",
    ]

    public static func make(status: String, contentType: String, body: Data, extraHeaders: [String] = []) -> Data {
        var head = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\n"
        head += "Accept-Ranges: bytes\r\nCache-Control: no-store\r\nConnection: close\r\n"
        for header in extraHeaders { head += header + "\r\n" }
        return Data((head + "\r\n").utf8) + body
    }

    /// A file's response for a GET with an optional Range header.
    public static func file(_ body: Data, name: String, range: String?) -> Data {
        let type = contentTypes[(name as NSString).pathExtension.lowercased()] ?? "application/octet-stream"
        switch ByteRange.resolve(header: range, length: body.count) {
        case .full:
            return make(status: "200 OK", contentType: type, body: body)
        case let .partial(bounds):
            return make(status: "206 Partial Content", contentType: type,
                        body: body.subdata(in: bounds.lowerBound..<(bounds.upperBound + 1)),
                        extraHeaders: ["Content-Range: bytes \(bounds.lowerBound)-\(bounds.upperBound)/\(body.count)"])
        case .unsatisfiable:
            return make(status: "416 Range Not Satisfiable", contentType: "text/plain", body: Data(),
                        extraHeaders: ["Content-Range: bytes */\(body.count)"])
        }
    }

    public static let notFound = make(status: "404 Not Found", contentType: "text/plain", body: Data("not found".utf8))
    public static let badRequest = make(status: "400 Bad Request", contentType: "text/plain", body: Data("bad request".utf8))
    public static let busy = make(status: "503 Service Unavailable", contentType: "text/plain", body: Data("too many phones".utf8))
}
```

`Sources/PhoneBoxCore/WebSocket.swift`:

```swift
import CryptoKit
import Foundation

/// RFC 6455, just what the dashboard needs: text frames, ping/pong and close; no fragmentation, no extensions.
public enum WebSocketHandshake {
    public static func acceptValue(for key: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))
        return Data(digest).base64EncodedString()
    }

    public static func response(for key: String) -> Data {
        Data(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
              + "Sec-WebSocket-Accept: \(acceptValue(for: key))\r\n\r\n").utf8)
    }
}

public enum WebSocketOpcode: UInt8, Sendable {
    case continuation = 0x0, text = 0x1, binary = 0x2, close = 0x8, ping = 0x9, pong = 0xA
}

public struct WebSocketFrame: Equatable, Sendable {
    public var opcode: UInt8
    public var payload: Data

    public init(opcode: UInt8, payload: Data) {
        self.opcode = opcode
        self.payload = payload
    }

    public var text: String? {
        opcode == WebSocketOpcode.text.rawValue ? String(data: payload, encoding: .utf8) : nil
    }
}

public enum WebSocketCodec {
    /// A server frame: final, unmasked.
    public static func encode(_ opcode: WebSocketOpcode, _ payload: Data) -> Data {
        var frame = Data([0x80 | opcode.rawValue])
        switch payload.count {
        case ..<126:
            frame.append(UInt8(payload.count))
        case ..<65_536:
            frame.append(126)
            frame.append(contentsOf: [UInt8(payload.count >> 8), UInt8(payload.count & 0xff)])
        default:
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) { frame.append(UInt8((payload.count >> shift) & 0xff)) }
        }
        return frame + payload
    }

    public static func text(_ string: String) -> Data {
        encode(.text, Data(string.utf8))
    }

    public static func close(code: UInt16, reason: String) -> Data {
        encode(.close, Data([UInt8(code >> 8), UInt8(code & 0xff)]) + Data(reason.utf8.prefix(120)))
    }
}

/// Turns the bytes a browser sends into frames. Browsers always mask their frames; an unmasked or
/// fragmented frame, or one over 64 KB, is a protocol error and the connection is closed.
public struct WebSocketDecoder: Sendable {
    public static let maxPayload = 65_536

    public enum DecodeError: Error, Equatable, Sendable {
        case unmasked, fragmented, tooLarge
    }

    private var buffer: [UInt8] = []

    public init() {}

    public mutating func append(_ data: Data) throws -> [WebSocketFrame] {
        buffer.append(contentsOf: data)
        var frames: [WebSocketFrame] = []
        while buffer.count >= 2 {
            let final = buffer[0] & 0x80 != 0
            let opcode = buffer[0] & 0x0f
            guard buffer[1] & 0x80 != 0 else { throw DecodeError.unmasked }
            var length = Int(buffer[1] & 0x7f)
            var offset = 2
            if length == 126 {
                guard buffer.count >= 4 else { break }
                length = Int(buffer[2]) << 8 | Int(buffer[3])
                offset = 4
            } else if length == 127 {
                guard buffer.count >= 10 else { break }
                length = buffer[2..<10].reduce(0) { $0 << 8 | Int($1) }
                offset = 10
            }
            guard length <= Self.maxPayload else { throw DecodeError.tooLarge }
            guard final, opcode != WebSocketOpcode.continuation.rawValue else { throw DecodeError.fragmented }
            guard buffer.count >= offset + 4 + length else { break }
            let mask = Array(buffer[offset..<(offset + 4)])
            let start = offset + 4
            var payload = Array(buffer[start..<(start + length)])
            for index in payload.indices { payload[index] ^= mask[index % 4] }
            frames.append(WebSocketFrame(opcode: opcode, payload: Data(payload)))
            buffer.removeFirst(start + length)
        }
        return frames
    }
}
```

- [ ] **Step 4: Bütün testlerin geçtiğini gör**

Run: `make test`
Expected: `Test run with 63 tests in 13 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/PhoneBoxCore/HTTP.swift Sources/PhoneBoxCore/WebSocket.swift Tests/PhoneBoxCoreTests/HTTPTests.swift Tests/PhoneBoxCoreTests/WebSocketTests.swift
git commit -m "Parse HTTP requests, byte ranges and WebSocket frames" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Uygulama hedefi: ayarlar, anahtar dosyası, metrik toplayıcılar ve örnekleyici

**Files:**
- Modify: `Package.swift` (uygulama hedefini ekle)
- Create: `Sources/PhoneBox/Log.swift`, `Sources/PhoneBox/Settings.swift`, `Sources/PhoneBox/PairingStore.swift`,
  `Sources/PhoneBox/Collectors/CPUCollector.swift`, `Sources/PhoneBox/Collectors/MemoryCollector.swift`,
  `Sources/PhoneBox/Sampler.swift`
- Create (geçici): `Sources/PhoneBox/main.swift` (Görev 9'da silinir)

**Interfaces:**
- Consumes: `PairingKey`, `AccessMode`, `CPULoad`, `CPUSample`, `MemoryUsage`, `Snapshot`
- Produces: `enum Log { app, server }`; `final class Settings { mode; port; hasEverPaired; static localHostName();
  personalURL(key:) }`; `enum PairingStore { fileURL; loadOrCreate(); reset() }`; `final class CPUCollector {
  reset(); sample() -> CPUSample? }`; `final class MemoryCollector { sample() -> MemorySample? }`;
  `final class Sampler { onSnapshot; isRunning; setRunning(_:); resetAfterWake() }`.

Bu görevdeki kod sistemle konuşur ve birim testi yoktur; doğrulama derleme ve Görev 10'daki çalıştırmadır.

- [ ] **Step 1: Uygulama hedefini pakete ekle**

`Package.swift`'in tamamını şununla değiştir:

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
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: Geçici giriş noktası**

Bir çalıştırılabilir hedefin giriş noktası olmalı; gerçeği (`PhoneBoxApp.swift`, `@main`) Görev 9'da gelir.
`Sources/PhoneBox/main.swift`:

```swift
// Temporary entry point; Task 9 replaces it with the real app.
print("PhoneBox")
```

- [ ] **Step 3: Log, ayarlar ve anahtar dosyası**

`Sources/PhoneBox/Log.swift`:

```swift
import os

/// `log stream --predicate 'subsystem == "com.phonebox.PhoneBox"'` shows these. Nothing is written to files.
enum Log {
    static let app = Logger(subsystem: "com.phonebox.PhoneBox", category: "app")
    static let server = Logger(subsystem: "com.phonebox.PhoneBox", category: "server")
}
```

`Sources/PhoneBox/Settings.swift`:

```swift
import Foundation
import PhoneBoxCore
import SystemConfiguration

/// The few choices PhoneBox remembers (design §8 "Menü çubuğu").
@MainActor
final class Settings {
    static let defaultPort: UInt16 = 4747
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var mode: AccessMode {
        get { AccessMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .cable }
        set { defaults.set(newValue.rawValue, forKey: "mode") }
    }

    /// `defaults write com.phonebox.PhoneBox port -int 4848` until the menu gets a port item (Plan 5).
    var port: UInt16 {
        let value = defaults.integer(forKey: "port")
        return (1024...65535).contains(value) ? UInt16(value) : Self.defaultPort
    }

    /// False until a phone has authenticated once; while false, plugging in an iPhone opens the QR window.
    var hasEverPaired: Bool {
        get { defaults.bool(forKey: "hasEverPaired") }
        set { defaults.set(newValue, forKey: "hasEverPaired") }
    }

    /// `Erens-MacBook-Pro` from System Settings → General → Sharing → Local hostname.
    static func localHostName() -> String {
        (SCDynamicStoreCopyLocalHostName(nil) as String?) ?? "localhost"
    }

    /// The personal link in the QR code (design §5). Always with `http://`: Safari tries HTTPS first for an
    /// address typed without a scheme (spike).
    func personalURL(key: PairingKey) -> String {
        "http://\(Self.localHostName()).local:\(port)/#k=\(key.base64URL)"
    }
}
```

`Sources/PhoneBox/PairingStore.swift`:

```swift
import Foundation
import PhoneBoxCore

/// Keeps the pairing key in `~/Library/Application Support/PhoneBox/pairing-key`, readable only by the user.
///
/// Not the keychain: PhoneBox is signed ad hoc, so macOS would ask for the keychain password after every update
/// (NotchBox does), and "nothing extra to do" is the point of PhoneBox. Anything that can read this file runs as
/// the user and could control the Mac anyway.
enum PairingStore {
    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhoneBox", isDirectory: true)
            .appendingPathComponent("pairing-key")
    }

    static func loadOrCreate() -> PairingKey {
        if let text = try? String(contentsOf: fileURL, encoding: .utf8),
           let key = PairingKey(base64URL: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return key
        }
        return reset()
    }

    /// A new key; every paired phone has to scan the new QR code.
    @discardableResult
    static func reset() -> PairingKey {
        let key = PairingKey.generate()
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try Data(key.base64URL.utf8).write(to: fileURL, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            Log.app.error("Could not save the pairing key: \(error.localizedDescription, privacy: .public)")
        }
        return key
    }
}
```

- [ ] **Step 4: CPU ve RAM toplayıcıları, örnekleyici**

`Sources/PhoneBox/Collectors/CPUCollector.swift`:

```swift
import Darwin
import PhoneBoxCore

/// Reads per-core tick counters and turns two readings into a `CPUSample` (design §6).
final class CPUCollector {
    private var previous: [CPUTicks]?

    /// Forget the last reading, e.g. after the Mac wakes: the next sample is nil instead of a jump.
    func reset() {
        previous = nil
    }

    func sample() -> CPUSample? {
        guard let current = Self.readTicks() else { return nil }
        defer { previous = current }
        guard let previous, let usage = CPULoad.usage(from: previous, to: current) else { return nil }
        return CPUSample(total: usage.total, cores: usage.cores, pCores: Self.performanceCores, load: Self.loadAverage())
    }

    static func readTicks() -> [CPUTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info
        else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        return (0..<Int(cpuCount)).map { core in
            let base = core * Int(CPU_STATE_MAX)
            func ticks(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[base + Int(state)])) }
            return CPUTicks(user: ticks(CPU_STATE_USER), system: ticks(CPU_STATE_SYSTEM),
                            idle: ticks(CPU_STATE_IDLE), nice: ticks(CPU_STATE_NICE))
        }
    }

    static let performanceCores: Int = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.perflevel0.logicalcpu", &value, &size, nil, 0) == 0 ? Int(value) : 0
    }()

    static func loadAverage() -> [Double] {
        var load = [Double](repeating: 0, count: 3)
        guard getloadavg(&load, 3) == 3 else { return [] }
        return load.map(CPULoad.rounded)
    }
}
```

`Sources/PhoneBox/Collectors/MemoryCollector.swift`:

```swift
import Darwin
import PhoneBoxCore

/// Reads the VM page counts, swap and memory pressure (design §6).
final class MemoryCollector {
    func sample() -> MemorySample? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS, Self.totalBytes > 0 else { return nil }
        let counts = VMPageCounts(
            pageSize: UInt64(vm_kernel_page_size), internalPages: UInt64(stats.internal_page_count),
            purgeable: UInt64(stats.purgeable_count), wired: UInt64(stats.wire_count),
            compressed: UInt64(stats.compressor_page_count))
        return MemoryUsage.sample(counts: counts, totalBytes: Self.totalBytes,
                                  swapUsedBytes: Self.swapUsedBytes(), pressureLevel: Self.pressureLevel())
    }

    static let totalBytes: UInt64 = {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        return sysctlbyname("hw.memsize", &value, &size, nil, 0) == 0 ? value : 0
    }()

    static func swapUsedBytes() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        return sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 ? usage.xsu_used : 0
    }

    static func pressureLevel() -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 ? Int(value) : 1
    }
}
```

`Sources/PhoneBox/Sampler.swift`:

```swift
import Foundation
import PhoneBoxCore

/// Builds a `Snapshot` once a second while at least one phone may receive data (design §4, §6).
@MainActor
final class Sampler {
    var onSnapshot: ((Snapshot) -> Void)?

    private var timer: Timer?
    private let cpu = CPUCollector()
    private let memory = MemoryCollector()

    var isRunning: Bool { timer != nil }

    func setRunning(_ running: Bool) {
        guard running != isRunning else { return }
        if running {
            cpu.reset()
            _ = cpu.sample()
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    /// After sleep the tick counters jumped; start over so the first value is not nonsense.
    func resetAfterWake() {
        cpu.reset()
    }

    private func tick() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        onSnapshot?(Snapshot(t: now, cpu: cpu.sample(), mem: memory.sample()))
    }
}
```

- [ ] **Step 5: Derle**

Run: `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"`
Expected: çıktı yok (Command Line Tools'un `ld: warning: search path … not found` uyarıları zararsızdır).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/PhoneBox
git commit -m "Add the app target with settings, the pairing key file and CPU and memory sampling" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: iPhone'u görmek: usbmuxd dinleyicisi ve USB arayüzleri

**Files:**
- Create: `Sources/PhoneBox/USBWatcher.swift`, `Sources/PhoneBox/USBLinks.swift`

**Interfaces:**
- Produces: `final class USBWatcher { onChange: ((Bool) -> Void)?; isAvailable; attachedDevices; hasIPhone; start() }`
  (olaylar ana iş parçacığında; `true` = bir iPhone takıldı); `enum USBLinks { iPhoneInterfaceNames() -> Set<String> }`.

- [ ] **Step 1: usbmuxd dinleyicisi**

`Sources/PhoneBox/USBWatcher.swift` (spike'taki `spike/usbwatch.swift`'in uygulama içi hali; bağlantı koparsa 5 sn'de
bir yeniden dener):

```swift
import Foundation

/// Listens to usbmuxd for iPhones plugged in and out (design §4; spike 5). PhoneBox uses it to open the QR
/// window the first time a phone is plugged in and to move Wi-Fi clients over to the cable; access itself
/// depends on the client's interface (`USBLinks`).
@MainActor
final class USBWatcher {
    /// Called on the main thread with `true` when an iPhone was just plugged in.
    var onChange: ((_ pluggedIn: Bool) -> Void)?
    private(set) var isAvailable = false
    private(set) var attachedDevices: Set<Int> = []

    var hasIPhone: Bool { !attachedDevices.isEmpty }

    func start() {
        let thread = Thread { [weak self] in Self.run(watcher: self) }
        thread.name = "PhoneBox usbmuxd"
        thread.start()
    }

    private func handle(_ message: [String: Any]) {
        let deviceID = message["DeviceID"] as? Int ?? -1
        switch message["MessageType"] as? String {
        case "Attached":
            let properties = message["Properties"] as? [String: Any] ?? [:]
            guard properties["ConnectionType"] as? String == "USB" else { return }
            attachedDevices.insert(deviceID)
            onChange?(true)
        case "Detached":
            guard attachedDevices.remove(deviceID) != nil else { return }
            onChange?(false)
        default:
            break
        }
    }

    private func setAvailable(_ available: Bool) {
        isAvailable = available
        if !available, !attachedDevices.isEmpty {
            attachedDevices.removeAll()
            onChange?(false)
        }
    }

    // MARK: usbmuxd, on a background thread

    private nonisolated static func run(watcher: USBWatcher?) {
        while true {
            let fd = connect()
            if fd >= 0 {
                send(fd, ["MessageType": "Listen", "ClientVersionString": "PhoneBox", "ProgName": "PhoneBox"])
                DispatchQueue.main.async { MainActor.assumeIsolated { watcher?.setAvailable(true) } }
                while let message = read(fd) {
                    DispatchQueue.main.async { MainActor.assumeIsolated { watcher?.handle(message) } }
                }
                close(fd)
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { watcher?.setAvailable(false) } }
            Thread.sleep(forTimeInterval: 5)
        }
    }

    private nonisolated static func connect() -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array("/var/run/usbmuxd".utf8) + [0]
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            close(fd)
            return -1
        }
        return fd
    }

    /// 16-byte little-endian header (length, version 1, message 8 = plist, tag) + XML plist.
    private nonisolated static func send(_ fd: Int32, _ message: [String: Any]) {
        guard let body = try? PropertyListSerialization.data(fromPropertyList: message, format: .xml, options: 0) else { return }
        var packet = Data()
        for value in [UInt32(16 + body.count), 1, 8, 1] {
            withUnsafeBytes(of: value.littleEndian) { packet.append(contentsOf: $0) }
        }
        packet.append(body)
        _ = packet.withUnsafeBytes { write(fd, $0.baseAddress, packet.count) }
    }

    private nonisolated static func read(_ fd: Int32) -> [String: Any]? {
        guard let header = readExactly(fd, 16) else { return nil }
        let length = Int(UInt32(littleEndian: header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
        guard length >= 16, length < 1 << 20, let body = readExactly(fd, length - 16) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: body, format: nil)) as? [String: Any] ?? [:]
    }

    private nonisolated static func readExactly(_ fd: Int32, _ count: Int) -> Data? {
        var data = Data(count: count)
        var received = 0
        while received < count {
            let n = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress! + received, count - received) }
            if n <= 0 { return nil }
            received += n
        }
        return data
    }
}
```

- [ ] **Step 2: iPhone USB arayüzleri**

`Sources/PhoneBox/USBLinks.swift`:

```swift
import Foundation
import IOKit

/// Which network interfaces are an iPhone's USB link (design §4). When a trusted iPhone is plugged in, macOS
/// gets one or more USB NCM interfaces from it (`anri*`, `en*`; spike); a connection that arrives on one of
/// them can only come from that cable. Names change from one plug-in to the next, so this asks IOKit each time.
enum USBLinks {
    static let appleVendorID = 0x05AC

    /// BSD names of the Ethernet interfaces that sit on an Apple USB device named iPhone or iPad.
    static func iPhoneInterfaceNames() -> Set<String> {
        var names = Set<String>()
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOEthernetInterface"), &iterator)
                == KERN_SUCCESS
        else { return names }
        defer { IOObjectRelease(iterator) }
        while case let interface = IOIteratorNext(iterator), interface != 0 {
            defer { IOObjectRelease(interface) }
            guard let name = property(interface, "BSD Name") as? String else { continue }
            if isOnIPhone(interface) { names.insert(name) }
        }
        return names
    }

    private static func isOnIPhone(_ interface: io_registry_entry_t) -> Bool {
        var current = interface
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }
        for _ in 0..<12 {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { return false }
            IOObjectRelease(current)
            current = parent
            if IOObjectConformsTo(current, "IOUSBHostDevice") != 0 {
                let vendor = property(current, "idVendor") as? Int ?? 0
                let product = property(current, "USB Product Name") as? String ?? ""
                return vendor == appleVendorID && (product.contains("iPhone") || product.contains("iPad"))
            }
        }
        return false
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
```

- [ ] **Step 3: Derle**

Run: `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"`
Expected: çıktı yok.

- [ ] **Step 4: Commit**

```bash
git add Sources/PhoneBox/USBWatcher.swift Sources/PhoneBox/USBLinks.swift
git commit -m "Watch for iPhones over usbmuxd and find their USB network links" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Sunucu: bağlantılar, dosyalar, WebSocket ve telefon oturumları

**Files:**
- Create: `Sources/PhoneBox/ClientConnection.swift`, `Sources/PhoneBox/DashboardServer.swift`,
  `Sources/PhoneBox/DashboardHub.swift`

**Interfaces:**
- Consumes: `HTTPRequestParser`, `HTTPResponse`, `WebSocketHandshake`, `WebSocketCodec`, `WebSocketDecoder`, `Session`,
  `AccessPolicy`, `ServerMessage`, `Snapshot`, `USBLinks.iPhoneInterfaceNames`, `Log`
- Produces: `final class ClientConnection { interfaceName; isWebSocket; start(); send(_ ServerMessage); close(code:reason:);
  cancel(); static interfaceName(of:) }`; `final class DashboardServer { State { stopped, listening(UInt16),
  failed(port:message:) }; onStateChange; state; start(port:); stop() }`; `final class DashboardHub { mode; canAccept;
  onStreamingChange; onClientsChange; onAuthenticated; onConnectionClosed; opened(_:); received(_:from:); closed(_:);
  broadcast(_:); replaceKey(_:); iPhonePluggedIn() }`.

- [ ] **Step 1: Tek bir tarayıcı bağlantısı**

`Sources/PhoneBox/ClientConnection.swift`:

```swift
import Foundation
import Network
import PhoneBoxCore

/// One TCP connection from a browser: an HTTP request for a dashboard file, or a WebSocket at `/ws`
/// (design §4 "Server"). Everything runs on the main queue.
@MainActor
final class ClientConnection {
    let connection: NWConnection
    /// The network interface the connection arrived on, e.g. `en8` for the iPhone's USB link or `en0` for Wi-Fi.
    private(set) var interfaceName: String?
    private(set) var isWebSocket = false

    private let webDirectory: URL
    private weak var hub: DashboardHub?
    private var head = Data()
    private var decoder = WebSocketDecoder()
    private var closed = false

    init(connection: NWConnection, webDirectory: URL, hub: DashboardHub) {
        self.connection = connection
        self.webDirectory = webDirectory
        self.hub = hub
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    self.interfaceName = Self.interfaceName(of: self.connection)
                    self.readHead()
                case .failed, .cancelled:
                    self.finish()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }

    /// The interface of the local end: link-local IPv6 addresses carry it (`fe80::…%en8`); otherwise the path's.
    static func interfaceName(of connection: NWConnection) -> String? {
        if case let .hostPort(host, _)? = connection.currentPath?.localEndpoint {
            switch host {
            case let .ipv6(address): if let name = address.interface?.name { return name }
            case let .ipv4(address): if let name = address.interface?.name { return name }
            default: break
            }
        }
        return connection.currentPath?.availableInterfaces.first { $0.type != .loopback }?.name
    }

    // MARK: HTTP

    private func readHead() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let data { self.head.append(data) }
                switch HTTPRequestParser.parse(self.head) {
                case .incomplete:
                    if isComplete || error != nil { self.cancel() } else { self.readHead() }
                case .tls:
                    self.cancel()
                case .invalid:
                    self.respond(HTTPResponse.badRequest)
                case let .complete(request):
                    self.route(request)
                }
            }
        }
    }

    private func route(_ request: HTTPRequestHead) {
        guard request.method == "GET" else { return respond(HTTPResponse.badRequest) }
        if request.path == "/ws" {
            guard request.headers["upgrade"]?.lowercased() == "websocket", let key = request.headers["sec-websocket-key"]
            else { return respond(HTTPResponse.badRequest) }
            guard let hub, hub.canAccept else { return respond(HTTPResponse.busy) }
            isWebSocket = true
            connection.send(content: WebSocketHandshake.response(for: key), completion: .contentProcessed { _ in })
            hub.opened(self)
            readFrames()
        } else {
            respond(fileResponse(path: request.path, range: request.headers["range"]))
        }
    }

    private func fileResponse(path: String, range: String?) -> Data {
        let name = path == "/" ? "index.html" : String(path.dropFirst())
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix("."),
              let body = try? Data(contentsOf: webDirectory.appendingPathComponent(name))
        else { return HTTPResponse.notFound }
        return HTTPResponse.file(body, name: name, range: range)
    }

    private func respond(_ response: Data) {
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        })
    }

    // MARK: WebSocket

    private func readFrames() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                do {
                    for frame in try self.decoder.append(data ?? Data()) {
                        self.handle(frame)
                        if self.closed { return }
                    }
                } catch {
                    return self.close(code: Session.policyViolationCode, reason: "bad frame")
                }
                if isComplete || error != nil { self.cancel() } else { self.readFrames() }
            }
        }
    }

    private func handle(_ frame: WebSocketFrame) {
        switch WebSocketOpcode(rawValue: frame.opcode) {
        case .text:
            guard let text = frame.text else { return close(code: Session.policyViolationCode, reason: "bad text") }
            hub?.received(text, from: self)
        case .ping:
            connection.send(content: WebSocketCodec.encode(.pong, frame.payload), completion: .contentProcessed { _ in })
        case .close:
            close(code: 1000, reason: "")
        default:
            break
        }
    }

    func send(_ message: ServerMessage) {
        guard isWebSocket, !closed else { return }
        connection.send(content: WebSocketCodec.text(message.json()), completion: .contentProcessed { _ in })
    }

    /// Sends a close frame, then drops the connection.
    func close(code: UInt16, reason: String) {
        guard !closed else { return }
        connection.send(content: WebSocketCodec.close(code: code, reason: reason), completion: .contentProcessed { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        })
        closed = true
    }

    func cancel() {
        connection.cancel()
        finish()
    }

    private func finish() {
        closed = true
        hub?.closed(self)
    }
}
```

- [ ] **Step 2: Dinleyici**

`Sources/PhoneBox/DashboardServer.swift`:

```swift
import Foundation
import Network

/// Listens on one TCP port (4747 by default) on every interface: Wi-Fi and the iPhone's USB link (design §4).
@MainActor
final class DashboardServer {
    enum State: Equatable {
        case stopped
        case listening(UInt16)
        case failed(port: UInt16, message: String)
    }

    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .stopped {
        didSet { onStateChange?(state) }
    }

    private let webDirectory: URL
    private let hub: DashboardHub
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: ClientConnection] = [:]

    init(webDirectory: URL, hub: DashboardHub) {
        self.webDirectory = webDirectory
        self.hub = hub
        hub.onConnectionClosed = { [weak self] connection in self?.connections[ObjectIdentifier(connection)] = nil }
    }

    func start(port: UInt16) {
        stop()
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: endpointPort)
        } catch {
            state = .failed(port: port, message: error.localizedDescription)
            return
        }
        listener.stateUpdateHandler = { [weak self] newState in
            MainActor.assumeIsolated {
                switch newState {
                case .ready:
                    Log.server.info("Listening on port \(port)")
                    self?.state = .listening(port)
                case let .failed(error):
                    Log.server.error("Listener failed: \(error.localizedDescription, privacy: .public)")
                    self?.state = .failed(port: port, message: error.localizedDescription)
                default:
                    break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        state = .stopped
    }

    private func accept(_ connection: NWConnection) {
        let client = ClientConnection(connection: connection, webDirectory: webDirectory, hub: hub)
        connections[ObjectIdentifier(client)] = client
        client.start()
    }
}
```

- [ ] **Step 3: Telefon oturumları ve erişim**

`Sources/PhoneBox/DashboardHub.swift`:

```swift
import Foundation
import PhoneBoxCore

/// Keeps track of the phones connected over WebSocket (design §5): the protocol session of each, whether it
/// came in over the iPhone's USB link, what it may do, and who gets the snapshots.
@MainActor
final class DashboardHub {
    static let maxClients = 4
    static let authTimeout: TimeInterval = 5
    /// Close code that tells the page to reconnect at once (to come back over the cable).
    static let reconnectCode: UInt16 = 4002

    private struct Client {
        let connection: ClientConnection
        var session: Session
        let onUSB: Bool
        var access: Access
    }

    var mode: AccessMode {
        didSet { if mode != oldValue { refreshAccess() } }
    }
    private var key: PairingKey
    private let appName: String
    private let usbInterfaces: () -> Set<String>
    private var clients: [ObjectIdentifier: Client] = [:]

    /// True while at least one phone may receive snapshots: the sampler runs only then.
    var onStreamingChange: ((Bool) -> Void)?
    /// Counts for the menu bar: phones receiving data, phones waiting for the cable.
    var onClientsChange: ((_ streaming: Int, _ waitingForCable: Int) -> Void)?
    /// A phone authenticated for the first time with this key.
    var onAuthenticated: (() -> Void)?
    var onConnectionClosed: ((ClientConnection) -> Void)?

    init(mode: AccessMode, key: PairingKey, appName: String, usbInterfaces: @escaping () -> Set<String> = USBLinks.iPhoneInterfaceNames) {
        self.mode = mode
        self.key = key
        self.appName = appName
        self.usbInterfaces = usbInterfaces
    }

    var canAccept: Bool { clients.count < Self.maxClients }
    private var isStreaming: Bool { clients.values.contains { $0.access.streaming } }

    func opened(_ connection: ClientConnection) {
        let onUSB = connection.interfaceName.map(usbInterfaces().contains) ?? false
        let session = Session(nonce: Session.makeNonce())
        clients[ObjectIdentifier(connection)] = Client(connection: connection, session: session, onUSB: onUSB, access: .unauthenticated)
        Log.server.info("Phone connected on \(connection.interfaceName ?? "?", privacy: .public) (USB: \(onUSB))")
        connection.send(.hello(nonce: session.nonce, app: appName))
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.authTimeout) { [weak self, weak connection] in
            MainActor.assumeIsolated {
                guard let self, let connection, let client = self.clients[ObjectIdentifier(connection)],
                      !client.session.isAuthenticated
                else { return }
                connection.close(code: Session.authFailedCode, reason: "no auth")
            }
        }
    }

    func received(_ text: String, from connection: ClientConnection) {
        let id = ObjectIdentifier(connection)
        guard var client = clients[id] else { return }
        let outcome = client.session.receive(text, key: key, commandsAllowed: client.access.commands, now: Date())
        clients[id] = client
        switch outcome {
        case .authenticated:
            let wasStreaming = isStreaming
            client.access = AccessPolicy.decide(mode: mode, clientOnUSB: client.onUSB, authenticated: true)
            clients[id] = client
            connection.send(.ready(mode: mode, access: client.access))
            onAuthenticated?()
            changed(wasStreaming: wasStreaming)
        case let .command(seq, _, _):
            // Commands arrive in Plan 3; until then every signed command is answered, never run.
            connection.send(.ack(seq: seq, ok: false, error: "unsupported"))
        case let .reply(message):
            connection.send(message)
        case let .close(code, reason):
            Log.server.notice("Closing a phone: \(reason, privacy: .public)")
            connection.close(code: code, reason: reason)
        }
    }

    func closed(_ connection: ClientConnection) {
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

- [ ] **Step 4: Derle**

Run: `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"`
Expected: çıktı yok.

- [ ] **Step 5: Commit**

```bash
git add Sources/PhoneBox/ClientConnection.swift Sources/PhoneBox/DashboardServer.swift Sources/PhoneBox/DashboardHub.swift
git commit -m "Serve the dashboard and run phone sessions over WebSocket" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Menü çubuğu, QR penceresi ve uygulamanın kendisi

**Files:**
- Delete: `Sources/PhoneBox/main.swift` (Görev 6'nın geçici dosyası)
- Create: `Sources/PhoneBox/PhoneBoxApp.swift`, `Sources/PhoneBox/AppDelegate.swift`, `Sources/PhoneBox/L10n.swift`,
  `Sources/PhoneBox/MenuBarController.swift`, `Sources/PhoneBox/QRWindowController.swift`
- Create: `Resources/Info.plist`, `Resources/en.lproj/Localizable.strings`, `Resources/tr.lproj/Localizable.strings`

**Interfaces:**
- Consumes: Görev 6–8'in hepsi.
- Produces: `MenuBarController { onShowQR; onModeChange; onResetPairing; update(status:active:) }`;
  `QRWindowController { show(link:); static qrImage(for:size:) }`; `L10n` metinleri.

- [ ] **Step 1: Geçici giriş noktasını sil**

Run: `git rm -q Sources/PhoneBox/main.swift`

- [ ] **Step 2: Metinler**

`Sources/PhoneBox/L10n.swift`:

```swift
import Foundation

/// Menu and window texts; English and Turkish in `Resources/{en,tr}.lproj/Localizable.strings`.
enum L10n {
    private static func text(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static var statusWaiting: String { text("status.waiting") }
    static func statusStreaming(_ count: Int) -> String { String(format: text("status.streaming"), count) }
    static var statusWaitingForCable: String { text("status.waitingForCable") }
    static func statusPortInUse(_ port: UInt16) -> String { String(format: text("status.portInUse"), Int(port)) }
    static var statusUSBUnavailable: String { text("status.usbUnavailable") }

    static var showQR: String { text("menu.showQR") }
    static var modeHeader: String { text("menu.mode") }
    static var modeCable: String { text("menu.mode.cable") }
    static var modeAlways: String { text("menu.mode.always") }
    static var launchAtLogin: String { text("menu.launchAtLogin") }
    static var resetPairing: String { text("menu.resetPairing") }
    static var quit: String { text("menu.quit") }

    static var resetTitle: String { text("reset.title") }
    static var resetMessage: String { text("reset.message") }
    static var resetConfirm: String { text("reset.confirm") }
    static var cancel: String { text("cancel") }

    static var qrTitle: String { text("qr.title") }
    static var qrInstructions: String { text("qr.instructions") }
    static var qrCopy: String { text("qr.copy") }
    static var qrCopied: String { text("qr.copied") }
}
```

`Resources/en.lproj/Localizable.strings`:

```
"status.waiting" = "Waiting for an iPhone";
"status.streaming" = "iPhone connected · %d";
"status.waitingForCable" = "Phone on Wi-Fi: plug in the cable";
"status.portInUse" = "Port %d is in use";
"status.usbUnavailable" = "Cannot see USB devices";

"menu.showQR" = "Show QR Code…";
"menu.mode" = "Send data";
"menu.mode.cable" = "Only While the Cable Is Plugged In";
"menu.mode.always" = "Always, Also over Wi-Fi";
"menu.launchAtLogin" = "Open at Login";
"menu.resetPairing" = "Reset Pairing…";
"menu.quit" = "Quit PhoneBox";

"reset.title" = "Reset pairing?";
"reset.message" = "Every paired phone is disconnected and has to scan the new QR code.";
"reset.confirm" = "Reset";
"cancel" = "Cancel";

"qr.title" = "Pair your iPhone";
"qr.instructions" = "Scan this code with the iPhone's camera. The dashboard opens in its browser.";
"qr.copy" = "Copy Link";
"qr.copied" = "Copied";
```

`Resources/tr.lproj/Localizable.strings`:

```
"status.waiting" = "iPhone bekleniyor";
"status.streaming" = "iPhone bağlı · %d cihaz";
"status.waitingForCable" = "Telefon Wi-Fi'de: kabloyu tak";
"status.portInUse" = "Port %d kullanımda";
"status.usbUnavailable" = "USB aygıtları görülemiyor";

"menu.showQR" = "QR kodunu göster…";
"menu.mode" = "Veri gönder";
"menu.mode.cable" = "Sadece kablo takılıyken";
"menu.mode.always" = "Her zaman, Wi-Fi'de de";
"menu.launchAtLogin" = "Girişte başlat";
"menu.resetPairing" = "Eşleştirmeyi sıfırla…";
"menu.quit" = "PhoneBox'tan çık";

"reset.title" = "Eşleştirme sıfırlansın mı?";
"reset.message" = "Eşleşmiş bütün telefonların bağlantısı kesilir; yeni QR kodunu okutmaları gerekir.";
"reset.confirm" = "Sıfırla";
"cancel" = "Vazgeç";

"qr.title" = "iPhone'unu eşleştir";
"qr.instructions" = "Bu kodu iPhone'un kamerasıyla okut. Dashboard telefonun tarayıcısında açılır.";
"qr.copy" = "Bağlantıyı kopyala";
"qr.copied" = "Kopyalandı";
```

- [ ] **Step 3: QR penceresi ve menü**

`Sources/PhoneBox/QRWindowController.swift`:

```swift
import AppKit
import CoreImage

/// The pairing window: the personal link as a QR code and as text (design §5 "Eşleştirme").
@MainActor
final class QRWindowController: NSObject {
    private var panel: NSPanel?
    private let imageView = NSImageView()
    private let linkField = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private var link = ""

    func show(link: String) {
        self.link = link
        let panel = self.panel ?? makePanel()
        self.panel = panel
        imageView.image = Self.qrImage(for: link, size: 260)
        linkField.stringValue = link
        copyButton.title = L10n.qrCopy
        panel.center()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 430),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = L10n.qrTitle
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let instructions = NSTextField(wrappingLabelWithString: L10n.qrInstructions)
        instructions.alignment = .center
        linkField.isSelectable = true
        linkField.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        linkField.textColor = .secondaryLabelColor
        linkField.lineBreakMode = .byCharWrapping
        linkField.maximumNumberOfLines = 3
        linkField.alignment = .center
        imageView.imageScaling = .scaleNone
        copyButton.bezelStyle = .rounded
        copyButton.target = self
        copyButton.action = #selector(copyLink)

        let stack = NSStackView(views: [imageView, instructions, linkField, copyButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = NSView()
        panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            instructions.widthAnchor.constraint(equalToConstant: 290),
            linkField.widthAnchor.constraint(equalToConstant: 290),
        ])
        return panel
    }

    @objc private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        copyButton.title = L10n.qrCopied
    }

    /// Black modules on white with a quiet zone, scaled by whole pixels so it stays sharp.
    static func qrImage(for text: String, size: CGFloat) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = max(1, (size / output.extent.width).rounded(.down))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
```

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
    var onResetPairing: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusLine = NSMenuItem()
    private let cableItem = NSMenuItem()
    private let alwaysItem = NSMenuItem()
    private let loginItem = NSMenuItem()
    private var mode: AccessMode

    init(mode: AccessMode) {
        self.mode = mode
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
        loginItem.title = L10n.launchAtLogin
        loginItem.action = #selector(toggleLaunchAtLogin)
        let resetItem = NSMenuItem(title: L10n.resetPairing, action: #selector(resetPairing), keyEquivalent: "")
        let quitItem = NSMenuItem(title: L10n.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        for item in [qrItem, cableItem, alwaysItem, loginItem, resetItem] { item.target = self }

        let menu = NSMenu()
        menu.delegate = self
        for item in [statusLine, .separator(), qrItem, .separator(), modeHeader, cableItem, alwaysItem, .separator(),
                     loginItem, resetItem, .separator(), quitItem] {
            menu.addItem(item)
        }
        statusItem.menu = menu
        update(status: L10n.statusWaiting, active: false)
    }

    func update(status: String, active: Bool) {
        statusLine.title = status
        statusItem.button?.contentTintColor = active ? .systemGreen : nil
        statusItem.button?.toolTip = "PhoneBox: \(status)"
    }

    func menuWillOpen(_ menu: NSMenu) {
        cableItem.state = mode == .cable ? .on : .off
        alwaysItem.state = mode == .always ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func showQR() { onShowQR?() }
    @objc private func chooseCable() { setMode(.cable) }
    @objc private func chooseAlways() { setMode(.always) }

    private func setMode(_ newMode: AccessMode) {
        mode = newMode
        onModeChange?(newMode)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.app.error("Open at Login failed: \(error.localizedDescription, privacy: .public)")
        }
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
}
```

- [ ] **Step 4: Uygulama**

`Sources/PhoneBox/AppDelegate.swift`:

```swift
import AppKit
import PhoneBoxCore

/// Wires the parts together (design §4).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let sampler = Sampler()
    private let usbWatcher = USBWatcher()
    private let qrWindow = QRWindowController()
    private var key = PairingStore.loadOrCreate()
    private var hub: DashboardHub!
    private var server: DashboardServer!
    private var menuBar: MenuBarController!
    private var streamingCount = 0
    private var waitingForCableCount = 0
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        hub = DashboardHub(mode: settings.mode, key: key, appName: "PhoneBox \(version)")
        let webDirectory = Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true)
        server = DashboardServer(webDirectory: webDirectory, hub: hub)
        menuBar = MenuBarController(mode: settings.mode)

        hub.onStreamingChange = { [weak self] streaming in self?.sampler.setRunning(streaming) }
        hub.onClientsChange = { [weak self] streaming, waiting in
            self?.streamingCount = streaming
            self?.waitingForCableCount = waiting
            self?.refreshStatus()
        }
        hub.onAuthenticated = { [weak self] in self?.settings.hasEverPaired = true }
        sampler.onSnapshot = { [weak self] snapshot in self?.hub.broadcast(snapshot) }
        server.onStateChange = { [weak self] _ in self?.refreshStatus() }

        menuBar.onShowQR = { [weak self] in self?.showQR() }
        menuBar.onModeChange = { [weak self] mode in
            self?.settings.mode = mode
            self?.hub.mode = mode
        }
        menuBar.onResetPairing = { [weak self] in
            guard let self else { return }
            key = PairingStore.reset()
            settings.hasEverPaired = false
            hub.replaceKey(key)
            showQR()
        }

        usbWatcher.onChange = { [weak self] pluggedIn in self?.iPhoneChanged(pluggedIn: pluggedIn) }
        usbWatcher.start()
        server.start(port: settings.port)

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampler.resetAfterWake() }
        }
    }

    private func showQR() {
        qrWindow.show(link: settings.personalURL(key: key))
    }

    private func iPhoneChanged(pluggedIn: Bool) {
        refreshStatus()
        guard pluggedIn else { return }
        if !settings.hasEverPaired { showQR() }
        // The USB link appears a moment after usbmuxd reports the phone; then move Wi-Fi phones to the cable.
        for delay in [3.0, 8.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.hub.iPhonePluggedIn() }
            }
        }
    }

    private func refreshStatus() {
        let status: String
        if case let .failed(port, _) = server.state {
            status = L10n.statusPortInUse(port)
        } else if streamingCount > 0 {
            status = L10n.statusStreaming(streamingCount)
        } else if waitingForCableCount > 0 {
            status = L10n.statusWaitingForCable
        } else if !usbWatcher.isAvailable {
            status = L10n.statusUSBUnavailable
        } else {
            status = L10n.statusWaiting
        }
        menuBar.update(status: status, active: streamingCount > 0)
    }
}
```

`Sources/PhoneBox/PhoneBoxApp.swift`:

```swift
import AppKit

@main
@MainActor
enum PhoneBoxApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // Route SIGTERM (e.g. `pkill`) through normal termination.
        signal(SIGTERM, SIG_IGN)
        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSource.setEventHandler {
            MainActor.assumeIsolated { app.terminate(nil) }
        }
        termSource.resume()
        withExtendedLifetime((delegate, termSource)) {
            app.run()
        }
    }
}
```

`Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>PhoneBox</string>
	<key>CFBundleExecutable</key>
	<string>PhoneBox</string>
	<key>CFBundleIdentifier</key>
	<string>com.phonebox.PhoneBox</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleLocalizations</key>
	<array>
		<string>en</string>
		<string>tr</string>
	</array>
	<key>CFBundleName</key>
	<string>PhoneBox</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSLocalNetworkUsageDescription</key>
	<string>PhoneBox shows this Mac's activity on your iPhone, over the USB cable or your local network.</string>
</dict>
</plist>
```

- [ ] **Step 5: Derle ve testleri çalıştır**

Run: `swift build 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"` → Expected: çıktı yok.
Run: `make test` → Expected: `Test run with 63 tests in 13 suites passed`.

- [ ] **Step 6: Commit**

```bash
git add -A Sources/PhoneBox Resources/Info.plist Resources/en.lproj Resources/tr.lproj
git commit -m "Add the menu bar, the QR pairing window and the app delegate" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Dashboard, ekranı açık tutan video ve uygulama paketi

**Files:**
- Create: `Resources/web/index.html`, `Resources/web/styles.css`, `Resources/web/app.js`
- Create: `scripts/make-video.swift`, `scripts/bundle.sh`

**Interfaces:**
- Consumes: `PBCrypto` (Görev 2), sunucunun protokolü (Görev 8).
- Produces: `make app` → `build/PhoneBox.app`; `make run` → derleyip açar.

- [ ] **Step 1: Sayfa ve stil**

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

main.stale { opacity: 0.35; }

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

- [ ] **Step 2: Sayfanın mantığı**

`Resources/web/app.js`:

```javascript
// PhoneBox dashboard (Plan 2: CPU and RAM). Design §5 (protocol), §8 (keep-awake, states).
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
      start: "Başlat",
      startNote: "Dokunduğunda ekran açık kalır. Telefonda çalan müzik durmaz.",
      memory: (used, total) => `${used} / ${total} GB`,
      load: (value) => `Yük ${value}`,
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
      start: "Start",
      startNote: "Once you tap, the screen stays on. Music playing on the phone keeps playing.",
      memory: (used, total) => `${used} / ${total} GB`,
      load: (value) => `Load ${value}`,
    },
  };
  const language = (navigator.language || "en").toLowerCase().startsWith("tr") ? "tr" : "en";
  const t = TEXT[language];
  const number = new Intl.NumberFormat(language, { maximumFractionDigits: 1, minimumFractionDigits: 1 });
  const $ = (id) => document.getElementById(id);
  document.documentElement.lang = language;

  // The key comes from the personal link's fragment (#k=…), or from localStorage on later visits (design §5).
  function readKey() {
    const fromLink = new URLSearchParams(location.hash.slice(1)).get("k");
    let stored = null;
    try {
      if (fromLink) localStorage.setItem("phonebox-key", fromLink);
      stored = localStorage.getItem("phonebox-key");
    } catch (error) {}
    const text = fromLink || stored;
    const bytes = text ? PBCrypto.base64UrlToBytes(text) : null;
    return bytes && bytes.length === 32 ? bytes : null;
  }

  const key = readKey();
  const state = { socket: null, retries: 0, started: false, stopped: false, nonce: null, receivedAt: 0 };

  function setStatus(kind, text) {
    $("status").className = "status " + kind;
    $("status-text").textContent = text;
  }

  function showMessage(text) {
    $("message").textContent = text || "";
    $("message").hidden = !text;
  }

  function setStale(stale) {
    $("metrics").classList.toggle("stale", stale);
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
    return video.play().catch(() => {});
  }

  // Chrome does not fire visibilitychange when the phone is unlocked, and WebKit pauses media while the
  // page is hidden, so check every few seconds (spike).
  setInterval(() => {
    if (state.started && document.visibilityState === "visible" && video.paused) keepAwake();
  }, 3000);

  $("start-button").textContent = t.start;
  $("start-note").textContent = t.startNote;
  $("start").addEventListener("click", () => {
    state.started = true;
    $("start").hidden = true;
    keepAwake();
  });

  // ---- Connection.
  function send(message) {
    if (state.socket && state.socket.readyState === WebSocket.OPEN) state.socket.send(JSON.stringify(message));
  }

  function connect() {
    if (state.stopped || (state.socket && state.socket.readyState <= WebSocket.OPEN)) return;
    if (!state.receivedAt) setStatus("", t.connecting);
    const socket = new WebSocket(`ws://${location.host}/ws`);
    state.socket = socket;
    socket.onmessage = (event) => handle(JSON.parse(event.data));
    socket.onclose = (event) => {
      if (state.socket === socket) state.socket = null;
      setStale(true);
      if (event.code === 4001) {
        state.stopped = true;
        setStatus("offline", t.unpaired);
        showMessage(t.badKey);
        return;
      }
      state.retries += 1;
      if (state.retries >= 3) {
        setStatus("offline", t.offline);
        showMessage(t.unreachable);
      } else {
        setStatus("", t.connecting);
      }
      const delay = event.code === 4002 ? 0 : [1000, 2000, 5000][Math.min(state.retries - 1, 2)];
      setTimeout(connect, delay);
    };
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
    if (access.streaming) {
      setStatus("connected", t.connected);
      showMessage("");
    } else if (access.reason === "not-on-cable") {
      setStatus("cable", t.cable);
      setStale(true);
      showMessage(t.notOnCable);
    }
  }

  function render(snapshot) {
    state.receivedAt = Date.now();
    setStale(false);
    if (snapshot.cpu) {
      setRing("cpu", snapshot.cpu.total);
      $("cpu-value").textContent = Math.round(snapshot.cpu.total) + "%";
      $("cpu-detail").textContent = snapshot.cpu.load.length ? t.load(number.format(snapshot.cpu.load[0])) : "";
    }
    if (snapshot.mem) {
      const percent = (snapshot.mem.used / snapshot.mem.total) * 100;
      setRing("ram", percent);
      $("ram-value").textContent = Math.round(percent) + "%";
      const gb = (bytes) => number.format(bytes / 1073741824);
      $("ram-detail").textContent = t.memory(gb(snapshot.mem.used), gb(snapshot.mem.total));
    }
  }

  function setRing(id, percent) {
    document.querySelector(`#${id} .ring`).style.setProperty("--p", Math.max(0, Math.min(100, percent)).toFixed(1));
  }

  // Reconnect right away when the page comes back (spike: iOS drops the socket 10–15 s after locking).
  for (const name of ["visibilitychange", "pageshow", "focus"]) {
    window.addEventListener(name, () => {
      if (document.visibilityState === "visible") connect();
    });
  }

  if (!key) {
    $("start").hidden = true;
    setStatus("offline", t.unpaired);
    showMessage(t.noKey);
    return;
  }
  connect();
})();
```

- [ ] **Step 3: Video üretici ve paketleme**

`scripts/make-video.swift`:

```swift
// Writes keepawake.mp4: 2 s of 64×64 black H.264 with a silent AAC track (spike V4, design §8).
// WebKit keeps the screen on only while an unmuted video with both tracks plays.
// Run: swift scripts/make-video.swift <output.mp4>
// macOS 27 marks these AVAssetWriter calls deprecated; they still work and this runs once per build.
import AVFoundation

func makeVideo(at url: URL, seconds: Int) throws {
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
    let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000,
    ])
    writer.add(audioInput)

    guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
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

    group.wait()
    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    finished.wait()
    guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/make-video.swift <output.mp4>\n".utf8))
    exit(1)
}
try makeVideo(at: URL(fileURLWithPath: CommandLine.arguments[1]), seconds: 2)
```

`scripts/bundle.sh`:

```bash
#!/usr/bin/env bash
# Builds build/PhoneBox.app (release): binary, Info.plist, translations, dashboard files and the keep-awake
# video. Ad-hoc signed, like NotchBox.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/PhoneBox.app"

swift build --package-path "$ROOT" -c release
BIN_DIR="$(swift build --package-path "$ROOT" -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/PhoneBox" "$APP/Contents/MacOS/PhoneBox"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# Translations go straight into Contents/Resources so that Bundle.main finds them.
ditto "$ROOT/Resources/en.lproj" "$APP/Contents/Resources/en.lproj"
ditto "$ROOT/Resources/tr.lproj" "$APP/Contents/Resources/tr.lproj"
ditto "$ROOT/Resources/web" "$APP/Contents/Resources/web"
swiftc -O -suppress-warnings "$ROOT/scripts/make-video.swift" -o "$ROOT/build/make-video"
"$ROOT/build/make-video" "$APP/Contents/Resources/web/keepawake.mp4"

xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
```

Run: `chmod +x scripts/bundle.sh && make app 2>&1 | grep -E "^Built|error"`
Expected: `Built …/build/PhoneBox.app`.

- [ ] **Step 4: Mac'te uçtan uca dene ("Her zaman" modunda)**

```bash
defaults write com.phonebox.PhoneBox mode always
open build/PhoneBox.app
```

Sonra:
- `lsof -nP -iTCP:4747 -sTCP:LISTEN` → Expected: `PhoneBox … TCP *:4747 (LISTEN)`.
- `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4747/` → `200`.
- `curl -s -D - -o /dev/null -r 0-1 http://localhost:4747/keepawake.mp4 | head -1` → `HTTP/1.1 206 Partial Content`.
- `curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:4747/../pairing-key"` → `404`.
- `stat -f "%Sp" ~/Library/Application\ Support/PhoneBox/pairing-key` → `-rw-------`.
- Anahtarı `cat ~/Library/Application\ Support/PhoneBox/pairing-key` ile al ve tarayıcıda
  `http://localhost:4747/#k=<anahtar>` aç → birkaç saniyede durum "Bağlı", CPU ve RAM halkaları dolar, RAM altında
  "x,y / 16,0 GB". "Başlat"a bas → kaplama kapanır.
- Adresteki anahtarı `#k=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA` yapıp sayfayı yenile → durum "Eşleşmedi",
  mesaj "Eşleştirme geçersiz…", değer gelmez.

- [ ] **Step 5: Kablo modunu dene**

```bash
pkill -x PhoneBox; defaults write com.phonebox.PhoneBox mode cable; open build/PhoneBox.app
```

Doğru anahtarla sayfayı yenile → Expected: durum "Kabloyu tak", mesaj "Bu telefon Wi-Fi üzerinden bağlı…", değer
gelmez (Mac'in kendi tarayıcısı USB'den gelmez).

- [ ] **Step 6: Test durumunu temizle**

Tarayıcının kimlik doğrulaması "eşleşti" bayrağını açar; temizlenmezse Görev 11'de QR penceresi kendiliğinden açılmaz.

```bash
pkill -x PhoneBox
defaults delete com.phonebox.PhoneBox
rm ~/Library/Application\ Support/PhoneBox/pairing-key
```

- [ ] **Step 7: Commit**

```bash
git add Resources/web/index.html Resources/web/styles.css Resources/web/app.js scripts/make-video.swift scripts/bundle.sh
git commit -m "Add the CPU and RAM dashboard, the keep-awake video and the app bundle" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: iPhone ile uçtan uca deneme, elle test listesi ve tasarım güncellemesi

**Files:**
- Create: `docs/manual-testing.md`
- Modify: `docs/design/2026-11-25-phonebox-design.md`

Bu görev kullanıcıyla birlikte yapılır. Telefonda açık kalan eski deneme sayfası varsa önce kapatılsın (4747'ye
eski protokolle bağlanmaya çalışır ve PhoneBox onu "bad message" ile kapatır).

- [ ] **Step 1: Uygulamayı başlat**

Run: `make run`
Expected: menü çubuğunda gri telefon simgesi; menünün ilk satırı "iPhone bekleniyor". (Spike'taki -10810 hatası
yalnızca `open --stdout` ile `~/Documents` içine log yazdırılınca çıkmıştı; düz `open build/PhoneBox.app` çalışır.)

- [ ] **Step 2: İlk takış ve QR**

Kullanıcı iPhone'u çıkarıp takar. Expected: Mac'te "iPhone'unu eşleştir" penceresi kendiliğinden açılır. Kullanıcı
QR'ı iPhone kamerasıyla okutur → telefonun tarayıcısında dashboard açılır, "Başlat"a basar. Expected: durum "Bağlı",
CPU/RAM canlı; menü çubuğundaki telefon yeşil, menüde "iPhone bağlı · 1 cihaz".
Doğrula: `log stream --info --predicate 'subsystem == "com.phonebox.PhoneBox"'` içinde
`Phone connected on en… (USB: true)` ya da `anri… (USB: true)`.

- [ ] **Step 3: Sadece kablo (Wi-Fi kapalı)**

Kullanıcı iPhone'da Wi-Fi'yi kapatır ve sayfayı yeniler → Expected: yine "Bağlı" ve canlı veri. Wi-Fi'yi geri açar.

- [ ] **Step 4: Ekran açık kalıyor, müzik durmuyor**

Otomatik Kilit 30 sn iken telefonda müzik çalarken dashboard'u açık bırak, 2 dk dokunma. Expected: ekran açık kalır,
müzik durmaz.

- [ ] **Step 5: Kablo çıkınca ve geri takılınca**

Kablo modunda kabloyu çıkar → Expected: sayfa birkaç saniye içinde "Kabloyu tak" (telefon Wi-Fi'de) ya da "Mac'e
ulaşılamıyor" gösterir, değerler soluklaşır. Kabloyu tak → en geç ~8 sn içinde Wi-Fi bağlantısı 4002 ile kapatılır,
sayfa kablo üzerinden yeniden bağlanır, değerler geri gelir. Hangi sürede geri geldiğini not et.

- [ ] **Step 6: Kilitle-aç ve menü**

Telefonu 1 dk kilitle, aç → bağlantı ve video kendiliğinden geri gelir. Menüden "Her zaman" modunu seç, kabloyu çıkar
(telefon aynı Wi-Fi'de) → veri Wi-Fi üzerinden akmaya devam eder. "Kablo takılıyken"e dön. "Eşleştirmeyi sıfırla…"
→ telefondaki sayfa "Eşleşmedi" gösterir; yeni QR okutulunca yeniden bağlanır.

- [ ] **Step 7: Elle test listesini yaz**

`docs/manual-testing.md`:

```markdown
# PhoneBox — Elle test listesi

Her sürümden önce gerçek bir iPhone ile. Otomatik Kilit 30 sn; Mac'te `make run`.

## Eşleştirme ve bağlantı
- [ ] İlk kurulumdan sonra iPhone takılınca QR penceresi kendiliğinden açılıyor.
- [ ] QR okutulunca dashboard varsayılan tarayıcıda açılıyor; "Başlat" sonrası CPU ve RAM canlı.
- [ ] Log'da bağlantı `(USB: true)`; iPhone'un Wi-Fi'si kapalıyken de çalışıyor.
- [ ] Ana Ekrana Ekle simgesinden açılınca anahtar korunuyor.
- [ ] "Eşleştirmeyi sıfırla…" → eski sayfa "Eşleşmedi"; yeni QR ile yeniden bağlanıyor.

## Kablo modu
- [ ] Kablo çıkınca değerler soluklaşıyor; "Kabloyu tak" ya da "Mac'e ulaşılamıyor".
- [ ] Kablo takılınca ~8 sn içinde kablo üzerinden geri geliyor.
- [ ] "Her zaman" modunda kablo yokken Wi-Fi üzerinden veri geliyor.

## Ekran ve ses
- [ ] Dashboard açıkken ekran 30 dk kapanmıyor.
- [ ] Telefonda çalan müzik durmuyor; kilit ekranında kullanıcının şarkısı görünüyor.
- [ ] Kilitle-aç sonrası bağlantı ve ekranı açık tutma geri geliyor.

## Mac
- [ ] Menü çubuğu simgesi veri akarken yeşil, değilken gri.
- [ ] "Girişte başlat" açılıp kapanıyor (Sistem Ayarları → Genel → Giriş Öğeleri'nde görünüyor).
- [ ] Kimse bağlı değilken PhoneBox'ın CPU kullanımı ~%0.

## Henüz denenmemiş (spike 8)
- [ ] Kestirmeler → Otomasyon → Şarj Aleti → "URL'yi Aç" (kişisel bağlantı) → "Hemen Çalıştır": kablo takılınca
  dashboard onaysız açılıyor mu?
```

Gözlemleri bu listenin altına tarih ve sonuçla ekle (geçti/kaldı ve notlar).

- [ ] **Step 8: Tasarımı bu plana göre güncelle**

`docs/design/2026-11-25-phonebox-design.md`'de:
- Bölüm 4 tablosunda `Pairing` satırının "Keychain" geçen kısımlarını şöyle değiştir: "32 baytlık anahtarı üretir ve
  `~/Library/Application Support/PhoneBox/pairing-key` dosyasında (`0600`) saklar; ad-hoc imzalı uygulama her
  güncellemeden sonra Anahtar Zinciri şifresi sorduracağı için Keychain kullanılmaz" ve bağımlılık sütununu `Dosya` yap.
- Bölüm 5 "Eşleştirme" 1. adımda "Keychain'e yazar" → "`pairing-key` dosyasına yazar".
- Bölüm 8 "Ekranı açık tutma" maddesinin başına ekle: "Sesi açık oynatma bir dokunuş gerektirdiği için dashboard ilk
  açılışta 'Başlat' düğmesi gösterir; video ilk dokunuşta başlar."
- Bölüm 8 menü listesinde "Port: 4747…" satırının sonuna ekle: "(Plan 5; o zamana kadar `defaults write
  com.phonebox.PhoneBox port -int <port>`)".

- [ ] **Step 9: Commit**

```bash
git add docs/manual-testing.md docs/design/2026-11-25-phonebox-design.md
git commit -m "Add the manual test list and record Plan 2 decisions in the design" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
