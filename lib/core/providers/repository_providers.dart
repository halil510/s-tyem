import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database_provider.dart';
import '../../data/repositories/cari_repository.dart';
import '../../data/repositories/sut_repository.dart';
import '../../data/repositories/yem_repository.dart';
import '../../data/repositories/cari_odeme_repository.dart';
import '../../data/repositories/fiyat_repository.dart';
import '../../data/repositories/terazi_cihaz_repository.dart';
import '../../data/repositories/veri_yonetimi_repository.dart';

/// ─────────────────────────────────────────────────────────────
/// REPOSITORY PROVIDER'LARI
/// ─────────────────────────────────────────────────────────────
///
/// Her repository, veritabanı hazır olduğunda (migration'lar dahil)
/// bir kez oluşturulur. Ekranlar bu provider'ları `ref.watch(...)`
/// ile bekleyip `.when(data: ..., loading: ..., error: ...)` şeklinde
/// tüketir — ya da daha üstteki "feature" provider'ları üzerinden
/// dolaylı olarak kullanır.

final cariRepositoryProvider = FutureProvider<CariRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return CariRepository(db);
});

final sutRepositoryProvider = FutureProvider<SutRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return SutRepository(db);
});

final yemRepositoryProvider = FutureProvider<YemRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return YemRepository(db);
});

final cariOdemeRepositoryProvider = FutureProvider<CariOdemeRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return CariOdemeRepository(db);
});

final fiyatRepositoryProvider = FutureProvider<FiyatRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return FiyatRepository(db);
});

final cariFiyatRepositoryProvider = FutureProvider<CariFiyatRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return CariFiyatRepository(db);
});

final teraziCihazRepositoryProvider = FutureProvider<TeraziCihazRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return TeraziCihazRepository(db);
});

final veriYonetimiRepositoryProvider = FutureProvider<VeriYonetimiRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return VeriYonetimiRepository(db);
});
