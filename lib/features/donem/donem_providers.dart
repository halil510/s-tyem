import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/providers/veri_surumu_provider.dart';
import '../../models/cari_model.dart';
import 'donem_servisi.dart';

final donemServisiProvider = FutureProvider<DonemServisi>((ref) async {
  return DonemServisi(await ref.watch(databaseProvider.future));
});

/// [ay] ('yyyy-MM') için dönem durumu ve hakediş satırları.
/// Kapalıysa dondurulmuş bordro, açıksa canlı hesap.
final donemBilgisiProvider =
    FutureProvider.autoDispose.family<DonemBilgisi, String>((ref, ay) async {
  ref.watch(veriSurumuProvider);
  final servis = await ref.watch(donemServisiProvider.future);
  return servis.bilgi(ay);
});

/// Kapalı aylar — giriş ekranları "bu dönem kapalı" uyarısı için.
final kapaliAylarProvider = FutureProvider.autoDispose<Set<String>>((ref) async {
  ref.watch(veriSurumuProvider);
  final servis = await ref.watch(donemServisiProvider.future);
  return servis.kapaliAylar();
});

/// Pasifler dahil tüm cariler (bordroda pasif ama bakiyeli cari de görünür).
final tumCarilerProvider = FutureProvider.autoDispose<Map<int, Cari>>((ref) async {
  ref.watch(veriSurumuProvider);
  final repo = await ref.watch(cariRepositoryProvider.future);
  return {for (final c in await repo.getAll(sadeceAktif: false)) if (c.id != null) c.id!: c};
});
