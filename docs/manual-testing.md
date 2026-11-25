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
