class Fiyat {
  int? id;
  String urunTuru; // 'sut' veya 'yem'
  double birimFiyat;
  String tarih;
  String? aciklama;

  Fiyat({
    this.id,
    required this.urunTuru,
    required this.birimFiyat,
    required this.tarih,
    this.aciklama,
  });

  factory Fiyat.fromMap(Map<String, dynamic> m) => Fiyat(
    id: m['id'] as int?,
    urunTuru: m['urun_turu'] as String,
    birimFiyat: (m['birim_fiyat'] as num).toDouble(),
    tarih: m['tarih'] as String,
    aciklama: m['aciklama'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'urun_turu': urunTuru,
    'birim_fiyat': birimFiyat,
    'tarih': tarih,
    'aciklama': aciklama,
  };
}
