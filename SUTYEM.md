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

## Testler

```bash
flutter test          # 55 test — hepsi geçmeli
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

**Temizlik**
- Derlenmeyen `lib/bluetooth/main.dart` ve kullanılmayan, yanlış hesaplı
  `cari_odemeler_ekrani.dart` → `_arsiv/` klasörüne taşındı (git'e girmez).
- Bozuk `widget_test.dart` gerçek ekran testleriyle değiştirildi.
- `flutter_lints` + `sqflite_common_ffi` dev bağımlılıkları eklendi.

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

- [ ] GitHub deposunu **private** oluştur, `git push -u origin master`.
- [ ] Sabit ana şifre konusunu çöz (bkz. Açık riskler 1).
- [ ] Yem girişi için de "aynı gün" uyarısı / düzenleme (yem çoklu teslimata izin veriyor, bilinçli).
- [ ] Cari ekstre ekranında denetim geçmişini (kim ne değiştirdi) gösteren bir sekme.
- [ ] Ay sonu toplu "hesap özeti" PDF'i (tüm cariler) + WhatsApp paylaşımı.
- [ ] Gerçek cihazda terazi (BLE/Classic/Wi-Fi) ile uçtan uca deneme.
- [ ] `withOpacity` → `withValues` gibi eski API uyarılarını temizle.
