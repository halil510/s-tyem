import '../utils/sayi_format.dart';

/// Sütün teslim edildiği fabrika (migration v15).
class Fabrika {
  final int? id;
  final String ad;
  final String? telefon;
  final String? adres;
  final String? notMetni;
  final bool aktif;

  const Fabrika({this.id, required this.ad, this.telefon, this.adres, this.notMetni, this.aktif = true});

  factory Fabrika.fromMap(Map<String, Object?> m) => Fabrika(
        id: m['id'] as int?,
        ad: (m['ad'] as String?) ?? '',
        telefon: m['telefon'] as String?,
        adres: m['adres'] as String?,
        notMetni: m['not_metni'] as String?,
        aktif: ((m['aktif'] as int?) ?? 1) == 1,
      );

  /// `id` ve `uuid` YOK: uuid'yi tetikleyici verir, güncellemede korunur.
  Map<String, Object?> toMap() => {
        'ad': ad,
        'telefon': telefon,
        'adres': adres,
        'not_metni': notMetni,
        'aktif': aktif ? 1 : 0,
      };

  Fabrika copyWith({bool? aktif}) =>
      Fabrika(id: id, ad: ad, telefon: telefon, adres: adres, notMetni: notMetni, aktif: aktif ?? this.aktif);
}

/// Fabrikaya bir süt teslimi.
class Sevkiyat {
  final int? id;
  final int fabrikaId;
  final String tarih; // yyyy-MM-dd
  final String? saat; // HH:mm
  final double kg;

  /// ₺/kg. 0 = fiyat henüz belli değil (tutar 0 sayılır, ekranda uyarı).
  final double birimFiyat;
  final String? fisNo;
  final String? plaka;
  final String? aciklama;

  const Sevkiyat({
    this.id,
    required this.fabrikaId,
    required this.tarih,
    this.saat,
    required this.kg,
    this.birimFiyat = 0,
    this.fisNo,
    this.plaka,
    this.aciklama,
  });

  /// Satır tutarı kuruşa yuvarlanır (ekstrede satırlar toplamı = genel toplam).
  double get tutar => kurusaYuvarla(kg * birimFiyat);
  bool get fiyatsiz => birimFiyat <= 0;

  factory Sevkiyat.fromMap(Map<String, Object?> m) => Sevkiyat(
        id: m['id'] as int?,
        fabrikaId: m['fabrika_id'] as int,
        tarih: m['tarih'] as String,
        saat: m['saat'] as String?,
        kg: ((m['kg'] as num?) ?? 0).toDouble(),
        birimFiyat: ((m['birim_fiyat'] as num?) ?? 0).toDouble(),
        fisNo: m['fis_no'] as String?,
        plaka: m['plaka'] as String?,
        aciklama: m['aciklama'] as String?,
      );

  Map<String, Object?> toMap() => {
        'fabrika_id': fabrikaId,
        'tarih': tarih,
        'saat': saat,
        'kg': kg,
        'birim_fiyat': birimFiyat,
        'fis_no': fisNo,
        'plaka': plaka,
        'aciklama': aciklama,
      };
}

/// Fabrika cari hareketi türü.
enum FabrikaHareketTuru {
  /// Fabrikadan alınan ödeme → alacağımız AZALIR.
  tahsilat('tahsilat', 'Tahsilat (fabrikadan alınan)'),

  /// Fabrikanın kestiği tutar (kalite, nakliye, fire…) → alacağımız AZALIR.
  kesinti('kesinti', 'Kesinti (fabrikanın düştüğü)'),

  /// Fabrikanın eklediği tutar (prim, fiyat farkı…) → alacağımız ARTAR.
  ek('ek', 'Ek ödeme / prim');

  final String kod;
  final String ad;
  const FabrikaHareketTuru(this.kod, this.ad);

  static FabrikaHareketTuru coz(String kod) =>
      values.firstWhere((t) => t.kod == kod, orElse: () => throw ArgumentError.value(kod, 'tur'));

  /// Alacağı artıran tür mü? (ek) — tahsilat ve kesinti azaltır.
  bool get alacagiArtirir => this == ek;
}

class FabrikaHareketi {
  final int? id;
  final int fabrikaId;
  final String tarih; // yyyy-MM-dd
  final FabrikaHareketTuru tur;
  final double tutar; // her zaman > 0; yönü türünden gelir
  final String? aciklama;

  const FabrikaHareketi({
    this.id,
    required this.fabrikaId,
    required this.tarih,
    required this.tur,
    required this.tutar,
    this.aciklama,
  });

  /// Fabrika bakiyesine işaretli etkisi (+ alacak artar).
  double get etki => tur.alacagiArtirir ? tutar : -tutar;

  factory FabrikaHareketi.fromMap(Map<String, Object?> m) => FabrikaHareketi(
        id: m['id'] as int?,
        fabrikaId: m['fabrika_id'] as int,
        tarih: m['tarih'] as String,
        tur: FabrikaHareketTuru.coz(m['tur'] as String),
        tutar: ((m['tutar'] as num?) ?? 0).toDouble(),
        aciklama: m['aciklama'] as String?,
      );

  Map<String, Object?> toMap() => {
        'fabrika_id': fabrikaId,
        'tarih': tarih,
        'tur': tur.kod,
        'tutar': tutar,
        'aciklama': aciklama,
      };
}
