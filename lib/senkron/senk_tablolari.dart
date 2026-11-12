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

/// (v13) Süt öğün zamanı sütunları — migration v13 bunları ekler.
const sutOgunleri = {'sabah': 'sabah_zaman', 'aksam': 'aksam_zaman'};

/// ─────────────────────────────────────────────────────────────
/// GRUPLU BİRLEŞME (v14): bu tablolarda satırın tamamı "son yazan kazanır" ile
/// EZİLMEZ; her alan grubunun kendi son değişiklik zamanı vardır, birleşmede her
/// grupta daha yeni olan kalır.
///  • süt: sabah / akşam (A sabahı, B akşamı girerse ikisi de kalır)
///  • cari fiyatı: süt fiyatı / yem fiyatları (Süt Fiyatı ve Yem Fiyatı ekranları birbirini ezmez)
///  • cari: kart bilgisi / rota sırası / aktiflik (rota kaydı, başka telefondaki telefon
///    düzeltmesini ya da "pasife al"ı geri almaz)
/// Zaman sütununu tetikleyici doldurur (yerel değişiklikte "şimdi"); repository kodu bilmez.
/// ─────────────────────────────────────────────────────────────
const alanGruplari = <String, Map<String, List<String>>>{
  'sutler': {
    'sabah_zaman': ['sabah'],
    'aksam_zaman': ['aksam'],
  },
  'cari_fiyatlar': {
    'sut_zaman': ['sut_fiyat'],
    'yem_zaman': ['sut_yemi_fiyat', 'besi_yemi_fiyat', 'b_baslangic_fiyat', 'b_buyutme_fiyat', 'kuzu_yemi_fiyat', 'tavuk_yemi_fiyat'],
  },
  'cariler': {
    'kart_zaman': ['ad', 'soyad', 'adres', 'telefon', 'hayvan_turu', 'not_metni'],
    'rota_zaman': ['sira'],
    'durum_zaman': ['aktif'],
  },
};

/// Silme bu tablolarda "her grubu silme anında boşalt" demektir: silmeden SONRA başka
/// telefonda girilen grup (ör. akşam sütü) kalır, silmeden ÖNCEKİ değerler geri gelmez.
/// (Cari gibi diğer gruplu tablolarda silme satırın tamamıdır: silmeden yeni bir
/// değişiklik varsa satır bütünüyle kalır, yoksa bütünüyle silinir.)
const parcaliSilinir = {'sutler', 'cari_fiyatlar'};

/// Kapalı dönem kilidi altındaki tablolar: ayı veren sütun.
const donemAyiSutunu = {'sutler': 'tarih', 'yemler': 'tarih', 'cari_odemeler': 'tarih', 'cari_fiyatlar': 'ay'};

bool dogalMi(String tablo) => dogalAnahtarlar.containsKey(tablo);
bool grupluMu(String tablo) => alanGruplari.containsKey(tablo);
