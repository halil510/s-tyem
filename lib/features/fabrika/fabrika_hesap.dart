import 'package:intl/intl.dart';

import '../../models/fabrika_model.dart';
import '../../utils/sayi_format.dart';

/// ─────────────────────────────────────────────────────────────
/// TANK / FİRE ve FABRİKA EKSTRESİ hesapları — ekransız, test edilebilir.
/// ─────────────────────────────────────────────────────────────
///
/// FİRE (gün gün):
///   giren  = önceki gün sonu tankta kalan + o gün üreticilerden toplanan
///   çıkan  = o gün fabrikaya sevk edilen + gün sonu tankta kalan
///   fark   = giren − çıkan
///     fark > 0 → kayıp (fire, döküntü, tartı farkı) ya da sevk girilmemiş
///     fark < 0 → toplanandan FAZLA sevk: büyük ihtimalle bir üreticinin sütü girilmemiş
/// Tank sayımı girilmemiş gün "tank boş" sayılır. Aylık fark, günlük farkların toplamıdır
/// (tank devri gün gün birbirini götürür) → ay özeti ile satırlar her zaman tutarlıdır.

/// Bu yüzdeyi aşan kayıp uyarı verir.
const fireUyariYuzde = 1.0;

/// Bu kadar kg'lık fark (tartı yuvarlaması) uyarı sayılmaz.
const farkToleransKg = 2.0;

enum FireDurumu {
  /// Fark tolerans içinde.
  normal,

  /// Kayıp eşiği aştı.
  fire,

  /// Toplanandan fazla sevk: süt girişi eksik olabilir.
  fazlaSevk,

  /// Bugün: gün bitmedi, fark kesin değil.
  suruyor,

  /// Bir gün kayıp, ERTESİ gün fazla sevk ve araya tank sayımı girilmemiş: süt büyük
  /// ihtimalle gece tankta kalıp ertesi gün sevk edildi. Alarm değil, "tankı girin" hatırlatması.
  tankGirilmemis,
}

class FireGunu {
  final String tarih;
  final double toplanan;
  final double sevk;
  final double tankOnceki;
  final double tankSonu;
  final bool bugun;

  /// [FireDurumu.tankGirilmemis] deseninin parçası (bkz. [fireGunleri]).
  final bool tankSupheli;

  const FireGunu({
    required this.tarih,
    required this.toplanan,
    required this.sevk,
    required this.tankOnceki,
    required this.tankSonu,
    this.bugun = false,
    this.tankSupheli = false,
  });

  FireGunu _supheli() => FireGunu(
      tarih: tarih, toplanan: toplanan, sevk: sevk, tankOnceki: tankOnceki, tankSonu: tankSonu, bugun: bugun, tankSupheli: true);

  double get giren => tankOnceki + toplanan;
  double get cikan => sevk + tankSonu;

  /// Kayan nokta artığı olmasın diye gram hassasiyetine yuvarlanır.
  double get fark => _gram(giren - cikan);

  /// Girenin yüzdesi olarak fark (giren 0 ise null).
  double? get yuzde => giren > 0 ? fark / giren * 100 : null;

  FireDurumu get durum {
    if (bugun) return FireDurumu.suruyor;
    if (tankSupheli) return FireDurumu.tankGirilmemis;
    return fireDurumu(fark, giren);
  }
}

/// Fark ve girene göre durum (gün ve dönem için aynı kural).
FireDurumu fireDurumu(double fark, double giren) {
  if (fark < -farkToleransKg) return FireDurumu.fazlaSevk;
  if (fark > farkToleransKg && (giren <= 0 || fark / giren * 100 > fireUyariYuzde)) return FireDurumu.fire;
  return FireDurumu.normal;
}

double _gram(double v) {
  final r = (v * 1000).roundToDouble() / 1000;
  return r == 0 ? 0 : r; // -0 gösterilmesin
}

final _gunBicimi = DateFormat('yyyy-MM-dd');
String gunAnahtari(DateTime d) => _gunBicimi.format(d);

/// [bas]..[son] (dahil) her gün için fire satırı. Hiç hareketi olmayan (toplanan, sevk ve
/// tank sıfır) günler atlanır. [tank], [bas]'tan BİR GÜN ÖNCESİNİ de içermelidir (devir).
List<FireGunu> fireGunleri({
  required DateTime bas,
  required DateTime son,
  required Map<String, double> toplanan,
  required Map<String, double> sevk,
  required Map<String, double> tank,
  required String bugun,
}) {
  final liste = <FireGunu>[];
  var onceki = gunAnahtari(DateTime(bas.year, bas.month, bas.day - 1));
  for (var d = DateTime(bas.year, bas.month, bas.day); !d.isAfter(son); d = DateTime(d.year, d.month, d.day + 1)) {
    final k = gunAnahtari(d);
    final g = FireGunu(
      tarih: k,
      toplanan: toplanan[k] ?? 0,
      sevk: sevk[k] ?? 0,
      tankOnceki: tank[onceki] ?? 0,
      tankSonu: tank[k] ?? 0,
      bugun: k == bugun,
    );
    onceki = k;
    if (g.toplanan == 0 && g.sevk == 0 && g.tankOnceki == 0 && g.tankSonu == 0) continue;
    liste.add(g);
  }
  // Tank deseni: d günü kayıp (gün sonu tank girilmemiş), d+1 günü fazla sevk → iki gün de
  // "tank girilmemiş?" (ertesi günün kendisi bugünse "sürüyor" kalır). Ay özeti etkilenmez.
  for (var i = 0; i + 1 < liste.length; i++) {
    final a = liste[i], b = liste[i + 1];
    final ardisik = gunAnahtari(DateTime.parse(a.tarih).add(const Duration(hours: 36))) == b.tarih;
    if (ardisik && !a.bugun && a.tankSonu == 0 && fireDurumu(a.fark, a.giren) == FireDurumu.fire && b.fark < -farkToleransKg) {
      liste[i] = a._supheli();
      liste[i + 1] = b._supheli();
    }
  }
  return liste;
}

/// Bir dönemin (ör. ay) tank/fire özeti — [gunler] [fireGunleri]'nden.
class FireOzeti {
  final double toplanan;
  final double sevk;
  final double tankBaslangic;
  final double tankSon;
  final int gunSayisi;

  const FireOzeti({
    required this.toplanan,
    required this.sevk,
    required this.tankBaslangic,
    required this.tankSon,
    required this.gunSayisi,
  });

  factory FireOzeti.hesapla(List<FireGunu> gunler) => FireOzeti(
        toplanan: gunler.fold(0.0, (t, g) => t + g.toplanan),
        sevk: gunler.fold(0.0, (t, g) => t + g.sevk),
        tankBaslangic: gunler.isEmpty ? 0 : gunler.first.tankOnceki,
        tankSon: gunler.isEmpty ? 0 : gunler.last.tankSonu,
        gunSayisi: gunler.length,
      );

  double get giren => tankBaslangic + toplanan;
  double get fark => _gram(giren - sevk - tankSon);
  double? get yuzde => giren > 0 ? fark / giren * 100 : null;
  FireDurumu get durum => fireDurumu(fark, giren);
}

// ───────────────────────────── FABRİKA EKSTRESİ ─────────────────────────────

class FabrikaEkstreSatiri {
  final String tarih;
  final Sevkiyat? sevkiyat;
  final FabrikaHareketi? hareket;

  /// Bakiyeye etkisi (+ alacak artar).
  final double etki;

  /// Satırdan sonraki yürüyen bakiye.
  final double bakiye;

  const FabrikaEkstreSatiri({required this.tarih, this.sevkiyat, this.hareket, required this.etki, required this.bakiye});
}

class FabrikaEkstresi {
  /// Dönem başından önceki bakiye.
  final double devir;
  final List<FabrikaEkstreSatiri> satirlar;
  final double sevkKg;
  final double sevkTutar;
  final double tahsilat;
  final double kesinti;
  final double ek;

  /// Dönemde fiyatı girilmemiş sevkiyat sayısı (tutarı 0 sayıldı).
  final int fiyatsizSayisi;

  const FabrikaEkstresi({
    required this.devir,
    required this.satirlar,
    required this.sevkKg,
    required this.sevkTutar,
    required this.tahsilat,
    required this.kesinti,
    required this.ek,
    required this.fiyatsizSayisi,
  });

  double get net => kurusaYuvarla(sevkTutar + ek - tahsilat - kesinti);
  double get sonBakiye => kurusaYuvarla(devir + net);
}

/// Fabrikanın [bas]..[son] ('yyyy-MM-dd', dahil) ekstresi. [sevkiyatlar] ve [hareketler]
/// fabrikanın TÜM kayıtlarıdır (devir onlardan hesaplanır); [son]'dan sonrakiler dışarıda kalır.
/// Aynı günde önce sevkiyatlar (saat sırasıyla), sonra ödemeler gelir.
FabrikaEkstresi fabrikaEkstresi({
  required List<Sevkiyat> sevkiyatlar,
  required List<FabrikaHareketi> hareketler,
  required String bas,
  required String son,
}) {
  var devir = 0.0;
  final donem = <(String, int, String, int, FabrikaEkstreSatiri Function(double))>[];
  for (final s in sevkiyatlar) {
    if (s.tarih.compareTo(bas) < 0) {
      devir += s.tutar;
    } else if (s.tarih.compareTo(son) <= 0) {
      donem.add((s.tarih, 0, s.saat ?? '', s.id ?? 0,
          (b) => FabrikaEkstreSatiri(tarih: s.tarih, sevkiyat: s, etki: s.tutar, bakiye: b)));
    }
  }
  for (final h in hareketler) {
    if (h.tarih.compareTo(bas) < 0) {
      devir += h.etki;
    } else if (h.tarih.compareTo(son) <= 0) {
      donem.add((h.tarih, 1, '', h.id ?? 0, (b) => FabrikaEkstreSatiri(tarih: h.tarih, hareket: h, etki: h.etki, bakiye: b)));
    }
  }
  donem.sort((a, b) {
    var c = a.$1.compareTo(b.$1);
    if (c != 0) return c;
    c = a.$2.compareTo(b.$2);
    if (c != 0) return c;
    c = a.$3.compareTo(b.$3);
    return c != 0 ? c : a.$4.compareTo(b.$4);
  });
  devir = kurusaYuvarla(devir);

  var bakiye = devir;
  var sevkKg = 0.0, sevkTutar = 0.0, tahsilat = 0.0, kesinti = 0.0, ek = 0.0;
  var fiyatsiz = 0;
  final satirlar = <FabrikaEkstreSatiri>[];
  for (final d in donem) {
    final satir0 = d.$5(0);
    bakiye = kurusaYuvarla(bakiye + satir0.etki);
    satirlar.add(d.$5(bakiye));
    final s = satir0.sevkiyat, h = satir0.hareket;
    if (s != null) {
      sevkKg += s.kg;
      sevkTutar += s.tutar;
      if (s.fiyatsiz) fiyatsiz++;
    } else if (h != null) {
      switch (h.tur) {
        case FabrikaHareketTuru.tahsilat:
          tahsilat += h.tutar;
        case FabrikaHareketTuru.kesinti:
          kesinti += h.tutar;
        case FabrikaHareketTuru.ek:
          ek += h.tutar;
      }
    }
  }
  return FabrikaEkstresi(
    devir: devir,
    satirlar: satirlar,
    sevkKg: _gram(sevkKg),
    sevkTutar: kurusaYuvarla(sevkTutar),
    tahsilat: kurusaYuvarla(tahsilat),
    kesinti: kurusaYuvarla(kesinti),
    ek: kurusaYuvarla(ek),
    fiyatsizSayisi: fiyatsiz,
  );
}
