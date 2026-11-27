# PhoneBox — Tasarım Dokümanı

- **Tarih:** 2026-11-25
- **Durum:** Onaylandı (2026-11-25); deneme sonuçlarına göre güncellendi (2026-11-25). Deneme planı:
  `docs/design/plans/2026-11-25-phonebox-spike.md`, sonuçlar: `docs/spike-results.md`. Görünüm ve canlılık
  (Aktivite Halkaları, Okyanus paleti, sınıra yaklaşınca kızarma, saat ve telefonun pili) eklendi ve onaylandı
  (2026-11-26, bölüm 8)
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
- Akıcı, canlı görünüm: değerler yumuşakça değişir, sınırına yaklaşan metrik kızarır, sınırda kalan göz ucuyla fark
  edilecek kadar belirgin uyarır; telefonun saati ve pili göstergede (bölüm 8).
- Telefondan komutlar: uygulama kapat / zorla kapat, oynat-duraklat / önceki / sonraki, ses seviyesi ve sessiz,
  Mac'i kilitle, ekranı kapat, uyut.
- QR kodla eşleştirme; imzalı (HMAC) kimlik doğrulama ve komutlar.
- İki erişim modu: "kablo takılıyken" (varsayılan) ve "her zaman"; ayarlar penceresinden seçilir.
- Arayüz dili İngilizce + Türkçe, telefonun / Mac'in diline göre otomatik.
- `curl | bash` kurulum, GitHub Releases, menüden güncelleme, `--uninstall`.

### Kapsam dışı (v1)

- Android ve native iOS uygulaması (kullanıcı kararı: sadece iPhone, telefona kurulum yok).
- CPU ve Neural Engine watt'ı (sayaçları root olmadan ilerlemiyor; bkz. `docs/spike-results.md`).
- Fan hızı, geçmiş kaydı (telefondaki 60 saniyelik grafik dışında), bildirimler (ses, titreşim, telefon
  bildirimi). Sınırlar yalnız ekranda renk ve ışıkla gösterilir (bölüm 8); sınırlar ayarlardan değiştirilemez.
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
| Mac uygulaması | Swift 6 araç zinciri (Swift 5 dil modu), AppKit menü çubuğu, SwiftUI ayarlar penceresi (0.4.0), SwiftPM | NotchBox ile aynı; Xcode gerekmez |
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
| AccessPolicy | Veri akışı ve komut iznine karar verir | `decide(mode, lockAndMusicOverWiFi, clientOnUSB, authenticated) -> Access` | Saf (Core) |
| Pairing | 32 baytlık anahtarı üretir ve `~/Library/Application Support/PhoneBox/pairing-key` dosyasında (`0600`, klasör `0700`) saklar, sıfırlar; kişisel bağlantıyı kurar. Keychain değil: ad-hoc imzalı uygulama her güncellemeden sonra Anahtar Zinciri şifresi sorardı | `loadOrCreate() -> (key, created)`, `reset()` | Dosya |
| Server | Tek portta dosyaları (Range destekli) ve `/ws` WebSocket'ini sunar; kimlik doğrulama; en fazla 4 istemci; her istemcinin hangi arayüzden geldiğini kaydeder | `start(port)`, `broadcast`, `onCommand` | Network.framework, CryptoKit, Core protokolü |
| CommandRunner | Komutları çalıştırır, sonuç döner | `run(Command) -> CommandResult` | AppKit, CoreAudio, mediaremote-adapter, pmset |
| PhoneBattery | Kabloyla takılı iPhone'un pilini okur (bölüm 6, `phone`) | `start()`, `stop()`, `latest` | `MobileDevice.framework` (resmi olmayan, `dlopen`) |
| MenuBar | Simge, menü, QR penceresi, ayarlar penceresi (0.4.0) | — | AppKit, SwiftUI, CoreImage (QR) |
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
| Mac → telefon | `{"type":"ready","mode":"cable"\|"always","host":"<Mac'in adı>","limits":{"power":[15,35]},"access":{"streaming":bool,"commands":["…"],"cable":bool,"reason":"…"},"build":"<12 hex>"}` | Kimlik doğrulandı; `host` bilgisayarın adı ("⋯" menüsünün başlığında görünür; her `ready`'de yeniden okunur, Mac yeniden adlandırılınca yeni ad gelir); `limits.power` güç kutusunun kızarmaya başladığı ve kıpkırmızı olduğu watt (bölüm 8, Mac çipine göre seçer); `access` alanı bir alttaki `access` mesajıyla aynı; `build` sayfa dosyalarının adı (`WebBuild`: yolların, boyların ve içeriklerin SHA-256'sının ilk 12 hanesi). Sayfa ilk `ready`'deki adı hatırlar; sonraki bir `ready` başka ad getirirse (PhoneBox güncellendi) kendini yeniden yükler ve "Başlat" yeniden ister. Sayfa kendi adını index.html'den de alır (Mac sunarken `<meta name="phonebox-build">` etiketine damgalar), böylece daha ilk `ready` başka ad getirse de yeniden yüklenir |
| Mac → telefon | `{"type":"access","streaming":bool,"commands":["…"],"cable":bool,"reason":"ok"\|"not-on-cable"}` | Erişim değiştiğinde; `commands` telefonun gönderebileceği komutların adları (bölüm 7): kablodan hepsi, Wi-Fi'den "Wi-Fi'den Kilit ve Müzik" açıkken `["media","lock"]`, değilse `[]` (aşağıda AccessPolicy); `cable` bu bağlantının USB'den gelip gelmediği ("kablo" / "Wi-Fi") |
| Mac → telefon | `{"type":"snapshot","t":<ms>, ...}` | Saniyede bir (bölüm 6) |
| telefon → Mac | `{"type":"cmd","seq":n,"name":"…","args":"<JSON metni>","mac":"<HMAC(k, "cmd:"+nonce+":"+seq+":"+name+":"+args) hex>"}` | `args` bir metin; imza tam bu metin üzerinden atılır, sonra çözülür |
| Mac → telefon | `{"type":"ack","seq":n,"ok":true}` / `{"ok":false,"error":"not-allowed"\|"app-changed"\|"unsupported"\|"failed"}` | Her komuta cevap |

Kurallar:
- `seq` her bağlantıda kesin olarak artmalı; artmayan `seq` reddedilir (tekrar saldırısı).
- `v` tam olarak tamsayı `1`, `seq` pozitif bir JSON tamsayısı olmalı (`true`, `1.0`, negatif sayı geçersiz); `name`
  bağlantının `access.commands` listesinde olmalı ve `args` o komutun biçimine uymalı. İmzası doğru ama listede
  olmayan ad (bilinmeyen ad da) `ack` ile `not-allowed`, listedeki adın bozuk biçimi `unsupported` döner; bozuk JSON
  ve tip hataları bağlantıyı kapatır (1008).
- Her istekte (dosya ve WebSocket) `Host` bu Mac'i göstermeli: `<LocalHostName>.local`, bir IP adresi (IPv4 ya da
  köşeli parantezli, bölgeli ya da bölgesiz IPv6) ya da `localhost`; port ve büyük/küçük harf fark etmez. Değilse ya da
  hiç yoksa 403 (0.4.1): adını Mac'in adresine çözdüren başka bir sitenin sayfası (DNS rebinding) kendi adını gönderir.
- WebSocket yükseltmesinde `Origin` başlığı varsa `http://` + `Host` başlığıyla aynı olmalı; değilse 403 (başka bir
  sitenin sayfası tarayıcı üzerinden bağlanamaz).
- Saniyede 10'dan fazla komut, bozuk JSON ya da yanlış imza → bağlantı kapanır. Bu sınırın, `WiFiCommandLimit`'in ve
  canlılık denetiminin süreleri monoton saatle ölçülür (`ContinuousClock`, 0.4.1): Mac'in saati değişince sınır uzamaz
  ya da atlanmaz, canlı telefon düşürülmez.
- Anahtar ağ üzerinden hiç gitmez. Metrikler şifresiz akar; aynı ağdakiler görebilir ama anahtar olmadan komut
  gönderemez. Bu açık bilerek kabul edilmiştir.

### AccessPolicy

`AccessPolicy.decide(mode, lockAndMusicOverWiFi, clientOnUSB, authenticated)`; `lockAndMusicOverWiFi` ayarlar
penceresindeki "Wi-Fi'den kilit ve müzik" ayarıdır (varsayılan kapalı).

| Mod | İstemcinin bağlantısı | Veri | Komut (`commands`) |
|---|---|---|---|
| Kablo takılıyken (varsayılan) | Yerel ucu, iPhone USB arayüzündeki kapsamlı bir IPv6 link-local adres (`fe80::…%anri1`/`%en8`); IPv4 hiçbir zaman sayılmaz | İzinli | Hepsi |
| Kablo takılıyken | Wi-Fi ya da başka bir arayüzden | Kapalı, `reason: not-on-cable` | Kapalı (`[]`), ayar ne olursa olsun |
| Her zaman | Kablodan | İzinli | Hepsi |
| Her zaman | Wi-Fi ya da başka bir arayüzden | İzinli | Ayar kapalıyken **kapalı** (`[]`); açıkken yalnız kilit ve medya (`["media","lock"]`) |

Komutlar her iki modda da kablodan gelen istemcilere açıktır, Wi-Fi'den gelenlere kapalıdır (kullanıcı kararı,
2026-11-25): sayfa düz HTTP ile sunulduğu için aynı ağdaki aktif bir saldırgan sahte sayfa sunup anahtarı ele
geçirebilir; kablo ise sadece Mac'e takılı ve ona güvenen iPhone'dan gelebilir. Tek istisna "Wi-Fi'den Kilit ve
Müzik" ayarıdır (kullanıcı kararı, 2026-11-26, 0.2.0): açıkken "Her zaman" modunda Wi-Fi'deki telefon Mac'i
kilitleyebilir ve müziği oynatıp duraklatabilir, sonrakine ya da öncekine geçebilir. Risk bilerek kabul edildi: anahtarı
ele geçiren biri en kötü ihtimalle ekranı kilitler (özel kilit çağrısı yoksa `lock` ekranı kapatır da) ya da şarkı atlatır; ses, sessiz, ekranı kapatma, uygulama kapatma
ve uyutma yine yalnız kablodan gelir. Bu komutlar Wi-Fi'de sınırlıdır (`WiFiCommandLimit`, bütün Wi-Fi
telefonlar birlikte sayılır, kablo sınırlanmaz): `lock` 30 sn'de en fazla bir kez, `media` herhangi bir 1 sn'de en fazla
3 kez; sınırı aşan komut çalıştırılmaz, `ack … failed` alır. Böylece çalınmış bir anahtarla da Mac sürekli kilitli
tutulamaz ya da medya yardımcı süreçleri art arda başlatılamaz; kötüye kullanım ayarı kapatınca ya da "Eşleştirmeyi
sıfırla" deyince biter. Wi-Fi'deki telefon verileri görür; izinli olmayan komutların düğmeleri soluk
görünür.

Kimlik doğrulamamış bir bağlantı hiçbir durumda veri almaz. USB bağlantısı yalnızca bu Mac'e kabloyla takılı ve
Mac'e güvenen bir iPhone'dan gelebilir; bu yüzden kablo modu gerçekten "kabloyla bağlı telefon" demektir.
Erişim kapanınca bağlantı açık kalır. Kablo çıkınca USB üzerindeki bağlantı kopar; sayfa Wi-Fi üzerinden yeniden
bağlanırsa kablo modunda "Kabloyu tak" görür. Bir iPhone takılınca (her iki modda) sunucu Wi-Fi'deki kimliği
doğrulanmış istemcileri 4002 koduyla kapatır; sayfa hemen yeniden bağlanır ve takılı telefon bu sefer USB üzerinden
gelir (iOS'un kablo varken USB adresini seçtiği spike'ta görüldü; Wi-Fi açıkken bu sıralama elle testte doğrulanır).
"Her zaman" modunda bütün komutlar ancak böyle açılır; takılı olmayan başka bir cihaz bir kez yeniden bağlanır.
Takıldıktan 3 ve 8 sn sonra bakılır (USB bağlantısı geç gelebilir); ikisi de yalnız takılmadan önce kimliğini
doğrulamış telefonları kapatır, böylece ilkinde Wi-Fi'den geri gelen telefon ikincide yeniden kapatılmaz (0.4.1).
Mod ya da "Wi-Fi'den Kilit ve Müzik" değişince kimliği doğrulanmış her istemcinin erişimi yeniden hesaplanır; erişimi
değişene `access` gönderilir.

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
| `battery` | `percent`, `charging`, `plugged` (prizde mi), `minutesLeft`; masaüstü Mac'te alan yok, prizdeyken şarj olmuyorsa `minutesLeft` yok | `IOPSCopyPowerSourcesInfo` (`plugged`: `Power Source State` = `AC Power`) |
| `phone` | Kabloyla takılı iPhone'un pili: `percent`, `charging`, `plugged`. USB'den yalnız bir iPhone takılıysa ve okunabildiyse var; okuma başarısız olursa son iyi değer 5 dk tutulur, sonra alan kalkar. Telefon takılınca ve sonra dakikada bir, yalnız örnekleyici çalışırken okunur; okuma ~150 ms sürdüğü için örnekleyiciyi bekletmez, ayrı kuyrukta yapılır, biri sürerken yenisi başlamaz | `MobileDevice.framework` (resmi olmayan, `dlopen`): `AMDeviceNotificationSubscribe`, yalnız USB arayüzündeki cihazlar (`AMDeviceGetInterfaceType` = 1); `AMDeviceConnect` → `ValidatePairing` → `StartSession` → `AMDeviceCopyValue("com.apple.mobile.battery", "BatteryCurrentCapacity" / "BatteryIsCharging" / "ExternalConnected")`. Root gerekmez; telefonun bu Mac'e güvenmesi yeter (2026-11-26, M4 / macOS 27.2'de denendi: %100, dolu, prizde, 149 ms) |
| `media` | Mac'te çalan: `title`, `artist`, `app` (uygulama adı), `playing` (bool); hiçbir şey yoksa alan yok (iki parça arasındaki kısa "hiçbir şey" 1,5 sn beklenir, monoton saatle) | mediaremote-adapter'ın olay akışındaki son durum (bölüm 7) |
| `audio` | `volume` (0…1), `muted` (bool); varsayılan çıkışta ses kontrolü yoksa alan yok | CoreAudio varsayılan çıkış cihazı |
| `apps` | 3 saniyede bir (diğer saniyelerde alan gönderilmez): CPU'ya göre ilk 5 ile RAM'e göre ilk 5'in birleşimi, en fazla 10 kayıt `{pid, bundleId, name, cpu, mem, quittable}` | `libproc` (`proc_listallpids`, `proc_pid_rusage`, `proc_pidpath`) |

- **Gruplama:** Bir sürecin yolu bir `.app` paketinin içindeyse, onu içeren paketlerden Dock'ta çalışan (regular) en
  içtekine, öyle biri yoksa en dıştaki `.app`'e yazılır (0.4.1): Xcode'un içindeki Simulator "Simulator" olur, kendi
  CPU'su ve Kapat'ıyla; "Chrome Helper" → "Chrome" (macOS bazı yardımcıları da listeler, ama Dock uygulaması olarak
  değil). Root'a ait sistem süreçleri izin olmadan okunamaz ve listede yer almaz. Uygulama adlarından
  görünmez yön karakterleri (`U+200E`, `U+200F`, `U+202A…U+202E`, `U+2066…U+2069`) temizlenir (WhatsApp'ın adı `U+200E`
  ile başlıyor) ve ad en fazla 80 karaktere kısaltılır. Paket dışındaki süreçler (ör. WebKit'in XPC süreçleri) çalıştırılabilir
  dosyanın yoluna göre ayrı satır olur; Safari'nin sekmeleri bu yüzden Safari'ye yazılmaz (Plan 4'te ele alınacak).
- **Uygulama CPU'su:** Önceki örnekten bu yana harcanan CPU zamanı aralığın süresine bölünür. Önceki örnekten sonra
  başlayan süreç (`ri_proc_start_abstime`) bütün CPU zamanını bu aralıkta harcamıştır, hepsi sayılır: bir saniyelik
  derleyici süreçleri de görünür (0.4.1). Daha eski olup ilk kez görülen süreç bu sefer %0 sayılır.
- **Uyku/uyanma ve ağ değişimi:** CPU, ağ ve disk sayaçlarının referansı sıfırlanır; ilk örnekte hız alanı
  gönderilmez, böylece anlamsız sıçrama olmaz. Başlarken sayaçlar bir kez önceden okunur, ilk snapshot dolu gelir.
  Saniyelik zamanlayıcı her saniyenin ortasında çalışır (sayfa her snapshot'ı tam saniyesine yazar); uykuda duran bir
  saate bağlı olduğu için uyanınca yeniden kurulur (0.4.1).
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
- Kablodan bütün komutlar gelir. Wi-Fi'den yalnız `media` ve `lock` gelebilir, `lock` 30 sn'de bir, `media` saniyede 3
  ile sınırlı (bütün Wi-Fi telefonlar birlikte; kablo sınırsız), o da "Her zaman" modunda "Wi-Fi'den
  Kilit ve Müzik" açıkken (kullanıcı kararı, 2026-11-26; bölüm 5): ikisi zararsızdır, sahte sayfayla anahtarı alan
  biri ekranı kilitler ya da şarkı atlatır, o kadar. Not: `lock`'ın yedeği olan `pmset displaysleepnow` (özel kilit
  çağrısı yoksa) ekranı da kapatır; Wi-Fi'den bu da `lock` ile olabilir. Ses ve sessiz, ekranı kapatma, uygulama kapatma (normal ve zorla)
  ve uyutma yine yalnız kablodan gelir. Adlar tek yerde durur (`Command.allNames`, `Command.wifiNames`).
- `quitApp` sadece `activationPolicy == .regular` olan uygulamalarda çalışır; Finder ve PhoneBox hariçtir (uygulama
  listesindeki `quittable` da aynı kuralla hesaplanır). Telefonun listesi 10 sn'ye kadar eski olabilir ve aynı paketin
  örnekleri tek satırdır; bu yüzden telefon `pid` göndermez: Mac uygulamayı `bundleId` ile bulur ve kapatılabilir
  bütün örneklerine uygular; yoksa `app-changed` döner.
- `sleep`'te `ack` önce gönderilir, Mac 1 sn sonra uyur (yoksa cevap telefona ulaşmaz).
- Ses kaydırıcısı sürüklenirken sayfa en fazla saniyede 4 `volume` gönderir, bırakınca son değeri gönderir (sınır 10/sn).
- Ses kontrolü olmayan çıkış cihazında `volume`/`mute` `unsupported` döner ve kaydırıcı devre dışı kalır; kontrol var
  ama değeri almadıysa `failed` döner.
- Spike 7'de uygulama kapatma, sessiz, ses seviyesi, ekranı kapatma ve kilit hiçbir izin penceresi açmadan
  çalıştı. Medya komutu NotchBox'ta çalışan adaptörle gönderilir.
- Adaptörün çerçevesi SIGTERM'i yalnız run loop'u durduracak şekilde değiştirir: `send` hiç run loop çalıştırmaz,
  run loop'u başlamadan durdurulan `stream` durdurmayı kaçırır. Bu yüzden SIGTERM'den 1,5 sn sonra hâlâ çalışan
  adaptör (`stream` ya da `send`, ShortProcess'in 5 sn'lik süresi dolunca) SIGKILL ile durdurulur (0.4.1).

## 8. Arayüz

### Dashboard (telefon)

Yerleşimler gerçek ölçüde görsel taslaklarla seçildi (2026-11-25, standart iPhone, yatayda 852×393). Kenarlarda
güvenli alan payları (`env(safe-area-inset-*)`) bırakılır; bu telefonda kullanılabilir alan yatayda 734×372. Ölçüler
ekran yüksekliğine göre ayarlanır, iPhone SE'den Pro Max'e kadar her şey kaydırmadan sığar.
Ana ekran uygulamasında telefon döndürülünce iOS görünür alanı ekrandan kısa bırakabiliyor (2026-11-26, Pro Max
yatayda: altta dikey durum çubuğu kadar boş şerit); bu yüzden orada tam ekran katmanların yüksekliği ekranın
yüksekliğidir (`screen.js` → `--screen-height`), tarayıcı sekmesinde CSS'in görünür alanı.

- **Yatay (ana görünüm), üç sütun:**
  - Sol: CPU (altında yük) ve RAM (altında kullanılan / toplam) halkaları.
  - Orta: seçili metriğin son 60 saniyelik grafiği; altında 3×2 metrik kutucuğu (GPU, Sıcaklık, Güç, Ağ, Disk boş,
    Pil); en altta kontrol şeridi.
  - Sağ: saat başlığı (aşağıda "Saat ve telefonun pili"), "Şimdi çalıyor" kartı, uygulama listesi (7 satır).
- **Dikey ("tek bakış"):** yukarıdan aşağı saat satırı (solda saat, sağda tarih ve telefonun pili), yan yana iki
  halka, grafik, 3×2 kutucuk, en çok kullanan 5 uygulama, "Şimdi çalıyor" (tek satır), kontrol şeridi. Kaydırma yok.
- **Stil: Aktivite Halkaları, Okyanus paleti** (2026-11-26, 12 stil ve 12 renk paleti arasından seçildi). Çok koyu
  lacivert zemin `#01060d`, kartlar `#0b1622`, ikincil yazı `#6d8aa3`, ana yazı `#eaf6ff`; sistem fontu, 16 px köşe,
  sayılarda sabit genişlikli rakamlar. Metrik renkleri (halkalarda koyudan açığa geçiş):

  | Metrik | Renk | Halkanın açık ucu |
  |---|---|---|
  | CPU | `#00c2ff` | `#7ff3ff` |
  | RAM | `#3d6bff` | `#9db4ff` |
  | GPU | `#7b61ff` | |
  | Sıcaklık | `#00e0b0` | |
  | Güç | `#4ff0d0` | |
  | Ağ | `#8be9ff` (↑ çizgisi `#7b61ff`) | |
  | Disk | `#6f8fa8` (yazma çizgisi `#4ff0d0`) | |
  | Pil | `#00d0a0` | |
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
  seviyesi), sessiz, "⋯". Simgeler sayfanın içinde SVG (emoji değil). Dokunma alanları en az 44×44 pt. İstisna,
  sıkı yerleşim için: uygulama satırları 34 px, sıralama düğmesi yaklaşık 24 px yüksek; yanlış satıra dokunmak
  sadece uygulamanın adını yazan paneli açar ve panelin düğmeleri 46 px. `audio` alanı yoksa kaydırıcı ve sessiz
  soluk. Kaydırıcı parmakla sürüklenir: en çok saniyede 4 değer gider, bırakınca son değer
  gider; bıraktıktan sonra 1,5 sn Mac'in eski değeri gösterilmez (düğme geri sıçramasın). Sessiz düğmesi dokunur
  dokunmaz değişir, sonraki snapshot doğrular.
- **Komut etkileşimleri** (görsel taslaklarla seçildi):
  - Uygulamaya dokununca alttan panel: ad, CPU ve bellek; "Kapat", "Zorla kapat", "Vazgeç". Gri satıra dokununca
    sadece "Bu süreç buradan kapatılamaz".
  - "⋯" menüsü şeridin üstünde açılır: Kilitle, Ekranı kapat, Uyut, ayraç, Kurulum rehberi.
  - Onay sadece "Zorla kapat" ve "Uyut" için (bölüm 7). "Uyut" penceresi bağlantının kesileceğini ve Mac'in
    klavyesine ya da trackpad'ine dokunarak uyandırılacağını, sonra dashboard'un kendiliğinden bağlanacağını söyler.
  - Komuttan sonra üstte 2 sn bildirim. Başarıda yeşil tik yalnız uygulama ve "⋯" komutlarında ("Code kapatıldı",
    "Mac kilitlendi"); medya, ses ve sessizde başarı zaten ekranda görünür, bildirim çıkmaz. Hatada her zaman kırmızı
    ve sebep (`not-allowed` → "Bu komut sadece kabloyla çalışır", `app-changed` → "Uygulama değişmiş, liste
    yenilendi", `unsupported` → ses komutlarında "Bu çıkışta ses kontrolü yok", diğerlerinde "Bu komut
    desteklenmiyor", `failed` ya da 5 sn içinde cevap gelmemesi → "Olmadı").
  - Komutlar numaralanır (`seq` sayfa açık kaldıkça hep artar) ve imzalanır; cevap (`ack`) numarasıyla eşlenir
    (`commands.js`). Sayfa herhangi bir saniyede en çok 9 komut gönderir (Mac'in sınırı 10, bölüm 5); onuncusu
    gönderilmez, "Olmadı" der.
  - Panel ve onay penceresi açıldıktan ya da kapandıktan sonra 0,4 sn boyunca dokunuşlar yok sayılır (panelin ve
    onayın düğmeleri, arka planları ve alttaki komutlar); "⋯" menüsünün komutları da menü açıldıktan sonra 0,4 sn,
    şerit de menü kapandıktan sonra 0,4 sn.
    Pencereler 0,25–0,35 sn'de belirip kaybolur ama dokunuşu hemen alır ya da hemen geçirir; böylece çift dokunuşun
    ikincisi kullanıcının henüz görmediği bir düğmeye (menüdeki "Uyut"un üstündeki onay düğmesine, uygulama
    satırlarının üstündeki "Kapat"a) basamaz. Kapalı panel ve onay `inert`tir: klavye ve VoiceOver da onlara ulaşmaz.
  - Her kontrol kendi komutuna bakar: komutu `access.commands` listesindeyse ve bağlantı komut gönderebiliyorsa
    çalışır. Medya düğmeleri `media`, ses kaydırıcısı `volume`, sessiz `mute`, panelin "Kapat" ve "Zorla kapat"ı
    `quitApp`, "⋯" menüsünün Kilitle, Ekranı kapat ve Uyut'u `lock`, `displaySleep`, `sleep`. İzinli olmayan kontrol
    soluk; dokununca hiçbir şey gönderilmez, "Bu komut sadece kabloyla çalışır" der (`not-allowed` cevabı da aynısını
    söyler). Kabloda hepsi açık; Wi-Fi'de ayar kapalıyken hepsi, açıkken medya düğmeleri ve Kilitle dışındakiler soluk.
- **Bağlantı göstergesi:** saat başlığında telefonun pilinin yanında renkli nokta: yeşil kabloda, turuncu Wi-Fi'de
  (yanında "Wi-Fi" yazar; komutlardan en çok kilit ve müzik açık), gri bağlanıyor. Mac'in adı (`ready.host`) "⋯"
  menüsünün başlığındadır.
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

### Görünüm ve hareket

Kullanıcının isteği: "akıcı, baktıkça bakası gelen" bir ekran; bileşenlerin yeri yukarıdaki gibi kalır. Görsel
önizlemelerle seçildi (2026-11-26).

- **Halkalar:** `<canvas>` üstünde kalın (çapın %12'si) halka; renk halka boyunca koyudan açığa geçer, ucu yuvarlak ve
  parlar (hafif nefes alan ışık), dolu kısmın üstünden 1,4 sn'de bir beyaz bir parıltı akar. Boş kısım metriğin
  renginde soluk iz.
- **Sayılar:** her yeni değere 0,9 sn'de yumuşakça kayar (yavaşlayarak biten geçiş); halkalar, kutucuklar, grafik
  başlığı. Metni kutuya sığdırma her karede değil, hedef değerin yazısı geldiğinde (saniyede bir) yapılır.
- **Grafik:** yumuşatılmış eğri, altı renk geçişiyle dolu; zaman sürekli akar (her karede kayar). Grafik Mac'in
  saatine (`snapshot.t`) göre, bir snapshot aralığı (1 sn) artı son gelişlerin düzensizliği kadar (artı 100 ms;
  150 ms–1,5 sn) geriden çizilir; yeni değer hep sağ kenarın dışından kayarak girer. Bu gecikmedeki değişimler
  gerçek zamanın en çok %10'u hızla yumuşatılır: grafiğin saati durmaz, sıçramaz, geri gitmez (3 sn'den çok
  saparsa, örneğin sayfa uyuduysa, atlar). Böylece Wi-Fi'deki iPhone'un veriyi toplu teslim etmesi grafiği
  duraklatıp sıçratmaz (telefon denemesinde görüldü, 2026-11-26); grafik sayılardan 1–2,5 sn geriden gelir. Geçmiş
  63 sn tutulur, ekranda 60 sn görünür. En sondaki nokta nabız gibi atan bir ışık halkasıyla işaretli. Metrik
  değişince eski grafik 0,3 sn'de söner, yenisi belirir.
- **Uygulama listesi:** sıra değişince satırlar eski yerlerinden yenilerine 0,7 sn'de kayar; altlarındaki CPU çubuğu
  1 sn'de uzar ya da kısalır; listeye giren satır belirir.
- **Şimdi çalıyor:** çalarken küçük bir ekolayzer (4 çubuk) oynar, duraklayınca durur.
- **Tek döngü:** bütün çizimleri tek bir `requestAnimationFrame` döngüsü yapar (ekranın tazelenme hızında, en fazla
  60 kare); sayfa görünmezken döngü durur. Telefondaki işlemci yükü telefon denemesinde ölçülür; ağır gelirse çizim
  30 kareye indirilir.
- **Hareketi Azalt:** telefonda açıksa (`prefers-reduced-motion`) parıltı, nabız, ışığın atması, rakam kayması ve
  satır kayması kapanır; renk değişimi ve sayı geçişleri kalır.

### Sınıra yaklaşınca kızarma

Telefon çalışırken yanda açık durur; bir metrik sınırına yaklaşınca dikkat çekmelidir (kullanıcı isteği, 2026-11-26).

- **Seviye:** her metrik için iki değer: kızarmaya başladığı ve kıpkırmızı olduğu. Aradaki değer 0…1 seviyeye
  çevrilir (doğrusal, iki uçta yumuşatılmış). Bazı metriklerde düşük değer kötüdür (disk boş yeri, pil); onlarda sınır
  başlangıçtan küçüktür.

  | Metrik | Kızarmaya başlar | Kıpkırmızı | Not |
  |---|---|---|---|
  | CPU | %40 | %95 | `cpu.total` |
  | RAM | bellek baskısı "uyarı" (yarı yolda) | bellek baskısı "kritik" | `mem.pressure`; halka kullanılan yüzdeyi gösterir ama renk ve alarm baskıya göre: macOS belleği bilerek dolu tutar, 8 GB'lık Mac'te %85–95 olağandır (kullanıcı kararı, 2026-11-26). RAM grafiği kızarmaz |
  | GPU | %40 | %95 | |
  | Sıcaklık | 60 °C | 95 °C | ortalama (`temp.avg`) |
  | Güç | `ready.limits.power[0]` | `ready.limits.power[1]` | Mac çipine göre seçer (aşağıda); gelmezse 15 / 35 W |
  | Ağ | 10 MB/s | 100 MB/s | ↓ + ↑ toplamı |
  | Disk boş | 30 GB | 5 GB | ondalık GB (Finder gibi); azaldıkça kızarır |
  | Pil | %30 | %10 | yalnız prizde değilken (`plugged` false); azaldıkça kızarır |
  | Uygulama satırı | %60 | %200 | uygulamanın CPU'su (iki çekirdek dolu = %200) |

  Güç sınırı (watt, `power.system` için; masaüstü Mac'te `power.gpu` için ikinci sütun). Dahili pili olan Mac
  (pilin değerleri o an okunamasa da) "Mac'in tamamı" sütununu kullanır. Değerler tahmindir; M4'te telefon denemesinde
  gerçek yükle kontrol edilir:

  | Çip (`machdep.cpu.brand_string`) | Mac'in tamamı | Yalnız GPU |
  |---|---|---|
  | Apple M… (temel) | 15 → 35 | 5 → 15 |
  | Apple M… Pro | 25 → 60 | 10 → 30 |
  | Apple M… Max | 35 → 100 | 20 → 60 |
  | Apple M… Ultra | 50 → 160 | 30 → 90 |
- **Renk yolu (B, "mor üzerinden"):** seviye arttıkça metriğin rengi OKLCH renk uzayında tonu artan yönde döner:
  okyanus → mavi → mor → pembe → kırmızı (`#ff2d2d`; halkanın açık ucu `#ff8a7a`). Ara renkler canlı kalsın diye yolun
  ortasında doygunluk biraz artırılır; ekranın gösteremediği renkte doygunluk ekrana sığana kadar azaltılır. Orta
  yükte okyanus havası bozulmaz (seçilmeyen yol A: yeşil-sarı-turuncu).
- **Kızaranlar:** halka (iki ucu da), halkadaki yüzde yazısı, kutucuğun noktası ve değeri, kutucuğun zemini (seviyeyle
  hafifçe), kutucuğun çerçevesi (seviye 0,4'ten sonra), grafik başlığındaki değer, uygulama satırının çubuğu ve
  yüzdesi. Renk değer gelir gelmez (sayı geçişiyle birlikte) kayar, beklemez.
- **Grafik:** çizginin ve altındaki dolgunun her yüksekliği kendi değerinin rengini alır; tepeler kırmızı görünür.
  Sınır kesikli kırmızı bir çizgi ve "SINIR" yazısıyla gösterilir. Disk grafiği okuma/yazma hızını çizdiği için
  kızarmaz (disk kutusu boş yere göre kızarır); pil grafiği prizdeyken kızarmaz.
- **Uyarı (alarm), "güçlü":** değer art arda 3 snapshot'ta (≈3 sn) sınırda ya da ötesindeyse çalar; seviye art arda
  3 snapshot'ta 0,9'un altındaysa söner (sınırın üstünde gidip gelen değer yanıp sönmez). Değeri gelmeyen ya da
  kızarmayan (prizdeki pil) metrik sakin sayılır. Bir anlık sıçrama (uygulama açılırken CPU %100) alarm çaldırmaz, renk yine anında kızarır. Karar
  gelen gerçek değerle verilir, ekrandaki geçiş değeriyle değil. Uygulama satırları yalnız kızarır, alarm çaldırmaz.
  - Çaldığı an: halka ya da kutucuk 0,7 sn içinde bir kez hafifçe büyüyüp döner, ekranın kenarı parlar.
  - Çaldığı sürece: ekranın dört kenarında geniş kırmızı bir ışık (ekranın üstünde, dokunmayı engellemeyen bir
    katman) saniyede bir nefes alır gibi atar; halka ve kutucuk aynı ritimde kırmızı ışıkla atar; grafik o metrikteyse
    çerçevesi de atar.
  - Saat başlığında tarihin yerine kırmızı "▲ CPU %100" yazar; birden fazla alarm varsa en yüksek seviyeli ikisi
    ("▲ CPU %100 · Sıcaklık 97 °C"). RAM'in alarmında yüzde değil bellek baskısı yazar ("▲ RAM kritik"). RAM grafiği
    kızarmaz ama alarmında çerçevesi atar, başlıktaki değeri kızarır.
  - Alarm yokken bir metrik seviye 0,7'yi geçerse kenarda soluk bir ışık belirir (seviye arttıkça güçlenir).
  - 2 dakika sonra alarm sakinleşir: kenar ışığı ve atma durur, "▲" yazısı sabit kalır, metrik değer düzelene kadar
    kırmızı kalır. Değer düzelip (3 snapshot boyunca 0,9'un altında) yeniden sınıra gelirse yeniden çalar. Bir metrik
    2 dakikadan uzun süre sınıra yakın kalırsa soluk kenar ışığı da söner; dolu kalan disk ekranı hep kızartmaz
    (kullanıcı kararı, 2026-11-26).
- **Veri bayatlayınca** (bölüm 5, değerler soluk): alarm ve kenar ışığı söner, renkler son değerde kalır.

### Saat ve telefonun pili

- **Yer (yerleşim 3):** sağ sütunun başında büyük saat (`HH:MM`, telefonun kendi saati); sağında üstte tarih
  ("26 Kas Per" / "Thu, Nov 26", `Intl.DateTimeFormat`), altta telefonun pili ve bağlantı noktası. Yatayda saatin
  boyu sağ sütunun genişliğinin %16'sı (28–38 px). Dikeyde en üstte tek satır: saat (22–30 px, ekran yüksekliğine
  göre), tarih, pil ve nokta; küçük telefonda uygulama listesine yer kalsın diye.
- **Saat:** dakika değişince değişen rakam yukarı kayarak çıkar, yenisi aşağıdan gelir (0,7 sn); iki nokta 2 sn'de
  bir yavaşça soluklaşıp parlar. Saniye yok.
- **Telefonun pili:** Safari sayfaya pil bilgisini vermez (Battery Status API yok); pil Mac'ten `phone` alanıyla
  gelir (bölüm 6). Pil simgesi: dolgusu seviyeye göre 1,2 sn'de kayar, şarj olurken üstünde ⚡; yanında "%76".
  Dolgu prizde değilken pil sınırlarına göre kızarır. Simge yalnız sayfa kablodaysa (`access.cable`) ve `phone`
  alanı varsa görünür; Wi-Fi'deki sayfada yerinde "Wi-Fi" yazar.
- **Pilin okunması (Mac):** MobileDevice ilk kullanımda yüklenir. Telefon takılınca 2 sn sonra, sonra dakikada bir
  okunur; okuma olmazsa (telefon uyanıyor ya da "Güven" soruyor) 10 sn sonra yeniden denenir, en çok 3 kez. İki
  telefondan biri çıkarılınca kalan okunur.

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
| `metrics.js` | her metriğin geçmişe yazılan değerleri, grafik çizgileri ve ölçeği, kutucuk ve başlık metinleri, renkleri ve kızarma değeri | JavaScriptCore |
| `heat.js` | sınırlar, seviye, OKLCH renk yolu, alarm kuralı (3 sn / 0,9) | JavaScriptCore |
| `motion.js` | sayı geçişleri (tween), tek `requestAnimationFrame` döngüsü, Hareketi Azalt | geçiş hesabı JavaScriptCore'da |
| `rings.js` | halkanın `<canvas>` çizimi | gözle |
| `clock.js` | saat, tarih, rakam kayması | biçim JavaScriptCore'da, kayma gözle |
| `chart.js` | grafik ölçeği (saf) ve her karede `<canvas>` çizimi (kızarma, sınır çizgisi, nabız) | ölçek JavaScriptCore'da, çizim gözle |
| `connection.js` | bağlantı, eşleşme, yeniden bağlanma (bugünkü `app.js`'ten) | gözle / telefonda |
| `commands.js` | komut imzası, `seq`, cevap eşleme, 5 sn zaman aşımı, saniyede en çok 9 komut, ses kaydırıcısının hız sınırı | imza (Swift'in `MessageAuth`'u ile), eşleme ve hız sınırları JavaScriptCore'da |
| `controls.js` | kontrol şeridi, uygulama paneli, "⋯" komutları, onay, bildirim, çift dokunuş kalkanı | hangi kontrolün `access.commands`'a göre gönderip soluk kaldığı JavaScriptCore'da (sahte sayfayla), gerisi gözle |
| `view.js` | halkalar, kutucuklar, liste (satır kayması), şarkı kartı, saat başlığı, telefonun pili, alarm ve kenar ışığı, durumlar | gözle |
| `ui.js` | ekranı açık tutma, "⋯" menüsünün açılıp kapanması, rehber, Başlat ekranı, OLED kayması | gözle |
| `app.js` | parçaları birbirine bağlar | — |

### Uygulama sırası

Plan 3B (Mac tarafı: bölüm 7'deki komutlar, `media` ve `audio` alanları, `host` ve `cable`, bölüm 5'teki protokol
kuralları ve bağlantı yöneticisinin testlerle denenebilir hâle getirilmesi) → Plan 4A (izleme arayüzü: yerleşimler,
halkalar, grafik, kutucuklar, uygulama listesi, şarkı kartı, durumlar, Başlat, rehber, OLED, ana ekran simgesi) →
Plan 4C (görünüm ve canlılık, 4B'den önce: Okyanus paleti, halkalar, hareketler, kızarma ve alarm, saat başlığı;
Mac tarafında `phone`, `battery.plugged`, `ready.limits`) → Plan 4B (komut arayüzü: kontrol şeridi, uygulama paneli,
"⋯" komutları, onay, bildirim; son görevi kullanıcıyla telefonda uçtan uca kontrol) → Plan 5 (dağıtım).

### Menü çubuğu (Mac)

Simge telefon çizimi: gri = izinli istemci yok, yeşil = en az bir istemci veri alıyor. 0.4.0'dan beri ayarlar menüde
değil, ayrı bir pencerede (aşağıda); menü kısadır:

- Durum satırı (ör. "iPhone bağlı · 1 cihaz", "Telefon Wi-Fi'de: kabloyu tak", "Port 4747 kullanımda", "USB aygıtları
  görülemiyor")
- Ayarlar… (⌘,): ayarlar penceresini öne getirir
- QR kodunu göster…
- "PhoneBox x.y.z sürümünü yükle…" (yalnız yeni sürüm varken) ve "Güncellemeleri denetle…" (NotchBox'taki gibi):
  açılıştan 15 sn sonra ve günde iki kez GitHub'ın "latest release" yanıtına bakılır (taslak ve ön sürüm sayılmaz).
  Yükle, kurulum komutunu PhoneBox'tan bağımsız bir kabukta çalıştırır: PhoneBox kapanır, yenisi yerine konup açılır,
  çıktısı `~/Library/Logs/PhoneBox/update.log`'a yazılır. Kurulum başarısızsa komut panoya konur ve kayıt gösterilir.
  `defaults write com.phonebox.PhoneBox CheckForUpdatesAutomatically -bool false` otomatik denetimi kapatır.
- PhoneBox'tan çık

PhoneBox çalışırken yeniden açılınca (Finder, Launchpad, `open`) ayarlar penceresi öne gelir. İlk eşleştirmedeki QR
davranışı aynıdır (bölüm 5).

### Ayarlar penceresi (0.4.0)

Sistem Ayarları gibi: solda renkli simgeli dört bölüm, sağda seçilenin ayarları gruplu bir formda (SwiftUI
`NavigationSplitView`, `Form` `.grouped`; AppKit penceresinde `NSHostingController`). Pencere "PhoneBox" başlıklı,
boyutu değiştirilebilir (en az 680×460), yeri hatırlanır; kapatmak yalnız gizler, ⌘W kapatır. Açıkken her şey canlı
güncellenir (bağlanan telefonlar, Claude oturumları, güncelleme durumu); Girişte başlat ve `~/.claude/settings.json`
kendiliğinden haber vermediği için pencere her öne geldiğinde yeniden okunur. Görünüm `SettingsModel`'dan okur; akışlar
(uyarılar, port penceresi, giriş öğesi, sıfırlama, Claude aç/kapa) menüdekiyle aynı metinlerle `AppDelegate`'te ve
`SettingsDialogs`'ta. Açık ve koyu temaya uyar.

- **Bağlantı:** üstte canlı durum (yeşil nokta + "iPhone bağlı", altında "1 cihaz · kabloyla" / "2 cihaz · 1 kabloyla,
  1 Wi-Fi'den"; ya da menünün diğer durum metinleri ve ne yapılacağı). "Telefona veri gönder": "Kablo takılıyken" /
  "Her zaman" (bölünmüş düğme). "Wi-Fi'den kilit ve müzik": yalnız "Her zaman"da kullanılır, kablo kipinde kapalı
  görünür ve soluktur (kayıtlı ayar kalır); açarken bölüm 5'teki uyarı sorar, kapatırken sormaz. "Port": numara ve
  "Değiştir…": 1024–65535 arası bir sayı sorar (`PortChoice`); geçersizse sebebini söyleyip yeniden sorar. Yeni port
  eski port dinlenirken açılır; hazır olunca eski dinleyici durur, onun kabul ettiği bağlantılar kapanır (1001), port
  kaydedilir ve telefonun bağlantısı portu içerdiği için QR penceresi açılır. Kullanımdaki bir port reddedilir: bir
  uyarı bunu söyler, PhoneBox ve bağlı telefonlar eski portta kalır, kayıtlı port değişmez. Yerini başkasına bırakan
  dinleyicinin geç gelen durumu ve bağlantısı yok sayılır. 4747 seçilince ayar silinir.
- **Eşleştirme:** kişisel bağlantının QR kodu pencerenin içinde, okutma metni, "Bağlantıyı kopyala" ("Kopyalandı" olur)
  ve "Büyüt…" (QR penceresi). "Eşleşmiş telefonlar": şu an bağlı telefonların sayısı (kablo bekleyenler dahil).
  "Eşleştirmeyi sıfırla" → "Sıfırla…": onay uyarısı; yeni anahtar, bütün telefonlar kapanır, QR penceresi açılır ve
  penceredeki QR yeni bağlantıyı gösterir.
- **Claude Code:** "Claude Code oturumlarını telefonda göster" (bölüm 14; açarken uyarı, hook'ları kurar; kapatınca
  sormadan siler). Durum: "Hook'lar kurulu · 3 oturum · 1 seni bekliyor", "Hook'lar kurulu değil" ya da "Kapalı"; son
  kurma ya da silme başarısızsa sebebi altında kırmızı (uyarı da çıkar). "~/.claude/settings.json" → "Finder'da göster"
  (sembolik bağlantı izlenip gerçek dosya; dosya yoksa soluk).
- **Genel:** "Girişte başlat" (ServiceManagement). macOS onay isterse (`requiresApproval`) anahtar açık görünür, altında
  bunu söyleyen bir satır ve "Giriş Öğeleri'ni aç" düğmesi; anahtara dokunmak isteği geri çekmez, onay uyarısını yeniden
  gösterir. "Güncelleme": "PhoneBox x.y.z", altında "Güncel" / "x.y.z sürümü var" / "Denetleniyor…" / "Denetlenemedi" ve
  son denetimin ne zaman olduğu; "Şimdi denetle" (menüdeki "Güncellemeleri denetle…" ile aynı) ve yeni sürüm varken
  "Yükle…". "Hakkında": "GitHub'da aç" (depo sayfası) ve "Lisanslar" (paketteki `LICENSE` ve `THIRD_PARTY_NOTICES.md`,
  TextEdit'te).

Görünüm testte açılamadığı için `SettingsViewRenderTests` onu örnek bir modelle (`SettingsModel.sample`) her bölüm
için açık ve koyu temada PNG'ye çizer (geçici klasörde `PhoneBoxSettings/`). Pencere açan bu test ve kenar çubuğu
testi (`SettingsSidebarTests`) ana iş parçacığını saniyelerce tuttuğu için yan yana koşan zamanlama testlerini
bozuyordu; yalnız `make test-ui` ile, tek başlarına koşarlar (oturum açık bir Mac gerekir).

Menü ve pencereler İngilizce ve Türkçe (`Resources/{en,tr}.lproj/Localizable.strings`); iki dosyanın anahtarları ve
her metnin yer tutucuları aynı olmalı (`LocalizationTests`).

## 9. Hata yönetimi

| Durum | Davranış |
|---|---|
| Port dolu | Açılışta başka porta geçilmez (kayıtlı bağlantı bozulmasın): menüde ve ayarlar penceresinde uyarı, port boşalana kadar 30 sn'de bir yeniden denenir (0.4.1); Ayarlar → Bağlantı → Port → "Değiştir…" ile yeni port; QR güncellenir. Port kullanımdayken "Değiştir…" aynı portu da kabul eder ve hemen dener (QR açılmaz, bağlantı aynı). Seçilen port kullanımdaysa reddedilir: uyarı çıkar, PhoneBox eski portta kalır, kayıtlı port değişmez |
| usbmuxd yok | Takma olayıyla QR penceresi açılamaz; menüde ve ayarlar penceresinde uyarı. Kablo modu etkilenmez (USB arayüzüne bakar) |
| Tarayıcı HTTPS deniyor | İlk baytı `0x16` (TLS el sıkışması) olan bağlantı hemen kapatılır; tarayıcı HTTP'ye düşer |
| Video byte aralığı istiyor | `Range` isteğine `206 Partial Content`, geçersize `416`; iOS aralıksız sunulan videoyu oynatmaz |
| Collector hatası / takılma | Her `sample()` zaman sınırlı; değer `null`, aynı hata log'a bir kez yazılır |
| Protokol ihlali | Bozuk mesaj, yanlış imza, artmayan `seq`, hız sınırı aşımı → bağlantı kapanır (1008) |
| Kimlik doğrulamadan önce metin dışı çerçeve | 1008 ile kapanır (ping seli koruması); sonrasında ikili çerçeve 1003, bir okumadaki pinglerden sadece sonuncusu cevaplanır |
| Geçersiz WebSocket çerçevesi | 125 bayttan uzun ya da parçalı kontrol çerçevesi, RSV bitleri, ayrılmış opcode'lar, 64 KB'tan büyük ya da negatif uzunluk → 1008 |
| Boşta ya da takılan bağlantı | İstek başlığı 10 sn'de gelmezse kapanır; henüz telefon olmayan (dosya isteği, kimliğini doğrulamamış soket) en fazla 32 TCP bağlantısı, bir adresten en fazla 16; kimliği doğrulanmış telefonlar ve iPhone'un USB bağlantısından gelenler sayılmaz, USB'den gelen her zaman kabul edilir (0.4.1); kapanış 2 sn'de bitmezse kesilir; 256'dan fazla gönderilmemiş mesaj birikirse kesilir |
| Ölü bağlantı | 15 sn'de bir ping; 45 sn hiçbir şey gelmezse kesilir (uykuyu da sayan monoton saatle); 5 sn uygun yol yoksa kesilir; kablo çıkınca 1,5 sn sonra kaybolan USB arayüzündeki istemciler kesilir |
| 5. istemci | Kimliğini doğrulamış en fazla 4 telefon: fazlası yükseltmede 503, kimlik doğrularken 4'ü dolmuşsa 1013 alır (sayfa sonra yeniden dener). Kimliğini doğrulamamış WebSocket'ler ayrıca sınırlı: bir adresten 2, toplam 8; anahtarı olmayan bir cihaz telefonların yerini tutamaz. iPhone'un USB bağlantısından gelen telefon her zaman kabul edilir (0.4.1) |
| Mac uyandı / ağ değişti | Sayaç referansları sıfırlanır, saniyelik zamanlayıcı yeniden kurulur; dinleyici tüm arayüzlerde kalır, `.local` yeni ağda çalışır |
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
  ve ses kaydırıcısının hız sınırı (bölüm 8, Sayfa kodu). Kızarma (`heat.js`): her metriğin seviyesi (ters çalışan
  disk ve pil, prizdeki pil, `ready.limits` ile gelen güç sınırı), renk yolunun iki ucu (seviye 0 metriğin rengi,
  1 kırmızı) ve tonun artan yönde döndüğü, alarmın 3 sn sonra çalıp seviye 0,9 altında 3 sn sonra söndüğü; sayı
  geçişinin hesabı; saatin ve tarihin biçimi.
- **Mac tarafı yeni testler:** `ready.limits` ve `phone`, `battery.plugged` kodlaması; çip adından güç sınırı tablosu;
  pil kaynağının `Power Source State`'ten `plugged` çıkarması; `MobileDevice` değerlerinden (`BatteryCurrentCapacity`,
  `BatteryIsCharging`, `ExternalConnected`) `phone` üretimi (saf). Takılı gerçek iPhone'dan pil okuma sadece
  `PHONEBOX_LIVE=1` ile çalışır.
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
  (`curl` ile inen dosya karantinaya alınmaz, imzasız uygulama engellenmez). Apple Silicon (`sysctl hw.optional.arm64`; Rosetta
  altındaki kabukta `uname -m` yanıltır) ve macOS 14+ denetlenir, imza doğrulanır, çalışan PhoneBox kapatılır, yeni
  kopya önce aynı klasörde geçici bir adla (`.PhoneBox-installing.app`) hazırlanır, sonra eskisinin yerine taşınır
  (kopya başarısız olursa eski uygulama kalır); uygulama `/Applications`'a (yazılamıyorsa `~/Applications`) konup
  açılır. `PHONEBOX_VERSION=x.y.z` belirli bir sürümü kurar. Denemek için `PHONEBOX_ZIP` (yerel zip), `PHONEBOX_DEST`
  (başka klasör; başka yerden çalışan PhoneBox'a dokunulmaz) ve `PHONEBOX_NO_OPEN=1`.
- Kaldırma `… | bash -s -- --uninstall`: uygulama, ayarlar (`defaults`), eşleştirme anahtarı
  (`~/Library/Application Support/PhoneBox`), kayıtlar (`~/Library/Logs/PhoneBox`) ve izinler (`tccutil`) silinir.
- `make app` (ad-hoc imzalı `build/PhoneBox.app`; simge `scripts/make-icon.swift` ile çizilir, `LICENSE` ve
  `THIRD_PARTY_NOTICES.md` uygulamanın içine konur), `make test`, `make dist` (`dist/PhoneBox-<sürüm>.zip`, imzası
  denetlenir), `make release VERSION=x.y.z` (temiz ve `origin/main` ile aynı `main`'den: sürüm numarası, test, zip,
  "Release x.y.z" commit'i, `vx.y.z` etiketi, push, GitHub Releases'a taslak olarak yayın, `PhoneBox.zip` yüklendikten SONRA yayımlanır; `DRY_RUN=1` prova eder).
- Gereksinim: Apple Silicon, macOS 14+. README önce Türkçe, sonra İngilizce, son kullanıcı için yazılır.

```
Package.swift  Makefile  install.sh  LICENSE  THIRD_PARTY_NOTICES.md  README.md
scripts/                  bundle.sh, build-adapter.sh, dist.sh, release.sh, make-icon.swift, make-touch-icon.swift,
                          make-video.swift
Sources/PhoneBoxCore/     modeller, hesaplar, protokol, HMAC, AccessPolicy
Sources/PhoneBox/         uygulama, Collectors, Sampler, USBWatcher, Server, Pairing, CommandRunner, MenuBar
Resources/                Info.plist, en.lproj, tr.lproj (AppIcon.icns `make app` sırasında çizilir)
Resources/web/            index.html, styles.css, sha256.js, i18n.js, format.js, history.js, metrics.js, heat.js,
                          motion.js, rings.js, clock.js, chart.js, connection.js, commands.js, view.js, ui.js,
                          controls.js, app.js, keepawake.mp4, apple-touch-icon.png
Vendor/mediaremote-adapter/   (git alt modülü)
Tests/PhoneBoxCoreTests/  Tests/PhoneBoxTests/
docs/design/2026-11-25-phonebox-design.md   docs/spike-results.md   docs/manual-testing.md
```

## 13. Açık riskler

- **Ekranın açık kalması:** WebKit'in "sesi açık görüntü+ses videosu oynarken uyuma" davranışına ve Audio Session
  API'ye dayanıyor; bir iOS güncellemesi değiştirirse kullanıcı "Otomatik Kilit"i elle ayarlar.
- **USB ağ bağlantısı:** iOS'un güvenilen bir Mac'e USB ağ bağlantısı açmasına dayanıyor; açmazsa dashboard Wi-Fi
  üzerinden çalışır, kablo modu ise "Kabloyu tak" gösterir (ayarlarda "Her zaman" moduna geçilebilir).
- **Resmi olmayan API'ler** (sıcaklık, güç, kilitleme, medya, telefonun pili): macOS güncellemesiyle bozulabilir; her
  biri tek başına devre dışı kalacak şekilde yalıtılır (telefonun pili okunamazsa simge gizlenir).
- **Telefonun pili kilitliyken:** iPhone kilitliyken pilin okunup okunmadığı henüz denenmedi (telefon denemesinde
  bakılır); okunmazsa son iyi değer 5 dk gösterilir, sonra simge gizlenir.
- **Animasyonun telefona yükü:** her karede çizim telefonu ısıtabilir; telefon denemesinde işlemci yükü ölçülür,
  gerekirse 30 kareye inilir (bölüm 8, Görünüm ve hareket).
- **Şifresiz metrik trafiği:** aynı ağdakiler CPU/uygulama adlarını görebilir; komutlar imzalı olduğu için pasif
  dinleyicilere karşı güvende.
- **Aynı ağdaki aktif saldırgan (Plan 2 son incelemesi):** sayfa düz HTTP ve `.local` adla sunulduğu için mDNS/ARP
  sahteciliği yapan biri değiştirilmiş bir sayfa sunup anahtarı alabilir ya da kimlik doğrulamayı aktarabilir. Bu yüzden
  komutlar her iki modda da kablodan (USB) gelen istemcilere açıktır; Wi-Fi'den yalnız kullanıcı "Wi-Fi'den Kilit ve
  Müzik"i açtıysa kilit ve medya gelir (bölüm 5, AccessPolicy). Böyle bir saldırgan "Her zaman" modunda yine de
  metrikleri görebilir; ayar açıksa Mac'i kilitleyebilir ve müziği değiştirebilir.
- **Safari depolama temizliği:** anahtar kişisel bağlantıda durduğu için etkilenmez; bozulursa QR yeniden okutulur.

## 14. Claude Code oturumları (0.3.0)

Telefonda, panonun altında ikinci bir sayfa: Mac'teki açık Claude Code oturumları (masaüstü uygulaması, VS Code,
terminal) ve hangisinin kullanıcıyı beklediği. Seçim 2026-11-26'da canlı önizlemeden yapıldı ("B · Claude sayfası").

### Ne gösterir

Her oturum bir kart: başlık, durum, o durumun ne zamandır sürdüğü (`0:42`, `12 dk`, `2 sa`), proje klasörünün adı ve
biliniyorsa model ("Opus 5.5"). Durumlar:

| Durum | Ne zaman | Kartta |
|---|---|---|
| Hazır | Oturum açıldı, henüz mesaj yok | gri, "Hazır" |
| Çalışıyor | Mesaj gönderildi; oturum bir araç kullanıyor ya da düşünüyor; ya da tur bitti ama arka planda iş sürüyor | mavi, ne yaptığı: "Düşünüyor", "Komut çalıştırıyor", "Dosya düzenliyor", "Dosya okuyor", "Web'e bakıyor", "Alt görev çalıştırıyor", "Araç kullanıyor", "Arka planda çalışıyor"; ince bir ilerleme çizgisi |
| Seni bekliyor | Oturum durdu | turuncu, parlayan; kesin bilinen ayrıntıyla: "İzin istiyor" (izin kartı), "Soru soruyor" (seçenekli soru ya da sondaki düğmeli kutu), değilse "Sıra sende" |

Mesaj, soru, komut ve dosya içerikleri hiçbir zaman okunmaz ve telefona gitmez. Telefona giden: başlık, proje
klasörünün adı, model, durum, etkinlik türü, süre. "Her zaman" kipinde bunlar Wi-Fi'den de şifresiz gider (uygulama ve
şarkı adları gibi, bölüm 13).

Sıralama: bekleyenler (en eski bekleyen önce), sonra çalışanlar, sonra hazırlar. En çok 12 kart.

### Sayfa ne zaman gelir, ne zaman gider

- Bir oturum **yeni** beklemeye başlayınca (oturum + bekleme başlangıcı daha önce görülmemişse) pano yukarı kayar,
  Claude sayfası gelir.
- Sayfa kendiliğinden geldiyse ve artık hiçbir oturum beklemiyorsa 3 sn sonra panoya döner.
- Kullanıcı parmakla panoya dönerse o an bekleyenlerin hepsi "görüldü" sayılır; sayfa ancak yeni bir bekleme
  başlayınca yeniden gelir. Kullanıcı parmakla Claude sayfasına geçtiyse sayfa kendiliğinden geri dönmez.
- Sayfa açılırken (yeniden yükleme, "Başlat") zaten bekleyen oturumlar da yeni sayılır.
- Dikey kaydırma (parmak yukarı/aşağı, 40 px'ten uzun ve yataydan baskın) iki sayfa arasında geçirir; sağ kenarda iki
  nokta hangi sayfada olunduğunu gösterir. Özellik kapalıyken (anlık görüntüde `claude` yok) ikinci sayfa, noktalar ve
  kaydırma yoktur. Özellik Claude sayfası açıkken kapanırsa pano kaydırmadaki gibi 0,8 sn'de aşağı iner; sayfa ve
  noktalar ondan sonra gider.
- Sayfanın üstünde "Claude", oturum sayısı, bekleyen sayısı ve saat; yatayda kartlar iki sütun (5 ve üstü oturumda üç)
  ve sayfanın yüksekliğini doldurur (satır = oturum / sütun, yukarı yuvarlanır: 1 oturum solda tek uzun kart, 2 oturum
  iki uzun kart; 2 satırdan fazlasında kartlar sıkışık), dikeyde tek sütun. Dikeyde sıkışık kartlar da sığmazsa (12
  oturum, 667 pt'lik telefon: 10 kart) yalnız tam sığanlar kalır, altlarında "+N oturum daha" yazar; gizlenenler en alt
  sıradakilerdir (Mac'in sırası korunur), kaydırma yok. Telefon dönünce (ve 350 ms sonra bir daha) yeniden ölçülür.
  Giden kart solarken yerini korur, ızgara
  kart gidince yeniden yerleşir. Oturum yoksa "Açık Claude oturumu yok". Hareket azaltma açıksa kayma ve kart girişleri
  anlık.

### Olaylar nasıl gelir

Claude Code'un komut hook'ları (`~/.claude/settings.json`). Her olayda Claude Code
`"<PhoneBox.app>/Contents/MacOS/PhoneBox" --claude-hook` çalıştırır (`"async": true`: oturum beklemez):

1. Yardımcı, AppKit'i hiç başlatmadan stdin'deki JSON'u okur (en çok 1 MB, en çok 4 sn bekler), `ClaudeEvent`'e
   çevirir: oturum kimliği, olay türü, araç adı, "soru mu" bayrağı, "arka planda iş var mı" bayrağı, `cwd`, oturum
   dosyasının yolu, `getppid()` (oturumun Claude işlemi; 2026-11-26 denendi: hook'un ebeveyni `claude`, `async` ile
   de), `SessionStart`'ta başlık (en çok 120 karakter, oturum dosyasındaki gibi) ve model, ve olayın zamanı `at`:
   yardımcı işlemin çekirdekteki başlangıç zamanı (`sysctl` `p_starttime`, µs; okunamazsa şimdiki zaman). Metin
   alanları (`prompt`, `last_assistant_message`, `tool_input`, `tool_response`) okunur ama hiçbir yere yazılmaz.
2. Bir satır JSON olarak `~/Library/Application Support/PhoneBox/claude.sock` Unix soketine yazar (klasör 0700, soket
   0600: yalnız bu kullanıcı; en çok 1 sn). PhoneBox kapalıysa ya da özellik kapalıysa sessizce çıkar; girdisi hiç
   bitmese de 5 sn içinde çıkar; her durumda çıkış kodu 0.
3. PhoneBox olayı `ClaudeSessions`'a uygular. Başlığı ve modeli oturum dosyasının son 256 KB'ından okur
   (`custom-title` kaydı ve son `"model":"claude-…"`; belgelenmemiş biçim, bulunamazsa başlık = klasör adı, model yok).
   5 sn'de bir oturumların işlemine bakar (`kill(pid, 0)`); işlemi biten oturum listeden düşer.

Olay → durum (`ClaudeSessions`, PhoneBoxCore, test edilir):

| Olay | Durum |
|---|---|
| `SessionStart` | yoksa ekle: Hazır (varsa durumu korunur; `/clear`, `compact`) |
| `UserPromptSubmit` | Çalışıyor · Düşünüyor (süre baştan) |
| `PreToolUse` `AskUserQuestion` | Seni bekliyor · Soru soruyor |
| `PreToolUse` `ExitPlanMode` | Seni bekliyor · İzin istiyor |
| `PreToolUse` `mcp__ccd_turn__wrap_up` (boş olmayan `ask` ile) | Çalışıyor, "tur sonunda soru var" işaretlenir |
| `PreToolUse` diğer | Çalışıyor · aracın türü |
| `PermissionRequest`, `Notification` (`permission_prompt`) | Seni bekliyor · İzin istiyor |
| `PostToolUse`, `PostToolUseFailure`, `PermissionDenied` | Çalışıyor (bekliyorsa Düşünüyor'a döner) |
| `Stop` | `background_tasks` doluysa Çalışıyor · Arka planda; değilse Seni bekliyor · işaret varsa Soru soruyor, yoksa Sıra sende |
| `SessionEnd` | listeden çıkar |

Süre yalnız durum ya da bekleme nedeni değişince sıfırlanır (aynı turdaki araçlar değiştirmez). Alt ajan olayları
(`agent_id`) ana oturumunkiler gibi işlenir, `Stop` hariç (alt ajanın `SubagentStop`'u kurulmaz).

Sıra: her hook ayrı bir işlem, iki olay birkaç ms arayla ters sırada gelebilir (`PermissionRequest` `PreToolUse`'dan
önce; `Stop` `SessionEnd`'den sonra). İşlemler Claude Code'un hook'ları çalıştırdığı sırayla başlar, bu yüzden `at`
sırası doğrudur: oturumun son uygulanan olayından eski `at`'li olay yok sayılır (aynı µs gelme sırasıyla uygulanır).
`SessionEnd`'den sonra oturum `at`'iyle 60 sn hatırlanır; `at`'i ondan eski ya da eşit olaylar yok sayılır, daha yeni
olan (`claude --resume` ile yeniden açılan oturumun `SessionStart`'ı) kabul edilir.
`at` duvar saatidir (yardımcının başlama zamanı): Mac'in saati geri alınırsa, bilinen bir oturumun olayları saat son
uygulanan `at`'i geçene kadar yok sayılır.

Olay listesi: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`,
`PermissionRequest`, `PermissionDenied`, `Notification` (eşleyici `permission_prompt`), `Stop`, `SessionEnd`.

Elenen yollar: `http` hook'u (oturumun işlemi bilinmez, `SessionStart` desteklemez, port değişince bozulur); hook'suz
oturum dosyalarını izlemek (izin beklemesi görünmez, biçim belgelenmemiş).

### Kurulum (ayarlar penceresi)

Ayarlar → Claude Code → "Claude Code oturumlarını telefonda göster" (0.3.0'da menüdeki "Claude Code Oturumları"; kapalı
başlar). Açarken uyarı: ne ekleneceği, dosyanın yedeği, başlıkların telefona (her
zaman kipinde Wi-Fi'den de) gideceği. Onaylanınca `ClaudeHooks.install`:

- `~/.claude/settings.json` okunur (yoksa boş nesne, `~/.claude` yoksa oluşturulur); kök nesne değilse ya da `hooks`
  nesne değilse dokunulmaz, hata gösterilir, ayar kapalı kalır. Sembolik bağlantı (dotfiles) izlenir, bağlantılar
  yerinde kalır; göreli hedef bağlantının gerçek klasöründen çözülür (`realpath`: `~/.claude -> dotfiles/claude` ve
  `settings.json -> ../shared/settings.json` ise `dotfiles/shared/settings.json`).
- Dosyada PhoneBox girdisi yoksa önce `settings.json.phonebox-backup`'a kopyalanır (yedek hep PhoneBox dokunmadan
  önceki dosyadır; yeniden kurma ve kaldırma yedek yazmaz); sonra yalnız PhoneBox'ın girdileri eklenir (her olayın
  dizisine bir grup), diğer her şey korunur; dosya atomik yazılır (anahtarlar sıralı, iki boşluk girinti).
- PhoneBox'ın girdisi: komutu `--claude-hook` ile biten ve `PhoneBox` içeren hook. Yeniden kurmak eskilerini (başka
  yoldakiler dahil) silip ekler; kaldırmak yalnız bunları siler, boşalan grupları/olayları/`hooks`'u da siler.
- Kapatınca kaldırır. Açılışta ayar açıksa dosyaya bakılır (`ClaudeHooks.launchCheck`): okunamıyorsa ya da dosya hiç
  yoksa (`~/.claude` yok) dokunulmaz, günlüğe yazılır, ayar açık kalır; PhoneBox girdisi yoksa (kullanıcı elle sildi) ayar kapanır; girdilerin çalıştırdığı uygulama artık yoksa
  (uygulama taşındı) ya da bazı olaylarda girdi yoksa bu uygulamanın yoluyla yeniden kurulur; girdilerin hepsi hâlâ duran başka
  PhoneBox'lara aitse, bu uygulamanınki yoksa (deneme kopyası) eksik olay olsa da dosyaya dokunulmaz, girdiler onlarındır.
- Aynı soketi iki PhoneBox kullanabilir (`PHONEBOX_DEST` ile kurulan deneme kopyası `/Applications`'takinin yanında):
  açılırken soket dosyası varsa önce bağlanmayı dener; biri kabul ederse dosyaya dokunmaz, günlüğe yazar ve dinlemez;
  yalnız kimse dinlemiyorsa (`ECONNREFUSED`, çökmüş bir PhoneBox'tan kalmış) dosyayı silip kendisi dinler. Kapanırken
  soket dosyasını yalnız hâlâ kendi yaptığı dosyaysa (`bind` sonrası `st_dev`/`st_ino`) siler.
- `install.sh --uninstall` uygulamayı silmeden önce `PhoneBox --remove-claude-hooks` çalıştırır.

Anlık görüntü: `claude` alanı yalnız özellik açıkken gelir:
`"claude":[{"id":"…","title":"…","project":"PhoneBox","model":"Opus 5.5","state":"waiting","reason":"question","since":<ms>}]`
(`state`: `ready` | `working` | `waiting`; `reason` yalnız `waiting`'de: `question` | `permission` | `turn`;
`activity` yalnız `working`'de: `think` | `command` | `edit` | `read` | `web` | `agent` | `tool` | `background`).
