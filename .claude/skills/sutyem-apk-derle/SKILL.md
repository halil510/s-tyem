---
name: sutyem-apk-derle
description: Sütyem için dağıtılacak release APK'yı derler; sürümü artırır, testleri koşar, imzayı doğrular, SUTYEM.md'ye işler. Kullanıcı "derle", "apk oluştur", "apk ver", "telefona kuracağım" dediğinde kullan.
---

# Sütyem APK derleme

Sırayı bozma; bir adım başarısızsa DUR ve kullanıcıya söyle.

1. **Sürüm**: `pubspec.yaml` `version: x.y.z+N`. Son dağıtılan APK'dan beri değişiklik varsa `+N`'yi 1 artır
   (versionCode düşük/aynı olursa telefon güncellemez). Özellik eklendiyse x.y.z'yi de uygun artır.
   SUTYEM.md oturum günlüğündeki son APK satırına bak: aynı N ile ikinci bir APK verme.
2. **Analiz**: `flutter analyze` — error varsa düzelt; uyarıları raporla.
3. **Testler**: `flutter test` (uzun sürer: timeout 600000, gerekirse arka planda). Hepsi geçmeli; sayıyı not et.
4. **Derle**: `flutter build apk --release` (timeout 600000). `~/.sutyem/key.properties` yoksa Gradle bilerek durur →
   anahtarı ASLA yeniden üretme; kullanıcıya klasörün yedeğini (USB / bulut) kopyalamasını söyle.
   Çıktı: `build/app/outputs/flutter-apk/Sutyem-<sürüm>+<N>.apk` (app-release.apk ile aynı dosya).
   "SDK XML version" uyarısı zararsızdır.
5. **Doğrula**: `apk-dogrula` skill'i, `-Uygulama sutyem`. HATA ise APK'yı verme.
6. **Defter**: SUTYEM.md oturum günlüğüne APK satırı: dosya adı, boyut, versionCode, imza TAMAM, test sayısı.
7. **Kullanıcıya rapor** (Türkçe, kısa): tam yol, sürüm, "güncelleme olarak kurulur, veriler kalır", telefonda neyi
   denemesi gerektiği (bu sürümde değişen ekranlar). Şema ya da eşitleme değiştiyse: **tüm telefonlar birlikte
   güncellenmeli**. Commit edilmemiş değişiklik varsa belirt ve commit'i teklif et (kendiliğinden yapma).
