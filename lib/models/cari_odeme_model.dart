import 'dart:convert';

class OdemeDetay {
  final double sutMiktar;
  final double sutFiyat;
  final double sutYemiMiktar;
  final double sutYemiFiyat;
  final double besiYemiMiktar;
  final double besiYemiFiyat;
  final double bBaslangicMiktar;
  final double bBaslangicFiyat;
  final double bBuyutmeMiktar;
  final double bBuyutmeFiyat;
  final double kuzuYemiMiktar;
  final double kuzuYemiFiyat;
  final double tavukYemiMiktar;
  final double tavukYemiFiyat;

  OdemeDetay({
    this.sutMiktar = 0, this.sutFiyat = 0,
    this.sutYemiMiktar = 0, this.sutYemiFiyat = 0,
    this.besiYemiMiktar = 0, this.besiYemiFiyat = 0,
    this.bBaslangicMiktar = 0, this.bBaslangicFiyat = 0,
    this.bBuyutmeMiktar = 0, this.bBuyutmeFiyat = 0,
    this.kuzuYemiMiktar = 0, this.kuzuYemiFiyat = 0,
    this.tavukYemiMiktar = 0, this.tavukYemiFiyat = 0,
  });

  factory OdemeDetay.fromJson(Map<String, dynamic> j) => OdemeDetay(
    sutMiktar: (j['sut_miktar'] as num?)?.toDouble() ?? 0,
    sutFiyat: (j['sut_fiyat'] as num?)?.toDouble() ?? 0,
    sutYemiMiktar: (j['sut_yemi_miktar'] as num?)?.toDouble() ?? 0,
    sutYemiFiyat: (j['sut_yemi_fiyat'] as num?)?.toDouble() ?? 0,
    besiYemiMiktar: (j['besi_yemi_miktar'] as num?)?.toDouble() ?? 0,
    besiYemiFiyat: (j['besi_yemi_fiyat'] as num?)?.toDouble() ?? 0,
    bBaslangicMiktar: (j['b_baslangic_miktar'] as num?)?.toDouble() ?? 0,
    bBaslangicFiyat: (j['b_baslangic_fiyat'] as num?)?.toDouble() ?? 0,
    bBuyutmeMiktar: (j['b_buyutme_miktar'] as num?)?.toDouble() ?? 0,
    bBuyutmeFiyat: (j['b_buyutme_fiyat'] as num?)?.toDouble() ?? 0,
    kuzuYemiMiktar: (j['kuzu_yemi_miktar'] as num?)?.toDouble() ?? 0,
    kuzuYemiFiyat: (j['kuzu_yemi_fiyat'] as num?)?.toDouble() ?? 0,
    tavukYemiMiktar: (j['tavuk_yemi_miktar'] as num?)?.toDouble() ?? 0,
    tavukYemiFiyat: (j['tavuk_yemi_fiyat'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'sut_miktar': sutMiktar, 'sut_fiyat': sutFiyat,
    'sut_yemi_miktar': sutYemiMiktar, 'sut_yemi_fiyat': sutYemiFiyat,
    'besi_yemi_miktar': besiYemiMiktar, 'besi_yemi_fiyat': besiYemiFiyat,
    'b_baslangic_miktar': bBaslangicMiktar, 'b_baslangic_fiyat': bBaslangicFiyat,
    'b_buyutme_miktar': bBuyutmeMiktar, 'b_buyutme_fiyat': bBuyutmeFiyat,
    'kuzu_yemi_miktar': kuzuYemiMiktar, 'kuzu_yemi_fiyat': kuzuYemiFiyat,
    'tavuk_yemi_miktar': tavukYemiMiktar, 'tavuk_yemi_fiyat': tavukYemiFiyat,
  };

  // Kalem kalem liste (0 olanları atla)
  List<Map<String, dynamic>> get kalemler {
    final list = <Map<String, dynamic>>[];
    if (sutMiktar > 0) list.add({'ad': 'Süt', 'miktar': sutMiktar, 'fiyat': sutFiyat, 'toplam': sutMiktar * sutFiyat, 'birim': 'kg'});
    if (sutYemiMiktar > 0) list.add({'ad': 'Süt Yemi', 'miktar': sutYemiMiktar, 'fiyat': sutYemiFiyat, 'toplam': sutYemiMiktar * sutYemiFiyat, 'birim': 'kg'});
    if (besiYemiMiktar > 0) list.add({'ad': 'Besi Yemi', 'miktar': besiYemiMiktar, 'fiyat': besiYemiFiyat, 'toplam': besiYemiMiktar * besiYemiFiyat, 'birim': 'kg'});
    if (bBaslangicMiktar > 0) list.add({'ad': 'B. Başlangıç', 'miktar': bBaslangicMiktar, 'fiyat': bBaslangicFiyat, 'toplam': bBaslangicMiktar * bBaslangicFiyat, 'birim': 'kg'});
    if (bBuyutmeMiktar > 0) list.add({'ad': 'B. Büyütme', 'miktar': bBuyutmeMiktar, 'fiyat': bBuyutmeFiyat, 'toplam': bBuyutmeMiktar * bBuyutmeFiyat, 'birim': 'kg'});
    if (kuzuYemiMiktar > 0) list.add({'ad': 'Kuzu Yemi', 'miktar': kuzuYemiMiktar, 'fiyat': kuzuYemiFiyat, 'toplam': kuzuYemiMiktar * kuzuYemiFiyat, 'birim': 'kg'});
    if (tavukYemiMiktar > 0) list.add({'ad': 'Tavuk Yemi', 'miktar': tavukYemiMiktar, 'fiyat': tavukYemiFiyat, 'toplam': tavukYemiMiktar * tavukYemiFiyat, 'birim': 'kg'});
    return list;
  }
}

class CariOdeme {
  int? id;
  int cariId;
  String tarih;

  /// 'sut' (kredi, +) · 'yem' (borç, -) · 'odeme' (borç, -) ·
  /// 'tahsilat' (kredi, +) · eski kayıtlar için 'alim' de 'sut' ile
  /// aynı (kredi) sayılır. Bkz. CariOdemeRepository doc yorumu.
  String islemTuru;
  double miktar;
  double birimFiyat;
  double toplamTutar;
  double odenenTutar;
  double kalanTutar;
  String? aciklama;
  String? detayJson; // OdemeDetay JSON
  String? vadeTarihi; // ISO yyyy-MM-dd (opsiyonel, ileride kullanım için)

  CariOdeme({
    this.id,
    required this.cariId,
    required this.tarih,
    required this.islemTuru,
    required this.miktar,
    required this.birimFiyat,
    required this.toplamTutar,
    this.odenenTutar = 0,
    this.kalanTutar = 0,
    this.aciklama,
    this.detayJson,
    this.vadeTarihi,
  });

  /// Bu hareket cariye KREDİ mi yazıyor (işletme cariye borçlanıyor)?
  /// Süt alımı ve tahsilat böyledir.
  bool get krediMi => islemTuru == 'sut' || islemTuru == 'alim' || islemTuru == 'tahsilat';

  /// Bu hareket cariyi BORÇLANDIRIYOR mu (cari işletmeye borçlanıyor)?
  /// Yem verişi ve nakit ödeme böyledir.
  bool get borcMi => islemTuru == 'yem' || islemTuru == 'odeme';

  /// Bakiyeye katkısı: kredi ise +toplamTutar, borç ise -toplamTutar.
  double get bakiyeyeEtki => krediMi ? toplamTutar : -toplamTutar;

  /// Ekranda gösterilecek insan-okur işlem adı.
  String get islemAdi => switch (islemTuru) {
    'sut' || 'alim' => 'Süt Alımı',
    'yem' => 'Yem Verişi',
    'odeme' => 'Ödeme (Cariye)',
    'tahsilat' => 'Tahsilat (Cariden)',
    _ => islemTuru,
  };

  OdemeDetay? get detay {
    if (detayJson == null || detayJson!.isEmpty) return null;
    try { return OdemeDetay.fromJson(jsonDecode(detayJson!)); } catch (_) { return null; }
  }

  factory CariOdeme.fromMap(Map<String, dynamic> map) => CariOdeme(
    id: map['id'] as int?,
    cariId: map['cari_id'] as int,
    tarih: map['tarih'] as String,
    islemTuru: map['islem_turu'] as String,
    miktar: (map['miktar'] as num).toDouble(),
    birimFiyat: (map['birim_fiyat'] as num).toDouble(),
    toplamTutar: (map['toplam_tutar'] as num).toDouble(),
    odenenTutar: (map['odenen_tutar'] as num?)?.toDouble() ?? 0,
    kalanTutar: (map['kalan_tutar'] as num?)?.toDouble() ?? 0,
    aciklama: map['aciklama'] as String?,
    detayJson: map['detay_json'] as String?,
    vadeTarihi: map['vade_tarihi'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'cari_id': cariId,
    'tarih': tarih,
    'islem_turu': islemTuru,
    'miktar': miktar,
    'birim_fiyat': birimFiyat,
    'toplam_tutar': toplamTutar,
    'odenen_tutar': odenenTutar,
    'kalan_tutar': kalanTutar,
    'aciklama': aciklama,
    'detay_json': detayJson,
    'vade_tarihi': vadeTarihi,
  };
}
