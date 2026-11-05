class Cari {
  int? id;
  String ad;
  String soyad;
  String? adres;
  String? telefon;
  String? hayvanTuru;
  bool aktif;
  String? notMetni;

  /// Süt toplama sırası (rota): 1, 2, 3… — null ise sırasız (en sonda).
  /// Yalnız `CariRepository.siraAta` / `rotaKaydet` ile değiştirilir.
  int? sira;

  Cari({
    this.id,
    required this.ad,
    required this.soyad,
    this.adres,
    this.telefon,
    this.hayvanTuru,
    this.aktif = true,
    this.notMetni,
    this.sira,
  });

  String get tamAd => '$ad $soyad'.trim();

  factory Cari.fromMap(Map<String, dynamic> m) => Cari(
    id: m['id'] as int?,
    ad: m['ad'] ?? '',
    soyad: m['soyad'] ?? '',
    adres: m['adres'],
    telefon: m['telefon'],
    hayvanTuru: m['hayvan_turu'],
    aktif: (m['aktif'] as int?) != 0,
    notMetni: m['not_metni'],
    sira: m['sira'] as int?,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'ad': ad,
    'soyad': soyad,
    'adres': adres,
    'telefon': telefon,
    'hayvan_turu': hayvanTuru,
    'aktif': aktif ? 1 : 0,
    'not_metni': notMetni,
    'sira': sira,
  };
}
