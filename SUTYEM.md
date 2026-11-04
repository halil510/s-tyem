# SÜTYEM — Proje Defteri (nerede kaldık?)

> Bu dosya her çalışma oturumunun sonunda güncellenir. Yeni oturuma
> başlarken **önce bunu oku**, "Sıradaki işler" bölümünden devam et.

## Proje özeti

- **Ne:** Süt toplama + yem satışı yapan işletme için cari (müşteri) takip uygulaması.
- **Teknoloji:** Flutter 3.47 / Dart 3.13, Riverpod, sqflite (SQLite), go_router.
- **Paket adı:** `sutyem_pro`
- **İş mantığı (çok önemli):** Normal veresiyenin TERSİ.
  `bakiye = (süt değeri + tahsilat) − (yem değeri + ödeme)`
  - bakiye > 0 → işletme cariye borçlu (cari **alacaklı**)
  - bakiye < 0 → cari işletmeye borçlu (cari **borçlu**)
  - Süt/yem tutarı, kaydın **GÜNÜNDE geçerli cari fiyatıyla** canlı hesaplanır
    (`cari_fiyatlar.ay` = `'yyyy-MM'` ay başından ya da `'yyyy-MM-dd'` o günden itibaren;
    kaydın tarihine kadar başlamış EN SON fiyat — `CariFiyatLookup.fiyatIcin(cariId, s.tarih)`.
    Ay anahtarıyla değil, KAYDIN TARİHİYLE sorgula!). Örn. 25 ₺, 4 Kasım'dan itibaren 27 ₺ →
    1–3 Kasım 25, 4 Kasım ve sonrası 27. Yem fiyatı aylık girilir, aynı ayın gün satırlarına yayılır.
  - Bu hesabın tek kaynağı: `lib/features/cari_hesap/providers/cari_hesap_providers.dart`
    (`sutTutari`, `yemTutari`, `cariEkstreProvider`, `tumKalanBorclarProvider`).

## Önemli kurallar (bozma!)

1. **Bir cari için bir günde TEK süt satırı** vardır (sabah + akşam aynı satırda).
   Veritabanında `uq_sutler_cari_tarih` UNIQUE index (migration v8) ile korunur.
   Süt yazmak için daima `SutRepository.gunlukKaydet` / `topluGunlukKaydet`.
2. **Sayı girişi** daima `sayiCoz()` ile (`lib/utils/sayi_format.dart`).
   Geçersiz giriş `null` döner → kullanıcıya hata göster, **asla 0 kaydetme**.
3. **Para** kuruşa yuvarlanır: `kurusaYuvarla()`.
4. Süt / yem / ödeme / fiyat / cari değiştiren her işlemden sonra
   `ref.veriDegisti()` (Riverpod ekran) ya da `veriDegistiBildir(context)`
   (düz StatefulWidget) çağır → bakiyeler, ekstre ve ana sayfa yenilenir.
5. **Yedek** alma/yükleme yalnızca `YedekServisi` üzerinden
   (`lib/data/yedek/yedek_servisi.dart`). `INSERT OR REPLACE` KULLANMA:
   `ON DELETE CASCADE` yüzünden carinin ödemelerini siler.
6. Şema değişikliği = yeni migration dosyası (`lib/core/database/migrations/`),
   `MigrationRunner._all` listesine ekle, test yaz. Yayınlanmış migration değiştirilmez.
7. Müşteri verisi içeren `.db` / `.zip` dosyaları **asla** git'e girmez (`.gitignore`).
8. **Supabase SQL eşliği (genel kural):** her yeni tablo/sütun/index (yeni migration)
   AYNI commit'te `supabase/supabase_sema.sql` dosyasına da eklenir; başlıktaki
   "yerel şema sürümü" ve sondaki DEĞİŞİKLİK GEÇMİŞİ güncellenir.
   `test/data/supabase_sema_test.dart` eksik tablo/sütunu yakalar.
9. **Kapalı dönem kilidi veritabanındadır** (migration v9 tetikleyicileri). Yeni bir tarihli
   tablo eklenirse ona da tetikleyici yazılmalı. Repository yazmaları `donemKilidiyle` / `_yaz`
   ile sarılır; ekranlar `DonemKapaliHatasi` mesajını gösterir.
10. **Ekranlar ve provider'lar SQL yazmaz.** Veriye yalnızca `lib/data/repositories/` üzerinden
   erişilir (istisna: kendi tablolarının sahibi `DonemServisi`). `DBHelper` kaldırıldı — geri getirme.
   Yeni sorgu = ilgili repository'ye metot. Tarih aralığı sorgusu yazınca indeks kullandığını kontrol et.
11. **Sekmeler (`AnaEkran`, IndexedStack) bellekte kalır.** Sekme ekranları veriyi ya
    `veriSurumuProvider` izleyen bir provider'dan almalı (ör. `aktifCarilerProvider`) ya da
    `ref.listen(veriSurumuProvider, …)` ile yenilenmeli. `build` içinde `FutureBuilder(future: repo…)` YASAK.
12. **Arama** her yerde `aramaEslesir` (`lib/utils/turkce.dart`) — `toLowerCase()` Türkçe İ/ı'yı bozar.
13. **Her dağıtılan APK'da `pubspec.yaml` sürümünün `+N` kısmı artırılır** (versionCode). Telefondaki
    uygulamayla AYNI imza anahtarı kullanılır; yoksa "güncelle" yerine "yüklenmedi" çıkar ve veri kaybı olur.
    Bluetooth izni yalnız `PermissionHelper.bluetoothIzinleri()` ile istenir.

## Testler

```bash
flutter test          # 176 test — hepsi geçmeli
flutter analyze       # 0 error olmalı (eski kodda info/warning'ler var)
```

| Dosya | Kapsam |
|---|---|
| `test/utils/sayi_format_test.dart` | Sayı ayrıştırma, kuruş yuvarlama |
| `test/data/migration_test.dart` | v7→v8 geçişi: mükerrer birleştirme, tarih normalizasyonu, UNIQUE |
| `test/data/sut_repository_test.dart` | Günlük upsert, doğrulama, toplu kayıt rollback, denetim izi |
| `test/data/yedek_servisi_test.dart` | Yedek tamlığı, REPLACE regresyonu, ya-hep-ya-hiç geri yükleme |
| `test/data/cari_repository_test.dart` | Pasife alma, silme etkisi, alan koruma |
| `test/features/cari_hesap_test.dart` | Bakiye/ekstre hesabı, fiyat devralma, önbellek yenileme |
| `test/widget_test.dart` | Gerçek ekranlar: Hızlı Süt Girişi, Süt Ekle, terazi, ödeme formu |
| `test/data/supabase_sema_test.dart` | Her SQLite tablo/sütunu Supabase SQL dosyasında var mı |
| `test/data/app_database_test.dart` | Gerçek dosyada açılış: migration hatası veriyi silmez, bozuk dosya kenara alınır |
| `test/features/aylik_ozet_test.dart` | Aylık özet: cari fiyatıyla, ekstreyle aynı, WhatsApp mesajı |
| `test/utils/sifre_ozeti_test.dart` | PBKDF2 test vektörleri, yanlış şifre/kilitlenme, kaynakta açık şifre yok |
| `test/services/toplu_mesaj_test.dart` | Telefon biçimi, toplu gönderim sayımı, haftalık süt toplamı, yem dökümü, rapor diyaloğu |
| `test/features/donem_test.dart` | Hakediş hesabı, kapatma kilidi (süt/yem/ödeme/fiyat/cari silme), fiyat sabitleme, yeniden açma, yedek |
| `test/donem_ekrani_test.dart` | Dönem ekranı: kapat → kilitli → gerekçeyle yeniden aç |
| `test/features/fis_test.dart` | Fiş düzeni (58/80 mm), ESC/POS baytları, Türkçe harf çevirisi/CP857, yazıcı kanalı, fiş verisi |
| `test/features/dashboard_test.dart` | Gelmeyen üreticiler kuralı, bugün sabah/akşam/dün, buzağı yemi dilimi, dönem hatırlatması |
| `test/dashboard_ekrani_test.dart` | Özet ekranı 360 px genişlikte taşmadan çizilir |
| `test/data/veri_yonetimi_test.dart` | Veri yönetimi repo (sayılar, temizlik + dönem kilidi, .db doğrulama), toplu fiyat (ya hep ya hiç), tarih indeksleri sorgu planında |
| `test/features/cari_excel_test.dart` | Excel'den cari: rapor biçimi, ayrı Ad/Soyad/Telefon, "Cari Kodu" tuzağı, başlıksız, tekrar, Türkçe İ/ı, ekran akışı |
| `test/akis_test.dart` | UYGULAMA AKIŞI (AnaEkran): Süt sekmesinde girilen süt → Cariler listesi + detay; yeni/içe alınan cari tüm açık sekmelere düşer; Türkçe arama; Ödemelerde pasif alacaklı |
| `test/ekran_tarama_test.dart` | TÜM EKRANLAR 360 px'de gerçekçi veriyle açılır (taşma/hata yok); alt panel yazıları; boş veritabanı |
| `test/features/yazici_fiyat_menu_test.dart` | Wi-Fi (TCP) fiş yazdırma, ulaşılamayan yazıcı, kayıtlı yazıcı kilidi, tümüne aynı süt fiyatı, ⋮ menüsü |
| `test/data/fiyat_toplu_test.dart` | Toplu ay fiyatı (tek sorgu) = eski cari-başına yöntem |
| `test/features/gunluk_fiyat_test.dart` | Ay ortası fiyat değişikliği (o günden itibaren), sonraki aya devir, kapalı dönem v11 kilidi, yem fiyatı yayma |

Test altyapısı: `test/helpers/test_db.dart` (bellek-içi SQLite, `sqflite_common_ffi`).

---

## Oturum günlüğü

### 2026-11-04 — Derin analiz + süt/cari güvenliği

**Bulunan ve düzeltilen hatalar**

| # | Önem | Sorun | Çözüm |
|---|---|---|---|
| 1 | KRİTİK | "Süt Ekle" her kaydette yeni satır açıyordu → aynı güne mükerrer kayıt. Hızlı Giriş sadece ilkini gösterip güncelliyor, diğerleri görünmeden bakiyeyi şişiriyordu. | Günlük upsert + migration v8 (mükerrerleri **toplayarak** birleştirir, bakiye değişmez; silinenler `islem_gecmisi`'ne yazılır) + UNIQUE index. |
| 2 | KRİTİK | Terazi bağlıyken her okuma **sabah alanının üzerine** yazıyordu (akşam tartılırken sabah değeri değişiyordu). | Otomatik yazma kaldırıldı; yalnızca "Sabaha/Akşama Uygula" butonları. |
| 3 | KRİTİK | JSON yedek geri yükleme `INSERT OR REPLACE` → CASCADE ile carinin **tüm ödeme/tahsilatlarını siliyordu** (testle kanıtlandı). Bluetooth yedeği ödemeleri/fiyatları hiç içermiyordu; alıcı cihazda hepsi siliniyordu. | `YedekServisi`: tüm tablolar, tek transaction, REPLACE yok, hata → hiçbir değişiklik yok. Eski biçimli yedekle "tamamen değiştir" reddedilir. |
| 4 | YÜKSEK | Hatalı yazım ("12,5x", "2O") sessizce **0 kg** kaydediliyordu. | `sayiCoz()` + tüm giriş ekranlarında hata gösterimi. |
| 5 | YÜKSEK | Süt/yem/fiyat girildikten sonra Ödemeler sekmesi, ekstre ve ana sayfa **eski bakiyeyi** gösteriyordu (önbellek yenilenmiyordu). | `veriSurumuProvider` + her yazmada `veriDegisti()`. |
| 6 | YÜKSEK | Hızlı Süt Girişi carileri tek tek kaydediyordu; ortada hata olursa yarım kalıyordu. | `topluGunlukKaydet`: tek transaction (ya hep ya hiç). |
| 7 | YÜKSEK | Cari silme, uyarısız şekilde tüm süt/yem/ödeme geçmişini siliyordu (CASCADE). | Kayıt sayılarını gösteren uyarı + **Pasife Al** önerisi + ikinci onay; "Pasif Cariler" listesinden geri açma. |
| 8 | ORTA | Cari düzenleme carinin **notunu** siliyordu. | Formda olmayan alanlar korunuyor. |
| 9 | ORTA | Detay ekranında tarih aralığı seçici çöküyordu (ay sonu > bugün). | `lastDate` düzeltildi. |
| 10 | ORTA | Yanlış bir `.db` seçilirse canlı veritabanının üzerine yazılıyordu. | Geri yüklemeden önce tablo + bütünlük kontrolü. |
| 11 | ORTA | Bluetooth yedeği 10.000 kayıt üstünde hata veriyordu; olmayan `alis_satis` tablosunu sorguluyordu. | Kaldırıldı; boyut sınırı 25 MB. |
| 12 | ORTA | Kayan nokta: `12.345 ₺` → `12.34`; ekstre satır toplamı ≠ genel toplam olabiliyordu. | `kurusaYuvarla()`, satır bazında yuvarlama. |
| 13 | ORTA | `assets/db/sut_yem.db` (gerçek müşteri isimleri) her APK'ya gömülüyordu, kodda kullanılmıyordu. | `pubspec.yaml`'dan çıkarıldı. |
| 14 | DÜŞÜK | Süt girişinde gelecek tarih seçilebiliyordu; tarihler saat bilgisiyle kaydedilince ay sonu sorgularda kayboluyordu. | Son tarih = bugün; migration v8 tarihleri normalize eder. |

**Yeni özellikler**
- Ödeme/Tahsilat formunda **tarih** ve **açıklama** (geçmişe dönük kayıt).
- Süt Ekle ekranı o günkü mevcut kaydı gösterir, butonu "GÜNCELLE" olur.
- Hızlı Süt Girişi: arama, günlük toplam kg, hatalı satır vurgusu, boşaltılan kaydın silinmesi için onay, kaydedilmemiş değişiklik uyarısı.
- Süt ve ödeme işlemleri için **denetim izi** (`islem_gecmisi`: ekle/güncelle/sil, önceki-yeni değer).

**Android derleme**
- Uygulama bu makinedeki Flutter 3.47 ile hiç derlenmiyordu (Gradle 8.12, AGP 8.9.1,
  Kotlin 2.1.0 → minimum altında). Yükseltildi: Gradle **8.14**, AGP **8.11.1**,
  Kotlin **2.2.20**. `flutter build apk --debug` başarılı.

**Temizlik**
- Derlenmeyen `lib/bluetooth/main.dart` ve kullanılmayan, yanlış hesaplı
  `cari_odemeler_ekrani.dart` → `_arsiv/` klasörüne taşındı (git'e girmez).
- Bozuk `widget_test.dart` gerçek ekran testleriyle değiştirildi.
- `flutter_lints` + `sqflite_common_ffi` dev bağımlılıkları eklendi.

### 2026-11-04 (2) — GitHub + Supabase şeması + profesyonelleşme planı

- GitHub'a gönderildi: `halil510/s-tyem`, dal `main`.
- `supabase/supabase_sema.sql` yazıldı (yerel v8 karşılığı; RLS, `(kullanici_id, id)` anahtarları).
  Postgres bu makinede yok → SQL henüz gerçek Supabase'de çalıştırılmadı.
- `test/data/supabase_sema_test.dart`: SQLite ↔ SQL dosyası eşlik testi. 57 test geçti.
- Altyapı incelemesi: migration sistemi (transaction + user_version) doğru.
  **Bulunan risk:** `AppDatabase._open` her hatada `_recoverCorrupted` çağırıyor →
  bir migration hata verirse canlı veritabanı yedeklenip SİLİNİYOR, uygulama boş açılıyor
  (yedek dosyası `sut_yem_backup_*.db`, kullanıcıya söylenmiyor). Plan madde A1.

### 2026-11-04 (3) — A1: veritabanı açılışı güvenli hale getirildi

- `AppDatabase` yeniden yazıldı (`lib/core/database/app_database.dart`):
  - Migration hatası → `VeritabaniGuncellemeHatasi`; dosyaya dokunulmaz, veri yerinde.
  - Kilit / disk dolu / izin hatası → `VeritabaniAcilisHatasi`; dosyaya dokunulmaz.
  - Yalnız gerçek bozulma (SQLite "malformed"/"not a database", `PRAGMA quick_check` ≠ ok)
    → dosya **silinmez**, `sut_yem_bozuk_<zaman>.db` adıyla kenara alınır (-wal/-shm dahil),
    yeni boş DB kurulur, `kurtarmaYedegi` dolar. Kenara alma başarısızsa yeni DB kurulmaz.
  - Aynı anda gelen `database` çağrıları tek açılışı paylaşır; hata sonrası yeniden denenebilir.
  - Test için `AppDatabase.test(factory:, klasor:, migrationRunner:)`;
    `MigrationRunner(migrations: [...])` ile hatalı migration enjekte edilebilir.
- Açılış ekranı: hata türüne göre anlaşılır Türkçe mesaj + "Tekrar Dene";
  bozuk dosya kenara alındıysa "Veritabanı Bozuk Bulundu" diyaloğu (eski dosya yolu, yedekten geri yükle önerisi).
- `HataSayfasi`: `baslik`, `aciklama`, `onTekrarDene` parametreleri.
- `.db` dosyasından geri yüklemede eski `-wal/-shm/-journal` dosyaları temizleniyor.
- Supabase SQL: şema değişmedi, güncelleme gerekmedi.
- Testler: 63/63 geçti; `flutter analyze` 0 error.

### 2026-11-04 (4) — A2 + A3: tek terazi ekranı, Aylık Rapor düzeltmesi

- **A2:** `lib/ekranlar/terazi_baglanti_ekrani.dart` hiçbir yerden çağrılmıyordu →
  `_arsiv/terazi_baglanti_ekrani_eski.dart.txt`. Menü ve Süt ekranı `AppRoutes.terazi` → Pro ekran.
- **A3 — KRİTİK HATA bulundu ve düzeltildi:** "Aylık Hesaplama & Rapor" ekranı carinin
  gerçek fiyatını kullanmıyordu; **sabit 12 ₺ süt / 8 ₺ yem** (tüm yem türlerine tek fiyat)
  ile hesaplayıp bu tutarları **müşteriye WhatsApp'tan** ve Excel'e gönderiyordu.
  "Toplam" sütunu da süt (alacak) ile yemi (borç) topluyordu.
  - Yeni `aylikOzetProvider(ay)` + `AylikCariOzet` (`cari_hesap_providers.dart`):
    ekstreyle aynı `sutTutari`/`yemTutari`, o ayın fiyatı (önceki aydan devralma dahil),
    ödeme/tahsilat, ay neti, genel bakiye, fiyat-eksik bayrağı.
  - Ekran yeniden yazıldı: elle fiyat kutusu yok; fiyat eksik uyarısı; gelecek aya geçilmez;
    pasif ama bakiyeli cariler de listede; "Tümüne WhatsApp" önce onay ister.
  - WhatsApp mesajı: yem için uydurma birim fiyat yok (`kg = tutar`), ödenen/tahsil edilen satırları.
  - Excel: Süt kg, Süt fiyatı, Süt tutarı, Yem kg, Yem tutarı, Ödenen, Tahsil edilen, Bu ay net, Genel bakiye.
- `fiyatlar` tablosunu kullanan ekran → "Piyasa Fiyat Notları" + "bu fiyatlar hesaplara girmez" bandı.
  (Veri silinmedi; tablo yedekte ve Supabase şemasında duruyor.)
- Supabase SQL: şema değişmedi.
- Testler: 68/68 geçti; `flutter analyze` 0 error.

### 2026-11-04 (5) — A4: master şifre koddan çıkarıldı

- **Bulunan ek güvenlik açığı:** Aktivasyon ekranında "Kullanıcı Listesini Gör" düğmesi
  10 şifreyi (master şifre dahil) **uygulama içinde gösteriyor ve kopyalatıyordu** —
  telefonu eline alan herkes aktive edebiliyordu. Liste ve düğme kaldırıldı.
  (Listedeki diğer 9 şifre zaten hiçbir yerde kabul edilmiyordu.)
- `lib/utils/sifre_ozeti.dart`: PBKDF2-HMAC-SHA256 (120.000 tur) + sabit zamanlı karşılaştırma.
- `AppLocker`: `_defaultMasterPassword` ve `_userPasswords` kaldırıldı; `_masterTuz` + `_masterOzet`.
  Doğrulama `Isolate.run` ile arka planda (PC'de ~0,6 sn; telefonda arayüz donmasın).
  **Mevcut şifre aynen çalışıyor** (özeti eski değerden üretildi ve doğrulandı) → kilitlenme riski yok.
  `getUsedPassword` artık şifrenin ilk 5 harfini göstermiyor ("Master şifre" / "Özel şifre").
- `tool/master_sifre_ozeti.dart`: yeni şifre için tuz+özet üretir (şifre hiçbir yere yazılmaz).
- Proje genelinde eski şifrelerin hiçbir izlenen dosyada kalmadığı denetlendi.
- Supabase SQL: şema değişmedi.
- Testler: 74/74 geçti; `flutter analyze` 0 error.

### 2026-11-04 (6) — A5: büyük ekranlar bölündü + toplu WhatsApp hataları

- Yeni dosyalar:
  - `lib/ekranlar/cari/cari_duzenle.dart` (CariDuzenle)
  - `lib/ekranlar/cari/cari_dialoglari.dart` — rapor tarih aralığı (eski iki ÖZDEŞ diyalog teke indi),
    WhatsApp seçenekleri, özel mesaj, ödeme bildirimi. Hepsi sonucu `Navigator.pop` ile döndürür.
  - `lib/services/toplu_mesaj_servisi.dart` — `TopluMesajServisi`, `sutRaporuToplamlari`,
    `sutRaporuBaslangici`, `yemRaporuDetayi` (UI'sız, test edilebilir).
  - `lib/ekranlar/detay/kayit_duzenle_dialoglari.dart` (SutDuzenleDialog, YemDuzenleDialog).
  - `WhatsAppService.telefonNormalize` artık tek telefon biçimlendirici (3 kopya vardı).
- **Düzeltilen hatalar (cari listesi):**
  1. Excel rapor diyaloğunda "Oluştur" → diyalog kapanıyor, ardından `Navigator.pop` İKİNCİ kez
     çağrılıp alttaki sayfayı kapatıyordu.
  2. Yem raporu WhatsApp'ı temizlenmemiş telefona gidiyordu; gönderim başarısız olsa da
     "gönderildi" sayılıyordu; B. Başlangıç / B. Büyütme yemleri mesajda yoktu.
  3. Süt raporu "haftalık" toplamı yalnız ayın 1'inden itibaren sayıyordu (ayın 2'sinde 2 gün).
  4. Hata metni 50 karakterden kısaysa `substring(0, 50)` çöküp tüm gönderim döngüsünü kesiyordu.
  5. Ödeme bildirimi tutarı "1.250,50" kabul etmiyordu (`sayiCoz`).
  6. Diyalog `TextEditingController`'ları hiç dispose edilmiyordu.
- Supabase SQL: şema değişmedi.
- Testler: 80/80 geçti; `flutter analyze` 0 error.

### 2026-11-04 (7) — B4: Dönem kapanışı & hakediş

Kullanıcı kararı: **aylık dönem**; kapanan dönem **kilitli, gerekçeyle yeniden açılabilir**.

- **Migration v9** (`migration_v9_donemler.dart`): `donemler` (ay, durum, kapanis_tarihi,
  acilis_sayisi, aciklama), `donem_hakedisleri` (dondurulmuş bordro).
  Tetikleyiciler: kapalı aya ait `sutler` / `yemler` / `cari_odemeler` / `cari_fiyatlar`
  satırı eklenemez/değişemez/silinemez → `RAISE(ABORT,'DONEM_KAPALI')`. Kapalı dönemin
  bordrosu silinemez. CASCADE silmelerde de çalışır (kapalı dönemde kaydı olan cari silinemez).
- `lib/data/repositories/donem_kilidi.dart`: `DonemKapaliHatasi`, `donemKilidiyle`.
  Süt/ödeme repoları `_yaz` (transaction + kilit çevirisi); yem, fiyat, cari silme sarıldı.
- `lib/features/donem/donem_servisi.dart`: `DonemServisi.hesapla / kapat / yenidenAc / bilgi`,
  `HakedisSatiri` (devir + süt + tahsilat − yem − ödeme = dönem sonu).
  - Yalnız bitmiş ay kapatılır; fiyatı eksik cari varsa kapatılmaz.
  - Kapanışta devralınan fiyat o aya **sabitlenir** (önceki ay fiyatı sonra değişse de kapalı ay değişmez).
  - Yeniden açma gerekçe ister; eski bordro JSON olarak `islem_gecmisi`'ne yazılır.
- Ekran: Menü → **Dönem Kapanışı & Hakediş** (`donem_ekrani.dart`): ay seçimi, durum kartı,
  toplamlar (ödenecek / alacak), üretici kartları, Excel bordro (`ExcelExport.exportHakedisBordrosu`).
- Süt Ekle, Hızlı Süt Girişi, Yem Girişi: kapalı ay seçilince `DonemKapaliBandi` uyarısı.
- Yedek format **v3**: `donemler`, `donem_hakedisleri` dahil. v2 yedekleri hâlâ "tam" sayılır.
  "Tamamen değiştir" önce yerel kilitleri açar, sonra yedekteki dönem durumlarını yazar.
- Supabase SQL: v9 tabloları + `donem_kilidi()` / `donem_bordrosu_kilidi()` tetikleyicileri + RLS.
- Bilinen sınır: kapalı ayın bordrosundaki "devir", kapanış anındaki değerdir; daha eski AÇIK
  bir ayda sonradan değişiklik yapılırsa kapalı ayın bordrosu değişmez (sonraki ayın devri doğru hesaplanır).
  Öneri: ayları sırayla kapatın.
- Testler: 90/90 geçti; `flutter analyze` 0 error.

### 2026-11-04 (8) — B8: Üretici fişi (termal yazıcı + WhatsApp)

- Kullanıcı: B2 (süt kalitesi) istemedi → iptal.
- **Android:** `TermalYazici.kt` + `termal_yazici` MethodChannel (`yazdir(address, bytes)`).
  Terazinin tek soketinden (MainActivity `btSocket`) **bağımsız**: her fişte ayrı RFCOMM bağlanır,
  512 baytlık parçalarla yazar, kapatır. Aynı anda iki yazdırma engellenir (`MESGUL`).
  Eski `classic_bluetooth.sendData` kullanılmadı: teraziyi koparırdı ve metni UTF-8 gönderiyordu.
- `lib/features/fis/uretici_fisi.dart`: `UreticiFisi` (işletme, fiş no = süt kaydı id, tarih,
  basım zamanı, üretici, sabah, akşam, günlük toplam, bu ay toplam kg), `FisSatiri`,
  `solSag`/`sar`, `EscPos` (başlat, hizalama, kalın, çift boy, ilerlet, kısmi kesim).
  Türkçe: varsayılan Latin harfine çevirme (ş→s, her yazıcıda çalışır); isteğe bağlı CP857.
  Önizleme, WhatsApp (``` blok) ve yazıcı AYNI satırlardan üretilir.
- `fis_servisi.dart`: `FisAyarlari` (SharedPreferences: yazıcı, genişlik 32/40/48 — varsayılan 40, işletme adı, CP857),
  `TermalYaziciServisi`, `sutFisiOlustur(db, cari, tarih)`.
- `fis_ekranlari.dart`: fiş önizleme alt sayfası (Yazdır / WhatsApp), Menü → **Fiş Yazıcısı**
  (eşleşmiş cihaz seçimi, kâğıt genişliği, işletme adı, Türkçe karakter, deneme fişi).
- Süt Ekle: **"KAYDET + FİŞ VER"** düğmesi (kaydeder → fiş → sayfa kapanır).
  Detay ekranı süt kaydı menüsü: **"Fiş Ver"** (geçmiş kaydın fişini yeniden bas).
- Kullanıcının yazıcısı: **80 mm rulo, satırda 40 karakter** → varsayılan genişlik 40. Seçenekler: 32 (58 mm), 40 (80 mm), 48 (80 mm geniş).
- Fişte para tutarı YOK (yalnız kg) — fiyatlar ay kapanana kadar değişebilir.
- Supabase SQL: şema değişmedi (ayarlar cihazda).
- Testler: 103/103; `flutter analyze` 0 error. **Gerçek bir termal yazıcıyla henüz denenmedi.**

### 2026-11-04 (9) — C1: Özet ekranı

- `dashboardDataProvider` yeni alanlar: `bugunSabah`, `bugunAksam`, `dunToplamSut`,
  `bugunGelenSayisi`, `gelmeyenler`, `kapanmamisGecenAy`.
- `gelmeyenUreticiler(...)` (saf fonksiyon): aktif + son 14 günde (bugün hariç) süt getirmiş +
  bugün kaydı olmayan (ya da 0 kg) üreticiler, ada göre.
- Ekran: banner "Bugün N üretici · X kg / Dün Y kg"; "Bugün Süt" kartında sabah/akşam;
  **BUGÜN GELMEYENLER** listesi (ilk 6 + tümünü göster; dokununca o üreticinin Süt Ekle sayfası);
  geçen ay hareketi olup dönemi kapatılmamışsa turuncu hatırlatma → Dönem ekranı.
- Hata düzeltmeleri: yem dağılımında B. Başlangıç/B. Büyütme "Besi" sayılıyordu → ayrı "Buzağı" dilimi.
  KPI kartları sabit en-boy oranlı ızgarada dar ekran/büyük yazıda **taşıyordu** (360 px testinde
  yakalandı) → içerik yüksekliğinde ikişerli satırlar; `KpiKarti` ve `BolumBasligi` taşmaya dayanıklı.
- Fiş: kullanıcının yazıcısı 80 mm / 40 karakter → varsayılan genişlik 40.
- Supabase SQL: şema değişmedi.
- Testler: 112/112; `flutter analyze` 0 error.

### 2026-11-04 (10) — A6: Repository katmanı + performans

- **DBHelper kaldırıldı** (`_arsiv/db_helper.dart.txt`). Kullanan 7 dosya repository'lere taşındı.
- Yeni `VeriYonetimiRepository` (`kayitSayilari`, `yedekJson`, `yedekYukle`, `sutVeYemSil`,
  `dbDosyasiniDogrula`) + `veriYonetimiRepositoryProvider`. Yedekleme ekranı, Bluetooth aktarımı,
  Excel yedeği artık SQL yazmıyor.
- `SutRepository.toplamCari`, `kayitVarMi`; `CariFiyatRepository.topluKaydet` (tek transaction).
- Fiş (`sutFisiOlustur(SutRepository, …)`) ve Özet (dönem hatırlatması) doğrudan SQL'den kurtuldu.
- **Migration v10:** `idx_sutler_tarih`, `idx_yemler_tarih`, `idx_odemeler_tarih`
  (v4 indeksleri `cari_id` ile başladığından tarih-yalnız sorgular tabloyu tarıyordu). Supabase SQL güncel.
- **Performans** (PC, 110.000 süt kaydı; telefonda kazanç daha belirgin):
  günün kayıtları 7,64→0,65 ms (~12×), aylık cari toplamları 9,87→1,45 ms (~7×),
  "ayda kayıt var mı" 5,69→0,27 ms (~21×); cari listesi 100 sorgu (25 ms) → 1 sorgu (~17×).
  Fiyat ekranları: cari başına ayrı yazım (her biri ayrı disk yazımı, yarıda kalabilir) → tek transaction.
- **Düzeltilen hatalar:**
  1. Wi-Fi aktarımı yedek dosyasını HİÇ oluşturmuyordu (`// TODO`), karşı taraf "Dosya bulunamadı" alıyordu.
  2. "Süt ve yem kayıtlarını temizle" kapalı dönem varken ham veritabanı hatası veriyordu; artık hiçbir şey
     silinmez + anlaşılır mesaj; silinen satır sayısı denetim kaydına yazılır.
  3. Cari listesi: ekrandan çıkarken yükleme bitince `setState` hatası (mounted kontrolü yoktu).
- Testler: 122/122; `flutter analyze` 0 error.

### 2026-11-04 (11) — Excel'den cari içeri alma

- Kullanıcı isteği: Excel'deki isim listesinden cari oluşturma. Örnek dosya proje kökünde
  `cariler.xlsx` (uygulamanın kendi "Süt Raporu" Excel'i, 38 cari + GENEL TOPLAM).
  **Gerçek müşteri isimleri içerdiği için `.gitignore`'a `*.xlsx` / `*.xls` eklendi; repoya girmez.**
- Yer: Cari listesi → Excel düğmesi → **"Excel'den Cari İçeri Al"**.
- `lib/features/cari/cari_excel_ice_aktarma.dart`: `CariExcelOkuyucu.oku(bayt)` — başlık satırını
  ilk 5 satırda arar (İsim Soyisim / Ad Soyad / Cari Adı / Üretici / Müşteri… ya da ayrı Ad + Soyad;
  isteğe bağlı Telefon/Cep/GSM, Adres/Köy). "Kod/No/Bakiye/Tutar" içeren başlıklar isim sanılmaz.
  Başlık yoksa ilk metin sütunu. "Toplam" satırları, boş satırlar, dosya içi tekrarlar atlanır.
  Ad soyad ayrımı: son kelime soyad ("MEHMET ALİ YILMAZ" → ad "MEHMET ALİ"). Yalnız .xlsx.
  `iceAktarmaPlani`: Türkçe harf kurallarıyla (İ/i, I/ı) ve boşluk farkı gözetmeden kayıtlı
  carilerle (pasifler dahil) eşleştirir — kayıtlılar tekrar eklenmez.
- `CariRepository.topluEkle` (tek transaction). Ekran: `cari_excel_ekrani.dart` (özet, hayvan türü,
  seçmeli liste, kayıtlı/atlanan listeleri). Süt/yem rakamları ALINMAZ, yalnız cariler.
- Gerçek dosyada denendi: 38 cari bulundu, başlık ve GENEL TOPLAM atlandı.
- Supabase SQL: şema değişmedi.
- Testler: 130/130; `flutter analyze` 0 error.

### 2026-11-04 (12) — "Süt ekledim, cari detayında görünmüyor" hatası + genel tarama

**Kök neden (testle yeniden üretildi, `test/akis_test.dart`):** `AnaEkran` sekmeleri `IndexedStack` ile
bellekte tutuyor. Cariler listesi verisini yalnız ilk açılışta yüklüyordu ve "veri değişti" sinyalini
dinlemiyordu → Süt sekmesinde süt girilince Cariler sekmesi eski veriyi (bu ayki süt 0) gösteriyordu.
Aynı kök neden: Süt/Yem/Ödemeler sekmeleri cari listesini `build` içindeki `FutureBuilder` ile
alıyordu → yeni eklenen / Excel'den alınan cari, uygulama yeniden açılana kadar bu sekmelerde görünmüyordu;
Ödemeler her yeniden çizimde veritabanına sorgu atıp titriyordu.

**Düzeltmeler**
- `lib/features/cari/providers/cari_providers.dart`: `aktifCarilerProvider`, `butunCarilerProvider`
  (veriSurumu izler). Süt, Yem, Ödemeler sekmeleri bunları kullanıyor.
- Cariler sekmesi `ref.listen(veriSurumuProvider)` ile kendini yeniliyor; yenilemede arama filtresi korunuyor
  (eskiden arama kutusu dolu ama tüm liste görünüyordu).
- **Türkçe arama** (`lib/utils/turkce.dart` → `turkceKucuk`, `aramaEslesir`): `toLowerCase()` "İ"yi "i̇" yapıyordu;
  Excel'den gelen BÜYÜK HARFLİ "İSMAİL" "ismail" diye aranınca bulunmuyordu. Cariler, Süt, Yem, Ödemeler,
  Hızlı Süt Girişi aramaları düzeltildi.
- **Ödemeler:** pasif ama açık bakiyeli cari üstteki toplamda sayılıp listede yoktu (ödeme yapılamıyordu) → artık
  "(pasif)" etiketiyle listede.
- Süt/Yem/Piyasa Fiyat kartlarında `ListTile` renkli `Container` içindeydi → dokunma efekti görünmüyordu,
  debug'da hata → `Material(transparency)` ile sarıldı.
- 14 "ekran kapandıktan sonra context kullanımı" (çökme riski) düzeltildi: yedekleme, Excel yedeği,
  Bluetooth/Wi-Fi aktarım, detay ekranı (geri çıkınca setState hatası).
- Testler: 132/132; `flutter analyze` 0 error.
- **GitHub push bu adımda otomatik izin sisteminde engellendi**; commit yalnız yerelde. Kullanıcı `git push` ile gönderebilir.

### 2026-11-04 (13) — Alt panel yazıları + tüm ekran taraması

- **Alt panel:** yazılar yalnız seçili sekmede görünüyordu → artık 5 sekmenin yazısı (Özet, Cariler,
  Süt, Yem, Ödemeler) HER ZAMAN görünür; seçili sekme renk + zeminle belirgin. "Öde" → "Ödemeler".
  Panel `ValueKey('altPanel')`.
- **`test/ekran_tarama_test.dart`:** her ekran 360 px telefon genişliğinde, uzun isimli / büyük rakamlı
  gerçekçi veriyle açılır; taşma veya hata = test kırılır. 16 ekran + ana ekran 5 sekme + boş veritabanı.
  **Yeni ekran eklenince bu listeye eklenmeli.**
- Taramanın bulduğu ve düzeltilen hatalar (hepsi dar telefonda / büyük yazı boyutunda görünür):
  1. **Hesap Ekstresi:** "Tahsilat Al" + "Ödeme Yap" düğmeleri yan yana sığmıyor, ekrandan taşıyordu
     → ekranı ikiye bölen iki düğme; bakiye rakamı ve 4'lü özet tek satırda küçülür; etiketler `Wrap`.
  2. **Cari Detay:** tarih aralığı kutusu ("01 Kasım 2026 - 30 Kasım 2026") ve süt kartında tarih + "BUGÜN" taşıyordu.
  3. **Hızlı Süt Girişi:** alt paneldeki Kayıtlı / Boş / Günlük Toplam kutuları büyük toplamla taşıyordu.
  4. **Yem Fiyatları:** `ExpansionTile` renkli kutuda → dokunma efekti görünmüyordu (debug hata).
  5. **Aktivasyon:** "UYGULAMAYI AKTİVE ET" düğme yazısı taşıyordu; eskimiş "her kullanıcı için farklı şifre" metni düzeltildi.
  6. **Yedekleme:** başlık satırı taşması.
- Testler: 150/150; `flutter analyze` 0 error.

**Kullanıcıya önerilen ekran iyileştirmeleri (karar bekliyor)** — bkz. "Sıradaki işler".

### 2026-11-04 (14) — Sürüm, imza, izinler, paketler

- **Sürüm:** `1.0.0+1` hiç artırılmamıştı → `1.1.0+2`. `+N` = Android versionCode; "Güncelle"
  için yeni APK'nın versionCode'u telefondakinden KÜÇÜK OLMAMALI (kural 13).
- **İmza (Güncelle mi, "yüklenmedi" mi):** APK'lar bu bilgisayarın debug anahtarıyla imzalanıyor
  (`~/.android/debug.keystore`, SHA-256 `CD:DB:9B:C2:…:7E:28`, release de bu anahtarla).
  Telefondaki uygulama AYNI anahtarla imzalıysa → "Güncelle", veriler korunur. Başka anahtarla
  (başka bilgisayar/eski APK) imzalıysa → "Uygulama yüklenmedi / paket çakışıyor"; eskisini silmek
  gerekir ve VERİLER SİLİNİR → önce JSON yedek al. Kalıcı çözüm: ayrı release keystore (karar bekliyor).
  `applicationId = com.example.sut_yem_clean` — değiştirilirse yeni uygulama sayılır (veriler taşınmaz); Play Store'a
  çıkılacaksa değişmeli.
- **KRİTİK izin hatası:** Bluetooth izinleri 4 yerde 4 farklı şekilde isteniyor ve hepsi KONUM iznini şart
  koşuyordu. Manifest'te konum yalnız API ≤30 → Android 12+ telefonda istek anında reddediliyor, terazi
  Bluetooth ile **hiç bağlanamıyordu** (Bluetooth aktarımı da). Tek kaynak: `lib/utils/permission_helper.dart`
  (`PermissionHelper.bluetoothIzinleri`): API 31+ → BLUETOOTH_SCAN + CONNECT (+ADVERTISE aktarımda),
  API ≤30 → konum. Terazi servisi, cihaz seçme, BLE aktarım, fiş yazıcısı bunu kullanıyor.
  Test: `test/utils/permission_helper_test.dart`.
- **Manifest:** kullanılmayan READ_MEDIA_IMAGES/VIDEO/AUDIO ve POST_NOTIFICATIONS kaldırıldı;
  `bluetooth`/`bluetooth_le` uses-feature `required="false"` (Wi-Fi terazi ile Bluetooth'suz cihazda da kurulur).
- **Paketler:** `flutter pub upgrade` (kısıtlar içinde): sqflite 2.4.5, path_provider 2.1.6,
  shared_preferences 2.5.6 vb.; geri çekilmiş (retracted) path_provider_foundation 2.5.0 → 2.6.0.
  Büyük sürüm atlamaları (riverpod 3, go_router 18, file_picker 13, flutter_blue_plus 2,
  permission_handler 13, excel 4, share_plus 13) YAPILMADI — kırıcı değişiklik; ayrı iş.
- Telefon bağlı değildi (`adb devices` boş) → canlı çalıştırma yapılamadı.
- Testler: 152/152; `flutter analyze` 0 error.

### 2026-11-04 (15) — Wi-Fi fiş yazıcısı, tümüne aynı süt fiyatı, menü düzeni (sürüm 1.1.1+3)

- **Wi-Fi / ağ fiş yazıcısı:** `FisAyarlari.baglanti` (bluetooth | wifi), `wifiAdres`, `wifiPort` (9100).
  `TermalYaziciServisi` ağda doğrudan TCP (ESC/POS) ile basar; `wifiTest` kâğıt harcamadan bağlantıyı dener.
  Ulaşılamayan yazıcıda anlaşılır Türkçe hata ("aynı Wi-Fi ağında mı, IP doğru mu"); aynı anda tek fiş.
  ("Bulut" yazıcı yok — yazıcı aynı yerel ağda olmalı. Yazıcıya modemden sabit IP verilmesi önerilir.)
- **Kayıtlı yazıcı KİLİTLİ:** ayar ekranında kayıtlıysa yeşil "Kayıtlı ✓" kartı; değiştirmek için "Değiştir" + onay.
  Wi-Fi'de "Test Et ve Kaydet": test geçmezse kaydedilmez. Ekran tekrar açılınca yazıcı aynen durur.
- **Süt Fiyatları → "Tüm carilere aynı fiyat"**: tek fiyat girilir, "Tümüne Uygula" tüm alanları doldurur;
  veritabanına ancak "Kaydet" ile yazılır (yanlışlıkla toplu fiyat kaydı olmasın). Bildirimde KAYDET kısayolu.
- **Excel'den cari içeri alma** Cariler ekranındaki Excel diyalogundan kaldırıldı → üst sağ **⋮ menüsü**.
- **Taşma hataları:** ⋮ menüsündeki uzun yazılar (Dönem Kapanışı & Hakediş, Aylık Hesaplama & Rapor…)
  dar ekranda/büyük yazıda taşıyordu → tüm menü öğeleri `_menuOgesi` ile; yazıcı ayar düğmeleri `OverflowBar`.
  Ekran taramasına "⋮ menüsü dar ekranda açılır" eklendi.
- **Performans:** `getAyFiyatlariHepsi` cari başına 2 sorgu yapıyordu (100 cari = 200) → TEK sorgu;
  eski yöntemle birebir aynı sonuç testi (`test/data/fiyat_toplu_test.dart`).
- Süt fiyat ekranında yükleme sonrası `mounted` kontrolü.
- Testler: 161/161 (`test/features/yazici_fiyat_menu_test.dart`: gerçek TCP soketiyle Wi-Fi yazdırma,
  ulaşılamayan yazıcı, kilitli yazıcı akışı, tümüne aynı fiyat, menü yeri); `flutter analyze` 0 error.

### 2026-11-04 (16) — Kullanıcı ekran görüntüleri: kusurat, terazi kartı, ay ortası fiyat (sürüm 1.1.2+4)

Kaynak: `bakılacaklar/` klasöründeki telefon ekran görüntüleri (AHMET ALMAÇ: 30,54 + 47,8 kg).

| # | Sorun | Çözüm |
|---|---|---|
| 1 | Toplam süt tek haneye yuvarlanıyordu: 30,54 + 47,8 = 78,34 → **78.3 kg** (Cariler listesi, cari detayı, Özet "en çok süt"); Özet'te aylık süt **"0.08 ton"**; Ödenecek tutar kuruşsuz (₺5374) | Tüm kg gösterimleri `sayiGoster` (2 haneye kadar, gereksiz sıfır yok); Özet `#,##0.##` kg, aylık süt kg ile, para kuruşu varsa `₺5.374,40`. `sayiGoster(12.001)` "12.0" veriyordu → düzeltildi. Detayda "Sabah: 25.0kg" → "25kg". |
| 2 | Süt Ekle ekranında terazi kartı en üstteydi; klavye açılınca KAYDET görünmüyordu | Terazi kartı KAYDET / KAYDET + FİŞ VER düğmelerinin ALTINA alındı; sabah/akşam alanlarına `scrollPadding` (alt 240) → odaklanınca düğmeler de klavyenin üstüne kayar. |
| 3 | **Fiyat ay ortasında değişince TÜM AY yeni fiyattan hesaplanıyordu** (fiyat yalnızca aylıktı: 4 Kasım'da 25→27 yapınca 1–3 Kasım sütü de 27'den) | Fiyat artık "**o günden itibaren**" geçerli: `cari_fiyatlar.ay` `'yyyy-MM-dd'` de olabilir (şema aynı). Tüm hesaplar (ekstre, bakiye, aylık özet, hakediş) fiyatı KAYDIN TARİHİYLE bulur. Süt Fiyatları ekranı: "Fiyat şu günden itibaren geçerli" (varsayılan bugün) + "Bugünden itibaren" / "Ayın başından" seçimleri; fiyatı değişmeyen cariye satır açılmaz. Ay içinde fiyat değiştiyse aylık özet/hakediş/WhatsApp'ta süt fiyatı **kg ağırlıklı ortalama** ("ort.") — tutar her gün kendi fiyatıyla. |
| 4 | (3'ün yan etkisi) Kapalı dönem kilidi `ay = dönem` karşılaştırıyordu; `'2026-10-15'` hiçbir dönemle eşleşmez → kapalı aya fiyat yazılabilirdi | **Migration v11**: `cari_fiyatlar` tetikleyicileri `substr(ay, 1, 7)` ile yeniden kuruldu. Supabase: CHECK gün biçimini de kabul eder, `donem_kilidi()` `left(ay, 7)`. |
| 5 | (3'ün yan etkisi) Gün satırları da yem fiyatı taşır; aylık yem fiyatı değişince ayın kalanı eski yem fiyatında kalırdı | Yem Fiyatları kaydı `topluKaydet(…, yemFiyatiniAyaYay: true)` → aynı ayın gün satırlarının yem fiyatlarını da günceller (süt fiyatına dokunmaz). |

- Yeni test: `test/features/gunluk_fiyat_test.dart` (ekstre/bakiye/özet/hakediş ay ortası fiyat, sonraki aya devir,
  kapalı dönem v11 kilidi, yem yayma, ekran ön dolgusu); `widget_test.dart` terazi kartı sırası; `sayiGoster` regresyonu.
- Testler: 172/172; `flutter analyze` 0 error.

### 2026-11-04 (17) — Kompakt cari özet kartları, kaydedilmemiş giriş uyarısı, toplu yem fiyatı (sürüm 1.1.3+5)

- **Cariler ekranı özet kartları** (Toplam / İnek / Koyun / Tavuk / Süt Toplam) küçültüldü: ikon solda, sayı +
  başlık sağda, hepsi eşit yükseklikte; bu ayki süt "İnek · 78,34 kg" gibi başlığın yanında.
- **Kaydedilmemiş giriş koruması** (`lib/widgetlar/kaydedilmemis_koruma.dart`, `PopScope`): Süt Ekle, Hızlı Süt
  Girişi ve Yem Ekle ekranlarında miktar yazılıp KAYDET'e basılmadan geri tuşuna (cihaz ya da üst ok) basılırsa
  "Kaydet / Kaydetmeden Çık / Vazgeç" sorulur. Değişiklik yoksa geri tuşu normal çalışır. "Kaydet" ekranın kendi
  kaydetme akışını kullanır (hatalı miktarda ekran açık kalır, hata görünür).
  KURAL: yeni bir giriş ekranı eklenirse aynı sarmalayıcı kullanılsın.
- **Yem Fiyatları → "Tüm carilere aynı yem fiyatı"**: yem türü seçilir, fiyat yazılır, "Tümüne Uygula" yalnız o
  türün alanlarını doldurur (diğer türler ve süt fiyatı korunur); veritabanına ancak "Kaydet" ile yazılır.
  Kart listenin başında, birlikte kayar (klavye açıkken dar ekranda taşma olmasın).
- Testler: 176/176 (geri tuşu: değişiklik yok / Vazgeç / Kaydetmeden Çık / Kaydet; toplu yem fiyatı);
  `flutter analyze` 0 error.

## ⚠️ Açık riskler / karar bekleyenler

1. **Yedekleme ekranındaki "veritabanı şifresi"**: dosyadan geri yükleme ve "tüm süt/yem kayıtlarını sil"
   bu şifreyle korunuyor; **varsayılanı `12345`** ve telefonda **düz metin** (SharedPreferences
   `veritabani_sifre`). Öneri: bu işlemleri master/uygulama şifresine bağla. KULLANICI KARARI BEKLİYOR.
2. **Wi-Fi aktarımı** yedeği yerel ağda 8080 portundan ŞİFRESİZ sunuyor: aynı Wi-Fi'daki herkes
   `/download` adresinden tüm müşteri verisini indirebilir (aktarım ekranı açıkken). Rastgele
   tek kullanımlık adres + aktarım bitince sunucuyu kapatma eklenmeli.
3. **Ana şifre (2026-11-04 güncel):** koddan kaldırıldı, yalnız PBKDF2 özeti var. ANCAK eski
   açık şifre GitHub'daki eski commit'lerde duruyor ve depo hâlâ PUBLIC → şifre ifşa olmuş
   sayılmalı. Yapılacak: (a) depoyu private yap, (b) `dart run tool/master_sifre_ozeti.dart`
   ile YENİ şifre belirle, çıkan iki satırı `app_locker.dart`'a koy, APK derle.
   Önceden aktive edilmiş telefonlar etkilenmez (aktivasyon cihazda saklı).
4. Yem fiyatı ekranı kaydederken her cari için o ayın satırını (süt fiyatını da
   kopyalayarak) yazar. Sonradan **önceki** bir ayın süt fiyatı değişirse bu ay
   eski kopyayı kullanır. İleride fiyatları ürün bazında ayrı satırlara ayırmak düşünülebilir.
5. `withOpacity` vb. ~180 adet "info" düzeyinde eski API uyarısı var (çalışmayı etkilemez).

## Sıradaki işler (öneri sırası)

### D. Ekran taraması önerileri (2026-11-04, kullanıcı onayı bekleniyor)

- [ ] D1. **Cari Kartı birleştirme:** "Detay" (yalnız kg) ve "Hesap Ekstresi" (yalnız ₺) iki ayrı ekran;
      kullanıcı ikisini karıştırıyor. Tek ekran, sekmeler: Özet (bakiye) · Süt · Yem · Ödemeler.
- [ ] D2. **Açılış ve aktivasyon ekranında sabit "HALİL İBRAHİM KABATLI / HALK MARKET"** yazıyor (market
      uygulamasından kalma). İşletme adı ayardan gelsin. WhatsApp/Excel altındaki sabit
      "Süt Yem Takip Sistemi" de işletme adı olsun.
- [ ] D3. **Ayarlar ekranı (B10):** işletme adı/telefonu (fiş, WhatsApp, Excel, açılış), şifre değiştirme,
      otomatik yedek hatırlatma. Bugün bu ayarlar dört farklı ekrana dağınık.
- [ ] D4. **Sayı biçimi tek tip:** Özet/Dönem/Fiş "1.234,5 kg" (Türkçe), Detay/Cari listesi/Yem "1234.5kg".
      Tüm ekranlarda Türkçe biçim (`NumberFormat('#,##0.##','tr_TR')`). 22 yer.
- [ ] D5. **Hızlı Süt Girişi menünün içinde gizli** — en çok kullanılan ekran. Süt sekmesinin en üstüne büyük
      "Toplu Giriş (tüm cariler)" düğmesi.
- [ ] D6. **İşlem geçmişi ekranı (B9):** kayıt zaten tutuluyor; Cari Kartı'nda "Geçmiş" sekmesi.
- [ ] D7. **Yem girişinde tutar önizlemesi:** girilen kg × o ayın fiyatı = ₺ (şu an yalnız kg görünüyor; fiyat eksikse uyarı).
- [ ] D8. Yedekleme ekranı şifresi (`12345`, düz metin) — bkz. Açık riskler 1.

### Profesyonelleşme planı (kullanıcı onayı bekleniyor)

**A. Altyapı (önce)**
- [x] A1. Migration hatasında veritabanı silinmiyor (2026-11-04). Ayrıntı: oturum günlüğü (3).
- [x] A2. Kullanılmayan eski `terazi_baglanti_ekrani.dart` arşive alındı; tek ekran: `features/terazi/screens/terazi_baglanti_ekrani_pro.dart` (düşük seviye `services/terazi_service.dart` Pro servis tarafından kullanılıyor, kalmalı).
- [x] A3. Aylık Rapor gerçek fiyatlarla hesaplanıyor; `fiyatlar` tablosu ekranı "Piyasa Fiyat Notları" oldu + "hesaplara girmez" bandı. Ayrıntı: oturum günlüğü (4).
- [x] A4. Açık şifre koddan kaldırıldı (özet + isolate). **Kullanıcı yeni şifre belirlemeli** (tool/master_sifre_ozeti.dart). Ayrıntı: oturum günlüğü (5).
- [x] A5. cari_listesi 1675→823, detay_ekrani 1094→813 satır; toplu WhatsApp hataları düzeltildi. Ayrıntı: oturum günlüğü (6).
- [x] A6. Repository katmanı tamamlandı, DBHelper kaldırıldı, tarih indeksleri (v10), N+1 ve toplu fiyat yazımı. Ayrıntı: oturum günlüğü (10).

**B. Yeni ekranlar**
- [ ] B1. Toplama turu (sabah/akşam vardiya, üretici sırası/rota, gelmeyenler).
- [~] B2. Süt kalitesi — İPTAL (2026-11-04, kullanıcı: "süt kalite ekranına gerek yok").
- [ ] B3. Tank ve sevkiyat (fabrikaya teslim, fire = toplanan − sevk).
- [x] B4. Aylık dönem kapanışı + hakediş bordrosu + DB seviyesinde kilit (migration v9). Ayrıntı: oturum günlüğü (7).
- [ ] B5. Kesintiler (stopaj vb. — oranlar ayarlanabilir) + müstahsil makbuzu çıktısı.
- [ ] B6. Yem stok/depo (alış, tedarikçi, stok, kritik stok uyarısı).
- [ ] B7. Raporlar merkezi (günlük, aylık üretici, bakiye listesi, yem satış; PDF/Excel/WhatsApp).
- [x] B8. Üretici fişi: Bluetooth termal yazıcı (ayrı kanal, teraziyi koparmaz) + WhatsApp. Ayrıntı: oturum günlüğü (8). **Gerçek yazıcıyla denenmedi.**
- [ ] B9. İşlem geçmişi ekranı (denetim izi).
- [ ] B10. Ayarlar (işletme bilgisi, şifre, dönem tipi, kesinti oranları, otomatik yedek).
- [ ] B11. Bulut senkron (Supabase) — en son.

**C. Mevcut ekranların yenilenmesi**
- [x] C1. Özet: bugün sabah/akşam, dün, gelen üretici sayısı, bugün gelmeyenler (dokununca süt girişi), dönem kapatma hatırlatması. Ayrıntı: oturum günlüğü (9).
- [ ] C2. Ortak tema/bileşenler (kart, boş durum, hata, yükleniyor) tüm ekranlarda aynı.

- [x] GitHub: https://github.com/halil510/s-tyem (dal: **main**). 2026-11-04 itibarıyla depo **PUBLIC** — Settings → Danger Zone → Change visibility → Private yapılmalı.
- [ ] Sabit ana şifre konusunu çöz (bkz. Açık riskler 3).
- [ ] Yem girişi için de "aynı gün" uyarısı / düzenleme (yem çoklu teslimata izin veriyor, bilinçli).
- [ ] Cari ekstre ekranında denetim geçmişini (kim ne değiştirdi) gösteren bir sekme.
- [ ] Ay sonu toplu "hesap özeti" PDF'i (tüm cariler) + WhatsApp paylaşımı.
- [ ] Gerçek cihazda terazi (BLE/Classic/Wi-Fi) ile uçtan uca deneme.
- [ ] `withOpacity` → `withValues` gibi eski API uyarılarını temizle.
