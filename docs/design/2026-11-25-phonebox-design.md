# PhoneBox — Tasarım Dokümanı

- **Tarih:** 2026-11-25
- **Durum:** Onaylandı (2026-11-25); deneme sonuçlarına göre güncellendi (2026-11-25). Deneme planı:
  `docs/design/plans/2026-11-25-phonebox-spike.md`, sonuçlar: `docs/spike-results.md`
- **Geliştirme Mac'i:** MacBook Pro (Mac16,1), Apple M4, 16 GB, macOS 27.2, Xcode yok (Command Line Tools)
- **Test telefonu:** Kullanıcının günlük iPhone'u
- **Örnek alınan proje:** NotchBox (`cyesaa/notch-box`): paketleme, kurulum, README ve doküman düzeni ondan alınır

## 1. Özet

PhoneBox, Mac'in anlık sistem verilerini (CPU, RAM, GPU, sıcaklık, güç, ağ, disk, pil, en çok kaynak
kullanan uygulamalar) iPhone'da yatay bir dashboard olarak gösteren bir menü çubuğu uygulamasıdır. Telefona hiçbir
şey kurulmaz: dashboard, Mac'teki PhoneBox'ın sunduğu bir web sayfasıdır ve iPhone'un tarayıcısında (Safari ya da
Chrome) açılır. iPhone kabloyla takılıyken veri **USB kablosu üzerinden** (iPhone'un USB ağ bağlantısı), değilse
yerel Wi-Fi üzerinden gider. Telefondan Mac'e komut da gönderilebilir: uygulama kapatma, medya ve ses kontrolü,
kilitleme ve uyutma.

Kullanıcı PhoneBox'ı NotchBox gibi tek bir `curl` satırıyla kurar. iPhone'u ilk kez kabloyla taktığında Mac'te
bir QR kod çıkar; telefon kamerasıyla okutulunca dashboard açılır. Sonraki takışlarda, isteğe bağlı bir Kestirmeler
otomasyonu sayesinde dashboard kendiliğinden açılır.

## 2. Hedefler ve kapsam dışı

### Hedefler (v1)

- Telefona uygulama, profil ya da sertifika kurmadan, sadece tarayıcıyla (Safari ya da Chrome) çalışan dashboard.
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
- CPU ve Neural Engine watt'ı (sayaçları root olmadan ilerlemiyor; bkz. `docs/spike-results.md`).
- Fan hızı, geçmiş kaydı (telefondaki 60 saniyelik grafik dışında), uyarı/bildirim eşikleri.
- Telefondan Mac'i uyandırma (Wake on LAN).
- Kendi Kestirmeler komutlarını ya da scriptleri çalıştırma.
- HTTPS, Apple notarization, App Store, Intel Mac'ler.

## 3. Platform kısıtları ve kararlar

| Konu | Karar | Neden |
|---|---|---|
| Telefon tarafı | iPhone tarayıcısında (Safari, Chrome; hepsi WebKit) açılan web sayfası, "Ana Ekrana Ekle" ile uygulama gibi | Kullanıcı telefona hiçbir şey kurulmasını istemiyor |
| Veri yolu | HTTP + WebSocket; kablo takılıyken iPhone'un USB NCM bağlantısı (IPv6 link-local), değilse Wi-Fi | Güvenilen iPhone takılınca USB üzerinden bir ağ bağlantısı açılıyor ve `.local` adı ona çözülüyor; Wi-Fi kapalıyken de çalıştı (spike) |
| Kablonun rolü | Veri yolu, "kabloyla bağlı" kanıtı (kablo modu) ve şarj | Mac, bir istemcinin USB arayüzünden geldiğini görebilir; `usbmuxd` takma olayını Xcode olmadan bildirir |
| HTTP, HTTPS değil | Düz HTTP | HTTPS için ya telefona sertifika kurmak ya da dışarıda sunucu işletmek gerekir; ikisi de hedefe aykırı |
| HTTP'nin bedeli | Wake Lock ve `crypto.subtle` yok | Ekran, sesi açık ama sessiz bir videoyla ve "ambient" ses oturumuyla açık tutulur (spike V4); SHA-256/HMAC sade JS ile yazılır |
| Mac uygulaması | Swift 6 araç zinciri (Swift 5 dil modu), AppKit menü çubuğu, SwiftPM | NotchBox ile aynı; Xcode gerekmez |
| Sunucu | Network.framework (`NWListener`, `NWProtocolWebSocket`) | Ek kütüphane yok |
| Dashboard kodu | Sade HTML/CSS/JS, uygulamanın içine gömülü (`Resources/web`) | Derleme adımı ve npm yok (yaklaşım A) |
| Minimum sistem | macOS 14, Apple Silicon | NotchBox ile aynı; sıcaklık/güç okuma Apple Silicon'a özgü |
| Adres | `http://<LocalHostName>.local:4747/` | `.local` adı IP değişse de sabit kalır; port ayarlardan değişir |
| Bundle ID | `com.phonebox.PhoneBox` | NotchBox'taki adlandırma |
| GitHub deposu | NotchBox'la aynı hesapta `phone-box` | Yayın aşamasında değiştirilebilir |

## 4. Mimari

```
 iPhone (Safari/Chrome)                   Mac: PhoneBox.app (menü çubuğu)
┌──────────────┐  USB kablo ya da Wi-Fi:      ┌──────────────────────────────────┐
│  Dashboard   │  HTTP + WebSocket            │ Server ◄── Sampler ◄── Collectors │
│  (HTML/JS)   │ ◄─────── snapshot / sn ──── │   │   └──► CommandRunner           │
│              │ ─────── cmd (imzalı) ─────► │   ▼                                │
└──────────────┘                              │ AccessPolicy ◄── USBLinks          │
                                              │ USBWatcher · Pairing · MenuBar (QR)│
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
| USBWatcher | `/var/run/usbmuxd` soketini dinler; iPhone takıldı/çıktı olayları (QR penceresini açmak için) | `isIPhoneAttached`, `onChange`, `isAvailable` | usbmuxd |
| USBLinks | Hangi ağ arayüzlerinin iPhone'un USB NCM bağlantısı olduğunu bilir (`AppleUSBNCM*` üzerindeki `anri*`/`en*`); arayüz adı ve numarası takıştan takışa değişir | `isUSB(interfaceName) -> Bool`, `onChange` | IOKit, `getifaddrs` |
| AccessPolicy | Veri akışı ve komut iznine karar verir | `decide(mode, clientOnUSB, authenticated) -> Access` | Saf (Core) |
| Pairing | 32 baytlık anahtarı üretir ve `~/Library/Application Support/PhoneBox/pairing-key` dosyasında (`0600`, klasör `0700`) saklar, sıfırlar; kişisel bağlantıyı kurar. Keychain değil: ad-hoc imzalı uygulama her güncellemeden sonra Anahtar Zinciri şifresi sorardı | `loadOrCreate() -> (key, created)`, `reset()` | Dosya |
| Server | Tek portta dosyaları (Range destekli) ve `/ws` WebSocket'ini sunar; kimlik doğrulama; en fazla 4 istemci; her istemcinin hangi arayüzden geldiğini kaydeder | `start(port)`, `broadcast`, `onCommand` | Network.framework, CryptoKit, Core protokolü |
| CommandRunner | Komutları çalıştırır, sonuç döner | `run(Command) -> CommandResult` | AppKit, CoreAudio, mediaremote-adapter, pmset |
| MenuBar | Simge, menü, QR penceresi | — | AppKit, CoreImage (QR) |
| Web dashboard | Yatay/dikey görünüm, grafik geçmişi, komut arayüzü, rehber, ekranı açık tutma | WebSocket protokolü (bölüm 5) | iOS WebKit (Safari, Chrome) |

## 5. Bağlantı, eşleştirme ve güvenlik

### Eşleştirme

1. PhoneBox ilk açılışta 32 rastgele bayt üretir ve `pairing-key` dosyasına yazar (yeni bir anahtar oluşunca
   `hasEverPaired` sıfırlanır). Bu anahtar base64url biçiminde kişisel
   bağlantının içine konur: `http://<mac>.local:4747/#k=<anahtar>`. `#` sonrası sunucuya hiç gönderilmez.
2. iPhone takıldığında, daha önce hiçbir telefon kimlik doğrulamasını tamamlamamışsa (`hasEverPaired == false`)
   QR penceresi kendiliğinden açılır. Aksi halde hiçbir pencere açılmaz, sadece menü simgesi durumu gösterir.
3. QR penceresinde kişisel bağlantı QR olarak ve altında yazı olarak durur. Bağlantı her yerde `http://` ile
   yazılır: Safari şemasız yazılan adreste önce HTTPS dener.
4. Dashboard anahtarı önce adresteki `#k=` kısmından, yoksa `localStorage`'dan okur ve `localStorage`'a da yazar.
   Adresteki `#k=` silinmez; "Ana Ekrana Ekle" ve Kestirmeler otomasyonu bu adresi kullanır. Ana ekran simgesinden
   açılan sayfanın `localStorage`'ı tarayıcınınkinden ayrıdır; anahtarı simgenin sakladığı adresten alır (2026-11-25,
   Chrome / iOS 27'de denendi: tam ekran, anahtar korunuyor). Eşleştirme sıfırlanınca simge eski anahtarla kalır: yeni
   QR okutulur, açılan sayfa yeniden ana ekrana eklenir, eski simge silinir.
5. "Eşleştirmeyi sıfırla": yeni anahtar üretilir, bağlı bütün istemciler kapatılır, `hasEverPaired = false` olur.

### WebSocket protokolü (`ws://<mac>.local:<port>/ws`, JSON, her mesajda `"v":1`)

| Yön | Mesaj | Açıklama |
|---|---|---|
| Mac → telefon | `{"type":"hello","nonce":"<32 hex>","app":"PhoneBox 0.1.0"}` | Bağlantıya özgü rastgele sayı |
| telefon → Mac | `{"type":"auth","mac":"<HMAC-SHA256(k, "auth:"+nonce) hex>"}` | Yanlışsa bağlantı 4001 ile kapanır (sayfa durur, "Eşleşmedi"); 5 sn içinde gelmezse 4003 ile kapanır (sayfa yeniden dener; telefon kilitliyken açılan bir bağlantı böyle kapanabilir) |
| Mac → telefon | `{"type":"ready","mode":"cable"\|"always","host":"<Mac'in adı>","access":{"streaming":bool,"commands":bool,"cable":bool,"reason":"…"}}` | Kimlik doğrulandı; `host` bilgisayarın adı (durum satırında görünür); `access` alanı bir alttaki `access` mesajıyla aynı |
| Mac → telefon | `{"type":"access","streaming":bool,"commands":bool,"cable":bool,"reason":"ok"\|"not-on-cable"}` | Erişim değiştiğinde; `cable` bu bağlantının USB'den gelip gelmediği ("kablo" / "Wi-Fi") |
| Mac → telefon | `{"type":"snapshot","t":<ms>, ...}` | Saniyede bir (bölüm 6) |
| telefon → Mac | `{"type":"cmd","seq":n,"name":"…","args":"<JSON metni>","mac":"<HMAC(k, "cmd:"+nonce+":"+seq+":"+name+":"+args) hex>"}` | `args` bir metin; imza tam bu metin üzerinden atılır, sonra çözülür |
| Mac → telefon | `{"type":"ack","seq":n,"ok":true}` / `{"ok":false,"error":"not-allowed"\|"bad-signature"\|"app-changed"\|"unsupported"\|"failed"}` | Her komuta cevap |

Kurallar:
- `seq` her bağlantıda kesin olarak artmalı; artmayan `seq` reddedilir (tekrar saldırısı).
- `v` tam olarak tamsayı `1`, `seq` pozitif bir JSON tamsayısı olmalı (`true`, `1.0`, negatif sayı geçersiz); `name`
  bölüm 7'deki adlardan biri olmalı ve `args` o komutun biçimine uymalı. İmzası doğru ama bilinmeyen ad ya da biçim
  `ack` ile `unsupported` döner; bozuk JSON ve tip hataları bağlantıyı kapatır (1008).
- WebSocket yükseltmesinde `Origin` başlığı varsa `http://` + `Host` başlığıyla aynı olmalı; değilse 403 (başka bir
  sitenin sayfası tarayıcı üzerinden bağlanamaz).
- Saniyede 10'dan fazla komut, bozuk JSON ya da yanlış imza → bağlantı kapanır.
- Anahtar ağ üzerinden hiç gitmez. Metrikler şifresiz akar; aynı ağdakiler görebilir ama komut gönderemez.
  Bu açık bilerek kabul edilmiştir.

### AccessPolicy

| Mod | İstemcinin bağlantısı | Veri | Komut |
|---|---|---|---|
| Kablo takılıyken (varsayılan) | Yerel ucu, iPhone USB arayüzündeki kapsamlı bir IPv6 link-local adres (`fe80::…%anri1`/`%en8`); IPv4 hiçbir zaman sayılmaz | İzinli | İzinli |
| Kablo takılıyken | Wi-Fi ya da başka bir arayüzden | Kapalı, `reason: not-on-cable` | Kapalı |
| Her zaman | Kablodan | İzinli | İzinli |
| Her zaman | Wi-Fi ya da başka bir arayüzden | İzinli | **Kapalı** (`commands: false`) |

Komutlar her iki modda da yalnızca kablodan gelen istemcilere açıktır (kullanıcı kararı, 2026-11-25): sayfa düz
HTTP ile sunulduğu için aynı ağdaki aktif bir saldırgan sahte sayfa sunup anahtarı ele geçirebilir; kablo ise sadece
Mac'e takılı ve ona güvenen iPhone'dan gelebilir. Wi-Fi'deki telefon verileri görür, komut düğmeleri kapalı görünür.

Kimlik doğrulamamış bir bağlantı hiçbir durumda veri almaz. USB bağlantısı yalnızca bu Mac'e kabloyla takılı ve
Mac'e güvenen bir iPhone'dan gelebilir; bu yüzden kablo modu gerçekten "kabloyla bağlı telefon" demektir.
Erişim kapanınca bağlantı açık kalır. Kablo çıkınca USB üzerindeki bağlantı kopar; sayfa Wi-Fi üzerinden yeniden
bağlanırsa kablo modunda "Kabloyu tak" görür. Kablo modunda erişimsiz bir istemci varken yeni bir USB bağlantısı
belirirse sunucu o istemcileri 4002 koduyla kapatır; sayfa hemen yeniden bağlanır ve bu sefer USB üzerinden gelir
(iOS'un kablo varken USB adresini seçtiği spike'ta görüldü; Wi-Fi açıkken bu sıralama elle testte doğrulanır).

### Yeniden bağlanma

Ekran kilitlenince iOS bağlantıyı yaklaşık 10–15 sn içinde keser. Sayfa kapanan bağlantıyı 1, 2, 5 saniye (sonra
5 saniyede bir) arayla yeniden dener; ayrıca `visibilitychange`, `pageshow` ve `focus` olaylarında hemen dener.
Chrome'da kilit açılınca `visibilitychange` gelmediği için zamanlayıcı şarttır. Bu sırada "bağlanıyor" durumu
gösterilir.

## 6. Metrikler

Sampler sadece en az bir izinli istemci varken çalışır. Hedef: PhoneBox'ın kendi CPU kullanımı %1'in altında. Ölçülen (Plan 3A, M4,
bir telefon bağlıyken `top`'ta 30 sn ortalama): %0,74. İlk sürümde sıcaklığı her saniye okumak tek başına ~%3,
"Energy Model" grubunun 175 kanalının tamamına abone olmak ~0,1–0,15 puan tutuyordu.
Okunamayan değer JSON'a hiç yazılmaz (alan yok); dashboard "—" gösterir.

| Alan | İçerik | Kaynak |
|---|---|---|
| `cpu` | `total` (%), `cores` (% dizisi), `pCores` (performans çekirdeği sayısı), `load` (1/5/15 dk) | `host_processor_info`, `sysctl hw.perflevel*`, `getloadavg` |
| `mem` | `used`, `total`, `app`, `wired`, `compressed`, `swapUsed` (bayt), `pressure` (`normal`/`warn`/`critical`) | `host_statistics64`, `sysctl hw.memsize`, `vm.swapusage`, `kern.memorystatus_vm_pressure_level` |
| `gpu` | `util` (%) | IOKit `IOAccelerator` → `PerformanceStatistics` |
| `temp` | `avg`, `max` (°C): çip die sensörleri (`PMU tdie*`, `PMU2 tdie*`); CPU/GPU ayrımı sensör adlarından güvenilir çıkarılamadığı için tek değer. 5 sn'de bir okunur | `IOHIDEventSystemClient` (resmi olmayan) |
| `power` | `gpu` (W); MacBook'ta `system` (W). CPU ve ANE watt'ı root gerektirdiği için yok | `IOReport` "Energy Model" grubunun yalnızca `GPU Energy` kanalına abone olunur (resmi olmayan); `AppleSmartBattery` → `PowerTelemetryData.SystemLoad` (pildeyken de Mac'in toplam çekişi), yoksa `SystemPowerIn` |
| `net` | `rx`, `tx` (bayt/sn), `iface` | `sysctl net.link.generic.ifdata.<index>.general` 64 bit sayaçları (`getifaddrs` ve `NET_RT_IFLIST2` güncel macOS'ta sadece alt 32 biti veriyor, 4 GiB'da başa dönüyor); birincil arayüz `SCDynamicStore`'dan (IPv4, yoksa IPv6), bulunan ad 10 sn saklanır |
| `disk` | `free`, `total` (bayt; 60 sn'de bir, okuması ~9 ms sürüyor), `read`, `write` (bayt/sn) | `URLResourceValues` (`volumeAvailableCapacityForImportantUsage`), IOKit `IOBlockStorageDriver` istatistikleri |
| `battery` | `percent`, `charging`, `minutesLeft`; masaüstü Mac'te alan yok, prizdeyken şarj olmuyorsa `minutesLeft` yok | `IOPSCopyPowerSourcesInfo` |
| `media` | Mac'te çalan: `title`, `artist`, `app` (uygulama adı), `playing` (bool); hiçbir şey yoksa alan yok | mediaremote-adapter'ın olay akışındaki son durum (bölüm 7) |
| `audio` | `volume` (0…1), `muted` (bool); varsayılan çıkışta ses kontrolü yoksa alan yok | CoreAudio varsayılan çıkış cihazı |
| `apps` | 3 saniyede bir (diğer saniyelerde alan gönderilmez): CPU'ya göre ilk 5 ile RAM'e göre ilk 5'in birleşimi, en fazla 10 kayıt `{pid, bundleId, name, cpu, mem, quittable}` | `libproc` (`proc_listallpids`, `proc_pid_rusage`, `proc_pidpath`) |

- **Gruplama:** Bir sürecin yolu bir `.app` paketinin içindeyse en dıştaki `.app`'e yazılır ("Chrome Helper" →
  "Chrome"). Root'a ait sistem süreçleri izin olmadan okunamaz ve listede yer almaz. Uygulama adlarından
  görünmez yön karakterleri (`U+200E`, `U+200F`, `U+202A…U+202E`, `U+2066…U+2069`) temizlenir (WhatsApp'ın adı `U+200E`
  ile başlıyor) ve ad en fazla 80 karaktere kısaltılır. Paket dışındaki süreçler (ör. WebKit'in XPC süreçleri) çalıştırılabilir
  dosyanın yoluna göre ayrı satır olur; Safari'nin sekmeleri bu yüzden Safari'ye yazılmaz (Plan 4'te ele alınacak).
- **Uyku/uyanma ve ağ değişimi:** CPU, ağ ve disk sayaçlarının referansı sıfırlanır; ilk örnekte hız alanı
  gönderilmez, böylece anlamsız sıçrama olmaz. Başlarken sayaçlar bir kez önceden okunur, ilk snapshot dolu gelir.
- **Sıcaklık/güç:** Stats ve macmon'un yöntemleri izlenir. Kod alınırsa lisansına uyulur ve
  `THIRD_PARTY_NOTICES.md`'ye yazılır. Sensör adları çipe göre değişir: M4'te test edilir, M1–M3 için Stats'in
  sensör listesi kullanılır, README'de "topluluk testine açık" diye belirtilir.

## 7. Komutlar

| `name` | `args` | Uygulama | Telefonda onay |
|---|---|---|---|
| `quitApp` | `{bundleId, force}` | `NSRunningApplication.terminate()` / `forceTerminate()` | Sadece `force` ("Zorla kapat") |
| `media` | `{action: "playPause"\|"next"\|"previous"}` | mediaremote-adapter (NotchBox'taki gibi, `Vendor/` alt modülü) | Hayır |
| `volume` | `{level: 0…1}` | CoreAudio varsayılan çıkış cihazı | Hayır |
| `mute` | `{on: bool}` | CoreAudio | Hayır |
| `lock` | `{}` | `login.framework` `SACLockScreenImmediate` (dlopen, dönüş değeri kullanılmaz); fonksiyon yoksa `pmset displaysleepnow` | Hayır |
| `displaySleep` | `{}` | `pmset displaysleepnow` | Hayır |
| `sleep` | `{}` | `pmset sleepnow` | Evet |

- Onay sütunu kullanıcı kararıdır (2026-11-25): sadece geri alınamayan "Zorla kapat" ve "Uyut" onay ister.
- `quitApp` sadece `activationPolicy == .regular` olan uygulamalarda çalışır; Finder ve PhoneBox hariçtir (uygulama
  listesindeki `quittable` da aynı kuralla hesaplanır). Telefonun listesi 10 sn'ye kadar eski olabilir ve aynı paketin
  örnekleri tek satırdır; bu yüzden telefon `pid` göndermez: Mac uygulamayı `bundleId` ile bulur ve kapatılabilir
  bütün örneklerine uygular; yoksa `app-changed` döner.
- `sleep`'te `ack` önce gönderilir, Mac 1 sn sonra uyur (yoksa cevap telefona ulaşmaz).
- Ses kaydırıcısı sürüklenirken sayfa en fazla saniyede 4 `volume` gönderir, bırakınca son değeri gönderir (sınır 10/sn).
- Ses kontrolü olmayan çıkış cihazında `volume`/`mute` `unsupported` döner ve kaydırıcı devre dışı kalır.
- Spike 7'de uygulama kapatma, sessiz, ses seviyesi, ekranı kapatma ve kilit hiçbir izin penceresi açmadan
  çalıştı. Medya komutu NotchBox'ta çalışan adaptörle gönderilir.

## 8. Arayüz

### Dashboard (telefon)

Yerleşimler gerçek ölçüde görsel taslaklarla seçildi (2026-11-25, standart iPhone, yatayda 852×393). Kenarlarda
güvenli alan payları (`env(safe-area-inset-*)`) bırakılır; bu telefonda kullanılabilir alan yatayda 734×372. Ölçüler
ekran yüksekliğine göre ayarlanır, iPhone SE'den Pro Max'e kadar her şey kaydırmadan sığar.

- **Yatay (ana görünüm), üç sütun:**
  - Sol: CPU (altında yük) ve RAM (altında kullanılan / toplam) halkaları.
  - Orta: seçili metriğin son 60 saniyelik grafiği; altında 3×2 metrik kutucuğu (GPU, Sıcaklık, Güç, Ağ, Disk boş,
    Pil); en altta kontrol şeridi.
  - Sağ: durum satırı, "Şimdi çalıyor" kartı, uygulama listesi (7–8 satır).
- **Dikey ("tek bakış"):** yukarıdan aşağı durum satırı, yan yana iki halka, grafik, 3×2 kutucuk, en çok kullanan
  5 uygulama, "Şimdi çalıyor" (tek satır), kontrol şeridi. Kaydırma yok.
- **Stil:** siyah zemin, sistem fontu, `#1c1c1e` kartlar, 16 px köşe, sayılarda sabit genişlikli rakamlar. Renkler:
  CPU yeşil, RAM mavi, GPU mor, sıcaklık turuncu, güç sarı, ağ camgöbeği, disk gri, pil yeşil.
- **Kutucuklar:** sadece ana değer (GPU %, ortalama °C, Mac'in tamamı W, ↓/↑ hız, boş alan, pil % ve şarj simgesi).
  Ayrıntılar grafik seçilince grafik başlığında görünür.
- **Grafik:** seçili metriğin son 60 saniyesi, `<canvas>` ile. Bir halkaya ya da kutucuğa dokununca grafik o metriğe
  geçer; seçili olan kendi renginde çerçevelenir. İlk açılışta CPU, sonra son seçim (`localStorage`). Geçmiş sadece
  telefonun belleğinde tutulur, sayfa yenilenince sıfırlanır; değer gelmeyen saniyeler çizgide boşluk olur. Başlıkta
  metrik adı, anlık değer ve ayrıntı (yük, en yüksek sıcaklık, arayüz adı, okuma/yazma…).

  | Metrik | Grafikte | Ölçek |
  |---|---|---|
  | CPU, RAM, GPU, Pil | % | 0–100 sabit |
  | Sıcaklık | ortalama çizgisi + ince "en yüksek" çizgisi | değerlere göre otomatik |
  | Güç | Mac'in tamamı (W) | 0'dan otomatik |
  | Ağ | ↓ ve ↑ iki çizgi | 0'dan otomatik, birim kendisi değişir |
  | Disk | okuma ve yazma iki çizgi | 0'dan otomatik |
- **Uygulama listesi:** CPU yüzdesi ve bellek (RAM halkasıyla aynı ikili birim: GB = 2³⁰ bayt). Varsayılan CPU'ya
  göre; başlığa dokununca RAM'e göre, tekrar dokununca CPU'ya. Kapatılamayan satırlar (`quittable: false`) gri.
- **Şimdi çalıyor:** şarkı, sanatçı ve uygulama (kapak resmi yok). `media` alanı yoksa gizlenir; yatayda liste bir
  satır uzar.
- **Kontrol şeridi:** önceki, oynat/duraklat (çalma durumuna göre simge), sonraki, ses kaydırıcısı (Mac'in o anki
  seviyesi), sessiz (🔈/🔇), "⋯". Dokunma alanları en az 44×44 pt. `audio` alanı yoksa kaydırıcı ve sessiz soluk.
- **Komut etkileşimleri** (görsel taslaklarla seçildi):
  - Uygulamaya dokununca alttan panel: ad, CPU ve bellek; "Kapat", "Zorla kapat", "Vazgeç". Gri satıra dokununca
    sadece "Bu süreç buradan kapatılamaz".
  - "⋯" menüsü şeridin üstünde açılır: Kilitle, Ekranı kapat, Uyut, ayraç, Kurulum rehberi.
  - Onay sadece "Zorla kapat" ve "Uyut" için (bölüm 7). "Uyut" penceresi bağlantının kesileceğini ve Mac'in
    klavyesine ya da trackpad'ine dokunarak uyandırılacağını, sonra dashboard'un kendiliğinden bağlanacağını söyler.
  - Her komuttan sonra üstte 2 sn bildirim: başarıda yeşil tik; hatada kırmızı ve sebep (`not-allowed` → "Komutlar
    sadece kabloyla çalışır", `app-changed` → "Uygulama değişmiş, liste yenilendi", `unsupported` → ses
    komutlarında "Bu çıkışta ses kontrolü yok", diğerlerinde "Bu komut desteklenmiyor", `failed` → "Olmadı").
  - `access.commands` false iken (Wi-Fi) şerit, panel düğmeleri ve menüdeki komutlar soluk; dokununca "Komutlar
    sadece kabloyla çalışır".
- **Durum satırı:** renkli nokta, Mac'in adı (`ready.host`) ve yol (`access.cable`): "● MacBook Pro · kablo". Yeşil
  bağlı, gri bağlanıyor, turuncu Wi-Fi'de (komutlar kapalı).
- **Durumlar:** veri gelmezse değerler donar ve soluklaşır, ortada küçük bir kart çıkar: "Kabloyu tak" (kablo
  modunda telefon Wi-Fi'de) · "Mac'e ulaşılamıyor" (arka planda yeniden dener) · "Eşleşmedi" ("Mac'teki QR kodunu
  okut, açılan sayfayı yeniden Ana Ekrana Ekle, eski simgeyi sil"). Okunamayan metrik "—".
- **Başlat ekranı:** her açılışta siyah ekranda büyük "Başlat" düğmesi ve altında "Ekranı açık tutmak için bir kez
  dokun" (aşağıdaki video bir dokunuşla başlayabiliyor).
- **İlk açılış rehberi** (bir kez; sonra "⋯ → Kurulum rehberi"):
  1. Ana Ekrana Ekle → tam ekran. Chrome ve Safari için ayrı kısa tarif; sayfa ana ekrandan açıldıysa
     (`navigator.standalone`) adım ✓ görünür.
  2. İsteğe bağlı, kablo takılınca otomatik açılsın: Kestirmeler → Otomasyon → Şarj Aleti → "URL'yi Aç" (kişisel
     bağlantı, "Kopyala" düğmesiyle). Bu yol sayfayı tam ekran değil tarayıcıda açar; henüz denenmedi, rehberde
     öyle yazar.
  3. Telefonu yan çevir (stand önerilir).

  Rehberin son düğmesi "Başlat"tır; ilk açılışta tek dokunuş yeter.
- **Ana ekran:** `apple-touch-icon.png` (180×180): siyah zemin üstünde iç içe yeşil ve mavi halka;
  `<meta name="apple-mobile-web-app-title" content="PhoneBox">`. Ana ekran simgesinden açılan sayfada adres çubuğu
  yoktur (bölüm 5, eşleştirme).
- **Ekranı açık tutma (spike V4):** Sesi açık oynatma bir dokunuş gerektirdiği için dashboard ilk açılışta "Başlat"
  düğmesi gösterir; video ilk dokunuşta başlar (oynatma reddedilirse düğme yeniden çıkar). 64×64 siyah görüntü ve sessiz ses izi
  olan 2 saniyelik bir video (`keepawake.mp4`) sesi açık (`muted` değil), döngüsüz ve satır içi oynatılır;
  0,5 sn'yi geçince başa sarılır. Oynatmadan önce `navigator.audioSession.type = "ambient"` yapılır; böylece
  telefondaki müzik durmaz ve kilit ekranı kullanıcının şarkısında kalır. Sayfa görünürken 3 saniyede bir "video
  duruyorsa başlat" denetimi yapılır (Chrome'da kilit açılınca video duraklamış kalıyor). `audioSession` yoksa
  video yine oynatılır ama telefondaki müzik durabilir; rehberde bu not edilir.
- **OLED koruması:** 3 dakikada bir bütün içerik ±2 piksel kayar.
- **Dil ve sayı biçimi:** `navigator.language`'a göre Türkçe/İngilizce; sayılar `Intl.NumberFormat` ile.

### Sayfa kodu

Sade HTML/CSS/JS, derleme adımı ve dış kütüphane yok. Her dosya tek bir iş yapar, `globalThis.PhoneBox` altına
yazar ve sırayla klasik `<script>` etiketleriyle yüklenir (ES modül `import`'u yok); böylece Swift testleri saf
parçaları JavaScriptCore'da doğrudan çalıştırabilir. İki yön için tek bir HTML vardır, yerleşimi CSS
(`@media (orientation: …)`) değiştirir. Mac'in sunduğu dosya listesi yeni dosyalara göre güncellenir.

| Dosya | Görevi | Test |
|---|---|---|
| `sha256.js` | SHA-256 ve HMAC (var) | JavaScriptCore |
| `i18n.js` | TR/EN metinler | — |
| `format.js` | sayı ve birim biçimleri | JavaScriptCore |
| `history.js` | metrik başına 60 saniyelik geçmiş | JavaScriptCore |
| `chart.js` | grafik ölçeği (saf) ve `<canvas>` çizimi | ölçek JavaScriptCore'da, çizim gözle |
| `connection.js` | bağlantı, eşleşme, yeniden bağlanma (bugünkü `app.js`'ten) | gözle / telefonda |
| `commands.js` | komut imzası, `seq`, ses kaydırıcısının hız sınırı | imza ve hız sınırı JavaScriptCore'da |
| `view.js` | halkalar, kutucuklar, liste, şarkı kartı, durumlar | gözle |
| `ui.js` | panel, menü, onay, bildirim, rehber, Başlat ekranı, OLED kayması | gözle |
| `app.js` | parçaları birbirine bağlar | — |

### Uygulama sırası

Plan 3B (Mac tarafı: bölüm 7'deki komutlar, `media` ve `audio` alanları, `host` ve `cable`, bölüm 5'teki protokol
kuralları ve bağlantı yöneticisinin testlerle denenebilir hâle getirilmesi) → Plan 4 (bu arayüz; son görevi
kullanıcıyla telefonda uçtan uca kontrol) → Plan 5 (dağıtım).

### Menü çubuğu (Mac)

Simge telefon çizimi: gri = izinli istemci yok, yeşil = en az bir istemci veri alıyor. Ayrı ayarlar penceresi yoktur.

- Durum satırı (ör. "iPhone bağlı · 1 cihaz", "Port 4747 kullanımda", "USB algılanamıyor")
- QR kodu göster
- Mod: ● Kablo takılıyken / ○ Her zaman
- Port: 4747… (Plan 5; o zamana kadar `defaults write com.phonebox.PhoneBox port -int <port>`)
- Girişte başlat (ServiceManagement)
- Eşleştirmeyi sıfırla
- Güncelleme (NotchBox'taki gibi)
- Çık

## 9. Hata yönetimi

| Durum | Davranış |
|---|---|
| Port dolu | Başka porta geçilmez (kayıtlı bağlantı bozulmasın). Menüde uyarı ve "Port…" ile yeni port; QR güncellenir |
| usbmuxd yok | Takma olayıyla QR penceresi açılamaz; menüde uyarı. Kablo modu etkilenmez (USB arayüzüne bakar) |
| Tarayıcı HTTPS deniyor | İlk baytı `0x16` (TLS el sıkışması) olan bağlantı hemen kapatılır; tarayıcı HTTP'ye düşer |
| Video byte aralığı istiyor | `Range` isteğine `206 Partial Content`, geçersize `416`; iOS aralıksız sunulan videoyu oynatmaz |
| Collector hatası / takılma | Her `sample()` zaman sınırlı; değer `null`, aynı hata log'a bir kez yazılır |
| Protokol ihlali | Bozuk mesaj, yanlış imza, artmayan `seq`, hız sınırı aşımı → bağlantı kapanır (1008) |
| Kimlik doğrulamadan önce metin dışı çerçeve | 1008 ile kapanır (ping seli koruması); sonrasında ikili çerçeve 1003, bir okumadaki pinglerden sadece sonuncusu cevaplanır |
| Geçersiz WebSocket çerçevesi | 125 bayttan uzun ya da parçalı kontrol çerçevesi, RSV bitleri, ayrılmış opcode'lar, 64 KB'tan büyük ya da negatif uzunluk → 1008 |
| Boşta ya da takılan bağlantı | İstek başlığı 10 sn'de gelmezse kapanır; en fazla 32 TCP bağlantısı; kapanış 2 sn'de bitmezse kesilir; 256'dan fazla gönderilmemiş mesaj birikirse kesilir |
| Ölü bağlantı | 15 sn'de bir ping; 45 sn hiçbir şey gelmezse kesilir; 5 sn uygun yol yoksa kesilir; kablo çıkınca 1,5 sn sonra kaybolan USB arayüzündeki istemciler kesilir |
| 5. istemci | Reddedilir (en fazla 4) |
| Mac uyandı / ağ değişti | Sayaç referansları sıfırlanır; dinleyici tüm arayüzlerde kalır, `.local` yeni ağda çalışır |
| Komut başarısız | `ack` içinde `error`; dashboard bildirim gösterir |

Süreç: SIGPIPE yok sayılır; örnekleyici çalışırken App Nap engellenir (`beginActivity`), durunca bırakılır.

Log: `os_log`, alt sistem `com.phonebox.PhoneBox`. Dosyaya yazılması gereken her şey `~/Library/Logs/PhoneBox` ya
da `~/Library/Caches` altına gider: spike'ta yeni başlatılan uygulama `~/Documents`'a yazamadığı için açılamadı.

## 10. Test

- **Birim testleri (`Tests/PhoneBoxCoreTests`, Swift Testing):** CPU yüzdesi (tick farkları), RAM hesabı, ağ
  sayacının sıfırlanması/taşması, uygulama gruplama, mesaj kodlama/çözme, HMAC (RFC 4231 test vektörleri),
  artmayan `seq`'in reddi, `AccessPolicy` tablosunun bütün satırları.
- **JS testleri:** Swift testleri sayfanın saf parçalarını JavaScriptCore'da çalıştırır (Node/npm gerekmez):
  `sha256.js` RFC 4231 vektörleri ve Swift'in HMAC sonucuyla; `format.js`, `history.js`, grafik ölçeği, komut imzası
  ve ses kaydırıcısının hız sınırı (bölüm 8, Sayfa kodu).
- **Görünüm kontrolü:** Mac'teki tarayıcı panelinde canlı veriyle dört iPhone ölçüsü (SE, standart, Pro Max; yatay ve
  dikey), ekran görüntüsüyle.
- **Bağlantı yöneticisi testleri (`Tests/PhoneBoxTests`):** uygulama hedefini `@testable import` ile dener; sahte
  bağlantı ve sahte komut çalıştırıcıyla `ready`, kablo kuralı, `ack` ve mod değişimi. Gerçek sistemi kullanan
  testler (ses seviyesini okuyup aynı değeri yazmak, Satranç'ı açıp kapatmak) sadece `PHONEBOX_LIVE=1` ile çalışır;
  kilitleme, uyutma ve ekranı kapatma hiçbir testte çalıştırılmaz.
- **Elle test:** `docs/manual-testing.md`, gerçek iPhone ile adım adım kontrol listesi (eşleştirme, iki mod, her
  komut, durumlar, dikey/yatay, yeniden bağlanma).

## 11. Spike (ilk iş)

Uygulamadan önce küçük bir deneme yapılır; sonuçlar `docs/spike-results.md`'ye yazılır. Kritik madde başarısız
olursa tasarıma dönülür. **Yapıldı (2026-11-25):** kritik maddelerin hepsi geçti; 6 ve 9 kısmen, 8 denenmedi.

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

Madde 3 sonradan denendi (2026-11-25, Chrome / iOS 27): ana ekran simgesi `#k=`'yi koruyor, sayfa tam ekran açılıyor
ve veri geliyor.

## 12. Dağıtım ve klasör yapısı

NotchBox ile aynı:

- Kurulum: `curl -fsSL https://raw.githubusercontent.com/cyesaa/phone-box/main/install.sh | bash`
  (`curl` ile inen dosya karantinaya alınmaz, imzasız uygulama engellenmez); kaldırma `… | bash -s -- --uninstall`.
- `make app` (ad-hoc imzalı `build/PhoneBox.app`), `make test`, `make release VERSION=x.y.z` (GitHub Releases'a
  `PhoneBox.zip`).
- Gereksinim: Apple Silicon, macOS 14+. README önce Türkçe, sonra İngilizce, son kullanıcı için yazılır.

```
Package.swift  Makefile  install.sh  LICENSE  THIRD_PARTY_NOTICES.md  README.md
scripts/                  bundle.sh, build-adapter.sh, dist.sh, release.sh, make-icon.swift
Sources/PhoneBoxCore/     modeller, hesaplar, protokol, HMAC, AccessPolicy
Sources/PhoneBox/         uygulama, Collectors, Sampler, USBWatcher, Server, Pairing, CommandRunner, MenuBar
Resources/                Info.plist, AppIcon.icns, en.lproj, tr.lproj
Resources/web/            index.html, styles.css, sha256.js, i18n.js, format.js, history.js, chart.js,
                          connection.js, commands.js, view.js, ui.js, app.js, keepawake.mp4, apple-touch-icon.png
Vendor/mediaremote-adapter/   (git alt modülü)
Tests/PhoneBoxCoreTests/  Tests/PhoneBoxTests/
docs/design/2026-11-25-phonebox-design.md   docs/spike-results.md   docs/manual-testing.md
```

## 13. Açık riskler

- **Ekranın açık kalması:** WebKit'in "sesi açık görüntü+ses videosu oynarken uyuma" davranışına ve Audio Session
  API'ye dayanıyor; bir iOS güncellemesi değiştirirse kullanıcı "Otomatik Kilit"i elle ayarlar.
- **USB ağ bağlantısı:** iOS'un güvenilen bir Mac'e USB ağ bağlantısı açmasına dayanıyor; açmazsa dashboard Wi-Fi
  üzerinden çalışır, kablo modu ise "Kabloyu tak" gösterir (menüde "Her zaman" moduna geçilebilir).
- **Resmi olmayan API'ler** (sıcaklık, güç, kilitleme, medya): macOS güncellemesiyle bozulabilir; her biri tek
  başına devre dışı kalacak şekilde yalıtılır.
- **Şifresiz metrik trafiği:** aynı ağdakiler CPU/uygulama adlarını görebilir; komutlar imzalı olduğu için pasif
  dinleyicilere karşı güvende.
- **Aynı ağdaki aktif saldırgan (Plan 2 son incelemesi):** sayfa düz HTTP ve `.local` adla sunulduğu için mDNS/ARP
  sahteciliği yapan biri değiştirilmiş bir sayfa sunup anahtarı alabilir ya da kimlik doğrulamayı aktarabilir. Bu yüzden
  komutlar her iki modda da yalnızca kablodan (USB) gelen istemcilere açıktır (bölüm 5, AccessPolicy). Böyle bir
  saldırgan "Her zaman" modunda yine de metrikleri görebilir.
- **Safari depolama temizliği:** anahtar kişisel bağlantıda durduğu için etkilenmez; bozulursa QR yeniden okutulur.
