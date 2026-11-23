---
name: sutyem-sema-degisikligi
description: Sütyem veritabanına yeni tablo, sütun, index ya da migration eklerken eksiksiz kontrol listesi (senkron, dönem kilidi, yedek, temizlik, Supabase aynası, testler). Şemaya dokunan her işte, kod yazmaya başlamadan önce kullan.
---

# Sütyem şema değişikliği — kontrol listesi

Bir adımı atlamak = veri kaybı, senkron hatası ya da eski yedeğin açılmaması. Her maddeyi bitirince işaretle;
"gerekmez" dediklerinin gerekçesini kullanıcıya raporda yaz. Örnek tam uygulama: `migration_v16_urunler.dart`
ve SUTYEM.md kural 21.

## 1. Migration
- Yeni dosya `lib/core/database/migrations/migration_vN_<ad>.dart`; `migration_runner.dart` `_all` listesine ekle.
  **Yayınlanmış migration DEĞİŞTİRİLMEZ.**
- Yeni sütun: `ALTER TABLE … ADD COLUMN` (NOT NULL ise DEFAULT şart). Yeni tablo: FK'ler — `ON DELETE CASCADE` yalnız
  gerçek çocukta; kaydı olan ebeveyn silinmesin → `RESTRICT`.
- Tetikleyicisi olan tabloyu değiştiriyorsan: önce kilit/senk tetikleyicilerini düşür, değiştir, sonra yeniden kur.
- Var olan veriyi dönüştürüyorsan: dönüşüm migration içinde; testte tutarların kuruşu kuruşuna aynı kaldığını kanıtla.

## 2. Çoklu cihaz (`lib/senkron/senk_tablolari.dart`)
- Eşitlenecek tablo → `senkTablolari` (ebeveyn ÖNCE); migration'da `senkTetikleyicileriKur(db)` yeniden çağır.
- UNIQUE doğal anahtarlı tablo → `dogalAnahtarlar`; id ile başka tabloya bağlanan sütun → `iliskiSutunlari`;
  ay sütunu varsa → `donemAyiSutunu`; gruplu birleşme gerekiyorsa → `alanGruplari`.
- Yeni eşitlenen tablo ekleyen migration: `senk_kanallar.son_cekilen = 0` + yeni `taban_nesil` (karışık sürüm kuralı).
- Hazır / tohum satırlar: sabit uuid + günlük zamanı `tabanZaman` (başka telefondaki düzeltmeyi ezmesin).
- `senk_cekirdek.dart` `_carininKapaliKaydiVar` ve `senkron_ekrani.dart` tablo etiketleri.

## 3. Kapalı dönem kilidi
- Tarihli / aylı tablo → `migration_v13_senkron.dart` `donemKilitleriniKur` kapsamına ekle; repository yazmaları
  `donemKilidiyle` ile sarılı. `DonemServisi.kapat`'ın o aya dondurması gereken bir değer var mı düşün.

## 4. Yedek (`lib/data/yedek/yedek_servisi.dart`)
- `formatSurumu` artır; tablo listesine ekle (FK sırası); doğal anahtar / uuid eşleşmesi; `_baskaVeritabaniMi`.
- ESKİ yedek yüklenince yeni yapıya **bellekte çevir**; aynı yedek iki kez birleştirilince çift kayıt olmamalı.
- `INSERT OR REPLACE` YASAK (CASCADE çocukları siler).

## 5. Diğer yerler
- `veri_yonetimi_repository.dart` temizlik seçenekleri (hangi temizlik bu tabloyu siler / korur).
- Repository + provider (`repository_providers.dart`); ekran SQL yazmaz; yazmalar `islem_gecmisi`'ne.
- Excel / rapor / WhatsApp / dashboard / ekstre bu veriyi gösteriyorsa güncelle.

## 6. Supabase aynası (kullanıcı kuralı)
- `supabase/supabase_sema.sql`: tablo bloğu (Postgres tipleri: date, numeric, boolean, jsonb), `kullanici_id` + RLS,
  `(kullanici_id, id)` anahtarı, updated_at tetikleyicisi, başlıktaki "yerel şema sürümü: vN", sondaki DEĞİŞİKLİK GEÇMİŞİ.
  Postgres ayrıntısı için `supabase-postgres-best-practices` skill'i.

## 7. Testler
- `test/data/migration_test.dart` hedef sürüm; boş kurulum + eski sürümden yükseltme; dönüşüm doğruluğu.
- `test/data/supabase_sema_test.dart`, `yedek_servisi_test.dart` (tablo sayısı), `test/ajan_senkron/` (iki cihaz).
- `test/helpers/test_db.dart` yardımcıları. Sonunda tam `flutter test`.

## 8. Defter
- SUTYEM.md "Önemli kurallar"a yeni madde (ne, nerede, neden), test tablosu, oturum günlüğü.
