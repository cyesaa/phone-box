# PhoneBox — Tasarım Dokümanı

- **Tarih:** 2026-11-25
- **Durum:** Onaylandı (2026-11-25). Deneme planı: `docs/design/plans/2026-11-25-phonebox-spike.md`
- **Geliştirme Mac'i:** MacBook Pro (Mac16,1), Apple M4, 16 GB, macOS 27.2, Xcode yok (Command Line Tools)
- **Test telefonu:** Kullanıcının günlük iPhone'u
- **Örnek alınan proje:** NotchBox (`cyesaa/notch-box`): paketleme, kurulum, README ve doküman düzeni ondan alınır

## 1. Özet

PhoneBox, Mac'in anlık sistem verilerini (CPU, RAM, GPU, sıcaklık, güç, ağ, disk, pil, en çok kaynak
kullanan uygulamalar) iPhone'da yatay bir dashboard olarak gösteren bir menü çubuğu uygulamasıdır. Telefona hiçbir
şey kurulmaz: dashboard, Mac'teki PhoneBox'ın yerel ağda sunduğu bir web sayfasıdır ve Safari'de açılır.
Telefondan Mac'e komut da gönderilebilir: uygulama kapatma, medya ve ses kontrolü, kilitleme ve uyutma.

Kullanıcı PhoneBox'ı NotchBox gibi tek bir `curl` satırıyla kurar. iPhone'u ilk kez kabloyla taktığında Mac'te
bir QR kod çıkar; telefon kamerasıyla okutulunca dashboard açılır. Sonraki takışlarda, isteğe bağlı bir Kestirmeler
otomasyonu sayesinde dashboard kendiliğinden açılır.

## 2. Hedefler ve kapsam dışı

### Hedefler (v1)

- Telefona uygulama, profil ya da sertifika kurmadan, sadece Safari ile çalışan dashboard.
- Yatay ana görünüm (yerleşim C, "sade koyu" stil); dikey tutulunca "tek bakış" yerleşimi.
- Saniyede bir güncellenen metrikler (bölüm 6), uygulama listesi 2 saniyede bir.
- Telefondan komutlar: uygulama kapat / zorla kapat, oynat-duraklat / önceki / sonraki, ses seviyesi ve sessiz,
  Mac'i kilitle, ekranı kapat, uyut.
- QR kodla eşleştirme; imzalı (HMAC) kimlik doğrulama ve komutlar.
- İki erişim modu: "kablo takılıyken" (varsayılan) ve "her zaman"; menü çubuğundan seçilir.
- Arayüz dili İngilizce + Türkçe, telefonun / Mac'in diline göre otomatik.
- `curl | bash` kurulum, GitHub Releases, menüden güncelleme, `--uninstall`.

### Kapsam dışı (v1)

- Android ve native iOS uygulaması (kullanıcı kararı: sadece iPhone, telefona kurulum yok).
- Verinin USB kablosu üzerinden taşınması (Safari, `usbmuxd` kanalını kullanamaz; bkz. bölüm 3).
- Fan hızı, geçmiş kaydı (telefondaki 60 saniyelik grafik dışında), uyarı/bildirim eşikleri.
- Telefondan Mac'i uyandırma (Wake on LAN).
- Kendi Kestirmeler komutlarını ya da scriptleri çalıştırma.
- HTTPS, Apple notarization, App Store, Intel Mac'ler.

## 3. Platform kısıtları ve kararlar

| Konu | Karar | Neden |
|---|---|---|
| Telefon tarafı | Safari'de açılan web sayfası, "Ana Ekrana Ekle" ile uygulama gibi | Kullanıcı telefona hiçbir şey kurulmasını istemiyor |
| Veri yolu | Yerel Wi-Fi üzerinden HTTP + WebSocket | iOS'ta USB üzerinden Mac'le konuşabilen tek şey native uygulama; Safari bunu yapamaz |
| Kablonun rolü | "Takılı" sinyali (kablo modu) ve şarj | Mac, `usbmuxd` ile iPhone'un takıldığını Xcode olmadan görür |
| HTTP, HTTPS değil | Düz HTTP | HTTPS için ya telefona sertifika kurmak ya da dışarıda sunucu işletmek gerekir; ikisi de hedefe aykırı |
| HTTP'nin bedeli | Wake Lock ve `crypto.subtle` yok | Ekranı açık tutmak için sessiz video yöntemi (spike ile doğrulanacak); SHA-256/HMAC sade JS ile yazılır |
| Mac uygulaması | Swift 6 araç zinciri (Swift 5 dil modu), AppKit menü çubuğu, SwiftPM | NotchBox ile aynı; Xcode gerekmez |
| Sunucu | Network.framework (`NWListener`, `NWProtocolWebSocket`) | Ek kütüphane yok |
| Dashboard kodu | Sade HTML/CSS/JS, uygulamanın içine gömülü (`Resources/web`) | Derleme adımı ve npm yok (yaklaşım A) |
| Minimum sistem | macOS 14, Apple Silicon | NotchBox ile aynı; sıcaklık/güç okuma Apple Silicon'a özgü |
| Adres | `http://<LocalHostName>.local:4747/` | `.local` adı IP değişse de sabit kalır; port ayarlardan değişir |
| Bundle ID | `com.phonebox.PhoneBox` | NotchBox'taki adlandırma |
| GitHub deposu | NotchBox'la aynı hesapta `phone-box` | Yayın aşamasında değiştirilebilir |

## 4. Mimari

```
 iPhone (Safari)                          Mac: PhoneBox.app (menü çubuğu)
┌──────────────┐   Wi-Fi: HTTP + WebSocket   ┌──────────────────────────────────┐
│  Dashboard   │ ◄─────── snapshot / sn ──── │ Server ◄── Sampler ◄── Collectors │
│  (HTML/JS)   │ ─────── cmd (imzalı) ─────► │   │   └──► CommandRunner           │
└──────┬───────┘                              │   ▼                                │
       │ USB kablo: sadece "takılı" sinyali   │ AccessPolicy ◄── USBWatcher        │
       └──────────────────────────────────────┤ Pairing (Keychain) · MenuBar (QR) │
                                              └──────────────────────────────────┘
```

İki SwiftPM hedefi var:

- **`PhoneBoxCore`**: Sistem çağrısı yapmayan, test edilen saf mantık: veri modelleri (`Snapshot`), CPU/RAM/ağ
  hesapları (ham sayaçlardan yüzde ve hız), yardımcı süreçleri uygulamaya gruplama, mesaj formatı, HMAC ve sıra
  numarası denetimi, `AccessPolicy` karar tablosu.
- **`PhoneBox`**: macOS ile konuşan her şey ve uygulamanın kendisi.

| Birim | Görevi | Arayüzü | Bağımlılığı |
|---|---|---|---|
| Collectors | Her metrik kaynağı ayrı birim (CPU, RAM, GPU, Sensörler, Ağ, Disk, Pil, Uygulamalar) | `sample() -> Reading?` (zaman sınırlı) | Mach, IOKit, libproc, IOReport |
| Sampler | Saniyede bir collector'ları çağırıp `Snapshot` üretir; sadece izinli bir istemci varken çalışır | `start()`, `stop()`, `onSnapshot` | Collectors, Core hesapları |
| USBWatcher | `/var/run/usbmuxd` soketini dinler; iPhone takıldı/çıktı olayları | `isIPhoneAttached`, `onChange`, `isAvailable` | usbmuxd |
| AccessPolicy | Veri akışı ve komut iznine karar verir | `decide(mode, attached, usbAvailable, authenticated) -> Access` | Saf (Core) |
| Pairing | 32 baytlık anahtarı üretir, Keychain'de saklar, sıfırlar; kişisel bağlantıyı kurar | `key`, `personalURL`, `reset()` | Keychain |
| Server | Dashboard dosyalarını sunar, `/ws` WebSocket'i, kimlik doğrulama, en fazla 4 istemci | `start(port)`, `broadcast`, `onCommand` | Network.framework, Core protokolü |
| CommandRunner | Komutları çalıştırır, sonuç döner | `run(Command) -> CommandResult` | AppKit, CoreAudio, mediaremote-adapter, pmset |
| MenuBar | Simge, menü, QR penceresi | — | AppKit, CoreImage (QR) |
| Web dashboard | Yatay/dikey görünüm, grafik geçmişi, komut arayüzü, rehber | WebSocket protokolü (bölüm 5) | Safari |

## 5. Bağlantı, eşleştirme ve güvenlik

### Eşleştirme

1. PhoneBox ilk açılışta 32 rastgele bayt üretir ve Keychain'e yazar. Bu anahtar base64url biçiminde kişisel
   bağlantının içine konur: `http://<mac>.local:4747/#k=<anahtar>`. `#` sonrası sunucuya hiç gönderilmez.
2. iPhone takıldığında, daha önce hiçbir telefon kimlik doğrulamasını tamamlamamışsa (`hasEverPaired == false`)
   QR penceresi kendiliğinden açılır. Aksi halde hiçbir pencere açılmaz, sadece menü simgesi durumu gösterir.
3. QR penceresinde kişisel bağlantı QR olarak ve altında yazı olarak durur.
4. Dashboard anahtarı önce adresteki `#k=` kısmından, yoksa `localStorage`'dan okur ve `localStorage`'a da yazar.
   Adresteki `#k=` silinmez; "Ana Ekrana Ekle" ve Kestirmeler otomasyonu bu adresi kullanır.
5. "Eşleştirmeyi sıfırla": yeni anahtar üretilir, bağlı bütün istemciler kapatılır, `hasEverPaired = false` olur.

### WebSocket protokolü (`ws://<mac>.local:<port>/ws`, JSON, her mesajda `"v":1`)

| Yön | Mesaj | Açıklama |
|---|---|---|
| Mac → telefon | `{"type":"hello","nonce":"<32 hex>","app":"PhoneBox 0.1.0"}` | Bağlantıya özgü rastgele sayı |
| telefon → Mac | `{"type":"auth","mac":"<HMAC-SHA256(k, "auth:"+nonce) hex>"}` | 5 sn içinde gelmezse ya da yanlışsa bağlantı 4001 koduyla kapanır |
| Mac → telefon | `{"type":"ready","mode":"cable"\|"always","access":{"streaming":bool,"commands":bool,"reason":"…"}}` | Kimlik doğrulandı; `access` alanı bir alttaki `access` mesajıyla aynı |
| Mac → telefon | `{"type":"access","streaming":bool,"commands":bool,"reason":"ok"\|"cable-unplugged"\|"usb-unavailable"}` | Erişim değiştiğinde |
| Mac → telefon | `{"type":"snapshot","t":<ms>, ...}` | Saniyede bir (bölüm 6) |
| telefon → Mac | `{"type":"cmd","seq":n,"name":"…","args":"<JSON metni>","mac":"<HMAC(k, "cmd:"+nonce+":"+seq+":"+name+":"+args) hex>"}` | `args` bir metin; imza tam bu metin üzerinden atılır, sonra çözülür |
| Mac → telefon | `{"type":"ack","seq":n,"ok":true}` / `{"ok":false,"error":"not-allowed"\|"bad-signature"\|"app-changed"\|"unsupported"\|"failed"}` | Her komuta cevap |

Kurallar:
- `seq` her bağlantıda kesin olarak artmalı; artmayan `seq` reddedilir (tekrar saldırısı).
- Saniyede 10'dan fazla komut, bozuk JSON ya da yanlış imza → bağlantı kapanır.
- Anahtar ağ üzerinden hiç gitmez. Metrikler şifresiz akar; aynı ağdakiler görebilir ama komut gönderemez.
  Bu açık bilerek kabul edilmiştir.

### AccessPolicy

| Mod | iPhone USB'de | usbmuxd erişilebilir | Veri ve komut |
|---|---|---|---|
| Kablo takılıyken (varsayılan) | Evet | Evet | İzinli |
| Kablo takılıyken | Hayır | Evet | Kapalı, `reason: cable-unplugged` |
| Kablo takılıyken | — | Hayır | Kapalı, `reason: usb-unavailable`, menüde uyarı; mod kendiliğinden değişmez |
| Her zaman | — | — | İzinli |

Kimlik doğrulamamış bir bağlantı hiçbir durumda veri almaz. Bilinen sınır: Mac, takılı iPhone ile tarayıcıdaki
sayfanın aynı telefon olduğunu doğrulayamaz; "eşleşmiş bir istemci var ve herhangi bir iPhone takılı" koşuluna bakar.
Erişim kapanınca bağlantı açık kalır; erişim geri gelince veri anında akmaya başlar.

### Yeniden bağlanma

Safari ekran kilitlenince bağlantıyı keser. Sayfa `visibilitychange`/`pageshow` ile görünür olunca 1, 2, 5 saniye
(sonra 5 saniyede bir) arayla yeniden bağlanır; bu sırada "bağlanıyor" durumu gösterilir.

## 6. Metrikler

Sampler sadece en az bir izinli istemci varken çalışır. Hedef: PhoneBox'ın kendi CPU kullanımı %1'in altında.
Okunamayan değer `null` gönderilir, dashboard "—" gösterir.

| Alan | İçerik | Kaynak |
|---|---|---|
| `cpu` | `total` (%), `cores` (% dizisi), `pCores` (performans çekirdeği sayısı), `load` (1/5/15 dk) | `host_processor_info`, `sysctl hw.perflevel*`, `getloadavg` |
| `mem` | `used`, `total`, `app`, `wired`, `compressed`, `swapUsed` (bayt), `pressure` (`normal`/`warn`/`critical`) | `host_statistics64`, `sysctl hw.memsize`, `vm.swapusage`, `kern.memorystatus_vm_pressure_level` |
| `gpu` | `util` (%) | IOKit `IOAccelerator` → `PerformanceStatistics` |
| `temp` | `cpuAvg`, `cpuMax`, `gpuAvg`, `gpuMax` (°C) | `IOHIDEventSystemClient` (resmi olmayan) |
| `power` | `cpu`, `gpu`, `ane` (W); MacBook'ta `system` (W) | `IOReport` "Energy Model" (resmi olmayan); pil telemetrisi |
| `net` | `rx`, `tx` (bayt/sn), `iface` | `getifaddrs` sayaçları, birincil arayüz |
| `disk` | `free`, `total` (bayt), `read`, `write` (bayt/sn) | `URLResourceValues`, IOKit `IOBlockStorageDriver` istatistikleri |
| `battery` | `percent`, `charging`, `minutesLeft`; masaüstü Mac'te `null` | `IOPSCopyPowerSourcesInfo` |
| `apps` | 2 saniyede bir (diğer saniyelerde alan gönderilmez): CPU'ya göre ilk 5 ile RAM'e göre ilk 5'in birleşimi, en fazla 10 kayıt `{pid, bundleId, name, cpu, mem, quittable}` | `libproc` (`proc_listallpids`, `proc_pid_rusage`, `proc_pidpath`) |

- **Gruplama:** Bir sürecin yolu bir `.app` paketinin içindeyse en dıştaki `.app`'e yazılır ("Chrome Helper" →
  "Chrome"). Root'a ait sistem süreçleri izin olmadan okunamaz ve listede yer almaz.
- **Uyku/uyanma ve ağ değişimi:** CPU, ağ ve disk sayaçlarının referansı sıfırlanır; ilk örnek hız yerine `null`
  döner, böylece anlamsız sıçrama olmaz.
- **Sıcaklık/güç:** Stats ve macmon'un yöntemleri izlenir. Kod alınırsa lisansına uyulur ve
  `THIRD_PARTY_NOTICES.md`'ye yazılır. Sensör adları çipe göre değişir: M4'te test edilir, M1–M3 için Stats'in
  sensör listesi kullanılır, README'de "topluluk testine açık" diye belirtilir.

## 7. Komutlar

| `name` | `args` | Uygulama | Telefonda onay |
|---|---|---|---|
| `quitApp` | `{pid, bundleId, force}` | `NSRunningApplication.terminate()` / `forceTerminate()` | Evet; `force` kırmızı uyarıyla |
| `media` | `{action: "playPause"\|"next"\|"previous"}` | mediaremote-adapter (NotchBox'taki gibi, `Vendor/` alt modülü) | Hayır |
| `volume` | `{level: 0…1}` | CoreAudio varsayılan çıkış cihazı | Hayır |
| `mute` | `{on: bool}` | CoreAudio | Hayır |
| `lock` | `{}` | `login.framework` `SACLockScreenImmediate` (dlopen); olmazsa `pmset displaysleepnow` | Evet |
| `displaySleep` | `{}` | `pmset displaysleepnow` | Hayır |
| `sleep` | `{}` | `pmset sleepnow` | Evet |

- `quitApp` sadece `activationPolicy == .regular` olan uygulamalarda çalışır; Finder ve PhoneBox hariçtir.
  Mac, `pid`'in hâlâ aynı `bundleId`'ye ait olduğunu denetler; değilse `app-changed` döner.
- Ses kontrolü olmayan çıkış cihazında `volume`/`mute` `unsupported` döner ve kaydırıcı devre dışı kalır.
- Bu komutların hiçbirinin Erişilebilirlik izni gerektirmemesi beklenir (spike 7 ile doğrulanır).

## 8. Arayüz

### Dashboard (telefon)

- **Yatay (ana görünüm, yerleşim C, sade koyu):** solda CPU ve RAM halkaları; ortada son 60 saniyenin grafiği ve
  altında kontrol şeridi (önceki / oynat-duraklat / sonraki, ses kaydırıcısı, sessiz, "⋯" menüsü); sağda GPU,
  sıcaklık, güç, ağ, disk, pil satırları ve en çok kaynak kullanan uygulamalar.
- **Dikey ya da yön kilidi açık:** aynı veriler "tek bakış" yerleşiminde (üstte iki halka, altta satırlar, en altta
  kontrol şeridi).
- **Stil:** siyah zemin, sistem fontu, yumuşak kartlar; renkler CPU yeşil, RAM mavi, GPU mor, sıcaklık turuncu,
  güç sarı, ağ camgöbeği.
- **Etkileşim:** bir halkaya ya da satıra dokununca ortadaki grafik o metriğe geçer (CPU, RAM, GPU, sıcaklık, güç,
  ağ). Grafik geçmişi telefonda tutulur. Uygulama listesi varsayılan olarak CPU'ya göre sıralanır; başlığına
  dokununca RAM'e göre sıralanır. Bir uygulamaya dokununca alttan "Kapat" ve "Zorla kapat" çıkar.
  "⋯" menüsünde Kilitle, Ekranı kapat, Uyut ve "Kurulum rehberi" bulunur. Komut sonucu kısa bir bildirimle görünür.
- **Durumlar:** bağlanıyor (gri nokta, soluk değerler) · bağlı (yeşil nokta) · kablo çıkarıldı (değerler donar ve
  soluklaşır, "Kabloyu tak") · Mac'e ulaşılamıyor (arka planda yeniden dener) · anahtar geçersiz ("Kabloyu tak ve QR
  kodu yeniden okut") · metrik okunamıyor ("—").
- **İlk açılış rehberi** (bir kez, kapatılabilir): 1) Ana Ekrana Ekle, 2) Kestirmeler → Otomasyon → "Şarj Aleti
  bağlandığında" → "URL'yi Aç" (kişisel bağlantı, "Kopyala" düğmesiyle) → "Hemen Çalıştır", 3) telefonu yan çevir.
  Spike 2 başarısız olursa rehbere "Otomatik Kilit" adımı eklenir.
- **Ekranı açık tutma:** küçük, sessiz, döngüde ve satır içi oynayan bir video (`Resources/web` içinde).
- **OLED koruması:** 3 dakikada bir içerik ±2 piksel kayar.
- **Dil ve sayı biçimi:** `navigator.language`'a göre Türkçe/İngilizce; sayılar `Intl.NumberFormat` ile.

### Menü çubuğu (Mac)

Simge telefon çizimi: gri = izinli istemci yok, yeşil = en az bir istemci veri alıyor. Ayrı ayarlar penceresi yoktur.

- Durum satırı (ör. "iPhone bağlı · 1 cihaz", "Port 4747 kullanımda", "USB algılanamıyor")
- QR kodu göster
- Mod: ● Kablo takılıyken / ○ Her zaman
- Port: 4747…
- Girişte başlat (ServiceManagement)
- Eşleştirmeyi sıfırla
- Güncelleme (NotchBox'taki gibi)
- Çık

## 9. Hata yönetimi

| Durum | Davranış |
|---|---|
| Port dolu | Başka porta geçilmez (kayıtlı bağlantı bozulmasın). Menüde uyarı ve "Port…" ile yeni port; QR güncellenir |
| usbmuxd yok | Kablo modunda erişim kapalı, menüde uyarı; mod kendiliğinden değişmez |
| Collector hatası / takılma | Her `sample()` zaman sınırlı; değer `null`, aynı hata log'a bir kez yazılır |
| Protokol ihlali | Bozuk mesaj, yanlış imza, artmayan `seq`, hız sınırı aşımı → bağlantı kapanır |
| 5. istemci | Reddedilir (en fazla 4) |
| Mac uyandı / ağ değişti | Sayaç referansları sıfırlanır; dinleyici tüm arayüzlerde kalır, `.local` yeni ağda çalışır |
| Komut başarısız | `ack` içinde `error`; dashboard bildirim gösterir |

Log: `os_log`, alt sistem `com.phonebox.PhoneBox`.

## 10. Test

- **Birim testleri (`Tests/PhoneBoxCoreTests`, Swift Testing):** CPU yüzdesi (tick farkları), RAM hesabı, ağ
  sayacının sıfırlanması/taşması, uygulama gruplama, mesaj kodlama/çözme, HMAC (RFC 4231 test vektörleri),
  artmayan `seq`'in reddi, `AccessPolicy` tablosunun bütün satırları.
- **JS kripto testi:** Swift testi `Resources/web/sha256.js`'i JavaScriptCore'da çalıştırıp RFC 4231 vektörleri ve
  Swift'in HMAC sonucuyla karşılaştırır (Node/npm gerekmez).
- **Elle test:** `docs/manual-testing.md`, gerçek iPhone ile adım adım kontrol listesi (eşleştirme, iki mod, her
  komut, durumlar, dikey/yatay, yeniden bağlanma).

## 11. Spike (ilk iş)

Uygulamadan önce küçük bir deneme yapılır; sonuçlar `docs/spike-results.md`'ye yazılır. Kritik madde başarısız
olursa tasarıma dönülür.

| # | Soru | Kritik mi |
|---|---|---|
| 1 | iPhone Safari `http://<mac>.local:4747` adresini açıyor mu (mDNS, Yerel Ağ izni)? | Evet |
| 2 | Sessiz döngü video ile ekran 30 dakika açık kalıyor mu? | Evet |
| 3 | "Ana Ekrana Ekle" simgesi `#k=` kısmını koruyor mu? Ana ekran uygulamasının `localStorage`'ı Safari'den ayrı mı? | Hayır (yedek: QR'ı ana ekran uygulamasında yeniden okut) |
| 4 | Ekran kilitlenip açılınca WebSocket yeniden kuruluyor mu? | Evet |
| 5 | `usbmuxd` iPhone takılma/çıkma olaylarını Xcode olmadan veriyor mu? | Hayır (yedek: IOKit USB bildirimleri) |
| 6 | M4'te sıcaklık ve güç sudo'suz okunuyor mu? | Hayır (yedek: o kartlar "—") |
| 7 | macOS 27'de mediaremote-adapter ile medya komutları çalışıyor mu, izin istiyor mu? | Hayır |
| 8 | Kestirmeler "Şarj Aleti" otomasyonu URL'yi onaysız açıyor mu? | Hayır |
| 9 | macOS, PhoneBox için Yerel Ağ / güvenlik duvarı izni istiyor mu? | Hayır (README'de belirtilir) |

## 12. Dağıtım ve klasör yapısı

NotchBox ile aynı:

- Kurulum: `curl -fsSL https://raw.githubusercontent.com/cyesaa/phone-box/main/install.sh | bash`
  (`curl` ile inen dosya karantinaya alınmaz, imzasız uygulama engellenmez); kaldırma `… | bash -s -- --uninstall`.
- `make app` (ad-hoc imzalı `build/PhoneBox.app`), `make test`, `make release VERSION=x.y.z` (GitHub Releases'a
  `PhoneBox.zip`).
- Gereksinim: Apple Silicon, macOS 14+. README önce Türkçe, sonra İngilizce, son kullanıcı için yazılır.

```
Package.swift  Makefile  install.sh  LICENSE  THIRD_PARTY_NOTICES.md  README.md
scripts/                  bundle.sh, dist.sh, release.sh, make-icon.swift
Sources/PhoneBoxCore/     modeller, hesaplar, protokol, HMAC, AccessPolicy
Sources/PhoneBox/         uygulama, Collectors, Sampler, USBWatcher, Server, Pairing, CommandRunner, MenuBar
Resources/                Info.plist, AppIcon.icns, en.lproj, tr.lproj
Resources/web/            index.html, app.js, sha256.js, styles.css, keepawake.mp4
Vendor/mediaremote-adapter/   (git alt modülü)
Tests/PhoneBoxCoreTests/
docs/design/2026-11-25-phonebox-design.md   docs/spike-results.md   docs/manual-testing.md
```

## 13. Açık riskler

- **Ekranın açık kalması** (spike 2): çalışmazsa kullanıcı "Otomatik Kilit"i elle ayarlar; deneyim zayıflar.
- **Resmi olmayan API'ler** (sıcaklık, güç, kilitleme, medya): macOS güncellemesiyle bozulabilir; her biri tek
  başına devre dışı kalacak şekilde yalıtılır.
- **Şifresiz metrik trafiği:** aynı ağdakiler CPU/uygulama adlarını görebilir; komutlar imzalı olduğu için güvende.
- **Kablo modu sınırı:** hangi iPhone'un takılı olduğu sayfayla eşleştirilemez.
- **Safari depolama temizliği:** anahtar kişisel bağlantıda durduğu için etkilenmez; bozulursa QR yeniden okutulur.
