# PhoneBox — Elle test listesi

Her sürümden önce gerçek bir iPhone ile. Otomatik Kilit 30 sn; Mac'te `make run`.
Bağlantıların hangi arayüzden geldiğini görmek için:
`log stream --info --predicate 'subsystem == "com.phonebox.PhoneBox"'` (satır: `Phone connected on … (scoped link-local: …, USB: …)`)
ya da `lsof -nP -iTCP:4747 -sTCP:ESTABLISHED` (`fe80:<scope>::…` adresinin scope'u `ifconfig` ile arayüze eşlenir).

## Eşleştirme ve bağlantı
- [ ] İlk kurulumdan sonra (ya da yeni bir anahtar oluşunca) iPhone takılıyken QR penceresi kendiliğinden açılıyor.
- [ ] QR okutulunca dashboard varsayılan tarayıcıda açılıyor; "Başlat" sonrası CPU ve RAM canlı.
- [ ] Kablo modunda bağlantı iPhone'un USB arayüzünden geliyor (`scoped link-local: true, USB: true`); iPhone'un
  Wi-Fi'si kapalıyken de çalışıyor.
- [ ] Ana Ekrana Ekle simgesinden açılınca anahtar korunuyor.
- [ ] "Eşleştirmeyi sıfırla…" → açık sayfa "Eşleşmedi" (Başlat katmanı mesajı örtmüyor); yeni QR okutulunca aynı
  sekme kendini yenileyip bağlanıyor.

## Kablo modu
- [ ] Kablo çıkınca birkaç saniyede menü simgesi griye dönüyor; sayfa "Kabloyu tak" ya da "Mac'e ulaşılamıyor".
- [ ] Kablo takılınca ~10 sn içinde kablo üzerinden geri geliyor (sayfayı yenilemeden).
- [ ] İlk kez takılan, henüz "Bu bilgisayara güven" denmemiş bir telefon: güvenildikten sonra veri yenilemeden geliyor.
- [ ] Kabloyu 5 kez çıkar-tak: hiçbir zaman 503 / "Mac'e ulaşılamıyor"da kalmıyor.
- [ ] "Her zaman" modunda kablo yokken Wi-Fi üzerinden veri geliyor; kablo moduna dönünce Wi-Fi'deki telefon
  "Kabloyu tak" görüyor.

## Ekran, ses ve kilit
- [ ] Dashboard açıkken ekran 30 dk kapanmıyor.
- [ ] Telefonda çalan müzik durmuyor; kilit ekranında kullanıcının şarkısı görünüyor.
- [ ] 1 dk kilitle-aç: bağlantı ve ekranı açık tutma geri geliyor, "Eşleşmedi" çıkmıyor.

## Mac
- [ ] Menü çubuğu simgesi veri akarken yeşil, değilken gri.
- [ ] "Girişte başlat" açılıp kapanıyor (Sistem Ayarları → Genel → Giriş Öğeleri'nde görünüyor).
- [ ] Kimse bağlı değilken PhoneBox'ın CPU kullanımı ~%0.
- [ ] Mac boştayken (ekran açık, kullanıcı yok) Etkinlik Monitörü'nde PhoneBox için "App Nap: Hayır" ve telefonda
  değerler saniyede bir değişiyor.

## Metrikler
- [ ] Yeni metrik satırları ve uygulama listesi telefonda okunaklı (dikey ve yatay; taşan ya da kesilen yok).
- [ ] Ağ satırı sayfa açılır açılmaz dolu (ilk saniyede "—" yok), değerler `netstat -ib` ile aynı büyüklükte.
- [ ] Pildeyken (adaptör çıkık) "Güç" satırı 0 W değil, Mac'in tamamının çekişini gösteriyor.
- [ ] Bir telefon veri alırken PhoneBox `top`'ta %1'in altında.

## Arayüz (Plan 4A)
- [ ] Yatay ve dikeyde her şey sığıyor; kesilen, taşan, üst üste binen yok (iPhone SE'den Pro Max'e).
- [ ] Halkaya ya da kutucuğa dokununca grafik ve başlık o metriğe geçiyor; seçim sayfa yeniden açılınca hatırlanıyor.
- [ ] Uygulama listesinin başlığına dokununca CPU/RAM sıralaması değişiyor; kapatılamayan uygulamalar gri.
- [ ] Mac'te bir şey çalarken şarkı kartı görünüyor, hiçbir şey çalmayınca birkaç saniyede gidiyor.
- [ ] Durum satırı kabloda yeşil "kablo", Wi-Fi'de turuncu "Wi-Fi"; veri kesilince gri "Bağlanıyor…" ve soluk değerler.
- [ ] İlk açılışta rehber çıkıyor, "Başlat" ekranı açık tutuyor; "⋯ → Kurulum rehberi" yeniden açıyor; "Kopyala"
  kişisel bağlantıyı kopyalıyor.
- [ ] Ana ekran simgesi yeşil ve mavi halkalı.

## Komutlar (kablodan; telefondan Plan 4'ün arayüzüyle denenir)
- [ ] Kapat: Dock'taki bir uygulama kapanıyor (kaydedilmemiş belge varsa Mac'te sorar); `ack` `ok`.
- [ ] Zorla kapat: uygulama hemen kapanıyor.
- [ ] Finder ve arka plan süreçleri kapatılamıyor (`app-changed` / gri satır).
- [ ] Medya: oynat-duraklat, sonraki, önceki Mac'te çalanı değiştiriyor; çalan şarkı kartı birkaç saniyede güncelleniyor.
- [ ] Ses kaydırıcısı ve sessiz Mac'in sesini değiştiriyor; Mac'te değişen ses telefona yansıyor.
- [ ] Kilitle: Mac kilit ekranına geçiyor. Ekranı kapat: ekran kararıyor.
- [ ] Uyut: telefona önce "oldu" geliyor, Mac 1 sn sonra uyuyor; uyanınca dashboard kendiliğinden bağlanıyor.
- [ ] Wi-Fi'deki telefon ("Her zaman" modu) veri alıyor ama her komuta `not-allowed`.
- [ ] "Her zaman" modunda Wi-Fi'den bağlı telefon kabloya takılınca birkaç saniyede "kablo"ya geçiyor, komutlar açılıyor.
- [ ] Kişisel Erişim Noktası açık, telefon takılı ve ikinci bir cihaz erişim noktasına bağlıyken o cihazdan
  `curl -g "http://[fe80::<Mac'in adresi>%<arayüz>]:4747/"` bağlanamıyor (bağlanırsa erişim noktasındaki cihazlar da
  "kablo" sayılır; o zaman bu arayüz dışlanır ya da risk §13'e yazılır).

## Henüz denenmemiş (spike 8)
- [ ] Kestirmeler → Otomasyon → Şarj Aleti → "URL'yi Aç" (kişisel bağlantı) → "Hemen Çalıştır": kablo takılınca
  dashboard onaysız açılıyor mu?

---

## Sonuçlar

### 2026-11-25 — Plan 2 (dal `plan2`, 96783c3), MacBook Pro M4 / macOS 27.2, iPhone iOS 27.0.1

Mac'te (tarayıcı paneli, Mac'in kendi tarayıcısı):
- Geçti: "Her zaman" modunda canlı CPU/RAM; "Başlat" sonrası video sesi açık, döngüsüz oynuyor.
- Geçti: PhoneBox 9 sn dondurulunca (SIGSTOP) değerler soluklaştı, devam edince ≤ 8 sn'de yeni bağlantıyla geri geldi.
- Geçti: yanlış anahtar → "Eşleşmedi", Başlat katmanı gizli; aynı sekmeye yeni `#k=` verilince sayfa yenilenip bağlandı.
- Geçti: kablo modunda `lo0` istemcisi → "Kabloyu tak" (`scoped link-local: false, USB: false`), sayfa ~11 sn'de bir
  kendini yokladı.

iPhone ile:
- Geçti: QR ile eşleşme; kablo modunda (varsayılan) canlı veri. Bağlantılar `fe80:1b::…` üzerinden, yani iPhone'un
  USB arayüzünden (`anri1`) geliyordu — "kapsamlı IPv6 link-local = kablo" kuralı gerçek cihazda doğrulandı.
- Geçti (kullanıcı bildirdi): iPhone Wi-Fi'si kapalıyken veri geldi.
- Geçti (log/durum): "Eşleştirmeyi sıfırla" → anahtar 20:35'te yenilendi, telefon yeni QR ile tekrar eşleşti.
- Geçti (durum): "Her zaman" modunda telefon Wi-Fi'den (`en0`, IPv6 link-local) bağlı ve veri alıyordu; bu bağlantı USB
  sayılmadı.
- Yapıldı, sorun bildirilmedi, ayrıntı/süre kaydedilmedi: kabloyu çıkar-tak, 1 dk kilit, müzik + 2 dk ekran açık.
- Denenmedi: 5 kez çıkar-tak, güvenilmemiş telefon, App Nap, Kestirmeler otomasyonu.

### 2026-11-25 — Plan 3A (dal `plan3a`, 4e56dfe), MacBook Pro M4 / macOS 27.2, iPhone iOS 27.0.1

Mac'te (tarayıcı paneli):
- Geçti: GPU, Sıcaklık (ort./en yüksek), Güç ("Mac'in tamamı", `SystemLoad`), Ağ (`en0`), Disk (boş/toplam, okuma/yazma),
  Pil satırları ve "En çok kullananlar" listesi Türkçe biçimlerle görünüyor; ağ satırı ilk gözlenen snapshot'ta dolu.
- Geçti: PhoneBox bir istemciye veri gönderirken `top`'ta 30 sn ortalama %0,74 CPU (düzeltmelerden önce %1,34).
- Bulundu ve düzeltildi: `getifaddrs` ve `NET_RT_IFLIST2` bu macOS'ta bayt sayaçlarının sadece alt 32 bitini veriyor
  (`en0` 961 MB, `netstat -ib` 48,2 GB); `net.link.generic.ifdata` tam değeri veriyor (`4e56dfe`).

iPhone ile:
- Geçti (kullanıcı bildirdi): yeni satırlar ve uygulama listesi dikey ve yatayda okunaklı, sorun yok. Telefon takılıydı ama
  mod "Her zaman" olduğu için bağlantı Wi-Fi'den (`en0`) geliyordu; görünüm bağlantı yolundan bağımsız.
- Denenmedi: pildeyken güç değeri (Mac prizdeydi), kablo modunda bu sürüm.

### 2026-11-25 — Ana Ekrana Ekle (main fd4771a), iPhone iOS 27.0.1, Chrome

- Geçti (kullanıcı bildirdi): Chrome'da paylaş → Ana Ekrana Ekle; simgeden açılan sayfa tam ekran (adres çubuğu yok),
  `#k=` anahtarı korunuyor, "Başlat" sonrası veri geliyor. Tarayıcıda adres çubuğu sayfadan gizlenemiyor; tam ekranın
  yolu bu.

### 2026-11-25 — Plan 3B Mac tarafı (dal `plan3b`, 5651a94), MacBook Pro M4 / macOS 27.2

Mac'te (tarayıcı paneli, `lo0`, "Her zaman" modu):
- Geçti: `ready` → `host: "Eren MacBook Pro"`, `access {streaming: true, commands: false, cable: false}`.
- Geçti: imzalı `mute` ve bilinmeyen komut → ikisi de `not-allowed` (kablo dışı istemci komut çalıştıramıyor).
- Geçti: snapshot'ta `audio {volume: 0.81, muted: false}`; o an hiçbir şey çalmadığı için `media` yok (adaptörün `get`'i
  `null`). Planlamada Chrome'da duraklatılmış bir YouTube videosu `media` olarak geldi.
- Geçti: WebSocket yükseltmesinde `Origin: http://localhost:4747` → 101, `Origin: http://evil.example` → 403.
- Geçti: PhoneBox 30 sn ortalama %0,60 CPU, adaptör süreci %0,03.
- Geçti: `PHONEBOX_LIVE=1` canlı testler (ses seviyesi ve sessiz okunup aynen yazıldı; Satranç açılıp `quitApp` ile
  kapandı; Finder ve çalışmayan uygulama `app-changed`; adaptörsüz medya `unsupported`).
- Bulundu ve düzeltildi (5651a94): PhoneBox kapanınca adaptör süreci sahipsiz kalıp bir sonraki medya değişikliğine kadar
  yaşıyordu; artık kapanışta durduruluyor (kapatma sonrası adaptör sayısı 0).
- Denenmedi (telefon kabloda gerekir, Plan 4): komutların USB'den gelmesi; kilit, ekranı kapatma, uyku ve medya gönderme
  bu Mac'te kullanıcıyı rahatsız etmemek için çalıştırılmadı (spike 7'de medya dışındakiler izin penceresi olmadan çalıştı).

### 2026-11-25 — Plan 4A (dal `plan4a`, 9d67dd7), MacBook Pro M4 / macOS 27.2, iPhone iOS 27.0.1

Mac'te (tarayıcı paneli, gerçek veri):
- Geçti: 734×372, 393×759, 667×375, 375×647, 814×409 ölçülerinde ekran dışına taşan öğe ya da kesilen kutucuk/başlık
  yok; grafik çiziliyor (SE dikeyde 63 px, 4 uygulama satırı); konsolda JavaScript hatası yok.
- Geçti: "Başlat" videoyu başlatıp ekranı açtı; kutucuk grafiği ve başlığı değiştirdi; "⋯" menüsü düğmesinin üstünde
  açıldı ve rehberi açtı; "Kabloyu tak" kartı soluk değerlerin üstünde göründü.
- Geçti: anahtarsız sayfada "Eşleşmedi" kartı; rehber menüden açılıyor.
- Geçti: PhoneBox 22 sn durdurulunca sayfa 1/2/5/5/5 sn arayla denedi ve kendiliğinden döndü.

iPhone ile (Chrome, ana ekran simgesi):
- Geçti (kullanıcı bildirdi): yeni simgeyle yeniden eklendi; rehber ve "Başlat"; yatay ve dikeyde düzgün; kutucuk
  grafiği değiştiriyor; sıralama; çalan şarkı kartı; kablo çıkar-tak. Adımlar ayrı ayrı kaydedilmedi.
- Denenmedi: telefonda "Kopyala" düğmesi, Safari'deki rehber metni, 3 dakikalık OLED kayması.

