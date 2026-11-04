class CariFiyat {
  int? id;
  int cariId;
  String ay; // 'yyyy-MM' formatı, örn: '2026-06'
  double sutFiyat;
  double sutYemiFiyat;
  double besiYemiFiyat;
  double bBaslangicFiyat;
  double bBuyutmeFiyat;
  double kuzuYemiFiyat;
  double tavukYemiFiyat;

  CariFiyat({
    this.id,
    required this.cariId,
    required this.ay,
    this.sutFiyat = 0,
    this.sutYemiFiyat = 0,
    this.besiYemiFiyat = 0,
    this.bBaslangicFiyat = 0,
    this.bBuyutmeFiyat = 0,
    this.kuzuYemiFiyat = 0,
    this.tavukYemiFiyat = 0,
  });

  factory CariFiyat.fromMap(Map<String, dynamic> m) => CariFiyat(
    id: m['id'] as int?,
    cariId: m['cari_id'] as int,
    ay: m['ay'] as String,
    sutFiyat: (m['sut_fiyat'] as num?)?.toDouble() ?? 0,
    sutYemiFiyat: (m['sut_yemi_fiyat'] as num?)?.toDouble() ?? 0,
    besiYemiFiyat: (m['besi_yemi_fiyat'] as num?)?.toDouble() ?? 0,
    bBaslangicFiyat: (m['b_baslangic_fiyat'] as num?)?.toDouble() ?? 0,
    bBuyutmeFiyat: (m['b_buyutme_fiyat'] as num?)?.toDouble() ?? 0,
    kuzuYemiFiyat: (m['kuzu_yemi_fiyat'] as num?)?.toDouble() ?? 0,
    tavukYemiFiyat: (m['tavuk_yemi_fiyat'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'cari_id': cariId,
    'ay': ay,
    'sut_fiyat': sutFiyat,
    'sut_yemi_fiyat': sutYemiFiyat,
    'besi_yemi_fiyat': besiYemiFiyat,
    'b_baslangic_fiyat': bBaslangicFiyat,
    'b_buyutme_fiyat': bBuyutmeFiyat,
    'kuzu_yemi_fiyat': kuzuYemiFiyat,
    'tavuk_yemi_fiyat': tavukYemiFiyat,
  };

  /// Bir ayın YEM BORCUNU hesaplar (cari işletmeye borçlanır — bkz.
  /// CariOdemeRepository doc yorumu).
  double yemBorc(double sutYemi, double besiYemi, double bBaslangic,
      double bBuyutme, double kuzuYemi, double tavukYemi) {
    return (sutYemi * sutYemiFiyat) +
        (besiYemi * besiYemiFiyat) +
        (bBaslangic * bBaslangicFiyat) +
        (bBuyutme * bBuyutmeFiyat) +
        (kuzuYemi * kuzuYemiFiyat) +
        (tavukYemi * tavukYemiFiyat);
  }

  /// Bir ayın SÜT ALACAĞINI hesaplar (işletme cariye borçlanır — bkz.
  /// CariOdemeRepository doc yorumu). İsim geriye dönük uyumluluk için
  /// "Borc" olarak kalmıştır ama anlamı ALACAKTIR.
  double sutBorc(double sutMiktari) => sutMiktari * sutFiyat;
}
