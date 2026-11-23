# Sütyem — Claude için kısa kurallar

- Kullanıcıyla **Türkçe** konuş. Kullanıcı süt toplama işletmesi sahibi; kayıtlarda **sıfır hata** önceliklidir.
- Oturum başında **SUTYEM.md**'yi oku ("Önemli kurallar (bozma!)" bölümü bağlayıcıdır); oturum sonunda oturum günlüğüne
  yaz, test sayısını güncelle.
- Commit / push yalnız kullanıcı isteyince. `~/.sutyem` anahtarı, `key.properties`, `.jks`, müşteri `.db` / `.zip`
  ASLA git'e girmez (depo herkese açık).
- **GENEL KURAL — SQL eşliği:** her yeni tablo / sütun / index eklendiğinde AYNI işte `supabase/supabase_sema.sql`
  dosyasına da SQL'i yazılır (tablo bloğu / ALTER, başlıktaki "yerel şema sürümü: vN", sondaki DEĞİŞİKLİK GEÇMİŞİ).
  Kullanıcının ayrıca istemesini bekleme. `test/data/supabase_sema_test.dart` eksikleri yakalar.
- Şema değişikliği (yeni tablo / sütun / migration) → `sutyem-sema-degisikligi` skill'i.
- APK derleme ("derle", "apk oluştur") → `sutyem-apk-derle` skill'i.
- Testler: `flutter test` — hepsi geçmeden iş bitmiş sayılmaz. Çoklu cihaz koduna dokununca `test/ajan_senkron/` mutlaka.
- Bash heredoc Türkçe metinle bozulabiliyor: Türkçe içerikli dosyayı Write aracıyla yaz.
- Flutter/Dart genel teknikleri için kurulu resmi skill'ler: flutter-add-widget-test, dart-add-unit-test,
  dart-run-static-analysis, flutter-fix-layout-issues, flutter-build-responsive-layout.
