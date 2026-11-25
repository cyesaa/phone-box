# PhoneBox — Deneme (spike) sonuçları

- **Tarih:** 2026-11-25
- **Mac:** MacBook Pro (Mac16,1), Apple M4, 16 GB, macOS 27.2
- **iPhone:** iOS 27.0.1 (Chrome for iOS 158 ve Safari 27.0.1 ile denendi)
- **Plan:** `docs/design/plans/2026-11-25-phonebox-spike.md`; araçlar `spike/` altında

## Özet

Tasarımın dayandığı kritik varsayımların hepsi geçti. Ayrıca beklenmedik bir şey öğrendik: **iPhone kabloyla
takılıyken tarayıcı Mac'e USB kablosu üzerinden bağlanıyor.** Kullanıcının ilk istediği "veri kablodan gitsin"
fikri, telefona hiçbir şey kurmadan gerçekleşiyor. Ekranı açık tutmanın tek yolu sesi açık bir video; telefondaki
müziği durdurmaması için Audio Session API ile "ambient" ses oturumu kullanılıyor (V4).

| # | Soru | Sonuç | Gözlem | Karar |
|---|---|---|---|---|
| 1 | `.local` adresi açılıyor mu? | Geçti | QR'dan Chrome, elle yazınca Safari `http://Eren-MacBook-Pro.local:4747` adresini açtı; iPhone izin sormadı. Kablo takılıyken ad USB bağlantısına çözüldü | `.local` adı kalır; bağlantılar her zaman `http://` ile verilir |
| 2 | Ekran açık kalıyor mu? | Geçti (V4) | V1 33 sn, V2 39 sn sonra kapandı. V3 30 dk açık tuttu ama telefondaki müziği durdurdu ve kilit ekranına medya kartı koydu. V4 Chrome'da ve Safari'de 2'şer dk açık tuttu, müzik durmadı, kilit ekranında çalan şarkı kaldı | V4 kullanılır; görünür sayfada video duraksa yeniden başlatan bir bekçi eklenir |
| 3 | Ana ekran simgesi anahtarı koruyor mu? | Geçti | Simgeden açılınca `standalone=true`, anahtar mevcut, bağlantı kuruldu. Önerilen ad "eren-macbook-pro.local", simge yok (404) | `apple-touch-icon.png` ve `apple-mobile-web-app-title` = PhoneBox eklenir |
| 4 | Kilitle-aç sonrası yeniden bağlanma | Geçti | Kısa kilit ve 2 dk 40 sn kilit sonrası bağlantı kendiliğinden geri geldi. Chrome'da kilit açılınca `visibilitychange` gelmedi; bağlantıyı yeniden deneme zamanlayıcısı kurdu | Yeniden bağlanma zamanlayıcıyla da yapılır, sadece `visibilitychange`'e güvenilmez |
| 5 | usbmuxd takma/çıkarma | Geçti | 18:13:34 `DETACHED`, 18:13:42 `ATTACHED`, anında. Cihaz numarası her takışta değişiyor (9 → 10) | USBWatcher "takılı bir iPhone var mı"ya bakar |
| 6 | Sıcaklık ve güç (sudo'suz) | Kısmen | 44 sıcaklık sensörü, GPU kullanımı, GPU watt'ı ve MacBook'ta toplam sistem gücü okunuyor. CPU ve ANE enerji sayaçları root olmadan ilerlemiyor | Güç = sistem W (MacBook) + GPU W; CPU/ANE watt'ı yok |
| 7 | Komutlar ve izinler | Geçti (medya hariç) | Uygulama kapatma, sessiz, ses seviyesi, ekranı kapatma, kilit izin penceresi olmadan çalıştı. Medya denenmedi (Mac'te çalan bir şey yoktu); adaptörün `get` komutu çalıştı | Tasarımdaki gibi; medya NotchBox'taki adaptörle |
| 8 | Kestirmeler şarj otomasyonu | Denenmedi | Fiziksel takıp çıkarma gerekiyordu; kullanıcı kalan adımları Claude'un yapmasını istedi, oturumda masaüstü kontrolü yoktu | İsteğe bağlı rehber adımı olarak kalır; Plan 2'nin elle test listesinde denenir |
| 9 | macOS izinleri | Kısmen | Bu Mac'te hiçbir izin penceresi çıkmadı; güvenlik duvarı kapalı olduğu için "gelen bağlantılar" penceresi burada görülemez | README'de güvenlik duvarı açık olanlar için not |

## Ayrıntılar

### USB üzerinden bağlantı (beklenmeyen bulgu)

- `lsof`, telefonun WebSocket'inin IPv6 link-local adresten (`fe80:1b::…`) geldiğini gösterdi. Arayüz `anri1`:
  `AppleUSBHostNCMRestrictedEthernetInterface`, `AppleUSBNCM11Data` / `IOUSBHostInterface` üzerinde, yani güvenilen
  iPhone'un USB NCM bağlantısı. Başka bir takışta aynı bağlantı `en8` (yine `AppleUSBNCM11Data`) üzerinden geldi.
  Arayüz adı ve numarası takıştan takışa değişiyor.
- iPhone'un Wi-Fi'si kapalıyken sayfa yenilendi ve bağlandı: **kablo tek başına yetiyor**, ortak Wi-Fi gerekmiyor.
- Sonuç: Mac, bir istemcinin kablodan mı Wi-Fi'den mi bağlandığını bağlantının arayüzünden anlayabilir.
  "Kablo takılıyken" modu artık "bu istemci USB bağlantısı üzerinden geliyor" anlamına gelebilir.

### Ekranı açık tutma

| Varyant | Video | Tarayıcı | Sonuç |
|---|---|---|---|
| V1 | Sessiz, döngülü, sadece görüntü | Chrome | 33 sn'de kilitlendi |
| V2 | Sessiz, döngüsüz (başa sarar), ses izli | Chrome | 39 sn'de kilitlendi |
| V3 | Sesi açık, döngüsüz, sessiz ses izli | Chrome | 30 dk açık kaldı; müziği durdurdu; kilit ekranında medya kartı |
| V4 | V3 + `navigator.audioSession.type = "ambient"` | Chrome, Safari | 2'şer dk açık kaldı; müzik sürdü; kilit ekranında kullanıcının şarkısı |

- WebKit ekranın uyumasını sadece sesi açık, döngüsüz, hem görüntü hem ses izi olan bir video oynarken engelliyor.
  Bu yüzden V3/V4'teki video döngü yerine 0,5 sn'den sonra başa sarılıyor.
- Audio Session API iOS 27'de Chrome'da da (WKWebView) var.
- V4'ün 30 dakikalık uzun testi ayrıca yapılmadı; aynı mekanizma (V3) 30 dakika geçti.
- Sayfa gizlenince video duruyor. Uygulama değiştirip dönünce `visibilitychange` ile yeniden başlatılabildi, ama
  Chrome'da kilit açılınca bu olay gelmediği için video duraklamış kaldı. Plan 2: sayfa görünürken birkaç saniyede bir
  "video duruyorsa başlat" denetimi, ayrıca `pageshow` ve `focus`.
- iOS videoları byte aralığı istekleriyle çekiyor (`bytes=0-1`, sonra `bytes=0-<son>`); sunucu `206 Partial Content`
  dönmeli.

### Tarayıcılar

- iPhone kamerası QR bağlantısını varsayılan tarayıcıda açıyor (bu kullanıcıda Chrome). Dashboard her iki tarayıcıda
  da çalıştı.
- Adres `http://` olmadan yazılınca Safari'den sunucuya istek gelmedi; büyük olasılıkla önce HTTPS denendi. Plan 2:
  ilk baytı `0x16` (TLS el sıkışması) olan bağlantıyı hemen kapat; bağlantıları hep `http://` ile göster.
- Safari'nin kullanıcı aracısı iOS sürümünü "18_7" diye donduruyor; sürüm tespiti için kullanılmamalı.

### Metrikler (planlama sırasında, 2026-11-25)

| Konu | Gözlem |
|---|---|
| Sıcaklık | 44 sensör (`PMU tdie1…14`, `PMU2 tdie1…10`, `PMU tdev*`, `NAND CH0 temp`, `gas gauge battery`) |
| Güç | "Energy Model"da `CPU Energy`, `ECPU`, `PCPU`, `ANE`, `DRAM` root olmadan sabit; bütün IOReport gruplarında ilerleyen tek enerji kanalı `GPU Energy` (nJ) |
| Sistem gücü | `AppleSmartBattery` → `PowerTelemetryData.SystemPowerIn`: 6,9–7,2 W |
| GPU kullanımı | `IOAccelerator` → `Device Utilization %`: %17–24 |
| Uygulama adları | `localizedName` görünmez yön karakteri içerebiliyor (WhatsApp → `U+200E` + "WhatsApp") |

### Mac tarafı

- `open --stdout <~/Documents içinde bir yol>` LaunchServices hatası -10810 verdi (kullanıcının kendi Terminal'inde de).
  Yeni başlatılan bir uygulama `~/Documents`'a yazamıyor. Log `/private/tmp` altına alınınca uygulama başladı.
  Plan 2: log ve geçici dosyalar `~/Library/Logs` / `~/Library/Caches` altında.
- Güvenlik duvarı bu Mac'te kapalı (`socketfilterfw --getglobalstate` → State = 0).
- `make-video.swift` macOS 27'de AVFoundation "deprecated" uyarıları veriyor; API'ler çalışıyor.

## Tasarıma etkileri

1. **Veri yolu:** Kablo takılıyken USB (iPhone'un USB NCM bağlantısı), değilse Wi-Fi. Bölüm 1, 2, 3, 4 güncellendi.
2. **Kablo modu:** "Herhangi bir iPhone takılı" yerine "istemci USB bağlantısı üzerinden geliyor". Eski "hangi iPhone"
   sınırı kalktı. usbmuxd QR penceresini açmak için kullanılmaya devam ediyor. Bölüm 5 ve 13 güncellendi.
3. **Ekranı açık tutma:** V4 ve video bekçisi. Bölüm 3 ve 8 güncellendi.
4. **Güç:** CPU/ANE watt'ı çıkarıldı. Bölüm 2, 6 ve 8 güncellendi.
5. **Ana ekran:** simge ve ad. Bölüm 8 güncellendi.
6. **HTTPS denemesi, Range, log yeri, uygulama adlarının temizlenmesi:** Bölüm 6, 9 ve 12 güncellendi.
