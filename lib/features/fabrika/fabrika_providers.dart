import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/providers/veri_surumu_provider.dart';
import '../../models/fabrika_model.dart';
import 'fabrika_hesap.dart';

/// Ay ('yyyy-MM') → ilk ve son gün.
(DateTime, DateTime) ayAraligi(String ay) {
  final p = ay.split('-');
  final y = int.parse(p[0]), m = int.parse(p[1]);
  return (DateTime(y, m, 1), DateTime(y, m + 1, 0));
}

/// Pasifler dahil tüm fabrikalar (aktifler önce).
final fabrikalarProvider = FutureProvider.autoDispose<List<Fabrika>>((ref) async {
  ref.watch(veriSurumuProvider);
  final repo = await ref.watch(fabrikaRepositoryProvider.future);
  return repo.fabrikalar();
});

/// Fabrika id → güncel bakiye (> 0: fabrika bize borçlu).
final fabrikaBakiyeleriProvider = FutureProvider.autoDispose<Map<int, double>>((ref) async {
  ref.watch(veriSurumuProvider);
  final repo = await ref.watch(fabrikaRepositoryProvider.future);
  return repo.bakiyeler();
});

class FireAyi {
  final List<FireGunu> gunler;

  /// Ayın tüm günleri (bugün dahil).
  final FireOzeti ozet;

  /// Bugün hariç (gün bitmeden fark kesinleşmez); bu ay değilse [ozet] ile aynı.
  final FireOzeti kesinOzet;

  const FireAyi(this.gunler, this.ozet, this.kesinOzet);
}

/// [ay] için gün gün toplanan / sevk / tank / fark. Bu ay ise bugüne kadar.
final fireAyiProvider = FutureProvider.autoDispose.family<FireAyi, String>((ref, ay) async {
  ref.watch(veriSurumuProvider);
  final bugun = ref.watch(bugunProvider).valueOrNull ?? DateTime.now();
  final fabrika = await ref.watch(fabrikaRepositoryProvider.future);
  final sut = await ref.watch(sutRepositoryProvider.future);

  final (bas, aySonu) = ayAraligi(ay);
  final son = aySonu.isAfter(bugun) ? DateTime(bugun.year, bugun.month, bugun.day) : aySonu;
  if (son.isBefore(bas)) {
    final bos = FireOzeti.hesapla(const []);
    return FireAyi(const [], bos, bos);
  }
  final b = gunAnahtari(bas), s = gunAnahtari(son);
  final gunler = fireGunleri(
    bas: bas,
    son: son,
    toplanan: await sut.gunlukToplamlar(b, s),
    sevk: await fabrika.gunlukSevkToplamlari(b, s),
    tank: await fabrika.tankSayimlari(gunAnahtari(DateTime(bas.year, bas.month, bas.day - 1)), s),
    bugun: gunAnahtari(bugun),
  );
  return FireAyi(gunler, FireOzeti.hesapla(gunler), FireOzeti.hesapla(gunler.where((g) => !g.bugun).toList()));
});

/// [ay] içindeki tüm sevkiyatlar (tüm fabrikalar).
final ayinSevkiyatlariProvider = FutureProvider.autoDispose.family<List<Sevkiyat>, String>((ref, ay) async {
  ref.watch(veriSurumuProvider);
  final repo = await ref.watch(fabrikaRepositoryProvider.future);
  final (bas, son) = ayAraligi(ay);
  return repo.sevkiyatlar(gunAnahtari(bas), gunAnahtari(son));
});

/// Bir fabrikanın [ay] ekstresi (devir, satırlar, yürüyen bakiye).
final fabrikaEkstresiProvider =
    FutureProvider.autoDispose.family<FabrikaEkstresi, ({int fabrikaId, String ay})>((ref, a) async {
  ref.watch(veriSurumuProvider);
  final repo = await ref.watch(fabrikaRepositoryProvider.future);
  final (bas, son) = ayAraligi(a.ay);
  return fabrikaEkstresi(
    sevkiyatlar: await repo.fabrikaSevkiyatlari(a.fabrikaId),
    hareketler: await repo.fabrikaHareketleri(a.fabrikaId),
    bas: gunAnahtari(bas),
    son: gunAnahtari(son),
  );
});
