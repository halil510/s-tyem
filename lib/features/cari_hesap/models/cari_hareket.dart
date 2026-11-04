/// Cari ekstresinde gösterilen TEK bir hareket satırı.
///
/// Süt/yem hareketleri CANLI olarak `sutler`/`yemler` tablolarından
/// hesaplanır (veritabanında ayrıca "kayıt" olarak tutulmaz); ödeme/
/// tahsilat hareketleri ise `cari_odemeler` tablosunda saklanan gerçek
/// kayıtlardır (bu yüzden `kayitId` doludur ve silinebilir).
class CariHareket {
  final DateTime tarih;

  /// 'sut' | 'yem' | 'odeme' | 'tahsilat'
  final String tur;
  final double tutar;

  /// true → krediye (cari alacağına) katkı; false → borca katkı.
  final bool kredi;
  final String baslik;
  final String? aciklama;

  /// Yalnızca ödeme/tahsilat için doludur (cari_odemeler.id) — silme
  /// işlemi için gereklidir. Süt/yem satırları burada silinemez;
  /// kaynağı Detay ekranından düzenlenir/silinir.
  final int? kayitId;

  /// Fiyat tanımsız olduğu için tutarı 0 çıkan bir süt/yem satırı mı?
  /// (kullanıcıyı fiyat girmeye yönlendirmek için)
  final bool fiyatEksik;

  const CariHareket({
    required this.tarih,
    required this.tur,
    required this.tutar,
    required this.kredi,
    required this.baslik,
    this.aciklama,
    this.kayitId,
    this.fiyatEksik = false,
  });

  bool get silinebilir => kayitId != null;
}

/// Cari hesap ekstresinin tam sonucu: hareket listesi + toplamlar +
/// net (işaretli) bakiye. `filtreliMi` true ise bu sonuç belirli bir
/// tarih aralığına göre hesaplanmıştır (bakiye o aralığın NET
/// hareketini gösterir, tüm zamanların toplam bakiyesini değil).
class CariEkstreSonucu {
  final List<CariHareket> hareketler; // tarihe göre azalan sıralı
  final double toplamSut;
  final double toplamYem;
  final double toplamOdeme;
  final double toplamTahsilat;

  /// Dönemdeki toplam süt / yem miktarı (kg) — ekstre özeti için.
  final double toplamSutKg;
  final double toplamYemKg;
  final double bakiye;
  final bool filtreliMi;
  final DateTime? filtreBaslangic;
  final DateTime? filtreBitis;
  final bool herhangiFiyatEksikMi;

  const CariEkstreSonucu({
    required this.hareketler,
    required this.toplamSut,
    required this.toplamYem,
    required this.toplamOdeme,
    required this.toplamTahsilat,
    this.toplamSutKg = 0,
    this.toplamYemKg = 0,
    required this.bakiye,
    required this.filtreliMi,
    this.filtreBaslangic,
    this.filtreBitis,
    required this.herhangiFiyatEksikMi,
  });

  /// Tutarlar kuruşa yuvarlandığı için yarım kuruşluk eşik yeterlidir:
  /// 0,01 ₺'lik gerçek bir bakiye bile "kapalı" sayılmaz.
  static const _epsilon = 0.005;
  bool get alacakliMi => bakiye > _epsilon;
  bool get borcluMu => bakiye < -_epsilon;
  bool get hesapKapaliMi => bakiye.abs() <= _epsilon;
}
