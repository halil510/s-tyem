class Yem {
  int? id;
  int cariId;
  String tarih;
  double sutYemi;
  double besiYemi;
  double bBaslangic;
  double bBuyutme;
  double kuzuYemi;
  double tavukYemi;
  double toplam;

  Yem({
    this.id,
    required this.cariId,
    required this.tarih,
    this.sutYemi = 0,
    this.besiYemi = 0,
    this.bBaslangic = 0,
    this.bBuyutme = 0,
    this.kuzuYemi = 0,
    this.tavukYemi = 0,
    double? toplam,
  }) : toplam = toplam ?? (sutYemi + besiYemi + bBaslangic + bBuyutme + kuzuYemi + tavukYemi);

  factory Yem.fromMap(Map<String, dynamic> m) => Yem(
    id: m['id'] as int?,
    cariId: m['cari_id'],
    tarih: m['tarih'],
    sutYemi: (m['sut_yemi'] ?? 0).toDouble(),
    besiYemi: (m['besi_yemi'] ?? 0).toDouble(),
    bBaslangic: (m['b_baslangic'] ?? 0).toDouble(),
    bBuyutme: (m['b_buyutme'] ?? 0).toDouble(),
    kuzuYemi: (m['kuzu_yemi'] ?? 0).toDouble(),
    tavukYemi: (m['tavuk_yemi'] ?? 0).toDouble(),
    toplam: (m['toplam'] ?? 0).toDouble(),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'cari_id': cariId,
    'tarih': tarih,
    'sut_yemi': sutYemi,
    'besi_yemi': besiYemi,
    'b_baslangic': bBaslangic,
    'b_buyutme': bBuyutme,
    'kuzu_yemi': kuzuYemi,
    'tavuk_yemi': tavukYemi,
    'toplam': sutYemi + besiYemi + bBaslangic + bBuyutme + kuzuYemi + tavukYemi,
  };
}
