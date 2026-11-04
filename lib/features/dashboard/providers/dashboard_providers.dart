import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/veri_surumu_provider.dart';
import '../../cari_hesap/providers/cari_hesap_providers.dart' show tumKalanBorclarProvider;

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
  final haftaBasStr = DateFormat('yyyy-MM-dd').format(bugun.subtract(const Duration(days: 6)));

  final cariler = await cariRepo.getAll(sadeceAktif: true);
  final cariAdMap = {for (final c in cariler) c.id!: c.tamAd};

  // Tek sorguda bu ayın tüm süt/yem kayıtlarını çek, geri kalanını
  // bellekte grupla.
  final aylikSutler = await sutRepo.getAllInRange(ayBasStr, ayBitStr);
  final aylikYemler = await yemRepo.getAllInRange(ayBasStr, ayBitStr);
  final haftalikSutler = await sutRepo.getAllInRange(haftaBasStr, bugunStr);

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
    haftalikSutGrafik.add(GunlukSutVerisi(DateFormat('E', 'tr_TR').format(gun), toplam));
  }

  // En çok süt veren 5 cari (bu ay) — bellekte grupla.
  final cariBazliSutToplam = <int, double>{};
  for (final s in aylikSutler) {
    cariBazliSutToplam[s.cariId] = (cariBazliSutToplam[s.cariId] ?? 0) + s.toplam;
  }
  final enCokSutVerenCariler = cariBazliSutToplam.entries
      .where((e) => e.value > 0 && cariAdMap.containsKey(e.key))
      .map((e) => CariSutVerisi(cariAdMap[e.key]!, e.value))
      .toList()
    ..sort((a, b) => b.miktar.compareTo(a.miktar));
  final ilkBes = enCokSutVerenCariler.take(5).toList();

  // Yem dağılımı (bu ay).
  double sutYemiTop = 0, besiYemiTop = 0, kuzuYemiTop = 0, tavukYemiTop = 0;
  for (final y in aylikYemler) {
    sutYemiTop += y.sutYemi;
    besiYemiTop += y.besiYemi + y.bBaslangic + y.bBuyutme;
    kuzuYemiTop += y.kuzuYemi;
    tavukYemiTop += y.tavukYemi;
  }
  final yemDagilimi = <YemTuruVerisi>[
    if (sutYemiTop > 0) YemTuruVerisi('Süt', sutYemiTop),
    if (besiYemiTop > 0) YemTuruVerisi('Besi', besiYemiTop),
    if (kuzuYemiTop > 0) YemTuruVerisi('Kuzu', kuzuYemiTop),
    if (tavukYemiTop > 0) YemTuruVerisi('Tavuk', tavukYemiTop),
  ];

  // Cari bakiyeleri — Ödemeler sekmesiyle AYNI kaynaktan (canlı
  // hesaplama), tutarsız rakam göstermeyi önlemek için.
  // Pozitif bakiye = cari alacaklı (işletme ÖDEYECEK).
  // Negatif bakiye = cari borçlu (işletme TAHSİL EDECEK).
  final kalanBorclar = await ref.watch(tumKalanBorclarProvider.future);
  const epsilon = 0.005; // Bakiyeler kuruşa yuvarlı; Ödemeler sekmesiyle aynı eşik
  final odenecekTutar = kalanBorclar.values.fold(0.0, (sum, v) => sum + (v > epsilon ? v : 0));
  final tahsilEdilecekTutar = kalanBorclar.values.fold(0.0, (sum, v) => sum + (v < -epsilon ? -v : 0));

  return DashboardData(
    toplamCari: cariler.length,
    bugunToplamSut: bugunToplamSut,
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
