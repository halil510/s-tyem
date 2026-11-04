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
flutter test          # 63 test — hepsi geçmeli
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

## ⚠️ Açık riskler / karar bekleyenler

1. **Sabit ana şifre:** `lib/utils/app_locker.dart` içinde `_defaultMasterPassword`
   kaynak kodda açık yazılı. Kodu (veya APK'yı) gören herkes uygulamayı açabilir.
   GitHub deposu bu yüzden **özel (private)** olmalı. Kalıcı çözüm: şifreyi
   koddan çıkarıp ilk kurulumda kullanıcıya belirletmek (kilitlenme riskine
   karşı dikkatli geçiş planı gerekir).
2. Yem fiyatı ekranı kaydederken her cari için o ayın satırını (süt fiyatını da
   kopyalayarak) yazar. Sonradan **önceki** bir ayın süt fiyatı değişirse bu ay
   eski kopyayı kullanır. İleride fiyatları ürün bazında ayrı satırlara ayırmak düşünülebilir.
3. `withOpacity` vb. ~180 adet "info" düzeyinde eski API uyarısı var (çalışmayı etkilemez).

## Sıradaki işler (öneri sırası)

### Profesyonelleşme planı (kullanıcı onayı bekleniyor)

**A. Altyapı (önce)**
- [x] A1. Migration hatasında veritabanı silinmiyor (2026-11-04). Ayrıntı: oturum günlüğü (3).
- [ ] A2. İki terazi ekranını (`terazi_baglanti_ekrani` + `_pro`) teke indir.
- [ ] A3. İki fiyat sistemi (`fiyatlar` genel / `cari_fiyatlar`) — "Genel Fiyat Geçmişi" bakiyeyi etkilemiyor; sadeleştir.
- [ ] A4. Sabit ana şifre → ilk kurulumda belirlenen şifre.
- [ ] A5. `cari_listesi.dart` (1675 satır) ve `detay_ekrani.dart` (1094) parçalara böl.

**B. Yeni ekranlar**
- [ ] B1. Toplama turu (sabah/akşam vardiya, üretici sırası/rota, gelmeyenler).
- [ ] B2. Süt kalitesi (yağ %, protein, yoğunluk, sıcaklık, antibiyotik testi) + kaliteye göre prim/kesinti.
- [ ] B3. Tank ve sevkiyat (fabrikaya teslim, fire = toplanan − sevk).
- [ ] B4. Dönem kapanışı / üretici hakedişi (15 günlük ya da aylık, kapanan dönem kilitli).
- [ ] B5. Kesintiler (stopaj vb. — oranlar ayarlanabilir) + müstahsil makbuzu çıktısı.
- [ ] B6. Yem stok/depo (alış, tedarikçi, stok, kritik stok uyarısı).
- [ ] B7. Raporlar merkezi (günlük, aylık üretici, bakiye listesi, yem satış; PDF/Excel/WhatsApp).
- [ ] B8. Üretici fişi (Bluetooth termal yazıcı / WhatsApp).
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
