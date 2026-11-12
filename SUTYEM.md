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
14. **İmza anahtarı (2026-11-04'ten itibaren):** paket adı `com.sutyem.pro` (DEĞİŞTİRME). Tüm APK'lar (debug +
    release) `~/.sutyem/sutyem-release.jks` ile imzalanır; şifreler `~/.sutyem/key.properties` içinde
    (ya da `android/key.properties`). **Depo HERKESE AÇIK → bu iki dosya ASLA git'e girmez** (`.gitignore`).
    Her bilgisayarda (ev + işyeri) `C:\Users\<kullanıcı>\.sutyem\` klasörü aynı olmalı; klasör yoksa
    derleme bilerek durur. Anahtar kaybolursa telefondaki uygulamalar bir daha GÜNCELLENEMEZ →
    klasörün en az iki yedeği tutulur (USB + bulut). Sertifika: `CN=SUTYEM PRO, O=SUTYEM, C=TR`.
15. **Girilmiş öğün kilitli (kullanıcı kararı 2026-11-05):** Süt Ekle ve Hızlı Süt Girişi'nde o gün
    girilmiş sabah/akşam DEĞİŞTİRİLEMEZ (kutu yerine "kayıtlı" yazısı, terazi uygulanamaz), bu ekranlardan
    kayıt silinmez; yalnız boş öğün girilir. Her tarih için geçerli. Düzeltme YALNIZ Cari Detay → Düzenle
    (`SutRepository.update`). Bu iki ekran `gunlukKaydet` / `topluGunlukKaydet`'i `kayitliOgunuKoru: true`
    ile çağırır → kayıtlı öğün değişirse `KayitliOgunHatasi` (toplu girişte hiçbir satır yazılmaz).
16. **Süt toplama rotası (`cariler.sira`, migration v12):** aktif carinin toplama sırası 1..N BOŞLUKSUZ.
    Yalnız `CariRepository.insert(sira:)`, `update(siraGuncelle:, sira:)`, `siraAta`, `rotaKaydet`,
    `pasifeAl`, `aktifYap(sira:)` değiştirir (araya ekleme sonrakileri kaydırır; pasifte null).
    `update` `cari.sira`'yı YOK SAYAR. `getAll` rota sırasıyla döner (`rotaSirala`: sıralılar, sonra
    sırasızlar alfabetik) → Cariler, Süt, Yem, Hızlı Giriş, Ödemeler. Raporlar (Excel, bordro, aylık)
    alfabetik kalır (`cariSirala`). Listelerde ad önünde `RotaRozeti`.
17. **Veri güvenliği (şarj biterse / kilitlenirse):**
    - Riskli her işlemden (süt/yem toplu silme, JSON/.db geri yükleme, cihaz aktarımı, hareketli cari
      kalıcı silme, güvenlik yedeğine dönüş) ÖNCE `OtomatikYedek.islemOncesiAl('...')` çağrılır; yedek
      alınamazsa işlem YAPILMAZ. Yeni riskli işlem eklersen bunu da ekle.
    - Otomatik yedek: `OtomatikYedekleyici` (AnaEkran) açılışta + arka plana geçişte, en çok 4 saatte bir.
      Klasör `Documents/otomatik_yedekler/`, son 15 otomatik + 10 işlem öncesi. Dosya `.tmp` yazılıp
      sonra adı değiştirilir (yarım dosya yedek sayılmaz). Yedekleme → "Otomatik Güvenlik Yedekleri".
    - Veritabanı dosyası YALNIZ `AppDatabase.dosyayiDegistir` + `dosyayiYerineKoy` ile değiştirilir
      (önce silip sonra taşıma YOK). .db yedeği `tutarliKopyala` ile alınır ve doğrulanır.
    - Ekleme yapan her kaydet fonksiyonu başında `if (_kaydediliyor) return;` (çift dokunma = mükerrer kayıt).
    - Hızlı Süt Girişi kaydedilmemiş girişleri SharedPreferences `hizli_sut_taslak`'a yazar; ekrandan
      normal çıkışta silinir, uygulama ölürse sonraki açılışta geri gelir (kendiliğinden KAYDEDİLMEZ).

18. **Süt sekmesi "alındı" tiki** saklanmaz, bugünkü süt satırından hesaplanır (`sut_toplama_durumu.dart`):
    saat < 12 → sabah kg > 0, sonra → akşam kg > 0. Saat ayrımı `aksamBaslangicSaati`. Yalnız Süt sekmesinde.

19. **Çoklu cihaz / bulut (v13, `lib/senkron/`):** her ekleme/düzeltme/silme TETİKLEYİCİYLE `senk_gunluk`'e
    yazılır — repository'ler senkronu bilmez, değiştirmeye gerek yok. Kurallar:
    - Yeni EŞİTLENECEK tablo = `senk_tablolari.dart` listesine ekle (ebeveyn önce) + migration'da
      `senkTetikleyicileriKur` yeniden çağır; tek-satırlık (UNIQUE) tablo ise `dogalAnahtarlar`'a yaz.
    - Yeni TARİHLİ tablonun dönem kilidi `donemKilitleriniKur` gibi "uzaktan uygulanıyorsa çalışma" istisnalı olmalı.
    - Süt satırı ÖĞÜN BAZINDA birleşir (`sabah_zaman`/`aksam_zaman`, tetikleyici doldurur). Süt yazan yeni kod
      bu sütunlara dokunmasın.
    - Yedekten TAM geri yükleme günlüğe yazmaz (`senk_durum.kapali`) ve sonra `SenkCekirdek.tabanYenile`;
      .db dosyası değişince `senkTabanBayragi` → bir sonraki başlangıçta taban. Yeni bir "veriyi topluca
      değiştir" yolu eklenirse bunlardan birini kullan.
    - `senk_ayarlar` (bulut şifresi…) yedeğe GİRMEZ, eşitlenmez. Cihaz kimliği SharedPreferences `sutyem_cihaz_id`.
    - Bulut SQL: `supabase/sutyem_bulut_sema.sql` (ayrı Supabase projesi). `supabase_sema.sql` yalnız şema aynası.

## Testler

```bash
flutter test          # 382 test — hepsi geçmeli
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
| `test/ekran_tarama_test.dart` | TÜM EKRANLAR gerçekçi veriyle açılır (taşma/hata yok): 360 px telefon + küçük telefon 320x568, yatay telefon 760x360, tablet dikey 800x1280 / yatay 1280x800, büyük yazı x1.3; alt panel yazıları; boş veritabanı |
| `test/features/yazici_fiyat_menu_test.dart` | Wi-Fi (TCP) fiş yazdırma, ulaşılamayan yazıcı, kayıtlı yazıcı kilidi, tümüne aynı süt fiyatı, ⋮ menüsü |
| `test/data/fiyat_toplu_test.dart` | Toplu ay fiyatı (tek sorgu) = eski cari-başına yöntem |
| `test/features/gunluk_fiyat_test.dart` | Ay ortası fiyat değişikliği (o günden itibaren), sonraki aya devir, kapalı dönem v11 kilidi, yem fiyatı yayma |
| `test/features/sanal_terazi_test.dart` | SANAL TERAZİ (gerçek TCP) → gerçek terazi servisi → Süt Ekle → KAYDET; bölünen/çoklu satır, farklı terazi biçimleri |
| `test/features/terazi_veri_cozucu_test.dart` | Tartı satırı çözme, parça birleştirme, satır sonu yok, cihaz kaydı yarışı |
| `test/features/derin_tarama_test.dart` | Türkçe alfabetik sıralama, aynı isimli cari uyarısı, 0 kg düzenlemede silme |
| `test/features/excel_rapor_test.dart` | Excel çıktıları geri okunur: boş Sheet1 yok, süt raporu 2. sayfa "Süt Toplamları", yuvarlama, pasif cari, yıllık rapor, ekstre dönem neti, hakediş, dosya adı |
| `test/features/pdf_ekstre_test.dart` | Excel/PDF ortak ekstre satırları (sıra, yürüyen bakiye, DÖNEM NETİ), PDF internetsiz oluşur, çok sayfa |
| `test/features/rota_test.dart` | Toplama rotası: sıra verme/kaydırma (Ahmet Atağ 1 → Ahmet Anıl 2), pasife alma, geri getirme, Cari Ekle/Düzenle/Pasif/Toplama Sırası ekranları |
| `test/features/sut_alindi_tik_test.dart` | Süt sekmesi yeşil tik: 12:00 öncesi sabah / sonrası akşam, sayaç, dünkü kayıt bugüne tik vermez |
| `test/features/veri_guvenligi_test.dart` | Otomatik güvenlik yedeği (tamlık, 4 saat aralık, temizlik, yarım .tmp), toplu silme sonrası geri dönüş, tek adımda .db değiştirme + bekleyen çağrı, tutarlı .db kopyası, Hızlı Süt taslağı, yemde çift dokunma |

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

### 2026-11-04 (18) — Kalıcı imza anahtarı + paket adı (sürüm 1.1.4+6)

- Kullanıcı ev ve işyeri bilgisayarında GitHub'dan çekip derliyor → iki bilgisayarın debug anahtarı FARKLI,
  biri diğerinin APK'sını güncelleyemezdi. Uygulama ileride başka kişilere de verilecek.
- `~/.sutyem/sutyem-release.jks` + `key.properties` oluşturuldu (depo dışında; depo herkese açık).
  `android/app/build.gradle.kts`: debug + release bu anahtarla; anahtar yoksa APK üretimi durur.
- Paket adı `com.example.sut_yem_clean` → **`com.sutyem.pro`** (Play Store `com.example` kabul etmez).
  Telefondaki eski deneme uygulaması bir kez silinip yenisi kurulur (deneme verisi; gerekirse JSON yedekle taşınır).
- `pubspec.yaml`'daki `assets/templates/` kaldırıldı: boş klasör git'e girmediği için GitHub'dan indirilen
  bilgisayarda `flutter build apk` "unable to find directory entry" ile duruyordu; kodda kullanılmıyordu.
- Doğrulandı: `app-release.apk` → `com.sutyem.pro`, versionCode 6, sertifika SHA-256 `9E:B0:EA:…:52:8D` = anahtar.

### 2026-11-05 — Sanal terazi ile uçtan uca test; terazi verisi hataları (sürüm 1.1.5+7)

Sanal terazi (gerçek TCP sunucusu, `test/features/sanal_terazi_test.dart`) + GERÇEK terazi servisi + Süt Ekle
ekranı: tartı gelir → Sabaha/Akşama Uygula → KAYDET → veritabanı. Bulunan ve düzeltilen hatalar:

| # | Sorun | Çözüm |
|---|---|---|
| 1 | Satır iki pakete bölünürse (`+0012` + `.80kg`) ekranda 12.00 / 80.00 görünüyordu; o an "Uygula" = yanlış kilo | `TeraziVeriCozucu` (`lib/features/terazi/services/`): parçaları biriktirir, satır sonunda (CR/LF/ETX) çözer; satır sonu yoksa 200 ms sessizlikte |
| 2 | Bir pakette birden çok satır → ilki (eski tartı) gösteriliyordu | En SON çözülebilen satır |
| 3 | `001 0033.60` (terazi no + tartı) → **10033** okunuyordu (sayılar arası boşluk birleştiriliyordu) | Birimi yazılı → ondalıklı → son sayı seçilir; `g` → kg'a çevrilir; "gross" gram sayılmaz |
| 4 | `OL`/`ST` gibi durum satırları göstergeye **0.00** basıyordu | Çözülemeyen satır yok sayılır, son tartı kalır |
| 5 | Klasik Bluetooth: Kotlin `String(...).trim()` satır sonlarını siliyordu → Dart satırları ayıramıyordu | `MainActivity.kt`: trim kaldırıldı (ISO-8859-1) |
| 6 | Yeni teraziye İLK bağlanışta cihaz kaydı iki kez aynı anda → UNIQUE hatası → "Bağlantı hatası" | `TeraziCihazRepository.kaydetVeyaGuncelle` tek transaction; dinleyicideki çağrı `catchError` |
| 7 | Eski `TeraziService` tekil (singleton): `dispose` ortak akışları kapatıyor, sonraki servis kapalı akışa yazıp çöküyordu | Tekil kaldırıldı; kapalı akışa yazma korundu; Wi-Fi/BLE `utf8` yerine `latin1` (bölünen baytta paket kaybı yok) |
| 8 | Süt Ekle açılırken terazi zaten bağlıyken otomatik yeniden bağlanma mevcut bağlantıyı koparabiliyordu | `baslangicOtomatikBaglan`: bağlı/bağlanıyorsa hiçbir şey yapmaz |

- **Elle deneme aracı:** `dart run tool/sanal_terazi.dart [port]` (varsayılan 9100) — bilgisayar Wi-Fi terazi
  gibi davranır; telefonda Terazi → Wi-Fi → ekrandaki IP/port. Komutlar: sayı = kilo, `b` bölünmüş paket,
  `d` oynak okuma, `q` çıkış.
- Not: testler gece yarısını aşarsa (test "bugün"ü başta hesaplar) Hızlı/Süt Ekle testleri bir kez düşebilir; tekrar çalıştır.
- Testler: 195/195; `flutter analyze` 0 error. Terazi telefonda (gerçek cihazla) kullanıcı tarafından denendi: çalışıyor.

### 2026-11-05 (2) — Tüm ekranların derin taraması (sürüm 1.1.6+8)

| # | Ekran | Sorun | Çözüm |
|---|---|---|---|
| 1 | Yedekleme → .db geri yükle | Mevcut veritabanı ÖNCE siliniyor, yeni dosya SONRA kopyalanıyordu → kopya yarıda kalırsa uygulama BOŞ açılırdı. Sonra uygulama kapalı veritabanıyla çalışmaya devam edip her ekranda hata veriyordu | Önce geçici kopya → eski DB yedeği → yer değiştir; hata olursa eski DB geri konur. Ardından `databaseProvider` yenilenir |
| 2 | Cari detayı, ekstre | Kapalı döneme ait süt/yem/ödeme silinirken hata YAKALANMIYORDU (mesaj yok, yarım kalan ekran) | try/catch + anlaşılır mesaj; `mounted` kontrolleri |
| 3 | Tüm listeler | `ORDER BY ad` / `toLowerCase().compareTo`: ÇETİN, ŞÜKRÜ, ÖMER, ÜMİT, İSMAİL listenin EN SONUNDA | `turkceKarsilastir` (`lib/utils/turkce.dart`) + `cariSirala` (repository, Özet, Aylık Rapor, Dönem) |
| 4 | Cari Ekle | Aynı ad-soyadla ikinci cari açılabiliyordu → süt yanlış kişiye | Türkçe harf duyarsız aynı isim kontrolü + "Yine de Ekle" onayı |
| 5 | Özet / Cariler | "Bugün" ve "bu ay" yalnız veri değişince hesaplanıyordu → uygulama gece açık kalırsa sabah DÜNÜN rakamları | `bugunProvider` (30 sn'de bir gün kontrolü) → `AnaEkran` gün değişince `veriDegisti` |
| 6 | Süt/Yem düzenle | Tüm miktar 0 yapılınca 0 kg'lık satır kalıyordu | Silme onayı sorulur, kayıt silinir |
| 7 | Yedekleme başlığı | Her yeniden çizimde DB sorgusu (FutureBuilder in build) → sayılar titriyordu | Future'lar bir kez; veri değişince yenilenir |
| 8 | Cari detayı | Başka ekrandaki değişiklikle yenilenmiyordu | `ref.listen(veriSurumuProvider)` |
| 9 | Yem Ekle, Cari Ekle, Piyasa Fiyat Notları | Kapanmış ekranda `setState` (çökme riski); fiyat girişi `double.tryParse` | `mounted` kontrolü; `sayiCoz` |

Bakılıp sorun bulunmayanlar: cari silme (CASCADE + dönem kilidi doğru), Ödemeler toplamı, Hızlı Süt Girişi tarih değişimi,
ödeme/tahsilat girişi, Wi-Fi aktarım mesajları (analizci uyarısı yanlış alarm: `context.mounted` kontrolü var).
- Testler: 203/203; `flutter analyze` 0 error.


### 2026-11-05 (3) — Excel dışa aktarmalarının taraması

6 Excel çıktısı (Süt raporu, Yem raporu, Hesap ekstresi, Aylık hesaplama, Hakediş bordrosu, Yedekleme → Excel)
gerçek dosya üretip geri okuyan testle (`test/features/excel_rapor_test.dart`) denendi.

| # | Rapor | Sorun | Çözüm |
|---|---|---|---|
| 1 | **Hakediş bordrosu** | HİÇ oluşmuyordu: excel 3.0 + archive 3.6 uyumsuzluğu, `delete('Sheet1')` "unmodifiable list" ile çöküyordu | `excel` paketi **4.0.6**'ya yükseltildi (hücre değerleri `TextCellValue`/`DoubleCellValue`, renkler `ExcelColor`) |
| 2 | Tüm raporlar | Dosya boş "Sheet1" sayfasıyla açılıyordu (rapor 2. sekmede) | Boş sayfa kaydetmeden önce silinir |
| 3 | Süt raporu (cari listesi) | ~1 yıllık aralıkta çöküyordu (sütun harfi hesabı 702. sütunda taşıyor) | Hücreler sütun/satır numarasıyla |
| 4 | Süt / Yem raporu | Pasif carinin sütü raporda ve GENEL TOPLAM'da YOKTU; yemi "Bilinmeyen Cari" | Aktif + aralıkta kaydı olan pasif cariler; listede olmayan kayıt "Silinmiş/pasif cari #id" satırı; genel toplam = tüm kayıtlar |
| 5 | Tüm raporlar | `0.30000000000000004` gibi kayan nokta değerleri | Her sayı kuruşa/2 haneye yuvarlanır |
| 6 | Hesap ekstresi | Tarih filtresi varken "NET BAKİYE" yazıyordu (aslında dönem neti, devir yok) → müşteri toplam borcu sanabilir | Başlıkta dönem; "DÖNEM NETİ" + not; eskiden yeniye, Alacak/Borç/yürüyen Bakiye sütunları; ALACAKLI/BORÇLU yazısı |
| 7 | Hesap ekstresi | Cari adında `/` varsa dosya yazılamıyordu | `ExcelExport.dosyaAdi` temizler |
| 8 | Yem raporu | Ekrandaki listeyi yerinde sıralıyordu (Detay'da sıra ters dönüyordu); tür bazında genel toplam yoktu | Kopya üzerinde; cariye göre gruplu, cari ara toplamı, her yem türünün genel toplamı |
| 9 | Aylık hesaplama, Hakediş | Fiyatı eksik cari Excel'de 0 ₺ görünüyordu, uyarı yok | "Not" sütunu: FİYAT EKSİK / fiyat ay içinde değişti (ortalama) |
| 10 | Yedekleme → Excel | Kendi kopya kodu; yıllıkta cari×gün×kayıt tarama (telefonda dakikalar); hata olursa diyalog sonsuza dek "yükleniyor" | `ExcelExport.exportSutVeYemRaporu` (ortak kod); hata mesajı; "geri yüklenemez, tam yedek JSON" notu |
| 11 | Paylaş | Her paylaşımda gereksiz 2 sn bekleme | Kaldırıldı |

- Yıllık süt raporu (40 cari × 365 gün): ~0,6 sn.
- **PDF ekstresi de düzeltildi** (aynı oturum): yazı tipi Google Fonts'tan İNDİRİLİYORDU (internetsiz PDF oluşmuyordu) → uygulama içi DejaVu Sans; Türkçe harfler ("Sut"→"Süt") ve para biçimi (1.250,10 TL); dönem + "DÖNEM NETİ" + not; Alacak/Borç/yürüyen Bakiye sütunları; adında "/" olan cari. Excel ve PDF aynı hesabı kullanır: `lib/utils/ekstre_satirlari.dart`.
- Supabase SQL: şema değişmedi.
- Testler: 216/216; `flutter analyze` 0 error.


### 2026-11-05 (4) — Süt girişinde kayıtlı öğün kilidi

Kullanıcı isteği: sabah girildiyse süt giriş ekranında sabah tekrar değiştirilemesin (kafa karışıklığı),
yalnız akşam girilsin; düzeltme Cari Detay'daki Düzenle'den. Karar: Hızlı Süt Girişi'nde de, her tarih için.

- **Süt Ekle:** kayıtlı öğün → `_KilitliOgun` (yeşil, kilit simgesi, "kayıtlı"); bilgi bandı "Sabah sütü kayıtlı
  (20 kg). Yalnız akşam sütü girilebilir. Düzeltmek için: Cariler → cari → Detay → Düzenle". Düğme hep
  "KAYDET" (GÜNCELLE kalktı); gün tamamsa KAYDET kapalı, ikinci düğme "FİŞ VER" (kayıt değişmeden fiş).
  Terazinin "Sabaha/Akşama Uygula" düğmesi kayıtlı öğün için kapalı. Bu ekrandan silme kalktı.
  Kilitli değer yazıdan değil kayıttan alınır (yuvarlama farkıyla yanlışlıkla değişmesin).
- **Hızlı Süt Girişi:** kayıtlı öğün hücresi kutu değil kilitli yazı; boşaltıp silme ve "Sil ve Kaydet" onayı kalktı.
- **Kayıt katmanı:** `kayitliOgunuKoru` + `KayitliOgunHatasi`; hata olursa ekran günü yeniden yükler.
  Detay → Düzenle (`update`) etkilenmez.
- Supabase SQL: şema değişmedi.
- Testler: 224/224; `flutter analyze` 0 error.

### 2026-11-05 (5) — Süt toplama rotası, Cari Düzenle yeniden tasarım, Pasif Cariler ekranı

Kullanıcı isteği: süt toplarken listeler uğranan sırayla dizilsin (Ahmet Atağ 1, Ahmet Anıl 2); sıra Cari Ekle ve
Cari Düzenle'den verilsin; Cari Düzenle ekranı iyileşsin; pasif cari listede görünmesin, ayrı ekrandan geri getirilsin.

- **Migration v12:** `cariler.sira` + `idx_cariler_sira`. Supabase SQL güncel (v12, `check (sira >= 1)`).
- **Kayıt katmanı** (`cari_repository.dart`): sıra işlemleri tek transaction; 1..N boşluksuz; araya ekleme kaydırır,
  rota sayısından büyük sıra en sona; pasife alınca rotadan çıkar ve kalanlar yeniden numaralanır.
- **Ortak form** (`lib/ekranlar/cari/cari_form.dart`): `CariBolumKarti`, `CariMetinAlani`, `HayvanTuruSecici`,
  `RotaSirasiAlani` (önizleme: "Şu an 1. sırada AHMET ANIL var → 2. sıraya kayar"), `ayniIsimliCariler`/`ayniIsimOnayi`.
- **Cari Ekle:** aynı görünüm + "Süt Toplama Sırası" bölümü (varsayılan rotanın sonu).
- **Cari Düzenle (yeniden):** özet başlık (baş harfler, Aktif/Pasif, rota sırası), Kişisel Bilgiler, Hayvan Türü,
  Süt Toplama Sırası, **Not** (artık düzenlenebilir), **Durum** anahtarı (pasife alma onaylı); Kaydet altta sabit;
  kaydedilmemiş değişiklik uyarısı; ad değişince aynı isim kontrolü. Bilgiler + sıra + durum tek transaction.
- **Pasif Cariler** (`pasif_cariler_ekrani.dart`): eski alt pencere yerine ayrı ekran; arama, açık bakiye,
  "Geri Getir" (rota sırası sorulur), dokununca Cari Düzenle. Giriş: Cariler'deki düğme ve ⋮ menü.
- **Toplama Sırası (Rota)** (`toplama_sirasi_ekrani.dart`): sürükle-bırak, Kaydet → 1..N. ⋮ menüde.
- Cariler, Süt, Yem, Hızlı Süt Girişi listelerinde ad önünde mavi sıra rozeti.
- Ekran taraması: Pasif Cariler + Toplama Sırası eklendi; Cari Düzenle'de Switch dokunma efekti gizleniyordu → düzeltildi.
- Testler: 237/237; `flutter analyze` 0 error.

### 2026-11-05 (6) — Veri güvenliği derin taraması (şarj biterse / kilitlenirse)

Kullanıcı isteği: süt raporu Excel'i ve genel olarak "mobil şarj biterse, kilitlenirse veri kaybı olmasın" — derin analiz.

Sağlam bulunanlar: her kayıt transaction içinde (yarım kayıt olmaz); açılışta bütünlük denetimi, bozuk dosya
silinmez kenara alınır; migration hatası veriye dokunmaz; Excel/PDF `flush: true`; süt raporu 100 cari × 365 gün
bilgisayarda 0,9 sn (doğru, çökmez).

Bulunan ve düzeltilenler:
- **.db geri yükleme:** önce eski dosya SİLİNİP sonra yenisi taşınıyordu → arada şarj biterse uygulama BOŞ açılırdı.
  Şimdi tek adımda yer değiştirme (`dosyayiYerineKoy`). Ayrıca değiştirme sırasında başka ekran eski dosyayı yeniden
  açabiliyordu (yazdıkları silinmiş dosyaya gidiyordu) → `dosyayiDegistir` kilidi.
- **.db yedeği:** açık veritabanı ham kopyalanıyordu (o an yazılan kayıt / günlükteki kayıtlar eksik kalabilirdi) →
  `tutarliKopyala` + paylaşmadan önce doğrulama. JSON yedek tek transaction'da okunuyor (tutarlı anlık görüntü).
- **Hiç otomatik yedek yoktu** → `OtomatikYedek` (kural 17) + Yedekleme'de "Otomatik Güvenlik Yedekleri" ekranı
  (listele, paylaş, şifreyle geri dön, şimdi yedek al).
- **Yem KAYDET'e çift dokunma yemi İKİ KEZ yazıyordu** (testle kanıtlandı: 2 kayıt) → koruma. Süt Ekle ve Cari Ekle'ye
  de aynı koruma; ödeme penceresinde çift dokunma alttaki ekranı kapatıyordu → düzeltildi.
- **Hızlı Süt Girişi:** tüm rota girilip kaydedilmeden şarj biterse hepsi kayboluyordu → taslak (kural 17).
- Cariler / Cari Detay Excel raporunda "Rapor hazırlanıyor…" penceresi (`beklemeyleCalistir`): donma sanılmaz,
  çift dokunmayla iki rapor açılmaz.
- Testler: 251/251; `flutter analyze` 0 error.

### 2026-11-05 (7) — Tüm cihaz boyutları: küçük telefon, yatay, tablet, büyük yazı

Kullanıcı sorusu: "tüm cihazlarda, mobilde ve tablette ekranlar sıkıntısız mı?" Önceden yalnız 360 px telefon test ediliyordu.
Ekran taraması 5 boyuta genişletildi (her ekran + ana ekran sekmeleri). Sonuç: **tablet (dikey/yatay) baştan temizdi**;
küçük telefon (320 px), yatay telefon ve büyük yazıda (x1.3) 15 yerde taşma vardı → hepsi düzeltildi:
- Uzun ekranlar tek parça kayar hale geldi (üst kart/özet listeyle birlikte kayar): Cari Detay, Ödemeler, Süt Fiyatları,
  Hızlı Süt Girişi (sütun başlığı ve alt panel sabit kalır).
- Büyük rakamlar (terazi kg, güncel fiyat, bakiye, hareket tutarı, bu ay kg) kesilmez, dar yerde küçülür (`FittedBox`).
- Başlık yazıları (Süt Miktarları, terazi durumu, Fiyat Geçmişi, Cari Hesapları, Lisans) gerekirse "…" ile kısalır.
- Rota rozeti çok dar yerde gizlenir (yalnız ad); Pasif Cariler "Geri Getir" düğmesi sıkılaştırıldı.
- Yedekleme sayaçları eşit genişlikte ve küçülebilir.
- **Süt raporu Excel'ine 2. sayfa "Süt Toplamları"** (kullanıcı isteği): her cari tek satır, İsim Soyisim | Toplam (kg),
  başlıkta tarih aralığı, en altta GENEL TOPLAM; sıra ve rakamlar 1. sayfayla aynı. Excel yedeğindeki süt+yem dosyasında da var.
- Testler: 352/352; `flutter analyze` 0 error. Yeni ekran eklenince `ekran_tarama_test.dart` listesine eklemek tüm boyutları kapsar.

### 2026-11-05 (8) — Elektrik kesintisi sonrası kontrol + GitHub'a gönderim

- Bilgisayar elektrik kesintisiyle kapandı. (5)–(7) oturumlarının işleri commit edilmemişti; dosyalar sağlam bulundu,
  352/352 test geçti. Hepsi tek commit'te GitHub'a (`main`) gönderildi. Sıradaki işlere buradan devam.

### 2026-11-05 (9) — Süt sekmesinde "alındı" yeşil tiki

Kullanıcı isteği: süt toplarken Süt sekmesindeki cari listesinde (Cariler sekmesinde DEĞİL) sütü alınan cariye
yeşil tik; öğleden sonra sıfırlansın, akşam rotasında yeniden tik atılsın.
- `lib/features/sut/sut_toplama_durumu.dart`: `toplamaOgunu` (saat < 12 → sabah, sonra akşam; `aksamBaslangicSaati`),
  `ogunAlindi`, `gunlukSutlerProvider(tarih)` (veriSurumu izler), `simdiProvider` (testte sabit saat).
- Tik **ayrıca kaydedilmez**: bugünkü süt satırının sabah/akşam kg'ından hesaplanır → "sıfırlama" kendiliğinden,
  uygulama kapanıp açılsa da doğru. Veritabanı/Supabase şeması DEĞİŞMEDİ.
- Kartta: soldaki damla yerine yeşil kutuda beyaz ✓, kart yeşil çerçeve, "Sabah alındı · 40 kg". Listenin üstünde
  "Sabah toplaması · 5 / 12 alındı" (hepsi alınınca yeşil). Sekme açık kalırsa 30 sn'de bir saat kontrolü (12:00 / gece yarısı).
- Test: `test/features/sut_alindi_tik_test.dart`. Testler: 357/357; `flutter analyze` 0 error.

### 2026-11-12 — Raporlar ekranı (B7, Fırın ERP'deki yapıdan)

Kullanıcı isteği: "Fırın ERP'deki raporlar gibi süt-yem'de de raporlar ekranı". ⋮ menü → **Raporlar**
("Aylık Hesaplama & Rapor"un üstünde; o ekran ve Dönem/Hakediş aynen duruyor).
- `lib/features/raporlar/`: `rapor_modeli.dart` (`RaporTablosu`, `RaporSutun` + `toplanir`, `RaporTuru` enum, Türkçe
  `kgYaz`/`tlYaz`/`hucreMetni`), `rapor_servisi.dart` (yalnız repository'lerden okur — SQL yok, kural 10),
  `rapor_disa_aktarim.dart` (Excel sayı hücreli + toplam, PDF DejaVu internetsiz, Yazdır, Paylaş),
  `rapor_ekrani.dart` (gruplu liste; Bugün / Bu ay / Geçen ay / Bu yıl / özel tarih; aranabilir cari seçici,
  pasifler dahil; tablo yatay kaydırmalı, sarı toplam satırı, altta not; `raporProvider` veriSurumu izler).
- 12 rapor: SÜT — Süt Girişleri (gün gün), Günlük Toplam Süt, Cari Bazlı Süt, Aylık Süt Karşılaştırması;
  YEM — Yem Teslimleri (6 tür), Yem Türü Bazlı, Cari Bazlı Yem; HESAP — Cari Hesap Özeti (dönem + genel bakiye),
  Bakiye Listesi (bitiş tarihi itibarıyla, alacaklı/borçlu ayrı sütun), Ödeme ve Tahsilatlar, Cari Ekstre (devir +
  yürüyen bakiye); KONTROL — Fiyatı Eksik Kayıtlar (kg var, fiyat yok → 0 TL sayılanlar).
- Tutarlar ekstreyle AYNI fonksiyonlardan (`sutTutari`, `yemTutari`, `CariFiyatLookup` — KAYDIN GÜNÜNDEKİ fiyat).
  Raporlar alfabetik (`cariSirala`, kural 16). Pasif/silinmiş carinin kaydı da rapora girer.
- "Yem Türü Bazlı" tutarları satır satır yuvarlanmadığından genel toplam birkaç kuruş farklı olabilir (raporda not var).
- Veritabanı / Supabase şeması DEĞİŞMEDİ. Test: `test/features/rapor_test.dart` (9: ay ortası fiyat, ekstre ve
  tumKalanBorclar ile kuruşu kuruşuna aynı, bakiye listesi tarihli, ekstre devir/yürüyen, eksik fiyat, yenilenme,
  Excel/PDF, 360 px'te 12 raporun hepsi hatasız). Testler: **366/366**.

### 2026-11-12 (2) — Çoklu cihaz ve bulut (B11, Fırın ERP / market yapısından) · sürüm 1.2.0+9

Kullanıcı isteği: "Fırın ERP'deki gibi çoklu cihaz ve bulut; bulut AYRI; internetli ya da internetsiz;
menüde Fiş Yazıcısı'nın altında; SQL'i metin dosyası olarak ver." ⋮ menü → **Çoklu Cihaz ve Bulut**.
- **Migration v13** (`migration_v13_senkron.dart`): cariler/fiyatlar/yemler/cari_odemeler `uuid`; sutler
  `sabah_zaman`/`aksam_zaman`; `senk_gunluk/durum/kanallar/bekleyen/hatalar/eksik_ref/ayarlar`; tüm senkron ve
  öğün tetikleyicileri; dönem kilitleri "uzaktan uygulanıyorsa çalışma" istisnasıyla yeniden kuruldu; mevcut veri
  taban zamanla günlüğe (ilk eşitlemede karşıya gider).
- `lib/senkron/`: `senk_tablolari` (8 tablo; doğal anahtar: cari_fiyatlar=cari|ay, sutler=cari|tarih,
  donemler=ay, donem_hakedisleri=dönem|cari), `senk_cekirdek` (Fırın çekirdeği + **süt öğün birleşmesi** + rota
  1..N düzeltme), `bulut_kanali` (Supabase RPC `sutyem_*` + market'teki **saat farkı** ölçümü — 5 dk üstü ekranda
  uyarı), `yerel_ag_kanali` (internetsiz; port **8767**, 6 haneli kod, 5 hatalı denemede 5 dk engel),
  `senkron_yoneticisi` (önce AL sonra GÖNDER; dakikada bir + açılış + öne gelme + arka plana geçiş),
  `senkron_ekrani`, `otomatik_esitleyici` (AnaEkran'ı sarar).
- Eşitlenmeyen: terazi listesi, islem_gecmisi (her telefonun kendi denetim izi), senk_ayarlar.
- Yedek: tam JSON geri yükleme günlüğe yazmaz + taban (diğer telefonlardan silmez, onların kayıtları geri gelir);
  çoklu cihaz öncesi (uuid'siz) yedek, eşitlenen telefona YÜKLENMEZ (cariler ikilenirdi). .db geri yükleme →
  `senkTabanBayragi`. "Süt/yem kayıtlarını sil" onayına "diğer telefonlardan da silinir" uyarısı.
- `supabase/sutyem_bulut_sema.sql` (yeni; pubspec asset → ekrandan paylaş/kopyala) — tek genel tablo
  `sutyem_kayitlar` (jsonb), RLS açık + doğrudan erişim yok, yalnız işletme kodu/şifresi doğrulayan fonksiyonlar.
  `supabase_sema.sql` aynasına v13 sütunları; `supabase_sema_test` senk_* tablolarını cihaza özel sayar.
- `http` paketi eklendi. Release APK derlendi (82.3 MB, kalıcı anahtar).
- Testler: `test/senkron/` — senkron_test (10: tam aktarım+bakiye, A sabah/B akşam birleşme, üç telefon ters sıra,
  0'a düzeltme, silme yayılması, kapalı dönem, rota çakışması, JSON geri yükleme silmez, uuid'siz yedek engeli,
  v12→v13 taban), senkron_ag_test (5: sahte Supabase uçtan uca + öğün birleşmesi, saat farkı, gizli anahtar,
  ayarlar yedekte yok, gerçek HTTP yerel ağ), senkron_ekrani_test (360 px). **382/382**.
- Bilerek böyle: iki telefon aynı cari FİYATINI aynı anda farklı değiştirirse son değiştiren kalır (satır bazında).
  Aynı kişi iki telefonda AYRI ayrı cari olarak açılırsa iki cari olur → önce carileri tek telefonda girip eşitleyin.
- Gerçek Supabase'de ve iki gerçek telefonda henüz DENENMEDİ.
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
6. **Telefon dışı yedek yok (2026-11-05):** otomatik yedekler telefonun içinde; telefon kaybolur/bozulur ya da
   uygulama silinirse onlar da gider. Kullanıcı ara sıra "Paylaş" ile dışarı göndermeli. İleride: Supabase'e
   otomatik bulut yedeği ya da "son dış yedek X gün önce" hatırlatması.

7. **Toplu WhatsApp (2026-11-05, kullanıcı kararı: "böyle kalsın"):** her cari için wa.me açılır, gönder tuşuna
   kullanıcı basar; "gönderildi" sayısı yalnız WhatsApp'ın açıldığını gösterir. Sıralı gönderim ekranı / Business API
   önerildi, istenmedi — kullanıcı tekrar sormadıkça yeniden önerme.
8. **Toplu SMS (fikir, 2026-11-05 "şimdilik dursun"):** telefonun SIM'inden otomatik SMS (SEND_SMS, APK'da sorun yok),
   kısa mesaj + Türkçe harf sadeleştirme (1 SMS = 160 harf; ş/ğ/ı varsa 70), Android 30 SMS/30 dk uyarısı. Kullanıcı isterse yapılır.

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
- [x] B7. Raporlar merkezi — 12 rapor, Excel/PDF/Yazdır/Paylaş (WhatsApp paylaşım menüsünden). Ayrıntı: oturum günlüğü 2026-11-12.
- [x] B8. Üretici fişi: Bluetooth termal yazıcı (ayrı kanal, teraziyi koparmaz) + WhatsApp. Ayrıntı: oturum günlüğü (8). **Gerçek yazıcıyla denenmedi.**
- [ ] B9. İşlem geçmişi ekranı (denetim izi).
- [ ] B10. Ayarlar (işletme bilgisi, şifre, dönem tipi, kesinti oranları, otomatik yedek).
- [x] B11. Çoklu cihaz + bulut (Supabase) + internetsiz yerel ağ — 2026-11-12 (2). Gerçek Supabase / iki telefonla denenecek.

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
