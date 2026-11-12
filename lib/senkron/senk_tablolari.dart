/// ─────────────────────────────────────────────────────────────
/// SENKRON YAPILANDIRMASI — hangi tablo, hangi sırayla, hangi anahtarla
/// cihazlar arasında taşınır (Fırın ERP / market uygulamasındaki yapının
/// süt-yem sürümü).
/// ─────────────────────────────────────────────────────────────
///
/// Kayıtlar cihazlar arasında YEREL id ile DEĞİL, her cihazda aynı olan
/// anahtarla eşleşir: çoğu tabloda `uuid`; bir güne / aya tek satırı olan
/// tablolarda DOĞAL ANAHTAR (ör. süt: cari + tarih). Böylece iki cihaz aynı
/// carinin aynı gününe süt girerse İKİ satır oluşmaz, aynı satırda birleşir.
/// İlişki sütunları (cari_id, donem_id) gönderilirken ebeveynin anahtarına
/// çevrilir, alınırken alan cihazın yerel id'sine geri çevrilir.
library;

/// Eşitlenen tablolar — EBEVEYN ÖNCE (alma sırası). Silmeler ters sırada.
/// Eşitlenmeyenler: `terazi_cihazlari` (cihaza özel), `islem_gecmisi` (her cihazın
/// kendi denetim izi), `_migration_log`, `senk_*`.
const senkTablolari = [
  'cariler',
  'cari_fiyatlar',
  'fiyatlar',
  'sutler',
  'yemler',
  'cari_odemeler',
  'donemler',
  'donem_hakedisleri',
];

/// uuid yerine DOĞAL ANAHTARLA eşleşen tablolar (UNIQUE kısıtıyla aynı).
/// Değerler '|' ile birleşir; ilişki sütunu ebeveynin anahtarıyla yazılır.
const dogalAnahtarlar = <String, List<String>>{
  'cari_fiyatlar': ['cari_id', 'ay'],
  'sutler': ['cari_id', 'tarih'],
  'donemler': ['ay'],
  'donem_hakedisleri': ['donem_id', 'cari_id'],
};

/// İlişki sütunu → ebeveyn tablo. Hepsi gerçek yabancı anahtar ("sert"):
/// ebeveyn henüz gelmediyse kayıt bekletilir.
const iliskiSutunlari = <String, String>{
  'cari_id': 'cariler',
  'donem_id': 'donemler',
};

/// v13'te uuid sütunu eklenen tablolar.
const uuidTablolari = ['cariler', 'fiyatlar', 'yemler', 'cari_odemeler'];

/// Süt satırında öğün başına ayrı birleşme: her öğünün kendi değişiklik zamanı var.
/// İki cihaz aynı günün farklı öğününü girerse ikisi de korunur.
const sutOgunleri = {'sabah': 'sabah_zaman', 'aksam': 'aksam_zaman'};

bool dogalMi(String tablo) => dogalAnahtarlar.containsKey(tablo);
