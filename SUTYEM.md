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
  - Süt/yem tutarı, kaydın ait olduğu **ayın cari fiyatıyla** canlı hesaplanır
    (`cari_fiyatlar`; o ay fiyat yoksa önceki aydan devralır).
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
9. **Kapalı dönem kilidi veritabanındadır** (migration v9 tetikleyicileri). Yeni bir tarihli
   tablo eklenirse ona da tetikleyici yazılmalı. Repository yazmaları `donemKilidiyle` / `_yaz`
   ile sarılır; ekranlar `DonemKapaliHatasi` mesajını gösterir.
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

## Testler

```bash
flutter test          # 103 test — hepsi geçmeli
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
- `fis_servisi.dart`: `FisAyarlari` (SharedPreferences: yazıcı, 58/80 mm, işletme adı, CP857),
  `TermalYaziciServisi`, `sutFisiOlustur(db, cari, tarih)`.
- `fis_ekranlari.dart`: fiş önizleme alt sayfası (Yazdır / WhatsApp), Menü → **Fiş Yazıcısı**
  (eşleşmiş cihaz seçimi, kâğıt genişliği, işletme adı, Türkçe karakter, deneme fişi).
- Süt Ekle: **"KAYDET + FİŞ VER"** düğmesi (kaydeder → fiş → sayfa kapanır).
  Detay ekranı süt kaydı menüsü: **"Fiş Ver"** (geçmiş kaydın fişini yeniden bas).
- Fişte para tutarı YOK (yalnız kg) — fiyatlar ay kapanana kadar değişebilir.
- Supabase SQL: şema değişmedi (ayarlar cihazda).
- Testler: 103/103; `flutter analyze` 0 error. **Gerçek bir termal yazıcıyla henüz denenmedi.**

## ⚠️ Açık riskler / karar bekleyenler

1. **Ana şifre (2026-11-04 güncel):** koddan kaldırıldı, yalnız PBKDF2 özeti var. ANCAK eski
   açık şifre GitHub'daki eski commit'lerde duruyor ve depo hâlâ PUBLIC → şifre ifşa olmuş
   sayılmalı. Yapılacak: (a) depoyu private yap, (b) `dart run tool/master_sifre_ozeti.dart`
   ile YENİ şifre belirle, çıkan iki satırı `app_locker.dart`'a koy, APK derle.
   Önceden aktive edilmiş telefonlar etkilenmez (aktivasyon cihazda saklı).
2. Yem fiyatı ekranı kaydederken her cari için o ayın satırını (süt fiyatını da
   kopyalayarak) yazar. Sonradan **önceki** bir ayın süt fiyatı değişirse bu ay
   eski kopyayı kullanır. İleride fiyatları ürün bazında ayrı satırlara ayırmak düşünülebilir.
3. `withOpacity` vb. ~180 adet "info" düzeyinde eski API uyarısı var (çalışmayı etkilemez).

## Sıradaki işler (öneri sırası)

### Profesyonelleşme planı (kullanıcı onayı bekleniyor)

**A. Altyapı (önce)**
- [x] A1. Migration hatasında veritabanı silinmiyor (2026-11-04). Ayrıntı: oturum günlüğü (3).
- [x] A2. Kullanılmayan eski `terazi_baglanti_ekrani.dart` arşive alındı; tek ekran: `features/terazi/screens/terazi_baglanti_ekrani_pro.dart` (düşük seviye `services/terazi_service.dart` Pro servis tarafından kullanılıyor, kalmalı).
- [x] A3. Aylık Rapor gerçek fiyatlarla hesaplanıyor; `fiyatlar` tablosu ekranı "Piyasa Fiyat Notları" oldu + "hesaplara girmez" bandı. Ayrıntı: oturum günlüğü (4).
- [x] A4. Açık şifre koddan kaldırıldı (özet + isolate). **Kullanıcı yeni şifre belirlemeli** (tool/master_sifre_ozeti.dart). Ayrıntı: oturum günlüğü (5).
- [x] A5. cari_listesi 1675→823, detay_ekrani 1094→813 satır; toplu WhatsApp hataları düzeltildi. Ayrıntı: oturum günlüğü (6).

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
- [ ] C1. Özet: bugün sabah/akşam kg, bu ay, gelmeyen üreticiler, bakiye özeti.
- [ ] C2. Ortak tema/bileşenler (kart, boş durum, hata, yükleniyor) tüm ekranlarda aynı.

- [x] GitHub: https://github.com/halil510/s-tyem (dal: **main**). 2026-11-04 itibarıyla depo **PUBLIC** — Settings → Danger Zone → Change visibility → Private yapılmalı.
- [ ] Sabit ana şifre konusunu çöz (bkz. Açık riskler 1).
- [ ] Yem girişi için de "aynı gün" uyarısı / düzenleme (yem çoklu teslimata izin veriyor, bilinçli).
- [ ] Cari ekstre ekranında denetim geçmişini (kim ne değiştirdi) gösteren bir sekme.
- [ ] Ay sonu toplu "hesap özeti" PDF'i (tüm cariler) + WhatsApp paylaşımı.
- [ ] Gerçek cihazda terazi (BLE/Classic/Wi-Fi) ile uçtan uca deneme.
- [ ] `withOpacity` → `withValues` gibi eski API uyarılarını temizle.
