/// Bir yem / ürün verişi: TEK ürün + miktar (migration v16).
///
/// Bir teslimatta birden çok ürün verildiyse her ürün ayrı satırdır
/// (Yem Ekle ekranı hepsini tek transaction'da yazar). Ürünün adı ve birimi
/// `urunler` tablosundadır ([urunId]); tutar = miktar × o günün cari ürün fiyatı.
///
/// Eski 6 sütun (sut_yemi, besi_yemi…) tabloda durur ama okunmaz/yazılmaz.
class Yem {
  int? id;
  int cariId;
  String tarih;
  int urunId;
  double miktar;

  Yem({
    this.id,
    required this.cariId,
    required this.tarih,
    required this.urunId,
    required this.miktar,
  });

  /// Geriye dönük ad: satırın miktarı (ürünün kendi biriminde).
  double get toplam => miktar;

  factory Yem.fromMap(Map<String, dynamic> m) => Yem(
        id: m['id'] as int?,
        cariId: m['cari_id'] as int,
        tarih: m['tarih'] as String,
        urunId: (m['urun_id'] as int?) ?? 0,
        miktar: (m['miktar'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'cari_id': cariId,
        'tarih': tarih,
        'urun_id': urunId,
        'miktar': miktar,
        'toplam': miktar,
      };
}
