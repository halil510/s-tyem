import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/veri_surumu_provider.dart';
import '../../../models/cari_model.dart';

/// Aktif cariler — Süt, Yem, Ödemeler sekmelerinin ortak listesi.
///
/// [veriSurumuProvider] izlendiği için cari eklenince / Excel'den alınınca /
/// pasife alınınca TÜM sekmeler kendiliğinden yenilenir. (Sekmeler
/// `IndexedStack` içinde bellekte durduğundan, eskiden uygulama yeniden
/// açılana kadar eski liste görünüyordu.)
final aktifCarilerProvider = FutureProvider<List<Cari>>((ref) async {
  ref.watch(veriSurumuProvider);
  final repo = await ref.watch(cariRepositoryProvider.future);
  return repo.getAll(sadeceAktif: true);
});

/// Pasifler dahil tüm cariler (Ödemeler: pasif ama açık bakiyeli cari de görünmeli).
final butunCarilerProvider = FutureProvider<List<Cari>>((ref) async {
  ref.watch(veriSurumuProvider);
  final repo = await ref.watch(cariRepositoryProvider.future);
  return repo.getAll();
});
