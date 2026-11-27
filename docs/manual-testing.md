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
- [ ] Ayarlar → Eşleştirme → "Sıfırla…" → açık sayfa "Eşleşmedi" (Başlat katmanı mesajı örtmüyor); yeni QR okutulunca aynı
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
- [ ] Ayarlar → Genel → "Girişte başlat" açılıp kapanıyor (Sistem Ayarları → Genel → Giriş Öğeleri'nde görünüyor).
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
- [ ] Saat başlığındaki nokta kabloda yeşil (yanında telefonun pili), Wi-Fi'de turuncu ve "Wi-Fi"; veri kesilince gri
  "Bağlanıyor…" ve soluk değerler. Mac'in adı "⋯" menüsünün başında.
- [ ] İlk açılışta rehber çıkıyor, "Başlat" ekranı açık tutuyor; "⋯ → Kurulum rehberi" yeniden açıyor; "Kopyala"
  kişisel bağlantıyı kopyalıyor.
- [ ] Ana ekran simgesi yeşil ve mavi halkalı.

## Görünüm ve kızarma (Plan 4C)
- [ ] Okyanus renkleri; halkaların ucu parlıyor, üstünden parıltı akıyor; sayılar yumuşakça değişiyor; uygulama
  satırları yer değiştirirken kayıyor; çalarken ekolayzer oynuyor.
- [ ] Grafik Wi-Fi'de de, kabloda da düzgün akıyor (durup geri sıçramıyor); tepeler sınıra yaklaştıkça kırmızı,
  sınır kesikli kırmızı çizgi.
- [ ] Saat ve tarih doğru, dakika değişince rakam kayarak dönüyor; kabloda telefonun pili Ayarlar'daki yüzdeyle aynı;
  kilitleyip açınca pil simgesi birkaç saniyede geri geliyor.
- [ ] Mac'te `bash -c 'for i in $(seq 10); do yes > /dev/null & done; sleep 20; kill $(jobs -p)'`: CPU halkası kızarıyor,
  ~3 sn sonra kenar ışığı atıyor ve saatin altında "▲ CPU %…"; yük bitince birkaç saniyede susuyor.
- [ ] Veri kesilince (kablo çıkar, Wi-Fi kapalı) alarm ve kenar ışığı sönüyor, değerler soluk ve kıpırdamıyor.
- [ ] Ayarlar → Erişilebilirlik → Hareket → Hareketi Azalt: parıltı, nabız ve kayma duruyor; renkler ve sayılar kalıyor.
- [ ] Güç sınırı: Mac'te en az 1 dk tam yükte (CPU + GPU) güç kutusunun gösterdiği en yüksek watt, çipin sınırına
  (M4: 35 W) yakın mı? (Mac'in güç değeri ~20 sn'de bir güncelleniyor.)

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

## Wi-Fi'den kilit ve müzik (0.2.0)
- [ ] Ayarlar → Bağlantı'da "Wi-Fi'den kilit ve müzik" kablo modunda kapalı ve soluk, "Her zaman" modunda
  kullanılabiliyor.
- [ ] Açarken uyarı çıkıyor; "Vazgeç" ayarı kapalı bırakıyor (işaret yok), "İzin ver" açıyor (işaret var); kapatırken
  soru sormuyor.
- [ ] Wi-Fi'deki telefonda (kablo yok, ayar açık): medya düğmeleri ve Kilitle çalışıyor.
- [ ] Aynı telefonda ses kaydırıcısı, sessiz, Ekranı kapat, Uyut ve uygulama panelinin Kapat / Zorla kapat düğmeleri
  soluk; dokununca "Bu komut sadece kabloyla çalışır" bildirimi çıkıyor ve hiçbir şey olmuyor.
- [ ] Kilitle'ye 30 sn içinde ikinci kez basınca bir şey olmuyor; 30 sn sonra yine kilitliyor.
- [ ] Kabloda her şey çalışıyor, Kilitle'ye art arda basmak da.

## Claude Code oturumları (0.3.0)
- [ ] Özellik kapalıyken telefonda ikinci sayfa, sağ kenarda noktalar ve dikey kaydırma yok; dashboard eskisi gibi.
- [ ] Ayarlar → Claude Code'da "Claude Code oturumlarını telefonda göster" önce soruyor; "Vazgeç" hiçbir şeye dokunmuyor. "Aç"tan sonra
  `~/.claude/settings.json`'da on olayın her birinde PhoneBox'ın `--claude-hook` grubu var, dosyanın diğer ayarları
  duruyor, `settings.json.phonebox-backup` eski dosyayla aynı. Telefonda ikinci sayfa ve noktalar beliriyor.
- [ ] Yeni bir oturum (terminalde `claude`, VS Code, masaüstü uygulaması) birkaç saniyede gri "Hazır" kartıyla
  görünüyor; başlık oturumun adı (yoksa klasörün adı), proje ve model çipleri doğru.
- [ ] Bir mesaj gönderince kart mavi "Düşünüyor"; araç kullanırken ne yaptığını yazıyor ("Komut çalıştırıyor",
  "Dosya düzenliyor"…) ve ince çizgi akıyor; aynı turdaki araçlar süreyi sıfırlamıyor.
- [ ] Oturum seçenekli bir soru sorunca pano yukarı kayıyor, Claude sayfası geliyor; kart turuncu, parlıyor, "Soru
  soruyor". Soru Mac'te cevaplanınca, başka bekleyen yoksa sayfa 3 sn sonra panoya dönüyor.
- [ ] İzin isteyen bir komut: "İzin istiyor" kartı, sayfa geliyor; izin verilince 3 sn sonra dönüyor. Tur bitince
  "Sıra sende"; arka planda iş sürüyorsa mavi "Arka planda çalışıyor".
- [ ] Sayfa gelince parmakla aşağı kaydırıp panoya dön: aynı oturumlar beklerken sayfa yeniden gelmiyor; biri yeniden
  beklemeye başlayınca geliyor. Parmakla Claude sayfasına geçince kimse beklemese de kendiliğinden dönmüyor.
- [ ] Ses kaydırıcısında sürükleme sayfa değiştirmiyor; panel, onay, "⋯" menüsü ya da rehber açıkken kaydırma bir şey
  yapmıyor; halkalar, kutucuklar, uygulama satırları ve şerit dokununca eskisi gibi çalışıyor. Chrome'da aşağı
  kaydırma sayfayı yenilemiyor.
- [ ] Oturumdan çıkınca (`/exit`, pencereyi kapatma) kartı birkaç saniyede gidiyor; Claude Code zorla kapatılınca en
  geç ~5 sn'de.
- [ ] Yatayda 4 oturuma kadar iki sütun, 5 ve üstünde üç sütun (sıkı kartlar); dikeyde tek sütun; kesilen ya da taşan
  yok. Oturum yokken "Açık Claude oturumu yok".
- [ ] Veri kesilince Claude sayfası da soluk ve kıpırdamıyor; Hareketi Azalt açıkken kayma ve kart girişleri anlık.
- [ ] Ayarlardan kapatınca hook'lar `settings.json`'dan siliniyor (diğer her şey duruyor); telefonda ikinci sayfa ve
  noktalar gidiyor, Claude sayfasındaysa panoya dönüyor.
- [ ] Özellik açıkken `install.sh --uninstall` hook'ları siliyor.
- [ ] Özellik kapalıyken zaten açık olan bir oturum, özellik açılınca bir sonraki olayında (mesaj, araç) listede
  beliriyor mu? (Hook'lar açılmadan önceki oturumlar yeni hook'ları ancak yeniden başlayınca ya da her olayda görür.)
- [ ] Kaldırdıktan (`install.sh --uninstall`) sonra açık kalan Claude oturumları hata vermiyor, Claude Code'da hook
  hatası görünmüyor.
- [ ] İki kopya: `PHONEBOX_DEST` ile `/Applications`'ın yanına deneme kopyası kur. Deneme kopyası soketi ve hook'ları
  almamalı (`/Applications`'takinin hook'ları yerinde, oturumlar oradan geliyor). Deneme kopyasında özelliği açıp
  kapatmak ortak ayarı ve hook'ları etkiler: yalnız bilerek yap.

## Ayarlar penceresi (0.4.0)
Açık ve koyu temada ayrı ayrı (Sistem Ayarları → Görünüm); iki dilde birer kez (Sistem Ayarları → Genel → Dil ve
Bölge → Uygulamalar → PhoneBox).
- [ ] Menü kısa: durum satırı, "Ayarlar…" (⌘, yazıyor), "QR kodunu göster…", (yeni sürüm varsa "PhoneBox x.y.z
  sürümünü yükle…"), "Güncellemeleri denetle…", "PhoneBox'tan çık". Mod, Wi-Fi'den kilit, Claude, Port, Girişte başlat
  ve Eşleştirmeyi sıfırla menüde yok.
- [ ] "Ayarlar…" pencereyi başka bir uygulamanın önüne getiriyor; Finder'dan ya da `open -a PhoneBox` ile yeniden açmak
  da getiriyor (ikinci bir PhoneBox açılmıyor). Kapatma düğmesi ve ⌘W yalnız gizliyor; yeniden açınca aynı bölüm.
- [ ] Pencere küçültülüp büyütülebiliyor, 680×460'tan küçülmüyor; PhoneBox yeniden açılınca aynı yerde ve boyutta.
- [ ] Kenar çubuğunda dört bölüm renkli simgeleriyle; seçili satır sistemin vurgu rengiyle; arama alanı yok.
- [ ] Bağlantı: telefon takılıyken yeşil nokta ve "iPhone bağlı", altında "1 cihaz · kabloyla"; kablo çıkınca birkaç
  saniyede "iPhone bekleniyor" (pencere açıkken, kapatıp açmadan). "Her zaman"da Wi-Fi'den bağlanınca "Wi-Fi'den";
  kablo kipinde Wi-Fi'deki telefonla turuncu "Telefon Wi-Fi'de: kabloyu tak".
- [ ] "Kablo takılıyken"e geçince "Wi-Fi'den kilit ve müzik" kapalı ve soluk; "Her zaman"a dönünce eski hâli. Telefonun
  erişimi menüdeki gibi hemen değişiyor.
- [ ] "Wi-Fi'den kilit ve müzik"i açarken 0.2.0'daki uyarı aynı metinle çıkıyor; "Vazgeç" anahtarı kapalı bırakıyor,
  "İzin ver" açıyor; kapatırken sormuyor.
- [ ] Port → "Değiştir…": port penceresi aynı; geçersiz sayıda yeniden soruyor; boş bir port seçince numara değişiyor ve
  QR penceresi açılıyor; kullanımdaki bir portta "Port … zaten kullanımda" uyarısı, numara değişmiyor.
- [ ] Eşleştirme: QR kodu telefonla okutulunca dashboard açılıyor. "Bağlantıyı kopyala" panoya kişisel bağlantıyı
  koyuyor ve "Kopyalandı" oluyor; "Büyüt…" QR penceresini açıyor. "Eşleşmiş telefonlar" bağlı telefon sayısını canlı
  gösteriyor. "Sıfırla…" uyarısı aynı; "Vazgeç" bir şey yapmıyor, "Sıfırla" sonrası penceredeki QR yeni bağlantıyı
  gösteriyor, telefon "Eşleşmedi" görüyor.
- [ ] Claude Code: açarken 0.3.0'daki uyarı; "Aç" sonrası durum "Hook'lar kurulu · N oturum", bir oturum soru sorunca
  "· 1 seni bekliyor" pencere açıkken beliriyor. Kapatınca "Kapalı". `settings.json` bozukken (geçici bir kopyayla)
  açmak uyarıyı gösteriyor, anahtar kapalı kalıyor ve sebep durumun altında kırmızı. "Finder'da göster" gerçek dosyayı
  seçiyor (sembolik bağlantıysa hedefini); dosya yoksa soluk.
- [ ] Genel: "Girişte başlat" açılıp kapanıyor ve Sistem Ayarları → Giriş Öğeleri ile aynı; orada kapatıp pencereye
  dönünce anahtar kapalı. Onay gerekirse açıklama satırı ve "Giriş Öğeleri'ni aç" görünüyor.
- [ ] Güncelleme: "PhoneBox 0.4.0", altında "Güncel · son denetim … önce"; "Şimdi denetle" sırasında "Denetleniyor…",
  sonra menüdeki gibi "PhoneBox … güncel." uyarısı. `UpdateFeedURL` ile yeni bir sürüm gösterilince "x.y.z sürümü var" ve
  "Yükle…" (onay uyarısı aynı). İnternet yokken "Denetlenemedi".
- [ ] "GitHub'da aç" depo sayfasını, "Lisanslar" `LICENSE` ve `THIRD_PARTY_NOTICES.md`'yi TextEdit'te açıyor.
- [ ] Bütün uyarılar (kilit ve müzik, Claude, port, sıfırlama, giriş öğeleri, güncelleme) 0.3.0'daki metinlerle; açıkken
  telefonun bağlantısı kopmuyor.
- [ ] Koyu ve açık temada metinler okunuyor, kontrol ve gruplar Sistem Ayarları gibi; tema pencere açıkken değişince
  pencere de değişiyor.

## 0.4.1
Telefonun sayfası:
- [ ] Dikeyde küçük telefonda (iPhone SE ya da 667 pt), Claude sayfası açıkken: sığan son yere düşen yeni bir oturum
  (ör. 9 oturum varken onuncusu, sıkışık kartlar en alta yakın) gelirken de sonra da görünüyor; "+N oturum daha" yalnız
  gerçekten sığmayan kart varken çıkıyor ve doğru sayıyor.
- [ ] Mac'teki Safari'nin Web Inspector'ı telefonun sayfasında, Timelines kaydı: Claude sayfası açıkken (ve Başlat
  ekranında) JavaScript işi saniyede bire iniyor, panodayken her karede. Claude sayfasının saati dakikayla dönüyor;
  parmakla panoya dönünce halkalar, parıltı ve grafik hemen akıyor. Mac'te CPU alarmı çalarken (Plan 4C'deki `yes`
  komutu) Claude sayfasında kenar ışığı atmaya devam ediyor.
- [ ] "Başlat" sonrası Ayarlar → Eşleştirme → "Sıfırla…": telefonda "Eşleşmedi"; ekran Otomatik Kilit süresinde
  kararıyor (video durdu), kilit açılınca Başlat ya da rehber çıkmıyor; "⋯ → Kurulum rehberi"nin düğmesi "Kapat".
- [ ] İlk açılışta (rehber açıkken) eşleştirmeyi sıfırla: rehber kapanıyor, "Eşleşmedi" kartı görünüyor.
- [ ] Mac'teki Safari'den Web Inspector ile telefonun sayfasına bağlan, Ağ'da `view.js` için bir engelleme kuralı koy
  ve sayfayı yenile: "Mac'e ulaşılamıyor" kartı (Başlat ekranı yok), 5 sn sonra sayfa kendini yeniliyor; kural
  dururken 15 sn, 30 sn, sonra dakikada bir. Kural kalkınca bir sonraki yenilemede normal açılıyor ("Başlat" istiyor).
- [ ] Aynı denemede kural dururken PhoneBox'tan çık: sayfa yenilenmiyor, kartta kalıyor (tarayıcının hata sayfasına
  düşmüyor). Kuralı kaldırıp PhoneBox'ı açınca birkaç saniyede kendini yenileyip bağlanıyor.
- [ ] "Her zaman" kipinde telefon Wi-Fi'de (kablosuz), pano açıkken telefonu 2 dakika kilitle, sonra aç: ~1 sn içinde
  taze değerler geliyor; yeşil noktayla eski (donmuş) değerler görünmüyor.

Claude Code oturumları ve güncelleme:
- [ ] Etkileşimli bir oturumda (masaüstü uygulaması ve terminal) tur sürerken Esc: yaklaşık bir dakika sonra kart
  "Çalışıyor"dan "Sıra sende"ye geçiyor, sayfa geliyor.
- [ ] Bir tur API hatasıyla bitince (aşırı yük, kullanım sınırı) kart hemen "Sıra sende" (`StopFailure`).
- [ ] Paralel alt ajanlarla birinin Bash izni istemesi: diğerleri çalışırken kart "İzin istiyor" (turuncu, "1 seni
  bekliyor") kalıyor; o ajanın komutu bitince çalışıyora dönüyor.
- [ ] Uzun bir komuta izin ver (`sleep 30`, `make test`), masaüstü uygulamasında ve terminalde: 1–2 sn içinde kart
  "Komut çalıştırıyor", sayfa 3 sn sonra panoya dönüyor.
- [ ] Oturum beklerken ("Sıra sende", "Soru soruyor") PhoneBox'ı güncelle (ya da çıkıp 10 dk içinde aç): bekleyen
  oturumlar aynı sürelerle hemen yeniden görünüyor.
- [ ] Özellik açıkken 0.4.0'dan 0.4.1'e ilk açılışta `~/.claude/settings.json`'a `StopFailure` ve `SubagentStop`
  ekleniyor, Notification eşleyicisi `permission_prompt|idle_prompt` oluyor; Claude Code uyarı göstermiyor.
- [ ] Başarısız güncelleme (ör. indirme sırasında Wi-Fi kapalı): uyarı çıkıyor, menü ve ayarlar yine "PhoneBox x.y.z
  sürümünü yükle…" / "Yükle…" sunuyor.

Mac (ağ ve ölçümler):
- [ ] "Her zaman" kipinde A telefonu Wi-Fi'de, B telefonunu tak: A bir kez yeniden bağlanıyor (~3 sn), ~8 sn'de yeniden
  değil.
- [ ] PhoneBox çalışırken Mac'in adını değiştir (Sistem Ayarları → Genel → Paylaşma): sonra bağlanan telefonun "⋯"
  menüsünde yeni ad.
- [ ] PhoneBox açılmadan 4747'yi tut (`nc -l 4747`): menü portun kullanımda olduğunu söylüyor; "Değiştir…" ile 4747
  "kullanımda" uyarısı veriyor; `nc` durunca 30 sn içinde 4747 dinleniyor ve kayıtlı bağlantı/Ana Ekran simgesi
  bağlanıyor. Yeniden tut, bırak ve "Değiştir…" ile 4747: port hemen alınıyor, QR penceresi açılmıyor.
- [ ] Sayfa `http://<LocalHostName>.local:<port>/` ve `http://<IP>:<port>/` ile açılıyor;
  `curl -H 'Host: evil.example' http://<mac>.local:<port>/` 403 alıyor.
- [ ] Yük altında kablodaki telefon: başka bir cihazdan 20+ boşta bağlantı aç
  (`for i in $(seq 20); do nc <mac-ip> 4747 & done`); kablodaki telefon yine bağlanıp veri alıyor.
- [ ] Xcode kapalıyken Simulator'ü aç (`open -a Simulator`): uygulama listesinde "Simulator" görünüyor ve kapatılabiliyor.
- [ ] Mac'te `swift build`/`make` sürerken derleyici işlemleri (`swift-frontend`, `clang`) gerçek yüzdelerle en üst CPU
  satırlarında.
- [ ] Pano açıkken Mac uyuyup uyanınca, yeniden bağlandıktan sonra grafikte düzenli boşluklar yok.

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

### 2026-11-26 — Plan 4C (dal `plan4c`, 39338f1), MacBook Pro M4 / macOS 27.2, iPhone iOS 27.0.1

Mac'te (tarayıcı paneli, sahte veriyle deneme sayfası):
- Geçti: 734×372, 667×375, 393×759, 375×647 ölçülerinde taşan ya da kesilen öğe yok; konsolda JavaScript hatası yok.
- Geçti: CPU %100 + 101 °C + 40 W senaryosunda renkler kızardı; 3 sn sonra kenar ışığı, atan halka ve kutucuklar,
  "▲ Güç 40,0 W · CPU %100". Değerler düşünce alarm 3 sn sonra sustu.
- Geçti: veri kesilince sayfa soluklaştı, alarm ve kenar ışığı söndü, saatin altına tarih döndü.
- Geçti: `PHONEBOX_LIVE=1 make test FILTER="PhoneBatteryLiveTests"`: kabloda takılı iPhone'un pili 2,35 sn'de okundu.

iPhone ile (Chrome, ana ekran simgesi; Mac "Her zaman" modunda):
- Geçti (kullanıcı bildirdi): saat, tarih ve hareketler düzgün.
- Bulundu ve düzeltildi: Wi-Fi'de grafik atlayarak ilerliyordu. Grafik snapshot'ın geliş anına göre kayıyordu;
  iPhone Wi-Fi'de veriyi toplu teslim ettiği için çizgi durup geri sıçrıyordu. 79f64a3 ve 39338f1 ile grafik Mac'in
  saatine göre, bir saniye artı geliş düzensizliği kadar geriden ve yumuşatılmış bir saatle çiziliyor. Sonra Wi-Fi'de
  düzgün aktı.
- Geçti: Mac'e 20 sn tam CPU yükü (`yes` ×10): CPU halkası kızardı, alarm çaldı, yük bitince sustu.
- Geçti: veri kablosu takılınca sayfa USB'ye (`en8`) geçti; sağ üstte telefonun pili Ayarlar'daki yüzdeyle aynı;
  telefon kilitlenip açılınca simge geri geldi.
- Not: Mac'in güç değeri (`AppleSmartBattery` `SystemLoad`) ~20 sn'de bir güncelleniyor (20 sn'lik yükte 8,3 W'ta
  kaldı, sonunda 12,5 W). M4'ün 35 W sınırı bu kısa testle ölçülemedi; daha uzun bir yükle bakılacak.
- Denenmedi: Hareketi Azalt; SE ve Pro Max'te telefonda görünüm; telefon kilitliyken pilin okunması (sayfa kilitliyken
  görünmediği ve PhoneBox o sırada okumadığı için gerekmiyor).


### 2026-11-26 — Plan 4B (dal `plan4b`, 2bea97a), MacBook Pro M4 / macOS 27.2, iPhone iOS 27.0.1

Mac'te (deneme sayfası, komutlara `ack` veren sahte Mac; dalın `make app` paketi):
- Geçti: şerit doğru komutları gönderdi (`media playPause`, `mute {on: true}`, kaydırıcıda `volume` 0,49 → 0,79);
  oynat ve sessiz simgeleri değişti.
- Geçti: uygulama satırı paneli açtı; Zorla kapat önce sordu, sonra `quitApp {force: true}` ve yeşil bildirim;
  kapatılamayan satır (Finder) yalnız "Bu süreç buradan kapatılamaz." dedi.
- Geçti: Uyut önce sordu; Vazgeç hiçbir şey göndermedi; bilerek basılan Uyut `sleep`'i gönderdi, bildirim tek satır.
- Geçti: sahte Mac `unsupported` dönünce kırmızı "Bu çıkışta ses kontrolü yok"; komutlar kapalıyken şerit soluk,
  dokununca "Komutlar sadece kabloyla çalışır", hiçbir komut gitmedi.
- Geçti (son incelemenin bulgusu, düzeltildi): yatayda "⋯ → Uyut" satırına çift dokunuş artık onayın düğmesine
  ulaşmıyor (hiçbir komut gitmedi); satıra 120 ms arayla iki dokunuş panelin "Kapat"ına ulaşmıyor; menü kapandıktan
  100 ms sonra şerite dokunuş yok sayılıyor, 500 ms sonra çalışıyor; kapalı panel ve onay `inert`.
- Geçti: `PHONEBOX_LIVE=1 make test FILTER="SystemAudioLiveTests|CommandRunnerLiveTests"` (ses okunup aynen yazıldı;
  Satranç açılıp `quitApp` ile kapandı; Finder `app-changed`).

iPhone ile (ana ekran simgesi, kablo; iPhone Yansıtma üzerinden):
- Geçti: şerit yeni sayfada görünüyor; şarkı çalmazken uygulama listesi boş satır bırakmadan yer kaplıyor.
- Geçti: sessiz düğmesi Mac'i sessize aldı ve geri açtı (`output muted` true → false), simge değişti.
- Geçti: kaydırıcıya dokunuş Mac'in sesini 6'dan 16'ya, sürükleme 8'e getirdi; düğme geri sıçramadı.
- Geçti: "⋯ → Uyut" onayı açtı, Vazgeç kapattı; Mac uyumadı. Uygulama satırı (node) paneli açtı, "Bu süreç buradan
  kapatılamaz.", Vazgeç kapattı.
- Denenmedi: medya düğmeleri (gece Mac'te ses çıkmasın diye; deneme sayfasında doğru komutu gönderiyor); Satranç'ı
  telefondan kapatma (az CPU kullandığı için listenin ilk satırlarında görünmedi; Mac tarafı canlı testte geçti);
  Wi-Fi'de soluk şerit (kablo çıkarılamadı; deneme sayfasında geçti). Kilitle ve Ekranı kapat en sonda denenecek,
  Uyut denenmez.
- Not: telefondaki açık sayfa yeni sürümün dosyalarını kendiliğinden almaz; uygulama değiştiriciden kapatıp ana ekran
  simgesinden yeniden açmak gerekti (Plan 5'te sayfa, PhoneBox'ın web dosyaları değişince kendini yeniler).

### 2026-11-26 — Plan 5 (main 4ea7032), MacBook Pro M4 / macOS 27.2

Mac'te:
- Geçti: `make app` simgeli paketi kurdu (`AppIcon.icns`, `LICENSE`, `THIRD_PARTY_NOTICES.md` içinde), `codesign --verify
  --strict` geçti; simge 1024, 64 ve 32 pikselde gözle kontrol edildi (küçük boylarda gölge ölçeklendi, a4af370).
- Geçti: `make dist` zip'i yaptı ve imzasını doğruladı; `PHONEBOX_ZIP=… PHONEBOX_DEST=<geçici> PHONEBOX_NO_OPEN=1
  ./install.sh` kurdu (geride ara kopya kalmadı), `--uninstall` kaldırdı; başka klasörden çalışan PhoneBox açık kaldı.
- Geçti: güncelleme denetimi açılıştan ~15 sn sonra çalıştı. `UpdateFeedURL` yerel bir v0.2.0 yanıtına bakınca kayıtta
  "Update available: 0.2.0"; v0.1.0 yanıtında hiçbir şey (güncel); depo henüz yokken GitHub'dan "Update check failed
  (HTTP 404)". Deneme anahtarı sonra silindi.
- Geçti: `PHONEBOX_LIVE=1 make test FILTER="PhoneBatteryLiveTests"` değişen pil okuyucusuyla (planlama sırasında).
- Denenmedi: menüdeki Port…, Güncellemeleri denetle… ve Girişte başlat'ın pencereleri (Mac'in ekranı gece kendiliğinden
  kilitlendi; menüye tıklamak ekran ister). Yeni sayfanın PhoneBox güncellenince kendini yenilemesi telefonda
  denenemedi (iPhone Yansıtma kilitli Mac'te çalışmıyor); mantığı JavaScriptCore testinde, `ready`'deki ad hub
  testinde doğrulandı.

### 2026-11-26 — 0.1.1 güncellemesi (yayın v0.1.1), MacBook Pro M4 / macOS 27.2, iPhone iOS 27

- Geçti: menüden "Güncellemeleri denetle…" 0.1.1'i buldu, "Yükle" kurulum betiğini çalıştırdı, PhoneBox kapanıp
  `/Applications`'tan 0.1.1 olarak açıldı; telefon 2 sn sonra yeniden bağlandı, sayfa kendini yenileyip "Başlat"ı
  istedi (kullanıcı). Girişte başlat `/Applications/PhoneBox.app`'i göstermeye devam etti.
- Geçti: kurulum betiği deneme klasörüne (`/tmp` kısayolu ve sondaki `/` ile) kurarken yalnızca oradan çalışan sahte bir
  PhoneBox sürecini kapattı, `/Applications`'takine dokunmadı.

### 2026-11-26 — 0.2.0 adayı (main 79f5c16), MacBook Pro M4 / macOS 27.2, iPhone iOS 27

- Geçti: "Wi-Fi'den Kilit ve Müzik" açıldı (ayar kaydedildi); telefon kablodan çıkınca Wi-Fi'den (en0) bağlandı ve
  müzik komutları Mac'te çalıştı (kayıtta "Running media"); kullanıcı ses, sessiz, Ekranı kapat, Uyut ve uygulama
  kapatmanın soluk kaldığını ve hepsinin beklendiği gibi çalıştığını söyledi.
- Geçti: Wi-Fi'den Kilitle (14:31, kayıtta "Running lock", telefon en0'da). Görülmedi: 30 sn içinde ikinci Kilitle.
- Bulunan ve düzeltilen: Ana Ekran uygulamasında telefon yan çevrilince sayfa ekranın altına uzanmıyordu (altta dikey
  durum çubuğu kadar boş şerit, Pro Max). `screen.js` tam ekran katmanlara ekranın yüksekliğini verdi (19c7bc3);
  telefon birkaç kez çevrildikten sonra sayfa ekranı dolduruyor (kullanıcı).
- Bulunan ve düzeltilen: adayı `PHONEBOX_ZIP=… ./install.sh` ile kurunca `open` bu ayarı uygulamaya geçirdi; menüden
  0.2.0'a güncelleme kurulum betiğini aynı ayarla çalıştırdı ve "Güncelleme yüklenemedi" dedi (betik göreli zip yolunu
  bulamadı). `PHONEBOX_VERSION=…` ile kuran bir kullanıcı da her güncellemede o sürümü yeniden kurardı. install.sh
  uygulamayı `PHONEBOX_*` olmadan açıyor, uygulama da kurulum betiğine bunları geçirmiyor (0.2.1). Mac, GitHub'daki
  kurulum komutuyla 0.2.0'a geçirildi.

### 2026-11-26 — 0.3.0 adayı (dal `v030`, cb85409), MacBook Pro M4 / macOS 27.2, iPhone (Wi-Fi, "Her zaman")

- Geçti: aday `/Applications`'a kuruldu (temiz ortam, `PHONEBOX_*` yok), imza geçerli, 4747 dinleniyor, telefon `en0`
  üzerinden yeniden bağlandı.
- Geçti: menüden "Claude Code Oturumları" → uyarı → "Aç": `~/.claude/settings.json`'da on olayın her birinde bir
  PhoneBox grubu (`async`, `timeout` 10); hook dışı anahtarlar aynı; `settings.json.phonebox-backup` hook'suz eski
  dosya; `claude.sock` 0600.
- Geçti: yeni bir `claude -p` oturumunun hata ayıklama kaydında `SessionStart` hook'u PhoneBox yardımcısını arka
  plana aldı (15 ms), yanıt üretmedi.
- Geçti: özellik açılmadan önce başlamış masaüstü oturumu yeni hook'ları yeniden başlamadan aldı; seçenekli soru
  sorulunca telefonda Claude sayfası kendiliğinden açıldı, bu oturum turuncu "Soru soruyor" kartıyla göründü.
- Geçti: soru Mac'te cevaplanınca kart çalışıyora döndü, sayfa birkaç saniye sonra panoya döndü.
- Denenmedi: izin kartı (oturum otomatik kipteydi), kaydırarak dönüp yeniden açılmama, oturum kapanınca kartın
  gitmesi, kapatınca hook'ların silinmesi, kaldırıcı, iki kopya.
