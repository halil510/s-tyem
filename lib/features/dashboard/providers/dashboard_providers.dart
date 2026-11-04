import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/veri_surumu_provider.dart';
import '../../../models/cari_model.dart';
import '../../../models/sut_model.dart';
import '../../cari_hesap/providers/cari_hesap_providers.dart'
    show tumKalanBorclarProvider;
import '../../donem/donem_providers.dart';

/// Bir günün toplam süt miktarı (haftalık grafik için).
@immutable
class GunlukSutVerisi {
  final String gunEtiketi; // örn. 'Pzt'
  final double miktar;
  const GunlukSutVerisi(this.gunEtiketi, this.miktar);
}

/// Bir carinin bu ayki toplam süt miktarı (en çok süt veren liste için).
@immutable
class CariSutVerisi {
  final String cariAdi;
  final double miktar;
  const CariSutVerisi(this.cariAdi, this.miktar);
}

/// Bir yem türünün bu ayki toplam miktarı (dağılım grafiği için).
@immutable
class YemTuruVerisi {
  final String tur;
  final double miktar;
  const YemTuruVerisi(this.tur, this.miktar);
}

/// Dashboard ekranının ihtiyaç duyduğu tüm KPI ve grafik verilerini
/// tek bir yerde toplayan, değişmez (immutable) veri sınıfı.
@immutable
class DashboardData {
  final int toplamCari;
  final double bugunToplamSut;
  final double bugunSabah;
  final double bugunAksam;
  final double dunToplamSut;

  /// Bugün kaydı olan üretici sayısı.
  final int bugunGelenSayisi;

  /// Düzenli getirip bugün henüz gelmeyenler (bkz. [gelmeyenUreticiler]).
  final List<Cari> gelmeyenler;

  /// Geçen ay hareket var ama dönem kapatılmamışsa o ay ('yyyy-MM').
  final String? kapanmamisGecenAy;
  final double bugunToplamYem;
  final double aylikToplamSut;
  final double aylikToplamYem;
  final double odenecekTutar;
  final double tahsilEdilecekTutar;
  final List<GunlukSutVerisi> haftalikSutGrafik;
  final List<CariSutVerisi> enCokSutVerenCariler;
  final List<YemTuruVerisi> yemDagilimi;

  const DashboardData({
    required this.toplamCari,
    required this.bugunToplamSut,
    this.bugunSabah = 0,
    this.bugunAksam = 0,
    this.dunToplamSut = 0,
    this.bugunGelenSayisi = 0,
    this.gelmeyenler = const [],
    this.kapanmamisGecenAy,
    required this.bugunToplamYem,
    required this.aylikToplamSut,
    required this.aylikToplamYem,
    required this.odenecekTutar,
    required this.tahsilEdilecekTutar,
    required this.haftalikSutGrafik,
    required this.enCokSutVerenCariler,
    required this.yemDagilimi,
  });
}

/// Bugün süt getirmesi beklenen ama henüz kaydı olmayan üreticiler.
///
/// "Düzenli üretici": aktif ve son [gunSayisi] günde (bugün hariç) en az bir
/// kez süt getirmiş cari. Bugün kaydı olan (sabah ya da akşam) listeye girmez.
/// Ada göre sıralı döner.
List<Cari> gelmeyenUreticiler({
  required List<Cari> aktifCariler,
  required List<Sut> sonSutler,
  required DateTime bugun,
  int gunSayisi = 14,
}) {
  final f = DateFormat('yyyy-MM-dd');
  final bugunStr = f.format(bugun);
  final basStr =
      f.format(DateTime(bugun.year, bugun.month, bugun.day - gunSayisi));
  final duzenli = <int>{};
  final bugunGelen = <int>{};
  for (final s in sonSutler) {
    if (s.toplam <= 0) continue;
    if (s.tarih == bugunStr) {
      bugunGelen.add(s.cariId);
    } else if (s.tarih.compareTo(basStr) >= 0 &&
        s.tarih.compareTo(bugunStr) < 0) {
      duzenli.add(s.cariId);
    }
  }
  return aktifCariler
      .where((c) =>
          c.id != null && duzenli.contains(c.id) && !bugunGelen.contains(c.id))
      .toList()
    ..sort((a, b) => a.tamAd.toLowerCase().compareTo(b.tamAd.toLowerCase()));
}

/// Dashboard'un tüm verilerini tek seferde, verimli sorgularla hesaplayan
/// provider.
///
/// Eski ekran, "en çok süt veren cariler" ve "bekleyen borç" için HER
/// cari başına ayrı ayrı sorgu atıyordu (N+1 sorgu problemi). Burada
/// bunun yerine:
/// - Süt/yem toplamları tek bir aralık sorgusuyla çekilip Dart tarafında
///   gruplanıyor.
/// - Kalan borçlar, `tumKalanBorclarProvider` (canlı süt/yem + kayıtlı
///   ödeme/tahsilat birleşimi) üzerinden hesaplanıyor — Ödemeler
///   sekmesiyle AYNI kaynak, tutarsız rakam göstermeyi önlüyor.
final dashboardDataProvider = FutureProvider<DashboardData>((ref) async {
  ref.watch(veriSurumuProvider);
  final cariRepo = await ref.watch(cariRepositoryProvider.future);
  final sutRepo = await ref.watch(sutRepositoryProvider.future);
  final yemRepo = await ref.watch(yemRepositoryProvider.future);

  final bugun = DateTime.now();
  final bugunStr = DateFormat('yyyy-MM-dd').format(bugun);
  final ayBaslangic = DateTime(bugun.year, bugun.month, 1);
  final ayBitis = DateTime(bugun.year, bugun.month + 1, 0);
  final ayBasStr = DateFormat('yyyy-MM-dd').format(ayBaslangic);
  final ayBitStr = DateFormat('yyyy-MM-dd').format(ayBitis);
  final haftaBasStr =
      DateFormat('yyyy-MM-dd').format(bugun.subtract(const Duration(days: 6)));
  final dunStr = DateFormat('yyyy-MM-dd')
      .format(DateTime(bugun.year, bugun.month, bugun.day - 1));
  final sonIkiHaftaStr = DateFormat('yyyy-MM-dd')
      .format(DateTime(bugun.year, bugun.month, bugun.day - 14));

  final cariler = await cariRepo.getAll(sadeceAktif: true);
  final cariAdMap = {for (final c in cariler) c.id!: c.tamAd};

  // Tek sorguda bu ayın tüm süt/yem kayıtlarını çek, geri kalanını
  // bellekte grupla.
  final aylikSutler = await sutRepo.getAllInRange(ayBasStr, ayBitStr);
  final aylikYemler = await yemRepo.getAllInRange(ayBasStr, ayBitStr);
  final haftalikSutler = await sutRepo.getAllInRange(haftaBasStr, bugunStr);
  final sonSutler = await sutRepo.getAllInRange(sonIkiHaftaStr, bugunStr);
  final bugunSutler = sonSutler.where((s) => s.tarih == bugunStr).toList();
  final bugunSabah = bugunSutler.fold(0.0, (t, s) => t + s.sabah);
  final bugunAksam = bugunSutler.fold(0.0, (t, s) => t + s.aksam);
  final dunToplamSut = sonSutler
      .where((s) => s.tarih == dunStr)
      .fold(0.0, (t, s) => t + s.toplam);
  final bugunGelenSayisi = bugunSutler
      .where((s) => s.toplam > 0)
      .map((s) => s.cariId)
      .toSet()
      .length;
  final gelmeyenler = gelmeyenUreticiler(
      aktifCariler: cariler, sonSutler: sonSutler, bugun: bugun);

  // Geçen ayın dönemi kapatılmamışsa hatırlat.
  final gecenAy =
      DateFormat('yyyy-MM').format(DateTime(bugun.year, bugun.month - 1));
  final donemServisi = await ref.watch(donemServisiProvider.future);
  final kapanmamisGecenAy =
      await sutRepo.kayitVarMi('$gecenAy-01', '$gecenAy-31') &&
              !await donemServisi.kapaliMi(gecenAy)
          ? gecenAy
          : null;

  final bugunToplamSut = aylikSutler
      .where((s) => s.tarih == bugunStr)
      .fold(0.0, (sum, s) => sum + s.toplam);
  final bugunToplamYem = aylikYemler
      .where((y) => y.tarih == bugunStr)
      .fold(0.0, (sum, y) => sum + y.toplam);
  final aylikToplamSut = aylikSutler.fold(0.0, (sum, s) => sum + s.toplam);
  final aylikToplamYem = aylikYemler.fold(0.0, (sum, y) => sum + y.toplam);

  // Son 7 gün — güne göre grupla.
  final haftalikSutGrafik = <GunlukSutVerisi>[];
  for (int i = 6; i >= 0; i--) {
    final gun = bugun.subtract(Duration(days: i));
    final gunStr = DateFormat('yyyy-MM-dd').format(gun);
    final toplam = haftalikSutler
        .where((s) => s.tarih == gunStr)
        .fold(0.0, (sum, s) => sum + s.toplam);
    haftalikSutGrafik
        .add(GunlukSutVerisi(DateFormat('E', 'tr_TR').format(gun), toplam));
  }

  // En çok süt veren 5 cari (bu ay) — bellekte grupla.
  final cariBazliSutToplam = <int, double>{};
  for (final s in aylikSutler) {
    cariBazliSutToplam[s.cariId] =
        (cariBazliSutToplam[s.cariId] ?? 0) + s.toplam;
  }
  final enCokSutVerenCariler = cariBazliSutToplam.entries
      .where((e) => e.value > 0 && cariAdMap.containsKey(e.key))
      .map((e) => CariSutVerisi(cariAdMap[e.key]!, e.value))
      .toList()
    ..sort((a, b) => b.miktar.compareTo(a.miktar));
  final ilkBes = enCokSutVerenCariler.take(5).toList();

  // Yem dağılımı (bu ay).
  double sutYemiTop = 0,
      besiYemiTop = 0,
      buzagiTop = 0,
      kuzuYemiTop = 0,
      tavukYemiTop = 0;
  for (final y in aylikYemler) {
    sutYemiTop += y.sutYemi;
    besiYemiTop += y.besiYemi;
    buzagiTop += y.bBaslangic + y.bBuyutme;
    kuzuYemiTop += y.kuzuYemi;
    tavukYemiTop += y.tavukYemi;
  }
  final yemDagilimi = <YemTuruVerisi>[
    if (sutYemiTop > 0) YemTuruVerisi('Süt', sutYemiTop),
    if (besiYemiTop > 0) YemTuruVerisi('Besi', besiYemiTop),
    if (buzagiTop > 0) YemTuruVerisi('Buzağı', buzagiTop),
    if (kuzuYemiTop > 0) YemTuruVerisi('Kuzu', kuzuYemiTop),
    if (tavukYemiTop > 0) YemTuruVerisi('Tavuk', tavukYemiTop),
  ];

  // Cari bakiyeleri — Ödemeler sekmesiyle AYNI kaynaktan (canlı
  // hesaplama), tutarsız rakam göstermeyi önlemek için.
  // Pozitif bakiye = cari alacaklı (işletme ÖDEYECEK).
  // Negatif bakiye = cari borçlu (işletme TAHSİL EDECEK).
  final kalanBorclar = await ref.watch(tumKalanBorclarProvider.future);
  const epsilon =
      0.005; // Bakiyeler kuruşa yuvarlı; Ödemeler sekmesiyle aynı eşik
  final odenecekTutar =
      kalanBorclar.values.fold(0.0, (sum, v) => sum + (v > epsilon ? v : 0));
  final tahsilEdilecekTutar =
      kalanBorclar.values.fold(0.0, (sum, v) => sum + (v < -epsilon ? -v : 0));

  return DashboardData(
    toplamCari: cariler.length,
    bugunToplamSut: bugunToplamSut,
    bugunSabah: bugunSabah,
    bugunAksam: bugunAksam,
    dunToplamSut: dunToplamSut,
    bugunGelenSayisi: bugunGelenSayisi,
    gelmeyenler: gelmeyenler,
    kapanmamisGecenAy: kapanmamisGecenAy,
    bugunToplamYem: bugunToplamYem,
    aylikToplamSut: aylikToplamSut,
    aylikToplamYem: aylikToplamYem,
    odenecekTutar: odenecekTutar,
    tahsilEdilecekTutar: tahsilEdilecekTutar,
    haftalikSutGrafik: haftalikSutGrafik,
    enCokSutVerenCariler: ilkBes,
    yemDagilimi: yemDagilimi,
  );
});
