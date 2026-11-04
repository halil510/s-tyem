class Sut {
  int? id;
  int cariId;
  String tarih; // ISO string
  double sabah;
  double aksam;
  double toplam;

  Sut({
    this.id,
    required this.cariId,
    required this.tarih,
    this.sabah = 0,
    this.aksam = 0,
    double? toplam,
  }) : toplam = toplam ?? (sabah + aksam);

  factory Sut.fromMap(Map<String, dynamic> m) => Sut(
    id: m['id'] as int?,
    cariId: m['cari_id'],
    tarih: m['tarih'],
    sabah: (m['sabah'] ?? 0).toDouble(),
    aksam: (m['aksam'] ?? 0).toDouble(),
    toplam: (m['toplam'] ?? 0).toDouble(),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'cari_id': cariId,
    'tarih': tarih,
    'sabah': sabah,
    'aksam': aksam,
    'toplam': sabah + aksam,
  };
}
